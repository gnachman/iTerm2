//
//  iTermUserNotificationTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "iTermUserNotificationTrigger.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermNotificationController.h"
#import "iTermRateLimitedUpdate.h"
#import "PTYSession.h"
#import "PTYTab.h"

// I foolishly renamed GrowlTrigger to iTermUserNotificationTrigger in 3.2.1, which broke everyone's triggers.
// It got renamed back in 3.2.2. If someone created a new trigger in 3.2.1 it would have the bogus name.
// Then the 3.3.0 betas didn't cherrypick the fix, so more problems. I'm done with this so let's just
// keep both around forever.
@interface GrowlTrigger : iTermUserNotificationTrigger
@end

@implementation GrowlTrigger
@end

@implementation iTermUserNotificationTrigger {
    iTermRateLimitedUpdate *_rateLimit;
}

+ (NSSet<NSString *> *)synonyms {
    return [NSSet setWithObject:@"GrowlTrigger"];
}

+ (NSString *)title {
    return @"Post Notification…";
}

- (BOOL)takesParameter {
    return YES;
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
    return @"Enter Message";
}

- (BOOL)performActionWithCapturedStrings:(NSArray<NSString *> *)stringArray
                          capturedRanges:(const NSRange *)capturedRanges
                               inSession:(id<iTermTriggerSession>)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    // Need to stop the world to get scope, provided it is needed. Notifs are so slow & rare that this is ok.
    id<iTermTriggerScopeProvider> scopeProvider = [aSession triggerSessionVariableScopeProvider:self];
    dispatch_queue_t queue = scopeProvider.triggerCompletionQueue;
    [[self paramWithBackreferencesReplacedWithValues:stringArray
#warning TODO: Variable scope will need an immutable copy :(
                                               scope:scopeProvider
                                               owner:aSession
                                    useInterpolation:useInterpolation] then:^(NSString * _Nonnull notificationText) {
        [self postNotificationWithText:notificationText
                             inSession:aSession
                                 queue:queue];
    }];
    return YES;
}

- (iTermRateLimitedUpdate *)rateLimit {
    // iTermRateLimitedUpdated only works on the main thread because it uses NSTimer.
    assert([NSThread isMainThread]);
    if (!_rateLimit) {
        _rateLimit = [[iTermRateLimitedUpdate alloc] initWithName:@"UserNotificationTrigger"
                                                  minimumInterval:[iTermAdvancedSettingsModel userNotificationTriggerRateLimit]];
        _rateLimit.suppressionMode = YES;
    }
    return _rateLimit;
}

- (void)postNotificationWithText:(NSString *)notificationText
                       inSession:(id<iTermTriggerSession>)aSession
                           queue:(dispatch_queue_t)queue {
    if (!notificationText) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self rateLimit] performRateLimitedBlock:^{
            dispatch_async(queue, ^{
                [self reallyPostNotificationWithText:notificationText
                                           inSession:aSession];
            });
        }];
    });
}

- (void)reallyPostNotificationWithText:(NSString *)notificationText
                             inSession:(id<iTermTriggerSession>)aSession {
    [aSession triggerSession:self postUserNotificationWithMessage:notificationText];
}

@end
