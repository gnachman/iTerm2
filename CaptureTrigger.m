//
//  CaptureTrigger.m
//  iTerm
//
//  Created by George Nachman on 5/22/14.
//
//

#import "CaptureTrigger.h"
#import "CommandHistory.h"
#import "iTermAnnouncementViewController.h"
#import "iTermApplicationDelegate.h"
#import "PTYSession.h"
#import "ToolbeltView.h"

static NSString *const kTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier =
    @"kTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier";
static NSString *const kSuppressCaptureOutputRequiresShellIntegrationWarning =
    @"kSuppressCaptureOutputRequiresShellIntegrationWarning";
static NSString *const kSuppressCaptureOutputToolNotVisibleWarning =
    @"kSuppressCaptureOutputToolNotVisibleWarning";

@implementation CapturedOutput

- (void)dealloc {
    [_values release];
    [_trigger release];
    [super dealloc];
}

@end


@implementation CaptureTrigger

- (NSString *)title {
    return @"Capture Output";
}

- (BOOL)takesParameter {
    return YES;
}

- (NSString *)paramPlaceholder {
  return @"Coprocess to run on activation";
}

- (BOOL)capturedOutputToolVisible {
    iTermApplicationDelegate *delegate = (iTermApplicationDelegate *)[NSApp delegate];
    if (![delegate showToolbelt]) {
        return NO;
    }
    return [ToolbeltView shouldShowTool:kCapturedOutputToolName];
}

- (void)showCaptureOutputTool {
    iTermApplicationDelegate *delegate = (iTermApplicationDelegate *)[NSApp delegate];
    if (![delegate showToolbelt]) {
        [delegate toggleToolbelt:nil];
    }
    if (![ToolbeltView shouldShowTool:kCapturedOutputToolName]) {
        [ToolbeltView toggleShouldShowTool:kCapturedOutputToolName];
    }
}

- (BOOL)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession onString:(NSString *)string atAbsoluteLineNumber:(long long)absoluteLineNumber {
    if (!aSession.screen.shellIntegrationInstalled) {
        if (![[NSUserDefaults standardUserDefaults] boolForKey:kSuppressCaptureOutputRequiresShellIntegrationWarning]) {
            [self showShellIntegrationRequiredAnnouncementInSession:aSession];
        }
    } else if (![self capturedOutputToolVisible]) {
        if (![[NSUserDefaults standardUserDefaults] boolForKey:kSuppressCaptureOutputToolNotVisibleWarning]) {
            [self showCapturedOutputToolNotVisibleAnnouncementInSession:aSession];
        }
    }
    CapturedOutput *output = [[[CapturedOutput alloc] init] autorelease];
    output.line = string;
    output.trigger = self;
    output.values = values;
    output.absoluteLineNumber = absoluteLineNumber;
    [aSession addCapturedOutput:output];
    return NO;
}

- (void)showCapturedOutputToolNotVisibleAnnouncementInSession:(PTYSession *)aSession {
    NSString *theTitle = @"A Capture Output trigger fired, but the Captured Output tool is not visible.";
    [aSession retain];
    void (^completion)(int selection) = ^(int selection) {
        switch (selection) {
            case 0:
                [self showCaptureOutputTool];
                break;
                
            case 1:
                [[NSUserDefaults standardUserDefaults] setBool:YES
                                                        forKey:kSuppressCaptureOutputToolNotVisibleWarning];
                break;
        }
        [aSession release];
    };
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcemenWithTitle:theTitle
                                                    style:kiTermAnnouncementViewStyleWarning
                                              withActions:@[ @"Show It", @"Ignore" ]
                                               completion:completion];
    [aSession queueAnnouncement:announcement
                     identifier:kTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier];
}

- (void)showShellIntegrationRequiredAnnouncementInSession:(PTYSession *)aSession {
    NSString *theTitle = @"A Capture Output trigger fired, but Shell Integration is not installed.";
    [aSession retain];
    void (^completion)(int selection) = ^(int selection) {
        switch (selection) {
            case 0:
                [aSession tryToRunShellIntegrationInstaller];
                break;
                
            case 1:
                [[NSUserDefaults standardUserDefaults] setBool:YES
                                                        forKey:kSuppressCaptureOutputRequiresShellIntegrationWarning];
                break;
        }
        [aSession release];
    };
    iTermAnnouncementViewController *announcement =
        [iTermAnnouncementViewController announcemenWithTitle:theTitle
                                                        style:kiTermAnnouncementViewStyleWarning
                                                  withActions:@[ @"Install", @"Ignore" ]
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
            [iTermAnnouncementViewController announcemenWithTitle:@"Can't run two coprocesses at once."
                                                            style:kiTermAnnouncementViewStyleWarning
                                                      withActions:@[ ]
                                                       completion:^(int selection) { }];
        [session queueAnnouncement:announcement
                        identifier:kTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier];
    }
    [session takeFocus];
}

@end
