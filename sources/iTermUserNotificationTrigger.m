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

+ (NSString *)title
{
    return @"Post Notification…";
}

- (BOOL)takesParameter
{
    return YES;
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
    return @"Enter Message";
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    [self paramWithBackreferencesReplacedWithValues:capturedStrings
                                              count:captureCount
                                              scope:aSession.variablesScope
                                              owner:aSession
                                   useInterpolation:useInterpolation
                                         completion:^(NSString *notificationText) {
                                             [self postNotificationWithText:notificationText inSession:aSession];
                                         }];
    return YES;
}

- (iTermRateLimitedUpdate *)rateLimit {
    if (!_rateLimit) {
        _rateLimit = [[iTermRateLimitedUpdate alloc] initWithName:@"UserNotificationTrigger"
                                                  minimumInterval:[iTermAdvancedSettingsModel userNotificationTriggerRateLimit]];
        _rateLimit.suppressionMode = YES;
    }
    return _rateLimit;
}

- (void)postNotificationWithText:(NSString *)notificationText
                       inSession:(PTYSession *)aSession {
    if (!notificationText) {
        return;
    }
    [[self rateLimit] performRateLimitedBlock:^{
        [self reallyPostNotificationWithText:notificationText
                                   inSession:aSession];
    }];
}

- (void)reallyPostNotificationWithText:(NSString *)notificationText
                             inSession:(PTYSession *)aSession {
    iTermNotificationController *notificationController = [iTermNotificationController sharedInstance];
    [notificationController notify:notificationText
                   withDescription:[NSString stringWithFormat:@"A trigger fired in session \"%@\" in tab #%d.",
                                    [[aSession name] removingHTMLFromTabTitleIfNeeded]
                                    ,
                                    aSession.delegate.tabNumber]
                       windowIndex:[aSession screenWindowIndex]
                          tabIndex:[aSession screenTabIndex]
                         viewIndex:[aSession screenViewIndex]];
}

@end
