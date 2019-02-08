//
//  ScriptTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "ScriptTrigger.h"
#import "DebugLogging.h"
#import "PTYSession.h"
#import "RegexKitLite.h"
#import "NSStringITerm.h"
#include <sys/types.h>
#include <pwd.h>

@implementation ScriptTrigger

+ (NSString *)title
{
    return @"Run Command…";
}

- (BOOL)takesParameter
{
    return YES;
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
    return @"Enter command to run";
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
                                         completion:^(NSString *command) {
                                             if (!command) {
                                                 return;
                                             }
                                             [NSThread detachNewThreadSelector:@selector(runCommand:)
                                                                      toTarget:[self class]
                                                                    withObject:command];
                                         }];
    return YES;
}

+ (void)runCommand:(NSString *)command {
    @autoreleasepool {
        // TODO: Use a buried single-purpose window or something somehow less terrible.
        DLog(@"Invoking command %@", command);
        system([command UTF8String]);
    }
}

@end
