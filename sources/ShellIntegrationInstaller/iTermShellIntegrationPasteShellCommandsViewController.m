//
//  iTermShellIntegrationPasteShellCommandsViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/19.
//

#import "iTermShellIntegrationPasteShellCommandsViewController.h"

#import "DebugLogging.h"

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
    // The step list's height in the nib, which is the least it ever gets.
    CGFloat _minimumStepListHeight;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [self fitBottomButtonsToTitles];
    [self fitPreviewCommandButtonsToTitles:@[ self.previewCommandTitle, self.sendAgainTitle ]];
}

- (NSString *)previewCommandTitle {
    return NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.PreviewCommand", nil, [NSBundle mainBundle], @"Preview Command", @"Button to preview the command that will be sent");
}

- (NSString *)sendAgainTitle {
    return NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.SendAgain", nil, [NSBundle mainBundle], @"Send Again", @"Button to send the preview command again");
}

// The preview buttons beside the step list get their titles in -update, and a translation can be
// wider than the English. Widen them to fit the widest title they can show, keeping their right
// edge, and narrow the step list beside them if they would otherwise overlap it.
- (void)fitPreviewCommandButtonsToTitles:(NSArray<NSString *> *)titles {
    NSTextField *field = self.textField;
    CGFloat neededWidth = 0;
    for (NSButton *button in self.previewCommandButtons) {
        NSString *savedTitle = button.title;
        for (NSString *title in titles) {
            button.title = title;
            neededWidth = MAX(neededWidth, ceil(button.cell.cellSize.width));
        }
        button.title = savedTitle;
    }
    for (NSButton *button in self.previewCommandButtons) {
        NSRect frame = button.frame;
        if (neededWidth <= NSWidth(frame)) {
            continue;
        }
        DLog(@"Widen preview command button from %@ to %@", @(NSWidth(frame)), @(neededWidth));
        // Keep the nib's spacing between the step list and the buttons.
        const CGFloat gap = field ? NSMinX(frame) - NSMaxX(field.frame) : 0;
        frame.origin.x = NSMaxX(frame) - neededWidth;
        frame.size.width = neededWidth;
        button.frame = frame;
        if (field && NSMaxX(field.frame) > NSMinX(frame) - gap) {
            NSRect fieldFrame = field.frame;
            fieldFrame.size.width = NSMinX(frame) - gap - NSMinX(fieldFrame);
            field.frame = fieldFrame;
        }
    }
}

// A translation of Cancel, Skip or Continue can be wider than the English. Widen any that need it
// and lay the row out again from the right edge, keeping the spacing from the nib.
- (void)fitBottomButtonsToTitles {
    NSButton *continueButton = self.continueButton;
    NSView *view = self.view;
    if (!continueButton || !view) {
        return;
    }
    NSMutableArray<NSButton *> *row = [NSMutableArray array];
    for (NSView *subview in view.subviews) {
        if ([subview isKindOfClass:[NSButton class]] &&
            NSMinY(subview.frame) == NSMinY(continueButton.frame) &&
            NSMinX(subview.frame) > NSWidth(view.bounds) / 3) {
            [row addObject:(NSButton *)subview];
        }
    }
    [row sortUsingComparator:^NSComparisonResult(NSButton *lhs, NSButton *rhs) {
        return [@(NSMinX(rhs.frame)) compare:@(NSMinX(lhs.frame))];
    }];
    if (row.count == 0) {
        return;
    }
    // Spacing between adjacent buttons in the nib, right to left.
    NSMutableArray<NSNumber *> *gaps = [NSMutableArray array];
    for (NSUInteger i = 1; i < row.count; i++) {
        [gaps addObject:@(NSMinX(row[i - 1].frame) - NSMaxX(row[i].frame))];
    }
    CGFloat maxX = NSMaxX(row.firstObject.frame);
    for (NSUInteger i = 0; i < row.count; i++) {
        NSButton *button = row[i];
        NSRect frame = button.frame;
        frame.size.width = MAX(NSWidth(frame), ceil(button.cell.cellSize.width));
        frame.origin.x = maxX - NSWidth(frame);
        button.frame = frame;
        if (i < gaps.count) {
            maxX = NSMinX(frame) - gaps[i].doubleValue;
        }
    }
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
    _writeFailed = NO;
    _discoveryFoundHelperShell = NO;
    [self update];
}

- (void)setDiscoveryFoundHelperShell:(BOOL)discoveryFoundHelperShell {
    _discoveryFoundHelperShell = discoveryFoundHelperShell;
    [self update];
}

- (void)setWriteFailed:(BOOL)writeFailed {
    _writeFailed = writeFailed;
    [self update];
}

- (NSTextField *)stepListField {
    return self.textField;
}

- (NSString *)waitingText {
    return NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.WaitingText", nil, [NSBundle mainBundle], @"⏳ Waiting for command to complete…", @"Status shown while waiting for a shell command to finish");
}

// The dotfile step for a shell that auto-loads the script, which is a no-op.
- (NSString *)autoloadStepFormat {
    if (self.shell == iTermShellIntegrationShellNu) {
        return NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.NuStepFormat", nil, [NSBundle mainBundle], @"Step %d. nushell auto-loads scripts from its autoload directory (no dotfile update needed).", @"Numbered step for nushell, which needs no dotfile update; %d is the step number");
    }
    return NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.XonshStepFormat", nil, [NSBundle mainBundle], @"Step %d. Xonsh auto-loads scripts from rc.d (no dotfile update needed).", @"Numbered step for xonsh, which needs no dotfile update; %d is the step number");
}

- (NSString *)autoloadDoneMessage {
    if (self.shell == iTermShellIntegrationShellNu) {
        return NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.NuDone", nil, [NSBundle mainBundle], @"✅ nushell auto-loads scripts from its autoload directory (no dotfile update needed).", @"Completion message for nushell, which needs no dotfile update");
    }
    return NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.XonshDone", nil, [NSBundle mainBundle], @"✅ Xonsh auto-loads scripts from rc.d (no dotfile update needed).", @"Completion message for xonsh, which needs no dotfile update");
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
        } else if (_discoveryFoundHelperShell) {
            step = NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.DiscoveredHelperShell", nil, [NSBundle mainBundle], @"🛑 The terminal is in a helper shell that an earlier install left running, not in your own shell. Enter “exit” until your own shell’s prompt is back, then select “Continue” to try again.", @"Shown when discovering the shell finds a helper shell (with a “>> ” prompt) that a canceled shell integration install left running in the terminal, instead of the user's own shell");
        } else {
            step = NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.ContinueToDiscover", nil, [NSBundle mainBundle], @"➡ Select “Continue” to discover.", @"Prompt to continue to the discover shell step");
        }
        indexToBold = lines.count;
    } else {  // stage > 0
        if (self.shell == iTermShellIntegrationShellUnknown) {
            step = NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.ShellNotSupported", nil, [NSBundle mainBundle], @"🛑 Your shell is not supported.\n\nOnly bash, fish, nu, tcsh, xonsh, and zsh work with shell integration", @"Message shown when the detected shell is unsupported");
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
            } else if (_writeFailed) {
                step = NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.WriteFailed", nil, [NSBundle mainBundle], @"🛑 The shell integration script was not written. Check the terminal for errors, then select “Continue” to try again.", @"Shown when the command that writes the shell integration script reports that the file was not written");
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
            } else if (stage == 2 && !_busy && _writeFailed) {
                step = NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.InstallFailed", nil, [NSBundle mainBundle], @"🛑 The iTerm2 utility scripts were not installed. Check the terminal for errors, then select “Continue” to try again.", @"Shown when the command that installs the iTerm2 utility scripts reports that they could not be extracted");
                indexToBold = lines.count;
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

        // A shell that auto-loads the script needs no dotfile modification. Show this step as
        // already complete for it.
        if (iTermShellIntegrationShellLoadsScriptAutomatically(self.shell)) {
            if (stage < i) {
                step = [NSString stringWithFormat:[self autoloadStepFormat], i + 1];
            } else {
                step = [self autoloadDoneMessage];
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
        
        // For a shell that auto-loads the script, stage >= i means we're at the dotfile step
        // which is a no-op, so treat it as done. For other shells, we need stage > i.
        BOOL isDone = (stage > i) || (stage >= i && iTermShellIntegrationShellLoadsScriptAutomatically(self.shell));
        if (isDone) {
            [lines addObject:@""];
            indexToBold = lines.count;
            [lines addObject:NSLocalizedStringWithDefaultValue(@"ShellIntegrationInstaller.Done", nil, [NSBundle mainBundle], @"Done! Select “Continue” to proceed.", @"Message shown when shell integration install is complete")];
            self.skipButton.enabled = NO;
        } else {
            // Discovery can't be skipped because every later stage depends on what it finds.
            self.skipButton.enabled = !_busy && stage > 0;
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
    [self sizeStepListToFit];
    NSString *preview = [self.shellInstallerDelegate shellIntegrationInstallerNextCommandForSendShellCommands];
    NSArray<NSButton *> *buttons = self.previewCommandButtons;
    for (NSInteger i = 0; i < self.previewCommandButtons.count; i++){
        buttons[i].hidden = unavailable || (i != stage) || preview == nil;
        if (_busy && i == stage) {
            [buttons[i] setTitle:self.sendAgainTitle];
        } else {
            [buttons[i] setTitle:self.previewCommandTitle];
        }
    }
    self.previewTextView.string = preview ?: @"";
}

// A step can wrap (a long message, or a translation), so grow the step list to fit its text instead
// of clipping the steps after it. The controls above the list's bottom edge move up with its top
// and the view grows by the same amount, so the buttons at the bottom stay where they are.
- (void)sizeStepListToFit {
    NSTextField *field = self.textField;
    NSView *view = field.superview;
    if (!field || !view) {
        return;
    }
    if (_minimumStepListHeight == 0) {
        _minimumStepListHeight = NSHeight(field.frame);
    }
    const NSRect fieldFrame = field.frame;
    const NSRect measureBounds = NSMakeRect(0, 0, NSWidth(fieldFrame), CGFLOAT_MAX);
    const CGFloat fittingHeight = ceil([field.cell cellSizeForBounds:measureBounds].height);
    const CGFloat delta = MAX(_minimumStepListHeight, fittingHeight) - NSHeight(fieldFrame);
    if (delta == 0) {
        return;
    }
    DLog(@"Resize step list by %@ to fit text needing %@", @(delta), @(fittingHeight));
    const BOOL autoresizes = view.autoresizesSubviews;
    view.autoresizesSubviews = NO;
    NSRect viewFrame = view.frame;
    viewFrame.size.height += delta;
    // Keep the view's top edge where it is.
    viewFrame.origin.y -= delta;
    view.frame = viewFrame;
    view.autoresizesSubviews = autoresizes;
    for (NSView *subview in view.subviews) {
        if (subview == field) {
            continue;
        }
        if (NSMinY(subview.frame) >= NSMinY(fieldFrame)) {
            NSRect frame = subview.frame;
            frame.origin.y += delta;
            subview.frame = frame;
        }
    }
    NSRect newFieldFrame = fieldFrame;
    newFieldFrame.size.height += delta;
    field.frame = newFieldFrame;
    [self.shellInstallerDelegate shellIntegrationInstallerContentSizeDidChange];
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

