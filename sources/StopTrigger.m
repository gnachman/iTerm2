//
//  StopTrigger.m
//  iTerm2
//
//  Created by George Nachman on 5/15/15.
//
//

#import "StopTrigger.h"

@implementation StopTrigger

+ (NSString *)title {
  return @"Stop Processing Triggers";
}

- (NSString *)description {
    return [StopTrigger title];
}

- (BOOL)takesParameter {
  return NO;
}

- (BOOL)isIdempotent {
    return YES;
}

- (BOOL)performActionWithCapturedStrings:(NSArray<NSString *> *)stringArray
                          capturedRanges:(const NSRange *)capturedRanges
                               inSession:(id<iTermTriggerSession>)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    *stop = YES;
    return NO;
}

@end
