//
//  iTermShellIntegrationSecondPageViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/19.
//

#import "iTermShellIntegrationSecondPageViewController.h"

@interface iTermShellIntegrationSecondPageViewController ()

@end

@implementation iTermShellIntegrationSecondPageViewController
- (void)setBusy:(BOOL)busy {
}

- (IBAction)downloadAndRun:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerConfirmDownloadAndRun];
}
- (IBAction)sendShellCommands:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerSendShellCommands:-1];
}
@end
