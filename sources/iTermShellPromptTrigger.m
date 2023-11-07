//
//  iTermPromptStartTrigger.m
//  iTerm2
//
//  Created by George Nachman on 1/2/17.
//
//

#import "iTermShellPromptTrigger.h"
#import "VT100GridTypes.h"

@implementation iTermShellPromptTrigger

+ (NSString *)title {
    return @"Prompt Detected";
}

- (BOOL)takesParameter {
    return NO;
}

- (BOOL)isIdempotent {
    return YES;
}

- (BOOL)detectsPrompt {
    return YES;
}

- (BOOL)performActionWithCapturedStrings:(NSArray<NSString *> *)stringArray
                          capturedRanges:(const NSRange *)capturedRanges
                               inSession:(id<iTermTriggerSession>)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    if (stringArray.count > 0) {
        VT100GridAbsCoordRange range = VT100GridAbsCoordRangeMake(capturedRanges[0].location, lineNumber, NSMaxRange(capturedRanges[0]), lineNumber);
        [aSession triggerSession:self didDetectPromptAt:range];
    }
    return NO;
}

@end
