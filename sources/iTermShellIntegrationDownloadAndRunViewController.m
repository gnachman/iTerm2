//
//  iTermShellIntegrationDownloadAndRunViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/19.
//

#import "iTermShellIntegrationDownloadAndRunViewController.h"

@interface iTermShellIntegrationDownloadAndRunViewController ()

@property (nonatomic, weak) IBOutlet id<iTermShellIntegrationInstallerDelegate> shellInstallerDelegate;
@property (nonatomic, strong) IBOutlet NSButton *continueButton;
@property (nonatomic, strong) IBOutlet NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) IBOutlet NSTextField *textField;

@end

@implementation iTermShellIntegrationDownloadAndRunViewController

- (void)willAppear {
    self.continueButton.enabled = YES;
    self.progressIndicator.hidden = YES;
    [self setInstallUtilities:_installUtilities];
}

- (NSString *)urlString {
    if (self.installUtilities) {
        return @"https://iterm2.com/shell_integration/install_shell_integration_and_utilities.sh";
    }
    return @"https://iterm2.com/shell_integration/install_shell_integration.sh";
}

- (NSString *)command {
    return [NSString stringWithFormat:@"\ncurl -L %@ | bash", self.urlString];
}

- (void)setInstallUtilities:(BOOL)installUtilities {
    _installUtilities = installUtilities;
    NSString *prefix = self.busy ? @"Waiting for this command to finish:" : @"Press “Continue” to run this command:";
    self.textField.stringValue = [NSString stringWithFormat:@"%@\n%@", prefix, self.command];
}

- (void)showShellUnsupportedError {
    self.textField.stringValue = @"😞 Your shell is not supported, or perhaps your $SHELL environment variable is not set correctly. Press “Continue” to try again.";
}

- (IBAction)pipeCurlToBash:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerReallyDownloadAndRun];
    self.continueButton.enabled = NO;
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    self.continueButton.enabled = !busy;
    self.progressIndicator.hidden = !busy;
    if (busy) {
        [self.progressIndicator startAnimation:nil];
    } else {
        [self.progressIndicator stopAnimation:nil];
    }
}

@end

