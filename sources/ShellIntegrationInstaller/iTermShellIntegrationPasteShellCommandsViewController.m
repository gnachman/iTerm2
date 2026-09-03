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
    return ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_Facing_WaitingForCommandToComplete", @"⏳ Waiting for command to complete…", @"Text shown in waitingText: ⏳ Waiting for command to complete…");
}
- (void)update {
    const int stage = _stage;
    if (stage < 0) {
        self.shell = iTermShellIntegrationShellUnknown;
    }
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSInteger indexToBold = NSNotFound;
    NSString *step;
    NSString *prefix;

    if (stage < 0) {
        prefix = ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_Facing_1Discover", @"1. Discover", @"Text shown in update: 1. Discover");
    } else if (stage == 0) {
        if (_busy) {
            prefix = self.waitingText;
        } else {
            prefix = ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_Facing_SelectContinueToDiscover", @"➡ Select “Continue” to discover", @"Text shown in update: ➡ Select “Continue” to discover");
        }
        indexToBold = lines.count;
    } else if (stage > 0) {
        if (self.shell == iTermShellIntegrationShellUnknown) {
            prefix = ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_Facing_YourShellIsNotSupportedNN", @"🛑 Your shell is not supported.\n\nOnly bash, fish, tcsh, xonsh, and zsh work with shell integration", @"Warning when the current shell is unsupported");
        } else {
            prefix = ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_Facing_Discovered", @"✅ Discovered", @"Text shown in update: ✅ Discovered");
        }
    }
    if (self.shell == iTermShellIntegrationShellUnknown || (_busy && stage == 0)) {
        step = prefix;
    } else {
        step = [NSString stringWithFormat:ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_FormattedFacing_YourShell_FORMAT", @"%1$@ your shell",@"Formatted user-facing text in update"), prefix];
    }
    if (stage > 0) {
        if (self.shell != iTermShellIntegrationShellUnknown) {
            step = [step stringByAppendingFormat:ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_FormattedFacing_YouUse_FORMAT", @": you use “%1$@”.",@"Formatted user-facing text in update"), iTermShellIntegrationShellString(self.shell)];
        }
    } else if (stage != 0 || !_busy) {
        step = [step stringByAppendingString:@"."];
    }
    [lines addObject:step];

    const BOOL unavailable = (stage == 1 && self.shell == iTermShellIntegrationShellUnknown);
    self.continueButton.enabled = !(unavailable || _busy);
    if (unavailable) {
        self.skipButton.enabled = NO;
    } else {
        if (stage < 1) {
            prefix = ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_Facing_Step2Write", @"Step 2. Write", @"Text shown in update: Step 2. Write");
        } else if (stage == 1) {
            if (self.shell == iTermShellIntegrationShellUnknown) {
                prefix = ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_Facing_Step2Write", @"Step 2. Write", @"Text shown in update: Step 2. Write");
            } else if (_busy) {
                prefix = self.waitingText;
            } else {
                prefix = ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_Facing_SelectContinueToWrite", @"➡ Select “Continue” to write", @"Text shown in update: ➡ Select “Continue” to write");
            }
            indexToBold = lines.count;
        } else if (stage > 1) {
            prefix = ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_Facing_Wrote", @"✅ Wrote", @"Text shown in update: ✅ Wrote");
        }
        if (_busy && stage == 1) {
            step = prefix;
        } else {
            step = [NSString stringWithFormat:ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_FormattedFacing_TheShellIntegrationScript_FORMAT", @"%1$@ the shell integration script.",@"Formatted user-facing text in update"), prefix];
        }
        [lines addObject:step];

        int i = 2;
        if (self.installUtilities) {
            i += 1;
            if (stage < 2) {
                prefix = ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_Facing_Step3Install", @"Step 3. Install", @"Text shown in update: Step 3. Install");
            } else if (stage == 2 && !_busy) {
                prefix = ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_Facing_SelectContinueToInstall", @"➡ Select “Continue” to install", @"Text shown in update: ➡ Select “Continue” to install");
                indexToBold = lines.count;
            } else if (stage == 2 && _busy) {
                prefix = self.waitingText;
                indexToBold = lines.count;
            } else {
                prefix = ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_Facing_Installed", @"✅ Installed", @"Text shown in update: ✅ Installed");
            }
            if (_busy && stage == 2) {
                step = prefix;
            } else {
                step = [NSString stringWithFormat:ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_FormattedFacing_ITerm2UtilityScripts_FORMAT", @"%1$@ iTerm2 utility scripts.",@"Formatted user-facing text in update"), prefix];
            }
            [lines addObject:step];
        }

        // Xonsh auto-loads scripts from rc.d, so no dotfile modification is needed.
        // Show this step as already complete for xonsh.
        if (self.shell == iTermShellIntegrationShellXonsh) {
            if (stage < i) {
                step = [NSString stringWithFormat:ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_FormattedFacing_StepXonshAutoLoadsScriptsFromRc_FORMAT", @"Step %1$d. Xonsh auto-loads scripts from rc.d (no dotfile update needed).",@"Formatted user-facing text in update"), i + 1];
            } else {
                step = [NSString stringWithFormat:ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_FormattedFacing_XonshAutoLoadsScriptsFromRcD", @"✅ Xonsh auto-loads scripts from rc.d (no dotfile update needed).",@"Formatted user-facing text in update")];
            }
            [lines addObject:step];
        } else {
            if (stage < i) {
                prefix = [NSString stringWithFormat:ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_FormattedFacing_StepUpdate_FORMAT", @"Step %1$d. Update",@"Formatted user-facing text in update"), i + 1];
            } else if (stage == i && !_busy) {
                prefix = ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_Facing_SelectContinueToUpdate", @"➡ Select “Continue” to update", @"Text shown in update: ➡ Select “Continue” to update");
                indexToBold = lines.count;
            } else if (stage == i && _busy) {
                prefix = self.waitingText;
                indexToBold = lines.count;
            } else if (stage > i) {
                prefix = ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_Facing_Updated", @"✅ Updated", @"Text shown in update: ✅ Updated");
            }
            if (_busy && stage == i) {
                step = prefix;
            } else {
                step =
                [NSString stringWithFormat:ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_FormattedFacing_YourShellSDotfile_FORMAT", @"%1$@ your shell's dotfile.",@"Formatted user-facing text in update"), prefix];
            }
            [lines addObject:step];
        }
        
        // For xonsh, stage >= i means we're at the dotfile step which is a no-op,
        // so treat it as done. For other shells, we need stage > i.
        BOOL isDone = (stage > i) || (stage >= i && self.shell == iTermShellIntegrationShellXonsh);
        if (isDone) {
            [lines addObject:@""];
            indexToBold = lines.count;
            [lines addObject:ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_Facing_DoneSelectContinueToProceed", @"Done! Select “Continue” to proceed.", @"Text shown in update: Done! Select “Continue” to proceed.")];
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
            [buttons[i] setTitle:ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_Menu_SendAgain", @"Send Again", @"Button title in update")];
        } else {
            [buttons[i] setTitle:ITLocalize(@"ShellIntegrationPasteShellCommandsViewController_Menu_PreviewCommand", @"Preview Command", @"Button title in update")];
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

