//
//  iTermPromptStartTrigger.m
//  iTerm2
//
//  Created by George Nachman on 1/2/17.
//
//

#import "iTermPromptStartTrigger.h"
#import "PTYSession.h"

@implementation iTermPromptStartTrigger

+ (NSString *)title {
    return @"Mark as Shell Prompt";
}

- (BOOL)takesParameter {
    return NO;
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                                    stop:(BOOL *)stop {
    [aSession triggerDidDetectStartOfPromptAtAbsoluteLine:lineNumber];
    return NO;
}

@end
