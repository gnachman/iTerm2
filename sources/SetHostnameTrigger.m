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

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
  return @"username@hostname";
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
                                   useInterpolation:useInterpolation
                                         completion:^(NSString *remoteHost) {
                                             if (remoteHost.length) {
                                                 [aSession didUseShellIntegration];
                                                 [aSession.screen terminalSetRemoteHost:remoteHost];
                                             }
                                         }];
    return YES;
}

@end
