//
//  AnnotateTrigger.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/13/19.
//

#import "AnnotateTrigger.h"
#import "PTYSession.h"

@implementation AnnotateTrigger

+ (NSString *)title
{
    return @"Annotate…";
}

- (BOOL)takesParameter
{
    return YES;
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
    return @"Enter annotation";
}


- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    const NSRange rangeInString = capturedRanges[0];
    const NSRange rangeInScreenChars = [stringLine rangeOfScreenCharsForRangeInString:rangeInString];
    const long long length = rangeInScreenChars.length;
    if (length == 0) {
        return YES;
    }
    const long long width = aSession.screen.width;
    VT100GridAbsCoordRange absRange = VT100GridAbsCoordRangeMake(rangeInScreenChars.location,
                                                                 lineNumber,
                                                                 (rangeInScreenChars.location + length) % width,
                                                                 lineNumber + (rangeInScreenChars.location + length - 1) / width);
    [self paramWithBackreferencesReplacedWithValues:capturedStrings
                                              count:captureCount
                                              scope:aSession.variablesScope
                                   useInterpolation:useInterpolation
                                         completion:^(NSString *annotation) {
                                             if (!annotation.length) {
                                                 return;
                                             }
                                             [aSession addNoteWithText:annotation inAbsoluteRange:absRange];
                                         }];
    return YES;
}

@end
