//
//  CaptureTrigger.m
//  iTerm
//
//  Created by George Nachman on 5/22/14.
//
//

#import "CaptureTrigger.h"

#import "CapturedOutput.h"
#import "iTermAnnouncementViewController.h"
#import "iTermApplicationDelegate.h"
#import "iTermCapturedOutputMark.h"
#import "iTermShellHistoryController.h"
#import "iTermToolbeltView.h"
#import "PTYTab.h"
#import "VT100ScreenMark.h"

@implementation CaptureTrigger

+ (NSString *)title {
    return @"Capture Output";
}

- (BOOL)takesParameter {
    return YES;
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
    return @"Coprocess to run on activation";
}

- (void)showCaptureOutputToolInSession:(id<iTermTriggerSession>)aSession {
    return [aSession triggerSessionShowCapturedOutputTool:self];
}

- (BOOL)performActionWithCapturedStrings:(NSArray<NSString *> *)stringArray
                          capturedRanges:(const NSRange *)capturedRanges
                               inSession:(id<iTermTriggerSession>)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    if (![aSession triggerSessionIsShellIntegrationInstalled:self]) {
        [aSession triggerSessionShowShellIntegrationRequiredAnnouncement:self];
    } else {
        [aSession triggerSessionShowCapturedOutputToolNotVisibleAnnouncementIfNeeded:self];
    }
    CapturedOutput *output = [[[CapturedOutput alloc] init] autorelease];
    output.absoluteLineNumber = lineNumber;
    output.line = stringLine.stringValue;
    output.trigger = self;
    output.values = stringArray;
    [aSession triggerSession:self didCaptureOutput:output];
    return NO;
}

// Called by UI
- (void)activateOnOutput:(CapturedOutput *)capturedOutput inSession:(id<iTermTriggerSession>)session {
    assert([NSThread isMainThread]);
    id<iTermTriggerScopeProvider> scopeProvider = [session triggerSessionVariableScopeProvider:self];
    const BOOL interpolate = [session triggerSessionShouldUseInterpolatedStrings:self];
    [[self paramWithBackreferencesReplacedWithValues:capturedOutput.values
                                               scope:scopeProvider
                                               owner:session
                                    useInterpolation:interpolate] then:^(NSString * _Nonnull command) {
        [session triggerSession:self
     launchCoprocessWithCommand:command
                     identifier:nil
                         silent:NO];
        [session triggerSessionMakeFirstResponder:self];
    }];
}

@end
