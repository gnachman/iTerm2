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
#import "PTYSession.h"
#import "PTYTab.h"
#import "VT100ScreenMark.h"

// This one cannot be suppressed.
static NSString *const kTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier =
    @"NoSyncTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier";

static NSString *const kSuppressCaptureOutputRequiresShellIntegrationWarning =
    @"NoSyncSuppressCaptureOutputRequiresShellIntegrationWarning";
static NSString *const kSuppressCaptureOutputToolNotVisibleWarning =
    @"NoSyncSuppressCaptureOutputToolNotVisibleWarning";


@implementation CaptureTrigger

+ (NSString *)title {
    return @"Capture Output";
}

- (BOOL)takesParameter {
    return YES;
}

- (NSString *)paramPlaceholder {
  return @"Coprocess to run on activation";
}

- (BOOL)capturedOutputToolVisibleInSession:(PTYSession *)aSession {
    if (!aSession.delegate.realParentWindow.shouldShowToolbelt) {
        return NO;
    }
    return [iTermToolbeltView shouldShowTool:kCapturedOutputToolName];
}

- (void)showCaptureOutputToolInSession:(PTYSession *)aSession {
    if (!aSession.delegate.realParentWindow.shouldShowToolbelt) {
        [aSession.delegate.realParentWindow toggleToolbeltVisibility:nil];
    }
    if (![iTermToolbeltView shouldShowTool:kCapturedOutputToolName]) {
        [iTermToolbeltView toggleShouldShowTool:kCapturedOutputToolName];
    }
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                                    stop:(BOOL *)stop {
    if (!aSession.screen.shellIntegrationInstalled) {
        if (![[NSUserDefaults standardUserDefaults] boolForKey:kSuppressCaptureOutputRequiresShellIntegrationWarning]) {
            [self showShellIntegrationRequiredAnnouncementInSession:aSession];
        }
    } else if (![self capturedOutputToolVisibleInSession:aSession]) {
        if (![[NSUserDefaults standardUserDefaults] boolForKey:kSuppressCaptureOutputToolNotVisibleWarning]) {
            [self showCapturedOutputToolNotVisibleAnnouncementInSession:aSession];
        }
    }
    CapturedOutput *output = [[[CapturedOutput alloc] init] autorelease];
    output.line = stringLine.stringValue;
    output.trigger = self;
    output.values = [NSArray arrayWithObjects:capturedStrings count:captureCount];
    output.mark = [aSession markAddedAtCursorOfClass:[iTermCapturedOutputMark class]];
    [aSession addCapturedOutput:output];
    return NO;
}

- (void)showCapturedOutputToolNotVisibleAnnouncementInSession:(PTYSession *)aSession {
    if ([aSession hasAnnouncementWithIdentifier:kSuppressCaptureOutputToolNotVisibleWarning]) {
        return;
    }
    NSString *theTitle = @"A Capture Output trigger fired, but the Captured Output tool is not visible.";
    [aSession retain];
    void (^completion)(int selection) = ^(int selection) {
        switch (selection) {
            case -2:
                [aSession release];
                break;

            case 0:
                [self showCaptureOutputToolInSession:aSession];
                break;

            case 1:
                [[NSUserDefaults standardUserDefaults] setBool:YES
                                                        forKey:kSuppressCaptureOutputToolNotVisibleWarning];
                break;
        }
    };
    iTermAnnouncementViewController *announcement =
        [iTermAnnouncementViewController announcementWithTitle:theTitle
                                                         style:kiTermAnnouncementViewStyleWarning
                                                   withActions:@[ @"Show It", @"Silence Warning" ]
                                                    completion:completion];
    announcement.dismissOnKeyDown = YES;
    [aSession queueAnnouncement:announcement
                     identifier:kSuppressCaptureOutputToolNotVisibleWarning];
}

- (void)showShellIntegrationRequiredAnnouncementInSession:(PTYSession *)aSession {
    NSString *theTitle = @"A Capture Output trigger fired, but Shell Integration is not installed.";
    [aSession retain];
    void (^completion)(int selection) = ^(int selection) {
        switch (selection) {
            case -2:
                [aSession release];
                break;

            case 0:
                [aSession tryToRunShellIntegrationInstaller];
                break;

            case 1:
                [[NSUserDefaults standardUserDefaults] setBool:YES
                                                        forKey:kSuppressCaptureOutputRequiresShellIntegrationWarning];
                break;
        }
    };
    iTermAnnouncementViewController *announcement =
        [iTermAnnouncementViewController announcementWithTitle:theTitle
                                                         style:kiTermAnnouncementViewStyleWarning
                                                   withActions:@[ @"Install", @"Silence Warning" ]
                                                    completion:completion];
    [aSession queueAnnouncement:announcement
                     identifier:kTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier];
}

- (void)activateOnOutput:(CapturedOutput *)capturedOutput inSession:(PTYSession *)session {
    if (!session.hasCoprocess) {
        NSString *command = [self paramWithBackreferencesReplacedWithValues:capturedOutput.values];
        if (command) {
            [session launchCoprocessWithCommand:command];
        }
    } else {
        iTermAnnouncementViewController *announcement =
            [iTermAnnouncementViewController announcementWithTitle:@"Can't run two coprocesses at once."
                                                             style:kiTermAnnouncementViewStyleWarning
                                                       withActions:@[ ]
                                                        completion:^(int selection) { }];
        announcement.timeout = 2;
        [session queueAnnouncement:announcement
                        identifier:kTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier];
    }
    [session takeFocus];
}

@end
