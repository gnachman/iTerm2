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

- (BOOL)takesParameter {
  return NO;
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    *stop = YES;
    return NO;
}

@end
