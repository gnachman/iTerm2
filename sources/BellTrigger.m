//
//  BellTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "BellTrigger.h"

#import "DebugLogging.h"
#import "VT100Screen.h"

@implementation BellTrigger

+ (NSString *)title
{
    return @"Ring Bell";
}

- (BOOL)takesParameter
{
    return NO;
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(id<iTermTriggerSession>)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    DLog(@"Ring bell trigger running");
    [aSession triggerSessionRingBell:self];
    return YES;
}

@end
