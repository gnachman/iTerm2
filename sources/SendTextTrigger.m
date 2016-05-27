//
//  SendTextTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/24/11.
//

#import "SendTextTrigger.h"
#import "PTYSession.h"

@implementation SendTextTrigger

+ (NSString *)title
{
    return @"Send Text…";
}

- (BOOL)takesParameter
{
    return YES;
}

- (NSString *)paramPlaceholder
{
    return @"Enter text to send";
}


- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                                    stop:(BOOL *)stop {
    NSString *message = [self paramWithBackreferencesReplacedWithValues:capturedStrings
                                                                  count:captureCount];
    [aSession writeTaskNoBroadcast:message];
    return YES;
}

@end
