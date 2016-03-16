//
//  GrowlTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "GrowlTrigger.h"
#import "iTermGrowlDelegate.h"
#import "PTYSession.h"
#import "PTYTab.h"

@implementation GrowlTrigger

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
    iTermGrowlDelegate *gd = [iTermGrowlDelegate sharedInstance];
    [gd growlNotify:[self paramWithBackreferencesReplacedWithValues:capturedStrings count:captureCount]
        withDescription:[NSString stringWithFormat:@"A trigger fired in session \"%@\" in tab #%d.",
                         [aSession name],
                         aSession.delegate.tabNumber]
        andNotification:@"Customized Message"
        windowIndex:[aSession screenWindowIndex]
           tabIndex:[aSession screenTabIndex]
          viewIndex:[aSession screenViewIndex]];
    return YES;
}

@end
