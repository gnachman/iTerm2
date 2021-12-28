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

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
    return @"Enter text to send";
}


- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(id<iTermTriggerSession>)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    // Need to stop the world to get scope, provided it is needed. This will be a modest performance issue at most.
    [self paramWithBackreferencesReplacedWithValues:capturedStrings
                                              count:captureCount
                                              scope:[aSession triggerSessionVariableScope:self]
                                              owner:aSession
                                   useInterpolation:useInterpolation
                                         completion:^(NSString *message) {
        if (!message) {
            return;
        }
        [aSession triggerSession:self writeText:message];
    }];
    return YES;
}

@end
