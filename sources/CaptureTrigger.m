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
    const BOOL interpolate = [aSession triggerSessionShouldUseInterpolatedStrings:self];
    output.promisedCommand = [self paramWithBackreferencesReplacedWithValues:stringArray
                                                                     absLine:lineNumber
                                                                       scope:[aSession triggerSessionVariableScopeProvider:self]
                                                            useInterpolation:interpolate];
    output.values = stringArray;
    [aSession triggerSession:self didCaptureOutput:output];
    return NO;
}

@end
