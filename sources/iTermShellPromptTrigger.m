//
//  iTermPromptStartTrigger.m
//  iTerm2
//
//  Created by George Nachman on 1/2/17.
//
//

#import "iTermShellPromptTrigger.h"
#import "PTYSession.h"

@implementation iTermShellPromptTrigger

+ (NSString *)title {
    return @"Prompt Detected";
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
    if (captureCount > 0) {
        [aSession triggerDidDetectStartOfPromptAt:VT100GridAbsCoordMake(capturedRanges[0].location, lineNumber)];
        [aSession triggerDidDetectEndOfPromptAt:VT100GridAbsCoordMake(NSMaxRange(capturedRanges[0]), lineNumber)];
    }
    return NO;
}

@end
