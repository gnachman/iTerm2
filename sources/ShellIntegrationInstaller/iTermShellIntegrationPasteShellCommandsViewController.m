//
//  iTermShellIntegrationPasteShellCommandsViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/19.
//

#import "iTermShellIntegrationPasteShellCommandsViewController.h"

@interface iTermShellIntegrationPasteShellCommandsViewController ()

@property (nonatomic, strong) IBOutlet NSTextField *textField;
@property (nonatomic, strong) IBOutlet NSButton *previewCommandButton1;
@property (nonatomic, strong) IBOutlet NSButton *previewCommandButton2;
@property (nonatomic, strong) IBOutlet NSButton *previewCommandButton3;
@property (nonatomic, strong) IBOutlet NSButton *previewCommandButton4;
@property (nonatomic, strong) IBOutlet NSTextView *previewTextView;
@property (nonatomic, strong) IBOutlet NSViewController *popoverViewController;
@property (nonatomic, strong) IBOutlet NSPopover *popover;
@property (nonatomic, strong) IBOutlet NSButton *continueButton;
@property (nonatomic, strong) IBOutlet NSButton *skipButton;

@end

@implementation iTermShellIntegrationPasteShellCommandsViewController {
    BOOL _busy;
}

- (void)setShell:(iTermShellIntegrationShell)shell {
    _shell = shell;
    if (shell == iTermShellIntegrationShellUnknown) {
        self.continueButton.enabled = NO;
    } else {
        self.continueButton.enabled = YES;
    }
}

- (void)setStage:(int)stage {
    _stage = stage;
    [self update];
}

- (NSString *)waitingText {
    return NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.WaitingText", nil, [NSBundle mainBundle], @"⏳ Waiting for command to complete…", @"Status shown while waiting for a shell command to finish");
}
- (void)update {
    const int stage = _stage;
    if (stage < 0) {
        self.shell = iTermShellIntegrationShellUnknown;
    }
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSInteger indexToBold = NSNotFound;
    NSString *step;

    // Each step renders a complete localized sentence per state rather than injecting a translated
    // verb phrase into a noun-phrase frame, whose grammar and word order differ by language.
    if (stage < 0) {
        step = NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.Step1Discover", nil, [NSBundle mainBundle], @"1. Discover.", @"Numbered step label for discovering the shell");
    } else if (stage == 0) {
        if (_busy) {
            step = self.waitingText;
        } else {
            step = NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.ContinueToDiscover", nil, [NSBundle mainBundle], @"➡ Select “Continue” to discover.", @"Prompt to continue to the discover shell step");
        }
        indexToBold = lines.count;
    } else {  // stage > 0
        if (self.shell == iTermShellIntegrationShellUnknown) {
            step = NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.ShellNotSupported", nil, [NSBundle mainBundle], @"🛑 Your shell is not supported.\n\nOnly bash, fish, tcsh, xonsh, and zsh work with shell integration", @"Message shown when the detected shell is unsupported");
        } else {
            step = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.Discovered", nil, [NSBundle mainBundle], @"✅ Discovered your shell: you use “%@”.", @"Completed discover step; %@ is the detected shell name"), iTermShellIntegrationShellString(self.shell)];
        }
    }
    [lines addObject:step];

    const BOOL unavailable = (stage == 1 && self.shell == iTermShellIntegrationShellUnknown);
    self.continueButton.enabled = !(unavailable || _busy);
    if (unavailable) {
        self.skipButton.enabled = NO;
    } else {
        if (stage < 1) {
            step = NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.Step2Write", nil, [NSBundle mainBundle], @"Step 2. Write the shell integration script.", @"Numbered step label for writing the shell integration script");
        } else if (stage == 1) {
            if (_busy) {
                step = self.waitingText;
            } else {
                step = NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.ContinueToWrite", nil, [NSBundle mainBundle], @"➡ Select “Continue” to write the shell integration script.", @"Prompt to continue to the write script step");
            }
            indexToBold = lines.count;
        } else {  // stage > 1
            step = NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.Wrote", nil, [NSBundle mainBundle], @"✅ Wrote the shell integration script.", @"Completed write script step");
        }
        [lines addObject:step];

        int i = 2;
        if (self.installUtilities) {
            i += 1;
            if (stage < 2) {
                step = NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.Step3Install", nil, [NSBundle mainBundle], @"Step 3. Install iTerm2 utility scripts.", @"Numbered step label for installing utility scripts");
            } else if (stage == 2 && !_busy) {
                step = NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.ContinueToInstall", nil, [NSBundle mainBundle], @"➡ Select “Continue” to install iTerm2 utility scripts.", @"Prompt to continue to the utility scripts install step");
                indexToBold = lines.count;
            } else if (stage == 2 && _busy) {
                step = self.waitingText;
                indexToBold = lines.count;
            } else {
                step = NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.Installed", nil, [NSBundle mainBundle], @"✅ Installed iTerm2 utility scripts.", @"Completed utility scripts install step");
            }
            [lines addObject:step];
        }

        // Xonsh auto-loads scripts from rc.d, so no dotfile modification is needed.
        // Show this step as already complete for xonsh.
        if (self.shell == iTermShellIntegrationShellXonsh) {
            if (stage < i) {
                step = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.XonshStepFormat", nil, [NSBundle mainBundle], @"Step %d. Xonsh auto-loads scripts from rc.d (no dotfile update needed).", @"Numbered step for xonsh, which needs no dotfile update; %d is the step number"), i + 1];
            } else {
                step = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.XonshDone", nil, [NSBundle mainBundle], @"✅ Xonsh auto-loads scripts from rc.d (no dotfile update needed).", @"Completion message for xonsh, which needs no dotfile update")];
            }
            [lines addObject:step];
        } else {
            if (stage < i) {
                step = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.StepUpdateFormat", nil, [NSBundle mainBundle], @"Step %d. Update your shell’s dotfile.", @"Numbered step label for updating the dotfile; %d is the step number"), i + 1];
            } else if (stage == i && !_busy) {
                step = NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.ContinueToUpdate", nil, [NSBundle mainBundle], @"➡ Select “Continue” to update your shell’s dotfile.", @"Prompt to continue to the dotfile update step");
                indexToBold = lines.count;
            } else if (stage == i && _busy) {
                step = self.waitingText;
                indexToBold = lines.count;
            } else {  // stage > i
                step = NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.Updated", nil, [NSBundle mainBundle], @"✅ Updated your shell’s dotfile.", @"Completed dotfile update step");
            }
            [lines addObject:step];
        }
        
        // For xonsh, stage >= i means we're at the dotfile step which is a no-op,
        // so treat it as done. For other shells, we need stage > i.
        BOOL isDone = (stage > i) || (stage >= i && self.shell == iTermShellIntegrationShellXonsh);
        if (isDone) {
            [lines addObject:@""];
            indexToBold = lines.count;
            [lines addObject:NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.Done", nil, [NSBundle mainBundle], @"Done! Select “Continue” to proceed.", @"Message shown when shell integration install is complete")];
            self.skipButton.enabled = NO;
        } else {
            self.skipButton.enabled = !_busy;
        }
    }

    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.lineSpacing = 4;
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] init];
    NSDictionary *regularAttributes =
    @{ NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]],
       NSForegroundColorAttributeName: [NSColor textColor],
       NSParagraphStyleAttributeName: paragraphStyle
    };
    NSDictionary *boldAttributes =
    @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont systemFontSize]],
       NSForegroundColorAttributeName: [NSColor textColor],
       NSParagraphStyleAttributeName: paragraphStyle
    };
    [lines enumerateObjectsUsingBlock:^(NSString * _Nonnull string, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *temp = [string stringByAppendingString:@"\n"];
        NSAttributedString *as = [[NSAttributedString alloc] initWithString:temp attributes:idx == indexToBold ? boldAttributes : regularAttributes];
        [attributedString appendAttributedString:as];
    }];
    self.textField.attributedStringValue = attributedString;
    NSString *preview = [self.shellInstallerDelegate shellIntegrationInstallerNextCommandForSendShellCommands];
    NSArray<NSButton *> *buttons = self.previewCommandButtons;
    for (NSInteger i = 0; i < self.previewCommandButtons.count; i++){
        buttons[i].hidden = unavailable || (i != stage) || preview == nil;
        if (_busy && i == stage) {
            [buttons[i] setTitle:NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.SendAgain", nil, [NSBundle mainBundle], @"Send Again", @"Button to send the preview command again")];
        } else {
            [buttons[i] setTitle:NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.PreviewCommand", nil, [NSBundle mainBundle], @"Preview Command", @"Button to preview the command that will be sent")];
        }
    }
    self.previewTextView.string = preview ?: @"";
}

- (NSArray<NSButton *> *)previewCommandButtons {
    return @[ self.previewCommandButton1, self.previewCommandButton2, self.previewCommandButton3, self.previewCommandButton4 ];
}

- (NSButton *)previewCommandButton {
    NSArray<NSButton *> *buttons = self.previewCommandButtons;
    if (self.stage < 0 || self.stage >= buttons.count) {
        return nil;
    }
    return buttons[self.stage];
}

- (IBAction)previewCommand:(id)sender {
    if (_busy) {
        [self.shellInstallerDelegate shellIntegrationInstallerCancelExpectations];
        [self.shellInstallerDelegate shellIntegrationInstallerSendShellCommands:_stage];
        return;
    }
    self.popover.behavior = NSPopoverBehaviorTransient;
    [self.popoverViewController view];
    self.previewTextView.font = [NSFont fontWithName:@"Menlo" size:12];
    [self.popover showRelativeToRect:self.previewCommandButton.bounds
                              ofView:self.previewCommandButton
                       preferredEdge:NSRectEdgeMaxY];
}

- (IBAction)skip:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerSkipStage];
}

- (IBAction)next:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerSendShellCommands:_stage];
}

- (IBAction)back:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerCancelExpectations];
    if (_stage == 0) {
        [self.shellInstallerDelegate shellIntegrationInstallerBack];
    } else {
        self.stage = self.stage - 1;
    }
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    [self update];
}

@end

