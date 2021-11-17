//
//  ScriptTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "ScriptTrigger.h"
#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermBackgroundCommandRunner.h"
#import "iTermCommandRunnerPool.h"
#import "PTYSession.h"
#import "RegexKitLite.h"
#import "NSStringITerm.h"
#include <sys/types.h>
#include <pwd.h>

@implementation ScriptTrigger

+ (iTermBackgroundCommandRunnerPool *)commandRunnerPool {
    static iTermBackgroundCommandRunnerPool *pool;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pool = [[iTermBackgroundCommandRunnerPool alloc] initWithCapacity:[iTermAdvancedSettingsModel maximumNumberOfTriggerCommands]];
    });
    return pool;
}

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
                                              owner:aSession
                                   useInterpolation:useInterpolation
                                         completion:^(NSString *command) {
        if (!command) {
            return;
        }
        [self runCommand:command session:aSession];
    }];
    return YES;
}

- (void)runCommand:(NSString *)command session:(PTYSession *)session {
    DLog(@"Invoking command %@", command);
    iTermBackgroundCommandRunner *runner = [[ScriptTrigger commandRunnerPool] requestBackgroundCommandRunnerWithTerminationBlock:nil];
    runner.command = command;
    runner.shell = session.userShell;
    runner.title = @"Run Command Trigger";
    runner.notificationTitle = @"Run Command Trigger Failed";
    [runner run];
}

@end
