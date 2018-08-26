//
//  iTermUserNotificationTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "iTermUserNotificationTrigger.h"
#import "iTermNotificationController.h"
#import "PTYSession.h"
#import "PTYTab.h"

@implementation iTermUserNotificationTrigger

+ (NSString *)title
{
    return @"Post Notification…";
}

- (BOOL)takesParameter
{
    return YES;
}

- (NSString *)paramPlaceholder
{
    return @"Enter Message";
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                                    stop:(BOOL *)stop {
    iTermNotificationController *gd = [iTermNotificationController sharedInstance];
    [gd notify:[self paramWithBackreferencesReplacedWithValues:capturedStrings count:captureCount]
        withDescription:[NSString stringWithFormat:@"A trigger fired in session \"%@\" in tab #%d.",
                         [aSession name],
                         aSession.delegate.tabNumber]
        windowIndex:[aSession screenWindowIndex]
           tabIndex:[aSession screenTabIndex]
          viewIndex:[aSession screenViewIndex]];
    return YES;
}

@end
