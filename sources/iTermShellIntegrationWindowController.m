//
//  iTermShellIntegrationWindowController.m
//  iTerm2
//
//  Created by George Nachman on 12/18/19.
//

#import "iTermShellIntegrationWindowController.h"

#import "iTermClickableTextField.h"
#import "iTermExpect.h"
#import "NSArray+iTerm.h"

@interface iTermShellIntegrationRootView: NSView
@end

@implementation iTermShellIntegrationRootView {
    NSTrackingArea *_area;
}

- (void)viewDidMoveToWindow {
    if (!_area) {
        [self createTrackingArea];
    }
    
}
- (void)createTrackingArea {
    NSTrackingAreaOptions options = NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways;
    _area = [[NSTrackingArea alloc] initWithRect:self.bounds options:options owner:self userInfo:nil];
    [self addTrackingArea:_area];
}

- (void)cursorUpdate:(NSEvent *)event {
    [[NSCursor pointingHandCursor] set];
}

@end

@interface iTermShellIntegrationPanel: NSPanel
@end

@implementation iTermShellIntegrationPanel
@end

@protocol iTermShellIntegrationInstallerViewController <NSObject>
- (void)setBusy:(BOOL)busy;
@optional
- (NSArray<NSTextField *> *)labelsNeedingSubstitutions;
@end

@protocol iTermShellIntegrationInstallerDelegate<NSObject>
- (void)shellIntegrationInstallerContinue;
- (void)shellIntegrationInstallerSetInstallUtilities:(BOOL)installUtilities;
- (void)shellIntegrationInstallerBack;
- (void)shellIntegrationInstallerCancel;
- (void)shellIntegrationInstallerConfirmDownloadAndRun;
- (void)shellIntegrationInstallerReallyDownloadAndRun;
- (void)shellIntegrationInstallerSendShellCommands:(int)stage;
- (NSString *)shellIntegrationInstallerNextCommandForSendShellCommands;
- (void)shellIntegrationInstallerCancelExpectations;
@end

@interface iTermShellIntegrationFirstPageViewController: NSViewController<iTermShellIntegrationInstallerViewController>
@property (nonatomic, weak) IBOutlet id<iTermShellIntegrationInstallerDelegate> shellInstallerDelegate;
@property (nonatomic, strong) IBOutlet NSButton *utilities;
@property (nonatomic, strong) IBOutlet NSTextField *descriptionLabel;
@property (nonatomic, strong) IBOutlet NSTextField *utilitiesLabel;
@end

@implementation iTermShellIntegrationFirstPageViewController
static NSString *const iTermShellIntegrationInstallUtilitiesUserDefaultsKey = @"NoSyncInstallUtilities";

- (void)setBusy:(BOOL)busy {
}

- (NSAttributedString *)attributedStringWithFont:(NSFont *)font
                                          string:(NSString *)string {
    NSDictionary *attributes = @{ NSFontAttributeName: font };
    return [[NSAttributedString alloc] initWithString:string attributes:attributes];
}

- (NSAttributedString *)attributedStringWithLinkToURL:(NSURL *)url title:(NSString *)title {
    NSDictionary *linkAttributes = @{ NSLinkAttributeName: url };
    NSString *localizedTitle = title;
    return [[NSAttributedString alloc] initWithString:localizedTitle
                                           attributes:linkAttributes];
}

- (void)appendLearnMoreToAttributedString:(NSMutableAttributedString *)attributedString
                                      url:(NSURL *)url {
    [attributedString appendAttributedString:[self attributedStringWithLinkToURL:url title:@"Learn more."]];
}

- (void)viewDidLoad {
    NSNumber *number = [[NSUserDefaults standardUserDefaults] objectForKey:iTermShellIntegrationInstallUtilitiesUserDefaultsKey];
    BOOL installUtilities = number ? number.boolValue : YES;
    self.utilities.state = installUtilities ? NSOnState : NSOffState;

    NSMutableAttributedString *attributedString;
    attributedString = [[self attributedStringWithFont:_descriptionLabel.font
                                                string:_descriptionLabel.stringValue] mutableCopy];
    [self appendLearnMoreToAttributedString:attributedString
                                        url:[NSURL URLWithString:@"https://iterm2.com/documentation-shell-integration.html"]];
    _descriptionLabel.attributedStringValue = attributedString;
    
    attributedString = [[self attributedStringWithFont:_utilitiesLabel.font
                                                string:_utilitiesLabel.stringValue] mutableCopy];
    [self appendLearnMoreToAttributedString:attributedString
                                        url:[NSURL URLWithString:@"https://www.iterm2.com/documentation-utilities.html"]];
    _utilitiesLabel.attributedStringValue = attributedString;
}

- (IBAction)toggleInstallUtilities:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:self.utilities.state == NSOnState forKey:iTermShellIntegrationInstallUtilitiesUserDefaultsKey];
}

- (IBAction)next:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerSetInstallUtilities:self.utilities.state == NSOnState];
    [self.shellInstallerDelegate shellIntegrationInstallerContinue];
}
@end

@interface iTermShellIntegrationSecondPageViewController: NSViewController<iTermShellIntegrationInstallerViewController>
@property (nonatomic, weak) IBOutlet id<iTermShellIntegrationInstallerDelegate> shellInstallerDelegate;
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

@interface iTermShellIntegrationDownloadAndRunViewController : NSViewController<iTermShellIntegrationInstallerViewController>
@property (nonatomic, weak) IBOutlet id<iTermShellIntegrationInstallerDelegate> shellInstallerDelegate;
@property (nonatomic, strong) IBOutlet NSButton *continueButton;
@property (nonatomic, strong) IBOutlet NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) IBOutlet NSTextField *textField;
@property (nonatomic) BOOL installUtilities;
@property (nonatomic) BOOL busy;
@property (nonatomic, readonly) NSString *urlString;
@property (nonatomic, readonly) NSString *command;
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
    return [NSString stringWithFormat:@"curl -L %@ | bash", self.urlString];
}

- (void)setInstallUtilities:(BOOL)installUtilities {
    _installUtilities = installUtilities;
    NSString *prefix = self.busy ? @"Waiting for this command to finish:" : @"Press “Continue” to run this command:";
    self.textField.stringValue = [NSString stringWithFormat:@"%@\n\n%@", prefix, self.command];
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

typedef NS_ENUM(NSUInteger, iTermShellIntegrationShell) {
    iTermShellIntegrationShellBash,
    iTermShellIntegrationShellTcsh,
    iTermShellIntegrationShellZsh,
    iTermShellIntegrationShellFish,
    iTermShellIntegrationShellUnknown
};

NSString *iTermShellIntegrationShellString(iTermShellIntegrationShell shell) {
    switch (shell) {
        case iTermShellIntegrationShellZsh:
            return @"zsh";
        case iTermShellIntegrationShellTcsh:
            return @"tcsh";
        case iTermShellIntegrationShellBash:
            return @"bash";
        case iTermShellIntegrationShellFish:
            return @"fish";
        case iTermShellIntegrationShellUnknown:
            return @"an unsupported shell";
    }
}

@interface iTermShellIntegrationPasteShellCommandsViewController : NSViewController<iTermShellIntegrationInstallerViewController>
@property (nonatomic, weak) IBOutlet id<iTermShellIntegrationInstallerDelegate> shellInstallerDelegate;
@property (nonatomic) int stage;
@property (nonatomic) iTermShellIntegrationShell shell;
@property (nonatomic, strong) IBOutlet NSTextField *textField;
@property (nonatomic, strong) IBOutlet NSButton *previewCommandButton1;
@property (nonatomic, strong) IBOutlet NSButton *previewCommandButton2;
@property (nonatomic, strong) IBOutlet NSButton *previewCommandButton3;
@property (nonatomic, strong) IBOutlet NSButton *previewCommandButton4;
@property (nonatomic, strong) IBOutlet NSTextView *previewTextView;
@property (nonatomic) BOOL installUtilities;
@property (nonatomic, strong) IBOutlet NSViewController *popoverViewController;
@property (nonatomic, strong) IBOutlet NSPopover *popover;
@property (nonatomic, strong) IBOutlet NSButton *continueButton;
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
    if (!unavailable) {
        if (stage < 1) {
            prefix = @"Step 2. Modify";
        } else if (stage == 1) {
            if (self.shell == iTermShellIntegrationShellUnknown) {
                prefix = @"Step 2. Modify";
            } else if (_busy) {
                prefix = self.waitingText;
            } else {
                prefix = @"➡ Select “Continue” to modify";
            }
            indexToBold = lines.count;
        } else if (stage > 1) {
            prefix = @"✅ Modfied";
        }
        if (_busy && stage == 1) {
            step = prefix;
        } else {
            step = [NSString stringWithFormat:@"%@ your shell’s startup scripts.", prefix];
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
            prefix = [NSString stringWithFormat:@"Step %d. Add", i + 1];
        } else if (stage == i && !_busy) {
            prefix = [NSString stringWithFormat:@"➡ Select “Continue” to add"];
            indexToBold = lines.count;
        } else if (stage == i && _busy) {
            prefix = self.waitingText;
            indexToBold = lines.count;
        } else if (stage > i) {
            prefix = @"✅ Added";
        }
        if (_busy && stage == i) {
            step = prefix;
        } else {
            step =
            [NSString stringWithFormat:@"%@ script files under your home directory.", prefix];
        }
        [lines addObject:step];
        
        if (stage > i) {
            [lines addObject:@""];
            indexToBold = lines.count;
            [lines addObject:@"Done! Select “Continue” to proceed."];
        }
    }
    
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] init];
    NSDictionary *regularAttributes =
    @{ NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]],
       NSForegroundColorAttributeName: [NSColor textColor] };
    NSDictionary *boldAttributes =
    @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont systemFontSize]],
       NSForegroundColorAttributeName: [NSColor textColor] };
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

@interface iTermShellIntegrationFinishedViewController: NSViewController<iTermShellIntegrationInstallerViewController>
@end

@implementation iTermShellIntegrationFinishedViewController
- (void)setBusy:(BOOL)busy {
}
@end

typedef NS_ENUM(NSUInteger, iTermShellIntegrationInstallationState) {
    iTermShellIntegrationInstallationStateFirstPage,
    iTermShellIntegrationInstallationStateSecondPage,
    iTermShellIntegrationInstallationStateDownloadAndRunConfirm,
    iTermShellIntegrationInstallationStateSendShellCommandsConfirm,
    iTermShellIntegrationInstallationStateConfirmation
};

@interface iTermShellIntegrationWindowController ()<iTermShellIntegrationInstallerDelegate>
@property (nonatomic, strong) IBOutlet NSView *containerView;

@property (nonatomic, strong) IBOutlet NSView *header;
@property (nonatomic, strong) NSViewController<iTermShellIntegrationInstallerViewController> *currentViewController;
@property (nonatomic, strong) IBOutlet iTermShellIntegrationFirstPageViewController *firstPageViewController;
@property (nonatomic, strong) IBOutlet NSViewController<iTermShellIntegrationInstallerViewController> *secondPageViewController;
@property (nonatomic, strong) IBOutlet iTermShellIntegrationDownloadAndRunViewController<iTermShellIntegrationInstallerViewController> *downloadAndRunViewController;
@property (nonatomic, strong) IBOutlet iTermShellIntegrationPasteShellCommandsViewController *sendShellCommandsViewController;
@property (nonatomic, strong) IBOutlet NSViewController<iTermShellIntegrationInstallerViewController> *finishedViewController;

@property (nonatomic) BOOL installUtilities;
@property (nonatomic) iTermShellIntegrationShell shell;
@property (nonatomic) iTermShellIntegrationInstallationState state;
@end

@implementation iTermShellIntegrationWindowController {
    NSMutableArray<iTermExpectation *> *_pendingExpectations;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    
    _pendingExpectations = [NSMutableArray array];
    NSPanel *panel = (NSPanel *)self.window;
    panel.movableByWindowBackground = YES;
    panel.floatingPanel = YES;
    self.containerView.autoresizesSubviews = YES;
    [self setState:iTermShellIntegrationInstallationStateFirstPage];
    panel.hidesOnDeactivate = YES;
    panel.opaque = NO;
}

- (iTermShellIntegrationInstallationState)nextState {
    switch (self.state) {
        case iTermShellIntegrationInstallationStateFirstPage:
            return iTermShellIntegrationInstallationStateSecondPage;
        case iTermShellIntegrationInstallationStateSecondPage:
            assert(NO);
        case iTermShellIntegrationInstallationStateDownloadAndRunConfirm:
        case iTermShellIntegrationInstallationStateSendShellCommandsConfirm:
            return iTermShellIntegrationInstallationStateConfirmation;

        case iTermShellIntegrationInstallationStateConfirmation:
            assert(NO);
    }
}

- (iTermShellIntegrationInstallationState)previousState {
    switch (self.state) {
        case iTermShellIntegrationInstallationStateFirstPage:
            assert(NO);
        case iTermShellIntegrationInstallationStateSecondPage:
            return iTermShellIntegrationInstallationStateFirstPage;
        case iTermShellIntegrationInstallationStateDownloadAndRunConfirm:
            return iTermShellIntegrationInstallationStateSecondPage;
        case iTermShellIntegrationInstallationStateSendShellCommandsConfirm:
            return iTermShellIntegrationInstallationStateSecondPage;
        case iTermShellIntegrationInstallationStateConfirmation:
            assert(NO);
    }
}

- (NSViewController<iTermShellIntegrationInstallerViewController> *)viewControllerForState:(iTermShellIntegrationInstallationState)state {
    switch (state) {
        case iTermShellIntegrationInstallationStateFirstPage:
            return self.firstPageViewController;
        case iTermShellIntegrationInstallationStateSecondPage:
            return self.secondPageViewController;
        case iTermShellIntegrationInstallationStateDownloadAndRunConfirm:
            return self.downloadAndRunViewController;
        case iTermShellIntegrationInstallationStateSendShellCommandsConfirm:
            return self.sendShellCommandsViewController;
        case iTermShellIntegrationInstallationStateConfirmation:
            return self.finishedViewController;
    }
    assert(NO);
    return nil;
}

- (void)setState:(iTermShellIntegrationInstallationState)state {
    [self cancelAllExpectations];
    _state = state;
    [self.currentViewController.view removeFromSuperview];
    self.currentViewController = [self viewControllerForState:state];
    if ([self.currentViewController respondsToSelector:@selector(willAppear)]) {
        [(id)self.currentViewController willAppear];
    }
    [self.containerView addSubview:self.currentViewController.view];
    NSRect frame = self.currentViewController.view.frame;
    frame.origin.x = 0;
    frame.origin.y = self.containerView.bounds.size.height - frame.size.height;
    self.currentViewController.view.frame = frame;
    if ([self.currentViewController respondsToSelector:@selector(labelsNeedingSubstitutions)]) {
        for (NSTextField *textField in [self.currentViewController labelsNeedingSubstitutions]) {
            [self performSubstitutionsInTextField:textField];
        }
    }
    self.downloadAndRunViewController.installUtilities = self.installUtilities;
    NSRect rect = self.window.frame;
    const CGFloat originalMaxY = NSMaxY(rect);
    rect.size = self.currentViewController.view.bounds.size;
    rect.size.height += self.header.bounds.size.height;
    rect = [NSWindow frameRectForContentRect:rect styleMask:self.window.styleMask];
    rect.origin.y = originalMaxY - NSHeight(rect);
    [self.window setFrame:rect display:YES animate:YES];
}

- (void)setShell:(iTermShellIntegrationShell)shell {
    _shell = shell;
    self.sendShellCommandsViewController.shell = shell;
    [self.sendShellCommandsViewController update];
}

- (void)setInstallUtilities:(BOOL)installUtilities {
    _installUtilities = installUtilities;
    self.sendShellCommandsViewController.installUtilities = installUtilities;
    self.downloadAndRunViewController.installUtilities = installUtilities;
}

- (void)cancelAllExpectations {
    [_pendingExpectations enumerateObjectsUsingBlock:^(iTermExpectation * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [[self.delegate shellIntegrationExpect] cancelExpectation:obj];
    }];
    [_pendingExpectations removeAllObjects];
    [self.currentViewController setBusy:NO];
}

#pragma mark - Common Actions

- (IBAction)cancel:(id)sender {
    [self cancelAllExpectations];
    [self close];
}

- (IBAction)next:(id)sender {
    [self setState:[self nextState]];
}

- (IBAction)back:(id)sender {
    [self setState:[self previousState]];
}

#pragma mark - Helpers

- (NSString *)humanReadableDotfileBaseName {
    switch (self.shell) {
        case iTermShellIntegrationShellTcsh:
            return @".login";
        case iTermShellIntegrationShellZsh:
            return @".zshrc";
        case iTermShellIntegrationShellBash:
            return @".profile or .bash_profile";
        case iTermShellIntegrationShellFish:
            return @"config.fish";
        case iTermShellIntegrationShellUnknown:
        return @"?";
    }
}

- (void)performSubstitutionsInTextField:(NSTextField *)label {
    NSString *string = label.identifier ?: label.stringValue;
    if (!label.identifier) {
        // Save a backup copy
        label.identifier = string;
    }
    NSDictionary *subs = @{ @"$DOTFILE": [self humanReadableDotfileBaseName] };
    for (NSString *key in subs) {
        NSString *value = subs[key];
        string = [string stringByReplacingOccurrencesOfString:key withString:value];
    }
    label.stringValue = string;
}

- (NSString *)shellIntegrationPath {
    return [NSString stringWithFormat:@"~/.iterm2_shell_integration.%@", iTermShellIntegrationShellString(self.shell)];
}

- (NSString *)scriptForCurrentShell {
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"iterm2_shell_integration" withExtension:iTermShellIntegrationShellString(self.shell)];
    if (!url) {
        return nil;
    }
    NSString *string = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    assert(string);
    if (!self.installUtilities) {
        return string;
    }
    
    // Add aliases
    url = [[NSBundle bundleForClass:self.class] URLForResource:@"utilities-manifest" withExtension:@"txt"];
    NSString *names = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    names = [names stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    assert(names);
    NSArray<NSString *> *commands = [names componentsSeparatedByString:@" "];
    NSArray<NSString *> *aliasCommands = [commands mapWithBlock:^id(NSString *command) {
        switch (self.shell) {
            case iTermShellIntegrationShellZsh:
            case iTermShellIntegrationShellBash:
            case iTermShellIntegrationShellFish:
                return [NSString stringWithFormat:@"alias %@=~/.iterm2/%@", command, command];
            case iTermShellIntegrationShellTcsh:
                return [NSString stringWithFormat:@"alias %@ ~/.iterm2/%@", command, command];
            case iTermShellIntegrationShellUnknown:
                return nil;
        }
    }];
    NSString *alias = [aliasCommands componentsJoinedByString:@";"];
    string = [string stringByAppendingString:@"\n"];
    return [string stringByAppendingString:alias];
}

- (NSString *)curlPipeBashCommand {
    return [self.downloadAndRunViewController.command stringByAppendingString:@"\n"];
}

- (void)copyString:(NSString *)string {
    NSPasteboard *generalPasteboard = [NSPasteboard generalPasteboard];
    [generalPasteboard declareTypes:@[ NSStringPboardType ] owner:nil];
    [generalPasteboard setString:string forType:NSStringPboardType];
}

- (NSString *)dotfileCommandWithBashDotfile:(NSString *)bashDotFile {
    NSString *home_prefix = @"~";
    NSString *shell_and = @"&&";
    NSString *shell_or = @"||";
    NSString *quote = @"";
    NSString *script = nil;
    switch (self.shell) {
        case iTermShellIntegrationShellTcsh:
            script = @"~/.login";
            break;
        case iTermShellIntegrationShellZsh:
            script = @"~/.zshrc";
            break;
        case iTermShellIntegrationShellBash:
            script = bashDotFile;
            break;
        case iTermShellIntegrationShellFish:
            script = @"~/.config/fish/config.fish";
            home_prefix=@"{$HOME}";
            shell_and=@"; and";
            shell_or=@"; or";
            break;
        case iTermShellIntegrationShellUnknown:
            assert(NO);
        }
    NSString *relative_filename = [NSString stringWithFormat:@"%@/.iterm2_shell_integration.%@",
                                   home_prefix, iTermShellIntegrationShellString(self.shell)];
    
    return [NSString stringWithFormat:@"test -e %@%@%@ %@ source %@%@%@ %@ true\n",
            quote, relative_filename, quote, shell_and, quote, relative_filename, quote, shell_or];
}

- (NSString *)amendDotFileWithExpectation:(inout iTermExpectation **)expectation
                               completion:(void (^)(void))completion {
    const BOOL reallySend = (completion != nil);
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    NSString *script = nil;
    switch (self.shell) {
        case iTermShellIntegrationShellTcsh:
            script = @"~/.login";
            break;
        case iTermShellIntegrationShellZsh:
            script = @"~/.zshrc";
            break;
        case iTermShellIntegrationShellBash: {
            NSString *assignment = @"IT2_INSTALLER_DOTFILE=$(test -f \"~/.bash_profile\" && SCRIPT=\"~/.bash_profile\" || SCRIPT=\"~/.profile\")\n";
            [strings addObject:assignment];
            script = @"\"$IT2_INSTALLER_DOTFILE\"";
            break;
        }
        case iTermShellIntegrationShellFish:
            [strings addObject:@"mkdir -p \"~/.config/fish\"\n"];
            script = @"~/.config/fish/config.fish";
            break;
        case iTermShellIntegrationShellUnknown:
            assert(NO);
    }
    [strings addObject:@"bash --noprofile --norc\n"];
    [strings addObject:@"PS1='>> '; PS2='> '\n"];
    [self sendText:[strings componentsJoinedByString:@""] reallySend:reallySend];
    NSString *joined = [strings componentsJoinedByString:@""];
    [strings removeAllObjects];
    
    [strings addObject:[self sendText:[NSString stringWithFormat:@"if ! grep iterm2_shell_integration %@  > /dev/null 2>&1; then\n", script]
                           reallySend:reallySend
                           afterRegex:@"^>> "
                          expectation:expectation]];
    [strings addObject:[self sendText:[NSString stringWithFormat:@"    cat <<-EOF >> %@\n", script]
                           reallySend:reallySend
                           afterRegex:@"^> "
                          expectation:expectation]];
    [strings addObject:[self sendText:[self dotfileCommandWithBashDotfile:@"$IT2_INSTALLER_DOTFILE"]
                           reallySend:reallySend
                           afterRegex:@"^> "
                          expectation:expectation]];
    [strings addObject:[self sendText:@"EOF\n"
                           reallySend:reallySend
                           afterRegex:@"^> "
                          expectation:expectation]];
    [strings addObject:[self sendText:@"fi\n"
                           reallySend:reallySend
                           afterRegex:@"^>> "
                          expectation:expectation]];
    [strings addObject:[self sendText:@"exit\n"
                           reallySend:reallySend
                           afterRegex:@"^>> "
                          expectation:expectation
                           completion:^(NSArray<NSString *> *captures) {
        if (completion) {
            completion();
        }
    }]];
    joined = [joined stringByAppendingString:[strings componentsJoinedByString:@""]];
    return joined;
}

- (iTermExpectation *)expectRegularExpression:(NSString *)regex
                                   completion:(void (^)(NSArray<NSString *> * _Nonnull))completion {
    return [self expectRegularExpression:regex after:nil willExpect:nil completion:completion];
}

- (iTermExpectation *)expectRegularExpression:(NSString *)regex
                                        after:(iTermExpectation *)precedecessor
                                   willExpect:(void (^)(void))willExpect
                                   completion:(void (^)(NSArray<NSString *> * _Nonnull))completion {
    __weak __typeof(self) weakSelf = self;
    __block BOOL removed = NO;
    [self.currentViewController setBusy:YES];
    __block iTermExpectation *expectation =
    [[self.delegate shellIntegrationExpect] expectRegularExpression:regex
                                                              after:precedecessor
                                                         willExpect:willExpect
                                                         completion:^(NSArray<NSString *> * _Nonnull captureGroups) {
        if (expectation) {
            removed = YES;
            [weakSelf removeExpectation:expectation];
        }
        if (completion) {
            completion(captureGroups);
        }
    }];
    if (!removed) {
        [_pendingExpectations addObject:expectation];
    }
    return expectation;
}

- (void)removeExpectation:(iTermExpectation *)expectation {
    [_pendingExpectations removeObject:expectation];
    if (_pendingExpectations.count == 0) {
        [self.currentViewController setBusy:NO];
    }
}

#pragma mark - iTermShellIntegrationInstallerDelegate

- (void)shellIntegrationInstallerConfirmDownloadAndRun {
    [self setState:iTermShellIntegrationInstallationStateDownloadAndRunConfirm];
}

- (void)shellIntegrationInstallerReallyDownloadAndRun {
    [self.delegate shellIntegrationWindowControllerSendText:[self curlPipeBashCommand]];
    __weak __typeof(self) weakSelf = self;

    [self expectRegularExpression:@"^Done.$"
                       completion:^(NSArray<NSString *> * _Nonnull captureGroups) {
        [weakSelf next:nil];
    }];
}

- (NSString *)discoverShell:(BOOL)reallySend {
    void (^completion)(NSString * _Nonnull) = ^(NSString * _Nonnull shell) {
        NSDictionary<NSString *, NSNumber *> *map = @{ @"tcsh": @(iTermShellIntegrationShellTcsh),
                                                       @"bash": @(iTermShellIntegrationShellBash),
                                                       @"zsh": @(iTermShellIntegrationShellZsh),
                                                       @"fish": @(iTermShellIntegrationShellFish) };
        NSNumber *number = map[shell ?: @""];
        if (number) {
            self.shell = number.integerValue;
        } else {
            self.shell = iTermShellIntegrationShellUnknown;
        }
        self.sendShellCommandsViewController.stage = 1;
    };
    if (reallySend) {
        [self expectRegularExpression:@"My shell is ([a-z]+)\\."
                           completion:^(NSArray<NSString *> * _Nonnull captureGroups) {
            if (completion) {
                completion(captureGroups[1]);
            }
        }];
    }
    return [self sendText:@"echo My shell is `basename $SHELL`.\n" reallySend:reallySend];
}

- (NSString *)addScriptFiles:(BOOL)reallySend {
    __weak __typeof(self) weakSelf = self;
    NSString *result = [self catToScript:reallySend completion:^{
        if (reallySend) {
            weakSelf.sendShellCommandsViewController.stage = 2;
        }
    }];
    return result;
}

- (NSString *)installUtilityScripts:(BOOL)reallySend {
    NSMutableString *result = [NSMutableString string];
    iTermExpectation *expectation = nil;
    __weak __typeof(self) weakSelf = self;
    [result appendString:[self catToUtilities:reallySend
                                  expectation:&expectation
                                   completion:^{
        if (reallySend) {
            [weakSelf.sendShellCommandsViewController setBusy:NO];
            weakSelf.sendShellCommandsViewController.stage = 3;
        }
    }]];
    if (reallySend) {
        [self.sendShellCommandsViewController setBusy:YES];
    }
    return result;
}

- (NSString *)modifyStartupScriptsAndProceedTo:(int)nextStage
                                    reallySend:(BOOL)reallySend {
    void (^completion)(void) = ^{
        self.sendShellCommandsViewController.stage = nextStage;
    };
    iTermExpectation *expectation = nil;
    return [self amendDotFileWithExpectation:&expectation
                                  completion:reallySend ? completion : nil];
}

- (void)finishSendShellCommandsInstall {
    [self next:nil];
    self.sendShellCommandsViewController.stage = 0;
}

- (void)shellIntegrationInstallerSendShellCommands:(int)stage {
    if (stage < 0) {
        _sendShellCommandsViewController.stage = 0;
        self.state = iTermShellIntegrationInstallationStateSendShellCommandsConfirm;
    } else {
        switch (stage) {
            case 0: {
                [self discoverShell:YES];
                break;
            }
            case 1:
                [self addScriptFiles:YES];
                break;
            case 2: {
                if (self.installUtilities) {
                    [self installUtilityScripts:YES];
                } else {
                    [self modifyStartupScriptsAndProceedTo:stage+1
                                                reallySend:YES];
                }
                break;
            }
            case 3:
                if (self.installUtilities) {
                    [self modifyStartupScriptsAndProceedTo:stage+1
                                                reallySend:YES];
                } else {
                    [self finishSendShellCommandsInstall];
                }
                break;
            case 4:
                [self finishSendShellCommandsInstall];
        }
    }
}

- (void)shellIntegrationInstallerSetInstallUtilities:(BOOL)installUtilities {
    self.installUtilities = installUtilities;
}

- (void)shellIntegrationInstallerBack {
    [self back:nil];
}

- (void)shellIntegrationInstallerCancel {
    [self dismissController:nil];
}

- (void)shellIntegrationInstallerContinue {
    [self next:nil];
}

- (NSString *)shellIntegrationInstallerNextCommandForSendShellCommands {
    const int stage = self.sendShellCommandsViewController.stage;
    switch (stage) {
        case 0: {
            return [self discoverShell:NO];
        }
        case 1:
            return [self addScriptFiles:NO];
            break;
        case 2: {
            if (self.installUtilities) {
                return [self installUtilityScripts:NO];
            } else {
                return [self modifyStartupScriptsAndProceedTo:stage+1
                                                   reallySend:NO];
            }
            break;
        }
        case 3:
            if (self.installUtilities) {
                return [self modifyStartupScriptsAndProceedTo:stage+1
                                                   reallySend:NO];
            } else {
                return nil;
            }
            break;
        case 4:
            return nil;
    }
    return nil;
}

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [self doesNotRecognizeSelector:_cmd];
}

- (NSString *)sendText:(NSString *)text
            reallySend:(BOOL)reallySend
            afterRegex:(NSString *)regex
           expectation:(inout iTermExpectation **)expectation {
    return [self sendText:text
               reallySend:reallySend
               afterRegex:regex
              expectation:expectation
               completion:nil];
}

- (NSString *)sendText:(NSString *)text
            reallySend:(BOOL)reallySend
            afterRegex:(NSString *)regex
           expectation:(inout iTermExpectation **)expectation
            completion:(void (^)(NSArray<NSString *> *))completion {
    if (!reallySend) {
        return text;
    }
    
    __weak __typeof(self) weakSelf = self;
    iTermExpectation *newExpectation =
    [self expectRegularExpression:regex
                            after:(*expectation).lastExpectation
                       willExpect:^{
        [weakSelf.delegate shellIntegrationWindowControllerSendText:text];
    }
                       completion:completion];
    if (!*expectation) {
        *expectation = newExpectation;
    }
    return text;
}

- (NSString *)switchToBash:(BOOL)reallySend
               expectation:(inout iTermExpectation **)expectation {
    return [self sendText:@"bash --noprofile --norc\nPS1='>> '; PS2='> '\n" reallySend:reallySend afterRegex:@"." expectation:expectation];
}

- (NSString *)catString:(NSString *)string
                     to:(NSString *)path
             reallySend:(BOOL)reallySend
            expectation:(out iTermExpectation **)expectation {
    NSMutableString *result = [NSMutableString string];
    [result appendString:[self switchToBash:reallySend expectation:expectation]];
    [result appendString:[self sendText:[NSString stringWithFormat:@"cat <<'EOF' > %@\n", path]
                             reallySend:reallySend
                             afterRegex:@"."
                            expectation:expectation]];
    [result appendString:[self sendText:string
                             reallySend:reallySend
                             afterRegex:@"^> "
                            expectation:expectation]];
    [result appendString:[self sendText:@"\nEOF\n"
                             reallySend:reallySend
                          afterRegex:@"."
                            expectation:expectation]];
    [result appendString:[self sendText:@"exit\n"
                             reallySend:reallySend
                          afterRegex:@"> EOF"
                            expectation:expectation]];
    return result;
}

- (NSString *)catToScript:(BOOL)reallySend
               completion:(void (^)(void))completion {
    NSMutableString *result = [NSMutableString string];
    iTermExpectation *expectation = nil;
    [result appendString:[self switchToBash:reallySend expectation:&expectation]];
    [result appendString:[self catString:[self scriptForCurrentShell]
                                      to:[self shellIntegrationPath]
                              reallySend:reallySend
                             expectation:&expectation]];
    [result appendString:[self sendText:[NSString stringWithFormat:@"chmod +x %@\n", [self shellIntegrationPath]]
                             reallySend:reallySend
                             afterRegex:@"^>> "
                            expectation:&expectation]];
    [result appendString:[self sendText:@"exit\n"
                             reallySend:reallySend
                          afterRegex:@"^>> "
                            expectation:&expectation
                             completion:^(NSArray<NSString *> *captures) {
        if (completion) {
            completion();
        }
    }]];
    return result;
}

- (NSString *)sendText:(NSString *)text reallySend:(BOOL)reallySend {
    if (reallySend) {
        [self.delegate shellIntegrationWindowControllerSendText:text];
    }
    return text;
}

- (NSString *)catToUtilities:(BOOL)reallySend
                 expectation:(out iTermExpectation **)expectation
                  completion:(void (^)(void))completion {
    NSMutableString *result = [NSMutableString string];
    [result appendString:[self switchToBash:reallySend expectation:expectation]];
    [result appendString:[self sendText:@"mkdir ~/.iterm2; echo ok\n"
                             reallySend:reallySend
                             afterRegex:@"."
                            expectation:expectation]];
    [result appendString:[self sendText:@"cd ~/.iterm2; echo ok\n"
                             reallySend:reallySend
                             afterRegex:@"^ok$"
                            expectation:expectation]];
    [result appendString:[self sendText:@"base64 -D <<'EOF'| tar xfz -\n"
                             reallySend:reallySend
                             afterRegex:@"^ok$"
                            expectation:expectation]];
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"utilities" withExtension:@"tgz"];
    if (!url) {
        completion();
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfURL:url];
    NSString *encoded = [data base64EncodedStringWithOptions:(NSDataBase64Encoding76CharacterLineLength | NSDataBase64EncodingEndLineWithLineFeed)];
    [result appendString:[self sendText:encoded
                             reallySend:reallySend
                             afterRegex:@"^> "
                            expectation:expectation]];
    [result appendString:[self sendText:@"\nEOF\n"
                             reallySend:reallySend
                             afterRegex:@"."
                            expectation:expectation]];
    [result appendString:[self sendText:@"exit\n"
                             reallySend:reallySend
                          afterRegex:@"> EOF"
                            expectation:expectation
                             completion:^(NSArray<NSString *> *captures) {
        completion();
    }]];
    return result;
}

- (void)shellIntegrationInstallerCancelExpectations {
    [self cancelAllExpectations];
}

@end
