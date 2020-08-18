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
    return @"⏳ Waiting for command to complete…";
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
        prefix = @"1. Discover";
    } else if (stage == 0) {
        if (_busy) {
            prefix = self.waitingText;
        } else {
            prefix = @"➡ Select “Continue” to discover";
        }
        indexToBold = lines.count;
    } else if (stage > 0) {
        if (self.shell == iTermShellIntegrationShellUnknown) {
            prefix = @"🛑 Your shell is not supported.\n\nOnly bash, fish, tcsh, and zsh work with shell integration";
        } else {
            prefix = @"✅ Discovered";
        }
    }
    if (self.shell == iTermShellIntegrationShellUnknown || (_busy && stage == 0)) {
        step = prefix;
    } else {
        step = [NSString stringWithFormat:@"%@ your shell", prefix];
    }
    if (stage > 0) {
        if (self.shell != iTermShellIntegrationShellUnknown) {
            step = [step stringByAppendingFormat:@": you use “%@”.", iTermShellIntegrationShellString(self.shell)];
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
            prefix = @"Step 2. Write";
        } else if (stage == 1) {
            if (self.shell == iTermShellIntegrationShellUnknown) {
                prefix = @"Step 2. Write";
            } else if (_busy) {
                prefix = self.waitingText;
            } else {
                prefix = @"➡ Select “Continue” to write";
            }
            indexToBold = lines.count;
        } else if (stage > 1) {
            prefix = @"✅ Wrote";
        }
        if (_busy && stage == 1) {
            step = prefix;
        } else {
            step = [NSString stringWithFormat:@"%@ the shell integration script.", prefix];
        }
        [lines addObject:step];

        int i = 2;
        if (self.installUtilities) {
            i += 1;
            if (stage < 2) {
                prefix = @"Step 3. Install";
            } else if (stage == 2 && !_busy) {
                prefix = @"➡ Select “Continue” to install";
                indexToBold = lines.count;
            } else if (stage == 2 && _busy) {
                prefix = self.waitingText;
                indexToBold = lines.count;
            } else {
                prefix = @"✅ Installed";
            }
            if (_busy && stage == 2) {
                step = prefix;
            } else {
                step = [NSString stringWithFormat:@"%@ iTerm2 utility scripts.", prefix];
            }
            [lines addObject:step];
        }

        if (stage < i) {
            prefix = [NSString stringWithFormat:@"Step %d. Update", i + 1];
        } else if (stage == i && !_busy) {
            prefix = [NSString stringWithFormat:@"➡ Select “Continue” to update"];
            indexToBold = lines.count;
        } else if (stage == i && _busy) {
            prefix = self.waitingText;
            indexToBold = lines.count;
        } else if (stage > i) {
            prefix = @"✅ Updated";
        }
        if (_busy && stage == i) {
            step = prefix;
        } else {
            step =
            [NSString stringWithFormat:@"%@ your shell’s dotfile.", prefix];
        }
        [lines addObject:step];
        
        if (stage > i) {
            [lines addObject:@""];
            indexToBold = lines.count;
            [lines addObject:@"Done! Select “Continue” to proceed."];
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
            [buttons[i] setTitle:@"Send Again"];
        } else {
            [buttons[i] setTitle:@"Preview Command"];
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

