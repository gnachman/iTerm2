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

- (BOOL)performActionWithCapturedStrings:(NSArray<NSString *> *)stringArray
                          capturedRanges:(const NSRange *)capturedRanges
                               inSession:(id<iTermTriggerSession>)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    if (disabled_) {
        return YES;
    }
    // Need to stop the world to get scope, provided it is needed. Alerts are so slow & rare that this is ok.
    id<iTermTriggerScopeProvider> scopeProvider = [aSession triggerSessionVariableScopeProvider:self];
    dispatch_queue_t queue = [scopeProvider triggerCompletionQueue];
    [[self paramWithBackreferencesReplacedWithValues:stringArray
                                               scope:scopeProvider
                                               owner:aSession
                                    useInterpolation:useInterpolation] then:^(NSString * _Nonnull message) {
        [self showAlertWithMessage:message inSession:aSession queue:queue];
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

- (void)showAlertWithMessage:(NSString *)message inSession:(id<iTermTriggerSession>)aSession queue:(dispatch_queue_t)queue {
    [[self rateLimit] performRateLimitedBlock:^{
        [self reallyShowAlertWithMessage:message inSession:aSession queue:queue];
    }];
}

- (void)reallyShowAlertWithMessage:(NSString *)message inSession:(id<iTermTriggerSession>)aSession queue:(dispatch_queue_t)queue {
    [aSession triggerShowAlertWithMessage:message disable:^{
        dispatch_async(queue, ^{
            self->disabled_ = YES;
        });
    }];
}

@end
