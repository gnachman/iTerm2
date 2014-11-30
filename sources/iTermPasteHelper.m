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
#import "iTermPasteSpecialWindowController.h"
#import "iTermWarning.h"
#import "NSStringITerm.h"
#import "PasteContext.h"
#import "PasteEvent.h"
#import "PasteViewController.h"

static NSString *const kPasteSpecialChunkSize = @"PasteSpecialChunkSize";
static NSString *const kPasteSpecialChunkDelay = @"PasteSpecialChunkDelay";

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
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSNumber *chunkSize = [userDefaults objectForKey:kPasteSpecialChunkSize];
    NSNumber *chunkDelay = [userDefaults objectForKey:kPasteSpecialChunkDelay];
    if (!chunkSize) {
        chunkSize = @(self.normalChunkSize);
    }
    if (!chunkDelay) {
        chunkDelay = @(self.normalDelay);
    }
    [iTermPasteSpecialWindowController showAsPanelInWindow:window
                                                 chunkSize:[chunkSize intValue]
                                        delayBetweenChunks:[chunkDelay doubleValue]
                                         bracketingEnabled:bracketingEnabled
                                                  encoding:[_delegate pasteHelperEncoding]
                                                completion:^(NSString *string,
                                                             NSInteger chosenChunkSize,
                                                             NSTimeInterval chosenDelay) {
                                                    [_buffer appendData:[string dataUsingEncoding:_delegate.pasteHelperEncoding]];
                                                    [userDefaults setInteger:chosenChunkSize
                                                                      forKey:kPasteSpecialChunkSize];
                                                    [userDefaults setDouble:chosenDelay
                                                                     forKey:kPasteSpecialChunkDelay];
                                                    [self pasteWithBytePerCallPrefKey:kPasteSpecialChunkSize
                                                                         defaultValue:chosenChunkSize
                                                             delayBetweenCallsPrefKey:kPasteSpecialChunkDelay
                                                                         defaultValue:chosenDelay];
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

+ (NSString *)sanitizeString:(NSString *)theString
                   withFlags:(iTermPasteFlags)flags {
    if (flags & kPasteFlagsSanitizingNewlines) {
        // Convert DOS (\r\n) CRLF newlines and linefeeds (\n) into carriage returns (\r==13).
        theString = [theString stringWithLinefeedNewlines];
    }

    NSMutableCharacterSet *controlSet = nil;
    if (flags & kPasteFlagsRemovingUnsafeControlCodes) {
        // All control codes except tab (9), newline (10), and form feed (12) are removed unless we are
        // pasting with literal tabs, in which case we also keep LNEXT (22, ^V).
        controlSet = [iTermPasteHelper unsafeControlCodeSet];
    }

    if (flags & kPasteFlagsEscapeSpecialCharacters) {
        // Paste escaping special characters
        theString = [theString stringWithEscapedShellCharacters];
    }

    if (flags & kPasteFlagsWithShellEscapedTabs) {
        // Remove ^Vs before adding them
        theString = [theString stringByReplacingOccurrencesOfString:@"\x16" withString:@""];
        // Add ^Vs before each tab.
        theString = [theString stringWithShellEscapedTabs];
        // Allow the ^Vs that were just added to survive cleaning up control chars.
        [controlSet removeCharactersInRange:NSMakeRange(22, 1)];  // LNEXT (^V)
    }

    if (flags & kPasteFlagsRemovingUnsafeControlCodes) {
        // Remove control characters
        theString =
            [[theString componentsSeparatedByCharactersInSet:controlSet] componentsJoinedByString:@""];
    }

    if (flags & kPasteFlagsBracket) {
        DLog(@"Send open bracket.");
        NSString *startBracket = [NSString stringWithFormat:@"%c[200~", 27];
        NSString *endBracket = [NSString stringWithFormat:@"%c[201~", 27];
        NSArray *components = @[ startBracket, theString, endBracket ];
        theString = [components componentsJoinedByString:@""];
    }

    return theString;
}

- (void)pasteString:(NSString *)theString flags:(PTYSessionPasteFlags)flags {
    DLog(@"-[iTermPasteHelper pasteString:flags:");
    DLog(@"length=%@, flags=%@", @(theString.length), @(flags));
    if ([theString length] == 0) {
        DLog(@"Tried to paste 0-byte string. Beep.");
        NSBeep();
        return;
    }
    if ([self isPasting]) {
        DLog(@"Already pasting. Enqueue event.");
        [self enqueueEvent:[PasteEvent pasteEventWithString:theString flags:flags]];
        return;
    }
    if (![self maybeWarnAboutMultiLinePaste:theString]) {
        DLog(@"Multiline paste declined.");
        return;
    }

    DLog(@"Sanitize control characters, escape, etc....");

    NSUInteger bracketFlag = [_delegate pasteHelperShouldBracket] ? kPasteFlagsBracket : 0;
    theString = [iTermPasteHelper sanitizeString:theString
                                       withFlags:(flags |
                                                  kPasteFlagsSanitizingNewlines |
                                                  kPasteFlagsRemovingUnsafeControlCodes |
                                                  bracketFlag)];

    DLog(@"String to paste now has length %@", @(theString.length));
    if ([theString length] == 0) {
        DLog(@"Tried to paste 0-byte string (became 0 length after removing controls). Beep.");
        NSBeep();
        return;
    }

    if (flags & kPTYSessionPasteSlowly) {
        [self pasteSlowly:theString];
    } else {
        [self pasteNormally:theString];
    }
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
    int eventsSent = 0;
    for (NSEvent *event in _eventQueue) {
        ++eventsSent;
        if ([event isKindOfClass:[PasteEvent class]]) {
            DLog(@"Found a queued paste event");
            PasteEvent *pasteEvent = (PasteEvent *)event;
            [self pasteString:pasteEvent.string flags:pasteEvent.flags];
            // Can't empty while pasting.
            break;
        } else {
            DLog(@"Found a queued keydown event");
            [_delegate pasteHelperKeyDown:event];
        }
    }
    DLog(@"Done dequeueing paste events.");
    [_eventQueue removeObjectsInRange:NSMakeRange(0, eventsSent)];
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
