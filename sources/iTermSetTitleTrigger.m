//
//  iTermSetTitleTrigger.m
//  iTerm2
//
//  Created by George Nachman on 1/1/17.
//
//

#import "iTermSetTitleTrigger.h"
#import "PTYSession.h"

@implementation iTermSetTitleTrigger

+ (NSString *)title
{
    return @"Set Title…";
}

- (NSString *)paramPlaceholder
{
    return @"Enter new title";
}

- (BOOL)takesParameter
{
    return YES;
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                                    stop:(BOOL *)stop {
    aSession.name = [self paramWithBackreferencesReplacedWithValues:capturedStrings
                                                              count:captureCount];
    return YES;
}

@end
