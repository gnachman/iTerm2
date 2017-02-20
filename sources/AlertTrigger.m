//
//  AlertTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "AlertTrigger.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PseudoTerminal.h"

@implementation AlertTrigger {
    BOOL disabled_;
}

+ (NSString *)title
{
    return @"Show Alert…";
}

- (NSString *)paramPlaceholder
{
    return @"Enter text to show in alert";
}

- (BOOL)takesParameter
{
    return YES;
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                                    stop:(BOOL *)stop {
    if (disabled_) {
        return YES;
    }
    NSString *message = [self paramWithBackreferencesReplacedWithValues:capturedStrings
                                                                  count:captureCount];
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Show Session"];
    [alert addButtonWithTitle:@"Disable This Alert"];
    switch ([alert runModal]) {
        case NSAlertFirstButtonReturn:
            break;
            
        case NSAlertSecondButtonReturn: {
            NSWindowController<iTermWindowController> * term = [[aSession delegate] realParentWindow];
            [[term window] makeKeyAndOrderFront:nil];
            [aSession.delegate sessionSelectContainingTab];
            [aSession.delegate setActiveSession:aSession];
            break;
            
        case NSAlertThirdButtonReturn:
            disabled_ = YES;
            break;
        }
            
        default:
            break;
    }
    return YES;
}

@end
