//
//  iTermPasteHelper.m
//  iTerm
//
//  Created by George Nachman on 3/29/14.
//
//

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplicationDelegate.h"
#import "iTermNumberOfSpacesAccessoryViewController.h"
#import "iTermPasteHelper.h"
#import "iTermPasteSpecialViewController.h"
#import "iTermPasteSpecialWindowController.h"
#import "iTermPasteViewManager.h"
#import "iTermPreferences.h"
#import "iTermWarning.h"
#import "NSData+iTerm.h"
#import "NSStringITerm.h"
#import "PasteboardHistory.h"
#import "PasteContext.h"
#import "PasteEvent.h"
#import "PasteViewController.h"
#import "RegexKitLite.h"

const int kNumberOfSpacesPerTabCancel = -2;
const int kNumberOfSpacesPerTabNoConversion = -1;

@interface iTermPasteHelper () <iTermPasteViewManagerDelegate>
@end

@implementation iTermPasteHelper {
    NSMutableArray *_eventQueue;
    PasteContext *_pasteContext;

    // Paste from the head of this string from a timer until it's empty.
    NSMutableString *_buffer;
    NSTimer *_timer;
    iTermPasteViewManager *_pasteViewManager;
}

+ (NSMutableCharacterSet *)unsafeControlCodeSet {
    NSMutableCharacterSet *controlSet = [[[NSMutableCharacterSet alloc] init] autorelease];
    [controlSet addCharactersInRange:NSMakeRange(0, 32)];
    [controlSet removeCharactersInRange:NSMakeRange(9, 2)];  // Tab and line feed
    [controlSet removeCharactersInRange:NSMakeRange(12, 2)];  // Form feed and carriage return
    return controlSet;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _eventQueue = [[NSMutableArray alloc] init];
        _buffer = [[NSMutableString alloc] init];
        _pasteViewManager = [[iTermPasteViewManager alloc] init];
        _pasteViewManager.delegate = self;
    }
    return self;
}

- (void)dealloc {
    [_eventQueue release];
    [_pasteContext release];
    [_buffer release];
    [_pasteViewManager release];
    if (_timer) {
        [_timer invalidate];
    }
    [super dealloc];
}

- (void)showPasteOptionsInWindow:(NSWindow *)window bracketingEnabled:(BOOL)bracketingEnabled {
    int chunkSize = [iTermPreferences intForKey:kPreferenceKeyPasteSpecialChunkSize];
    NSTimeInterval chunkDelay = [iTermPreferences floatForKey:kPreferenceKeyPasteSpecialChunkDelay];
    [iTermPasteSpecialWindowController showAsPanelInWindow:window
                                                 chunkSize:chunkSize
                                        delayBetweenChunks:chunkDelay
                                         bracketingEnabled:bracketingEnabled
                                                  encoding:[_delegate pasteHelperEncoding]
                                          canWaitForPrompt:[_delegate pasteHelperCanWaitForPrompt]
                                           isAtShellPrompt:![_delegate pasteHelperShouldWaitForPrompt]
                                                completion:^(PasteEvent *event) {
                                                    [self tryToPasteEvent:event];
                                                    [iTermPreferences setInt:event.defaultChunkSize
                                                                      forKey:kPreferenceKeyPasteSpecialChunkSize];
                                                    [iTermPreferences setFloat:event.defaultDelay
                                                                        forKey:kPreferenceKeyPasteSpecialChunkDelay];
                                                }];
}

- (void)abort {
    if (_timer) {
        [_timer invalidate];
        _timer = nil;
        [_eventQueue removeAllObjects];
    }
    [_buffer release];
    _buffer = [[NSMutableString alloc] init];
    [self hidePasteIndicator];
}

- (BOOL)isPasting {
    return _timer != nil || _pasteContext.isBlocked;
}

+ (void)sanitizePasteEvent:(PasteEvent *)pasteEvent encoding:(NSStringEncoding)encoding {
    NSUInteger flags = pasteEvent.flags;
    NSString *theString = pasteEvent.string;

    if (flags & kPasteFlagsRemovingNewlines) {
        theString = [[theString stringByReplacingOccurrencesOfString:@"\r" withString:@""]
                     stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    } else if (flags & kPasteFlagsSanitizingNewlines) {
        // Convert DOS (\r\n) CRLF newlines and linefeeds (\n) into carriage returns (\r==13).
        theString = [theString stringWithLinefeedNewlines];
    }

    if (flags & kPasteFlagsConvertUnicodePunctuation) {
        theString = [theString stringByReplacingOccurrencesOfString:kPasteSpecialViewControllerUnicodeDoubleQuotesRegularExpression
                                                         withString:@"\""
                                                            options:NSRegularExpressionSearch
                                                              range:NSMakeRange(0, theString.length)];
        theString = [theString stringByReplacingOccurrencesOfString:kPasteSpecialViewControllerUnicodeSingleQuotesRegularExpression
                                                         withString:@"'"
                                                            options:NSRegularExpressionSearch
                                                              range:NSMakeRange(0, theString.length)];
        theString = [theString stringByReplacingOccurrencesOfString:kPasteSpecialViewControllerUnicodeDashesRegularExpression
                                                         withString:@"-"
                                                            options:NSRegularExpressionSearch
                                                              range:NSMakeRange(0, theString.length)];
    }

    if (flags & kPasteFlagsRemovingUnsafeControlCodes) {
        // All control codes except tab (9), newline (10), form feed (12), carriage return (13),
        // and shell escape (22) are removed. This must be done before transforming tabs since
        // that transformation might add ^Vs.
        theString =
        [[theString componentsSeparatedByCharactersInSet:[iTermPasteHelper unsafeControlCodeSet]]
         componentsJoinedByString:@""];
    }

    switch (pasteEvent.tabTransform) {
        case kTabTransformNone:
            break;

        case kTabTransformConvertToSpaces: {
            NSString *spaces = [@" " stringRepeatedTimes:pasteEvent.spacesPerTab];
            theString = [theString stringByReplacingOccurrencesOfString:@"\t"
                                                             withString:spaces];
            break;
        }

        case kTabTransformEscapeWithCtrlV:
            theString = [theString stringWithShellEscapedTabs];
            break;
    }

    if (flags & kPasteFlagsEscapeSpecialCharacters) {
        // Put backslash before anything the shell might interpret.
        if (pasteEvent.tabTransform != kTabTransformEscapeWithCtrlV) {
            theString = [theString stringWithEscapedShellCharactersIncludingNewlines:NO];
        } else {
            // Avoid double-escaping tabs with both ^V and backslash.
            theString = [theString stringWithEscapedShellCharactersExceptTabAndNewline];
        }
    }

    if (pasteEvent.flags & kPasteFlagsUseRegexSubstitution && pasteEvent.regex.length > 0) {
        NSString *replacement = nil;
        @try {
            replacement = [theString stringByReplacingOccurrencesOfRegex:pasteEvent.regex ?: @""
                                                              withString:[pasteEvent.substitution stringByExpandingVimSpecialCharacters] ?: @""] ?: @"";
            if (replacement) {
                theString = replacement;
            }
        } @catch (NSException *exception) {
            NSLog(@"Exception with s/%@/%@/g: %@", pasteEvent.regex ?: @"", pasteEvent.substitution ?: @"", exception);
        }
    }
    if (pasteEvent.flags & kPasteFlagsBase64Encode) {
        NSData *temp = [theString dataUsingEncoding:encoding];
        theString = [temp stringWithBase64EncodingWithLineBreak:@"\r"];
    }

    pasteEvent.string = theString;
}

- (void)pasteString:(NSString *)theString stringConfig:(NSString *)jsonConfig {
    PasteEvent *pasteEvent = [iTermPasteSpecialViewController pasteEventForConfig:jsonConfig
                                                                           string:theString];
    [self tryToPasteEvent:pasteEvent];
}

- (void)pasteString:(NSString *)theString
             slowly:(BOOL)slowly
   escapeShellChars:(BOOL)escapeShellChars
           isUpload:(BOOL)isUpload
       tabTransform:(iTermTabTransformTags)tabTransform
       spacesPerTab:(int)spacesPerTab {
    [self pasteString:theString slowly:slowly escapeShellChars:escapeShellChars isUpload:isUpload tabTransform:tabTransform spacesPerTab:spacesPerTab progress:nil];
}

- (void)pasteString:(NSString *)theString
             slowly:(BOOL)slowly
   escapeShellChars:(BOOL)escapeShellChars
           isUpload:(BOOL)isUpload
       tabTransform:(iTermTabTransformTags)tabTransform
       spacesPerTab:(int)spacesPerTab
           progress:(void (^)(NSInteger))progress {
    NSUInteger bracketFlag = [_delegate pasteHelperShouldBracket] ? kPasteFlagsBracket : 0;
    NSUInteger flags = (kPasteFlagsSanitizingNewlines |
                        kPasteFlagsRemovingUnsafeControlCodes |
                        bracketFlag);
    if (escapeShellChars) {
        flags |= kPasteFlagsEscapeSpecialCharacters;
    }
    int defaultChunkSize;
    NSTimeInterval defaultDelay;
    NSString *chunkKey;
    NSString *delayKey;
    if (slowly) {
        defaultChunkSize = 16;
        defaultDelay = 0.125;
        chunkKey = @"SlowPasteBytesPerCall";
        delayKey = @"SlowPasteDelayBetweenCalls";
    } else {
        defaultChunkSize = 1024;
        defaultDelay = 0.01;
        chunkKey = @"QuickPasteBytesPerCall";
        delayKey = @"QuickPasteDelayBetweenCalls";
    }
    PasteEvent *event = [PasteEvent pasteEventWithString:theString
                                                   flags:flags
                                        defaultChunkSize:defaultChunkSize
                                                chunkKey:chunkKey
                                            defaultDelay:defaultDelay
                                                delayKey:delayKey
                                            tabTransform:tabTransform
                                            spacesPerTab:spacesPerTab
                                                   regex:nil
                                            substitution:nil];
    event.progress = progress;
    event.isUpload = isUpload;
    [self tryToPasteEvent:event];
}

// this needs to take the delay, chunk size, key names, and the exact flags it wants
- (void)tryToPasteEvent:(PasteEvent *)pasteEvent {
    DLog(@"-[iTermPasteHelper pasteString:flags:");
    DLog(@"length=%@, flags=%@", @(pasteEvent.string.length), @(pasteEvent.flags));
    if ([pasteEvent.string length] == 0) {
        DLog(@"Tried to paste 0-byte string. Beep.");
        NSBeep();
        return;
    }
    if (!(pasteEvent.flags & kPasteFlagsCommands)) {
        if (![self maybeWarnAboutMultiLinePaste:pasteEvent]) {
            DLog(@"Multiline paste declined.");
            return;
        }
    }
    if ([self isPasting]) {
        DLog(@"Already pasting. Enqueue event.");
        [self enqueueEvent:pasteEvent];
        return;
    }

    DLog(@"Sanitize control characters, escape, etc....");
    [self pasteEventImmediately:pasteEvent];
}

- (void)pasteEventImmediately:(PasteEvent *)pasteEvent {
    // A queued up paste command might have wanted bracketing but the host might not accept it
    // any more.
    if (pasteEvent.isUpload || ![_delegate pasteHelperShouldBracket]) {
        pasteEvent.flags = pasteEvent.flags & ~kPasteFlagsBracket;
    }

    [iTermPasteHelper sanitizePasteEvent:pasteEvent encoding:[_delegate pasteHelperEncoding]];

    // Save to history
    if (!pasteEvent.isUpload && pasteEvent.string.length > 0) {
        DLog(@"Save string being pasted to history");
        [[PasteboardHistory sharedInstance] save:pasteEvent.string];
    }

    if (pasteEvent.flags & kPasteFlagsBracket) {
        DLog(@"Bracketing string to paste.");
        NSString *startBracket = [NSString stringWithFormat:@"%c[200~", 27];
        NSString *endBracket = [NSString stringWithFormat:@"%c[201~", 27];
        NSArray *components = @[ startBracket, pasteEvent.string, endBracket ];
        pasteEvent.string = [components componentsJoinedByString:@""];
    }

    DLog(@"String to paste now has length %@", @(pasteEvent.string.length));
    if ([pasteEvent.string length] == 0) {
        DLog(@"Tried to paste 0-byte string (became 0 length after removing controls). Beep.");
        NSBeep();
        return;
    }

    [_buffer appendString:pasteEvent.string];
    [self pasteWithBytePerCallPrefKey:pasteEvent.chunkKey
                         defaultValue:pasteEvent.defaultChunkSize
             delayBetweenCallsPrefKey:pasteEvent.delayKey
                         defaultValue:pasteEvent.defaultDelay
                       blockAtNewline:!!(pasteEvent.flags & kPasteFlagsCommands)
                             isUpload:pasteEvent.isUpload
                             progress:pasteEvent.progress];
}

// Outputs 16 bytes every 125ms so that clients that don't buffer input can handle pasting large buffers.
// Override the constants by setting defaults SlowPasteBytesPerCall and SlowPasteDelayBetweenCalls
- (void)pasteSlowly:(NSString *)theString {
    DLog(@"pasteSlowly length=%@", @(theString.length));
    [_buffer appendString:theString];
    [self pasteWithBytePerCallPrefKey:@"SlowPasteBytesPerCall"
                         defaultValue:16
             delayBetweenCallsPrefKey:@"SlowPasteDelayBetweenCalls"
                         defaultValue:0.125
                       blockAtNewline:NO
                             isUpload:NO
                             progress:nil];
}

- (void)pasteNormally:(NSString *)aString {
    DLog(@"pasteNormally length=%@", @(aString.length));
    // This is the "normal" way of pasting. It's fast but tends not to
    // outrun a shell's ability to read from its buffer. Why this crazy
    // thing? See bug 1031.
    [_buffer appendString:aString];
    [self pasteWithBytePerCallPrefKey:@"QuickPasteBytesPerCall"
                         defaultValue:1024
             delayBetweenCallsPrefKey:@"QuickPasteDelayBetweenCalls"
                         defaultValue:0.01
                       blockAtNewline:NO
                             isUpload:NO
                             progress:nil];
}

- (NSInteger)normalChunkSize {
    NSNumber *n = [[NSUserDefaults standardUserDefaults] objectForKey:@"QuickPasteBytesPerCall"];
    if (!n) {
        return 1024;
    } else {
        return [n integerValue];
    }
}

- (NSTimeInterval)normalDelay {
    NSNumber *n = [[NSUserDefaults standardUserDefaults] objectForKey:@"QuickPasteDelayBetweenCalls"];
    if (!n) {
        return 0.01;
    } else {
        return [n doubleValue];
    }
}

- (void)dequeueEvents {
    DLog(@"Dequeueing paste events...");
    while (_eventQueue.count) {
        NSEvent *event = [[[_eventQueue firstObject] retain] autorelease];
        [_eventQueue removeObjectAtIndex:0];
        if ([event isKindOfClass:[PasteEvent class]]) {
            DLog(@"Found a queued paste event");
            PasteEvent *pasteEvent = (PasteEvent *)event;
            [self pasteEventImmediately:pasteEvent];
            // Can't empty while pasting.
            break;
        } else {
            DLog(@"Found a queued keydown event");
            [_delegate pasteHelperKeyDown:event];
        }
    }
    DLog(@"Done dequeueing paste events.");
}

- (void)enqueueEvent:(NSEvent *)event {
    DLog(@"Enqueue paste event %@", event);
    [_eventQueue addObject:event];
}

- (void)showPasteIndicatorInView:(NSView *)view
         statusBarViewController:(iTermStatusBarViewController *)statusBarViewController {
    _pasteViewManager.pasteContext = _pasteContext;
    _pasteViewManager.bufferLength = _buffer.length;
    [_pasteViewManager startWithViewForDropdown:view
                        statusBarViewController:statusBarViewController];
}

- (void)hidePasteIndicator {
    [_pasteViewManager didStop];
}

- (void)updatePasteIndicator {
    [_pasteViewManager setRemainingLength:_buffer.length];
}

- (void)pasteNextChunkAndScheduleTimer {
    DLog(@"pasteNextChunkAndScheduleTimer");
    BOOL block = NO;
    NSRange range;
    range.location = 0;
    range.length = MIN(_pasteContext.bytesPerCall, [_buffer length]);
    if (range.length > 0) {
        if (_pasteContext.blockAtNewline) {
            // If there is a newline in the range about to be pasted, only paste up to and including
            // it and the block to YES.
            NSRange newlineRange = [_buffer rangeOfString:@"\n"];
            if (newlineRange.location == NSNotFound) {
                newlineRange = [_buffer rangeOfString:@"\r"];
            }
            if (newlineRange.location != NSNotFound) {
                range.length = newlineRange.location + newlineRange.length;
                block = YES;
            }
        }
        range = [_buffer makeRangeSafe:range];
        [_delegate pasteHelperWriteString:[_buffer substringWithRange:range]];
        _pasteContext.bytesWritten = _pasteContext.bytesWritten + range.length;
        if (_pasteContext.progress) {
            _pasteContext.progress(_pasteContext.bytesWritten);
        }
    }
    [_buffer replaceCharactersInRange:range withString:@""];

    [self updatePasteIndicator];
    if ([_buffer length] > 0) {
        DLog(@"Schedule timer after %@", @(_pasteContext.delayBetweenCalls));
        [_pasteContext updateValues];
        if (!block) {
            [self scheduleNextPasteForCurrentPasteContext];
        } else {
            _pasteContext.isBlocked = YES;
            _timer = nil;
        }
    } else {
        DLog(@"Done pasting");
        _timer = nil;
        [self hidePasteIndicator];
        [_pasteContext release];
        _pasteContext = nil;
        [self dequeueEvents];
    }
}

- (void)scheduleNextPasteForCurrentPasteContext {
    [_timer invalidate];
    _timer = [self scheduledTimerWithTimeInterval:_pasteContext.delayBetweenCalls
                                           target:self
                                         selector:@selector(pasteNextChunkAndScheduleTimer)
                                         userInfo:nil
                                          repeats:NO];
    if (_pasteContext.isUpload) {
        // Ensure the timer runs while the uploads menu is open.
        [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    }
}

- (void)unblock {
    if (_pasteContext.isBlocked) {
        _pasteContext.isBlocked = NO;
        [self pasteNextChunkAndScheduleTimer];
    }
}

- (void)pasteWithBytePerCallPrefKey:(NSString*)bytesPerCallKey
                       defaultValue:(int)bytesPerCallDefault
           delayBetweenCallsPrefKey:(NSString*)delayBetweenCallsKey
                       defaultValue:(float)delayBetweenCallsDefault
                     blockAtNewline:(BOOL)blockAtNewline
                           isUpload:(BOOL)isUpload
                           progress:(void (^)(NSInteger))progress {
    [_pasteContext release];
    _pasteContext = [[PasteContext alloc] initWithBytesPerCallPrefKey:bytesPerCallKey
                                                         defaultValue:bytesPerCallDefault
                                             delayBetweenCallsPrefKey:delayBetweenCallsKey
                                                         defaultValue:delayBetweenCallsDefault];
    _pasteContext.blockAtNewline = blockAtNewline;
    _pasteContext.isUpload = isUpload;
    _pasteContext.progress = progress;
    const int kPasteBytesPerSecond = 10000;  // This is a wild-ass guess.
    const NSTimeInterval sumOfDelays =
        _pasteContext.delayBetweenCalls * _buffer.length / _pasteContext.bytesPerCall;
    const NSTimeInterval timeSpentWriting = _buffer.length / kPasteBytesPerSecond;
    const NSTimeInterval kMinEstimatedPasteTimeToShowIndicator = 3;
    if (!isUpload) {
        if ((sumOfDelays + timeSpentWriting > kMinEstimatedPasteTimeToShowIndicator) ||
            blockAtNewline) {
            [self showPasteIndicatorInView:[_delegate pasteHelperViewForIndicator]
                   statusBarViewController:[_delegate pasteHelperStatusBarViewController]];
        }
    }

    if (_pasteContext.blockAtNewline && [_delegate pasteHelperShouldWaitForPrompt]) {
        DLog(@"Not at shell prompt at start of paste.");
        _pasteContext.isBlocked = YES;
        return;
    }

    [self pasteNextChunkAndScheduleTimer];
}

// This may modify pasteEvent.string.
- (BOOL)maybeWarnAboutMultiLinePaste:(PasteEvent *)pasteEvent {
    NSCharacterSet *newlineCharacterSet =
        [NSCharacterSet characterSetWithCharactersInString:@"\r\n"];
    NSRange rangeOfFirstNewline = [pasteEvent.string rangeOfCharacterFromSet:newlineCharacterSet];
    if (rangeOfFirstNewline.length == 0) {
        return YES;
    }
    if ([iTermAdvancedSettingsModel suppressMultilinePasteWarningWhenPastingOneLineWithTerminalNewline] &&
        rangeOfFirstNewline.location == pasteEvent.string.length - 1) {
        return YES;
    }
    BOOL atShellPrompt = [_delegate pasteHelperIsAtShellPrompt];
    if ([iTermAdvancedSettingsModel suppressMultilinePasteWarningWhenNotAtShellPrompt] &&
        !atShellPrompt) {
        return YES;
    }
    NSArray *lines = [pasteEvent.string componentsSeparatedByRegex:@"(?:\r\n)|(?:\r)|(?:\n)"];
    NSString *theTitle;
    NSMutableArray<iTermWarningAction *> *actions = [NSMutableArray array];

    __block BOOL result = YES;
    iTermWarningAction *cancel = [iTermWarningAction warningActionWithLabel:@"Cancel"
                                                                      block:^(iTermWarningSelection selection) { result = NO; }];
    iTermWarningAction *paste = [iTermWarningAction warningActionWithLabel:@"Paste"
                                                                     block:^(iTermWarningSelection selection) { result = YES; }];
    iTermWarningAction *pasteWithoutNewline =
        [iTermWarningAction warningActionWithLabel:@"Paste Without Newline"
                                             block:^(iTermWarningSelection selection) {
                                                 NSCharacterSet *newlines = [NSCharacterSet newlineCharacterSet];
                                                 pasteEvent.string =
                                                     [pasteEvent.string stringByTrimmingTrailingCharactersFromCharacterSet:newlines];
                                                 result = YES;
                                             }];

    [actions addObject:paste];
    [actions addObject:cancel];
    NSString *identifier = [iTermAdvancedSettingsModel noSyncDoNotWarnBeforeMultilinePasteUserDefaultsKey];
    BOOL prompt = YES;
    if (lines.count > 1) {
        if (atShellPrompt) {
            theTitle = [NSString stringWithFormat:@"OK to paste %d lines at shell prompt?",
                        (int)[lines count]];
        } else {
            prompt = [iTermAdvancedSettingsModel promptForPasteWhenNotAtPrompt];
            theTitle = [NSString stringWithFormat:@"OK to paste %d lines?",
                        (int)[lines count]];
        }
    } else {
        [actions insertObject:pasteWithoutNewline atIndex:1];
        if (atShellPrompt) {
            identifier = [iTermAdvancedSettingsModel noSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPromptUserDefaultsKey];
            theTitle = @"OK to paste one line ending in a newline at shell prompt?";
        } else {
            prompt = [iTermAdvancedSettingsModel promptForPasteWhenNotAtPrompt];
            theTitle = @"OK to paste one line ending in a newline?";
        }
    }

    if (!prompt) {
        return YES;
    }
    // Issue 5115
    [iTermWarning unsilenceIdentifier:identifier ifSelectionEquals:[actions indexOfObjectIdenticalTo:cancel]];

    iTermWarning *warning = [[[iTermWarning alloc] init] autorelease];
    warning.title = theTitle;
    warning.warningActions = actions;
    warning.identifier = identifier;
    warning.warningType = kiTermWarningTypePermanentlySilenceable;
    warning.cancelLabel = @"Cancel";
    warning.window = [[self.delegate pasteHelperViewForIndicator] window];
    [warning runModal];
    return result;
}

- (int)numberOfSpacesToConvertTabsTo:(NSString *)source {
    if ([source rangeOfString:@"\t"].location != NSNotFound) {
        iTermNumberOfSpacesAccessoryViewController *accessoryController =
            [[[iTermNumberOfSpacesAccessoryViewController alloc] init] autorelease];

        iTermWarningSelection selection =
            [iTermWarning showWarningWithTitle:@"You're about to paste a string with tabs."
                                       actions:@[ @"Paste with tabs", @"Cancel", @"Convert tabs to spaces" ]
                                     accessory:accessoryController.view
                                    identifier:@"AboutToPasteTabsWithCancel"
                                   silenceable:kiTermWarningTypePermanentlySilenceable
                                        window:self.delegate.pasteHelperViewForIndicator.window];
        switch (selection) {
            case kiTermWarningSelection0:  // Paste with tabs
                return kNumberOfSpacesPerTabNoConversion;
            case kiTermWarningSelection1:  // Cancel
                return kNumberOfSpacesPerTabCancel;
            case kiTermWarningSelection2:  // Convert to spaces
                [accessoryController saveToUserDefaults];
                return accessoryController.numberOfSpaces;
            default:
                return kNumberOfSpacesPerTabNoConversion;
        }
    }
    return kNumberOfSpacesPerTabNoConversion;
}

- (BOOL)dropDownPasteViewIsVisible {
    return _pasteViewManager.dropDownPasteViewIsVisible;
}

#pragma mark - iTermPasteViewManagerDelegate

- (void)pasteViewManagerDropDownPasteViewVisibilityDidChange {
    [self.delegate pasteHelperPasteViewVisibilityDidChange];
}

- (void)pasteViewManagerUserDidCancel {
    [self hidePasteIndicator];
    [_timer invalidate];
    _timer = nil;
    [_buffer release];
    _buffer = [[NSMutableString alloc] init];
    [_pasteContext release];
    _pasteContext = nil;
    [self dequeueEvents];
}

#pragma mark - Testing

- (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti
                                     target:(id)aTarget
                                   selector:(SEL)aSelector
                                   userInfo:(id)userInfo
                                    repeats:(BOOL)yesOrNo {
    return [NSTimer scheduledTimerWithTimeInterval:ti
                                            target:aTarget
                                          selector:aSelector
                                          userInfo:userInfo
                                           repeats:yesOrNo];
}

@end
