//
//  SetDirectoryTrigger.m
//  iTerm2
//
//  Created by George Nachman on 11/9/15.
//
//

#import "SetDirectoryTrigger.h"

#import "DebugLogging.h"
#import "PTYSession.h"
#import "VT100Screen.h"

@implementation SetDirectoryTrigger

+ (NSString *)title {
  return @"Report Directory";
}

- (BOOL)takesParameter{
  return YES;
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
  return @"Directory";
}

- (BOOL)isIdempotent {
    return YES;
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    [self paramWithBackreferencesReplacedWithValues:capturedStrings
                                              count:captureCount
                                              scope:aSession.variablesScope
                                              owner:aSession
                                   useInterpolation:useInterpolation
                                         completion:^(NSString *currentDirectory) {
        DLog(@"SetDirectoryTrigger completed substitution with %@", currentDirectory);
        if (currentDirectory.length) {
            [aSession didUpdateCurrentDirectory];
            [aSession.screen terminalCurrentDirectoryDidChangeTo:currentDirectory];
        }
    }];
    return YES;
}


@end
