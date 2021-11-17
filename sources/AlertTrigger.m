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
#import "iTermAdvancedSettingsModel.h"
#import "iTermRateLimitedUpdate.h"

@implementation AlertTrigger {
    BOOL disabled_;
    iTermRateLimitedUpdate *_rateLimit;
}

+ (NSString *)title
{
    return @"Show Alert…";
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
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
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    if (disabled_) {
        return YES;
    }
    [self paramWithBackreferencesReplacedWithValues:capturedStrings
                                              count:captureCount
                                              scope:aSession.variablesScope
                                              owner:aSession
                                   useInterpolation:useInterpolation
                                         completion:^(NSString *message) {
                                             [self showAlertWithMessage:message inSession:aSession];
                                         }];
    return YES;
}

- (iTermRateLimitedUpdate *)rateLimit {
    if (!_rateLimit) {
        _rateLimit = [[iTermRateLimitedUpdate alloc] initWithName:@"AlertTrigger"
                                                  minimumInterval:[iTermAdvancedSettingsModel alertTriggerRateLimit]];
        _rateLimit.suppressionMode = YES;
    }
    return _rateLimit;
}

- (void)showAlertWithMessage:(NSString *)message inSession:(PTYSession *)aSession {
    if (!message) {
        return;
    }
    [[self rateLimit] performRateLimitedBlock:^{
        [self reallyShowAlertWithMessage:message inSession:aSession];
    }];
}

- (void)reallyShowAlertWithMessage:(NSString *)message inSession:(PTYSession *)aSession {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message ?: @"";
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
        }

        case NSAlertThirdButtonReturn:
            disabled_ = YES;
            break;

        default:
            break;
    }
}

@end
