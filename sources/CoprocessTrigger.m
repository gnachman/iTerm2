//
//  InteractiveScriptTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/24/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "CoprocessTrigger.h"
#import "iTermAnnouncementViewController.h"
#import "PTYSession.h"

static NSString *const kSuppressCoprocessTriggerWarning = @"NoSyncSuppressCoprocessTriggerWarning";

@implementation CoprocessTrigger

+ (NSString *)title {
    return @"Run Coprocess…";
}

- (BOOL)takesParameter {
    return YES;
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
    return @"Enter coprocess command to run";
}

- (BOOL)performActionWithCapturedStrings:(NSArray<NSString *> *)stringArray
                          capturedRanges:(const NSRange *)capturedRanges
                               inSession:(id<iTermTriggerSession>)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    // Need to stop the world to get scope, provided it is needed. Coprocesses are so slow & rare that this is ok.
    id<iTermTriggerScopeProvider> scopeProvider = [aSession triggerSessionVariableScopeProvider:self];
    id<iTermTriggerCallbackScheduler> scheduler = [scopeProvider triggerCallbackScheduler];
    [[self paramWithBackreferencesReplacedWithValues:stringArray
                                             absLine:lineNumber
                                               scope:scopeProvider
                                    useInterpolation:useInterpolation] then:^(NSString * _Nonnull command) {
        [scheduler scheduleTriggerCallback:^{
            [aSession triggerSession:self
          launchCoprocessWithCommand:command
                          identifier:kSuppressCoprocessTriggerWarning
                              silent:self.isSilent];
        }];
    }];
    return YES;
}

- (BOOL)isSilent {
    return NO;
}

@end

@implementation MuteCoprocessTrigger

+ (NSString *)title {
    return @"Run Silent Coprocess…";
}

- (BOOL)takesParameter {
    return YES;
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
    return @"Enter coprocess command to run";
}

- (BOOL)isSilent {
    return YES;
}

@end
