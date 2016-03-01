//
//  SetHostnameTrigger.m
//  iTerm2
//
//  Created by George Nachman on 11/9/15.
//
//

#import "SetHostnameTrigger.h"
#import "PTYSession.h"
#import "VT100Screen.h"

@implementation SetHostnameTrigger

+ (NSString *)title {
  return @"Report User & Host";
}

- (BOOL)takesParameter{
  return YES;
}

- (NSString *)paramPlaceholder {
  return @"username@hostname";
}


- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                                    stop:(BOOL *)stop {
  NSString *remoteHost = [self paramWithBackreferencesReplacedWithValues:capturedStrings
                                                                   count:captureCount];
  if (remoteHost.length) {
    [aSession.screen terminalSetRemoteHost:remoteHost];
  }
  return YES;
}

@end
