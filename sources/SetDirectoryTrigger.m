//
//  SetDirectoryTrigger.m
//  iTerm2
//
//  Created by George Nachman on 11/9/15.
//
//

#import "SetDirectoryTrigger.h"
#import "PTYSession.h"
#import "VT100Screen.h"

@implementation SetDirectoryTrigger

+ (NSString *)title {
  return @"Report Directory";
}

- (BOOL)takesParameter{
  return YES;
}

- (NSString *)paramPlaceholder {
  return @"Directory";
}


- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                                    stop:(BOOL *)stop {
  NSString *currentDirectory = [self paramWithBackreferencesReplacedWithValues:capturedStrings
                                                                         count:captureCount];
  if (currentDirectory.length) {
    [aSession.screen terminalCurrentDirectoryDidChangeTo:currentDirectory];
  }
  return YES;
}


@end
