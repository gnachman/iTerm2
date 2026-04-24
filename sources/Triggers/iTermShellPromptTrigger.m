//
//  iTermPromptStartTrigger.m
//  iTerm2
//
//  Created by George Nachman on 1/2/17.
//
//

#import "iTermShellPromptTrigger.h"
#import "ScreenChar.h"
#import "VT100GridTypes.h"

@implementation iTermShellPromptTrigger

+ (NSString *)title {
    return @"Prompt Detected";
}

- (NSString *)description {
    return [iTermShellPromptTrigger title];
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
        const NSRange screenCharRange = [stringLine rangeOfScreenCharsForRangeInString:capturedRanges[0]];
        [aSession triggerSession:self
        didDetectPromptAtAbsLine:lineNumber
                           range:screenCharRange];
    }
    return NO;
}

@end
