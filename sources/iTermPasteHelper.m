//
//  iTermPasteHelper.m
//  iTerm
//
//  Created by George Nachman on 3/29/14.
//
//

#import "iTermPasteHelper.h"
#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplicationDelegate.h"
#import "iTermNumberOfSpacesAccessoryViewController.h"
#import "iTermPasteSpecialViewController.h"
#import "iTermPasteSpecialWindowController.h"
#import "iTermPreferences.h"
#import "iTermWarning.h"
#import "NSData+iTerm.h"
#import "NSStringITerm.h"
#import "PasteContext.h"
#import "PasteEvent.h"
#import "PasteViewController.h"

@interface iTermPasteHelper () <PasteViewControllerDelegate>
@end

@implementation iTermPasteHelper {
    NSMutableArray *_eventQueue;
    PasteViewController *_pasteViewController;
    PasteContext *_pasteContext;

    // Paste from the head of this string from a timer until it's empty.
    NSMutableData *_buffer;
    NSTimer *_timer;

}

+ (NSMutableCharacterSet *)unsafeControlCodeSet {
    NSMutableCharacterSet *controlSet = [[[NSMutableCharacterSet alloc] init] autorelease];
    [controlSet addCharactersInRange:NSMakeRange(0, 32)];
    [controlSet removeCharactersInRange:NSMakeRange(9, 2)];  // Tab and line feed
    [controlSet removeCharactersInRange:NSMakeRange(12, 2)];  // Form feed and carriage return
    return controlSet;
}

- (id)init {
    self = [super init];
    if (self) {
        _eventQueue = [[NSMutableArray alloc] init];
        _buffer = [[NSMutableData alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_eventQueue release];
    [_pasteViewController release];
    [_pasteContext release];
    [_buffer release];
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
                                                completion:^(PasteEvent *event) {
                                                    [self pasteEvent:event];
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
    [self hidePasteIndicator];
}

- (BOOL)isPasting {
    return _timer != nil;
}

+ (void)sanitizePasteEvent:(PasteEvent *)pasteEvent encoding:(NSStringEncoding)encoding {
    NSUInteger flags = pasteEvent.flags;
    NSString *theString = pasteEvent.string;

    if (flags & kPasteFlagsSanitizingNewlines) {
        // Convert DOS (\r\n) CRLF newlines and linefeeds (\n) into carriage returns (\r==13).
        theString = [theString stringWithLinefeedNewlines];
    }

    if (flags & kPasteFlagsEscapeSpecialCharacters) {
        // Put backslash before anything the shell might interpret.
        theString = [theString stringWithEscapedShellCharacters];
    }

    if (flags & kPasteFlagsRemovingUnsafeControlCodes) {
        // All control codes except tab (9), newline (10), form feed (12), and carriage return (13)
        // are removed.
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

        case kTabTransformEscapeWithCtrlZ:
            theString = [theString stringWithShellEscapedTabs];
            break;
    }

    if (pasteEvent.flags & kPasteFlagsBase64Encode) {
        NSData *temp = [pasteEvent.string dataUsingEncoding:encoding];
        theString = [temp stringWithBase64EncodingWithLineBreak:@"\r"];
    }

    pasteEvent.string = theString;
}

- (void)pasteString:(NSString *)theString stringConfig:(NSString *)jsonConfig {
    PasteEvent *pasteEvent = [iTermPasteSpecialViewController pasteEventForConfig:jsonConfig
                                                                           string:theString];
    [self pasteEvent:pasteEvent];
}

- (void)pasteString:(NSString *)theString
             slowly:(BOOL)slowly
   escapeShellChars:(BOOL)escapeShellChars
       tabTransform:(iTermTabTransformTags)tabTransform
       spacesPerTab:(int)spacesPerTab {
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
                                            spacesPerTab:spacesPerTab];
    [self pasteEvent:event];
}

// this needs to take the delay, chunk size, key names, and the exact flags it wants
- (void)pasteEvent:(PasteEvent *)pasteEvent {
    static BOOL running;
    assert(!running);
    running = YES;
    DLog(@"-[iTermPasteHelper pasteString:flags:");
    DLog(@"length=%@, flags=%@", @(pasteEvent.string.length), @(pasteEvent.flags));
    if ([pasteEvent.string length] == 0) {
        DLog(@"Tried to paste 0-byte string. Beep.");
        NSBeep();
        running = NO;
        return;
    }
    if ([self isPasting]) {
        DLog(@"Already pasting. Enqueue event.");
        [self enqueueEvent:pasteEvent];
        running = NO;
        return;
    }
    if (![self maybeWarnAboutMultiLinePaste:pasteEvent.string]) {
        DLog(@"Multiline paste declined.");
        running = NO;
        return;
    }

    DLog(@"Sanitize control characters, escape, etc....");

    // A queued up paste command might have wanted bracketing but the host might not accept it
    // any more.
    if (![_delegate pasteHelperShouldBracket]) {
        pasteEvent.flags = pasteEvent.flags & ~kPasteFlagsBracket;
    }

    [iTermPasteHelper sanitizePasteEvent:pasteEvent encoding:[_delegate pasteHelperEncoding]];

    if (pasteEvent.flags & kPasteFlagsBracket) {
        DLog(@"Send open bracket.");
        NSString *startBracket = [NSString stringWithFormat:@"%c[200~", 27];
        NSString *endBracket = [NSString stringWithFormat:@"%c[201~", 27];
        NSArray *components = @[ startBracket, pasteEvent.string, endBracket ];
        pasteEvent.string = [components componentsJoinedByString:@""];
    }

    DLog(@"String to paste now has length %@", @(pasteEvent.string.length));
    if ([pasteEvent.string length] == 0) {
        DLog(@"Tried to paste 0-byte string (became 0 length after removing controls). Beep.");
        NSBeep();
        running = NO;
        return;
    }

    [_buffer appendData:[pasteEvent.string dataUsingEncoding:[_delegate pasteHelperEncoding]]];
    [self pasteWithBytePerCallPrefKey:pasteEvent.chunkKey
                         defaultValue:pasteEvent.defaultChunkSize
             delayBetweenCallsPrefKey:pasteEvent.delayKey
                         defaultValue:pasteEvent.defaultDelay];
    running = NO;
}

// Outputs 16 bytes every 125ms so that clients that don't buffer input can handle pasting large buffers.
// Override the constants by setting defaults SlowPasteBytesPerCall and SlowPasteDelayBetweenCalls
- (void)pasteSlowly:(NSString *)theString {
    DLog(@"pasteSlowly length=%@", @(theString.length));
    [_buffer appendData:[theString dataUsingEncoding:[_delegate pasteHelperEncoding]]];
    [self pasteWithBytePerCallPrefKey:@"SlowPasteBytesPerCall"
                         defaultValue:16
             delayBetweenCallsPrefKey:@"SlowPasteDelayBetweenCalls"
                         defaultValue:0.125];
}

- (void)pasteNormally:(NSString *)aString
{
    DLog(@"pasteNormally length=%@", @(aString.length));
    // This is the "normal" way of pasting. It's fast but tends not to
    // outrun a shell's ability to read from its buffer. Why this crazy
    // thing? See bug 1031.
    [_buffer appendData:[aString dataUsingEncoding:[_delegate pasteHelperEncoding]]];
    [self pasteWithBytePerCallPrefKey:@"QuickPasteBytesPerCall"
                         defaultValue:1024
             delayBetweenCallsPrefKey:@"QuickPasteDelayBetweenCalls"
                         defaultValue:0.01];
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
            // -pasteEvent: can call dequeueEvents indirectly, so this method must be reentrant.
            [self pasteEvent:pasteEvent];
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

- (void)showPasteIndicatorInView:(NSView *)view {
    _pasteViewController = [[PasteViewController alloc] initWithContext:_pasteContext
                                                                 length:_buffer.length];
    _pasteViewController.delegate = self;
    _pasteViewController.view.frame = NSMakeRect(20,
                                                 view.frame.size.height - _pasteViewController.view.frame.size.height,
                                                 _pasteViewController.view.frame.size.width,
                                                 _pasteViewController.view.frame.size.height);
    [view addSubview:_pasteViewController.view];
    [_pasteViewController updateFrame];
}

- (void)hidePasteIndicator {
    [_pasteViewController close];
    [_pasteViewController release];
    _pasteViewController = nil;
}

- (void)updatePasteIndicator {
    [_pasteViewController setRemainingLength:_buffer.length];
}

- (void)pasteNextChunkAndScheduleTimer {
    DLog(@"pasteNextChunkAndScheduleTimer");
    NSRange range;
    range.location = 0;
    range.length = MIN(_pasteContext.bytesPerCall, [_buffer length]);
    if (range.length > 0) {
        [_delegate pasteHelperWriteData:[_buffer subdataWithRange:range]];
    }
    [_buffer replaceBytesInRange:range withBytes:"" length:0];

    [self updatePasteIndicator];
    if ([_buffer length] > 0) {
        DLog(@"Scheduling timer");
        NSLog(@"Schedule timer after %@", @(_pasteContext.delayBetweenCalls));
        [_pasteContext updateValues];
        _timer = [NSTimer scheduledTimerWithTimeInterval:_pasteContext.delayBetweenCalls
                                                  target:self
                                                selector:@selector(pasteNextChunkAndScheduleTimer)
                                                userInfo:nil
                                                 repeats:NO];
    } else {
        DLog(@"Done pasting");
        _timer = nil;
        [self hidePasteIndicator];
        [_pasteContext release];
        _pasteContext = nil;
        [self dequeueEvents];
    }
}

- (void)pasteWithBytePerCallPrefKey:(NSString*)bytesPerCallKey
                       defaultValue:(int)bytesPerCallDefault
           delayBetweenCallsPrefKey:(NSString*)delayBetweenCallsKey
                       defaultValue:(float)delayBetweenCallsDefault
{
    [_pasteContext release];
    _pasteContext = [[PasteContext alloc] initWithBytesPerCallPrefKey:bytesPerCallKey
                                                         defaultValue:bytesPerCallDefault
                                             delayBetweenCallsPrefKey:delayBetweenCallsKey
                                                         defaultValue:delayBetweenCallsDefault];
    const int kPasteBytesPerSecond = 10000;  // This is a wild-ass guess.
    const NSTimeInterval sumOfDelays =
        _pasteContext.delayBetweenCalls * _buffer.length / _pasteContext.bytesPerCall;
    const NSTimeInterval timeSpentWriting = _buffer.length / kPasteBytesPerSecond;
    const NSTimeInterval kMinEstimatedPasteTimeToShowIndicator = 3;
    if (sumOfDelays + timeSpentWriting > kMinEstimatedPasteTimeToShowIndicator) {
        [self showPasteIndicatorInView:[_delegate pasteHelperViewForIndicator]];
    }

    [self pasteNextChunkAndScheduleTimer];
}

- (BOOL)maybeWarnAboutMultiLinePaste:(NSString *)string
{
    iTermApplicationDelegate *applicationDelegate = [[NSApplication sharedApplication] delegate];
    if (![applicationDelegate warnBeforeMultiLinePaste]) {
        return YES;
    }
    NSRange rangeOfFirstNewline = [string rangeOfString:@"\n"];
    if (rangeOfFirstNewline.length == 0) {
        return YES;
    }
    if ([iTermAdvancedSettingsModel suppressMultilinePasteWarningWhenPastingOneLineWithTerminalNewline] &&
        rangeOfFirstNewline.location == string.length - 1) {
        return YES;
    }
    if ([iTermAdvancedSettingsModel suppressMultilinePasteWarningWhenNotAtShellPrompt] &&
        ![_delegate pasteHelperIsAtShellPrompt]) {
        return YES;
    }
    NSString *theTitle = [NSString stringWithFormat:@"OK to paste %d lines?",
                             (int)[[string componentsSeparatedByString:@"\n"] count]];
    iTermWarningSelection selection =
        [iTermWarning showWarningWithTitle:theTitle
                                   actions:@[ @"Paste", @"Cancel" ]
                                identifier:kMultiLinePasteWarningUserDefaultsKey
                               silenceable:YES];
    return selection == kiTermWarningSelection0;
}

- (int)numberOfSpacesToConvertTabsTo:(NSString *)source {
    if ([source rangeOfString:@"\t"].location != NSNotFound) {
        iTermNumberOfSpacesAccessoryViewController *accessoryController =
            [[[iTermNumberOfSpacesAccessoryViewController alloc] init] autorelease];

        iTermWarningSelection selection =
        [iTermWarning showWarningWithTitle:@"You're about to paste a string with tabs."
                                   actions:@[ @"Paste with tabs", @"Convert tabs to spaces" ]
                                 accessory:accessoryController.view
                                identifier:@"AboutToPasteTabs"
                               silenceable:kiTermWarningTypePermanentlySilenceable];
        switch (selection) {
            case kiTermWarningSelection1:
                [accessoryController saveToUserDefaults];
                return accessoryController.numberOfSpaces;
            case kiTermWarningSelection0:
            default:
                return -1;
        }
    }
    return -1;
}

#pragma mark - PasteViewControllerDelegate

- (void)pasteViewControllerDidCancel
{
    [self hidePasteIndicator];
    [_timer invalidate];
    _timer = nil;
    [_buffer release];
    _buffer = [[NSMutableData alloc] init];
    [self dequeueEvents];
}

@end
