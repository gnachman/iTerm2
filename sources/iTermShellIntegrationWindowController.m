//
//  iTermShellIntegrationWindowController.m
//  iTerm2
//
//  Created by George Nachman on 12/18/19.
//

#import "iTermShellIntegrationWindowController.h"

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
@end

@interface iTermShellIntegrationFirstPageViewController: NSViewController<iTermShellIntegrationInstallerViewController>
@property (nonatomic, weak) IBOutlet id<iTermShellIntegrationInstallerDelegate> shellInstallerDelegate;
@property (nonatomic, strong) IBOutlet NSButton *utilities;
@end

@implementation iTermShellIntegrationFirstPageViewController
- (IBAction)next:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerSetInstallUtilities:self.utilities.state == NSOnState];
    [self.shellInstallerDelegate shellIntegrationInstallerContinue];
}
@end

@interface iTermShellIntegrationSecondPageViewController: NSViewController<iTermShellIntegrationInstallerViewController>
@property (nonatomic, weak) IBOutlet id<iTermShellIntegrationInstallerDelegate> shellInstallerDelegate;
@end

@implementation iTermShellIntegrationSecondPageViewController
- (IBAction)downloadAndRun:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerConfirmDownloadAndRun];
}
- (IBAction)sendShellCommands:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerSendShellCommands:-1];
}
@end

@interface iTermShellIntegrationDownloadAndRunViewController : NSViewController<iTermShellIntegrationInstallerViewController>
@property (nonatomic, weak) IBOutlet id<iTermShellIntegrationInstallerDelegate> shellInstallerDelegate;
@end

@implementation iTermShellIntegrationDownloadAndRunViewController
- (IBAction)pipeCurlToBash:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerReallyDownloadAndRun];
}
@end

@interface iTermShellIntegrationPasteShellCommandsViewController : NSViewController<iTermShellIntegrationInstallerViewController>
@property (nonatomic, weak) IBOutlet id<iTermShellIntegrationInstallerDelegate> shellInstallerDelegate;
@property (nonatomic) int stage;
@property (nonatomic, copy) NSString *shell;
@property (nonatomic, strong) IBOutlet NSTextField *textField;
@property (nonatomic, strong) IBOutlet NSButton *previewCommandButton1;
@property (nonatomic, strong) IBOutlet NSButton *previewCommandButton2;
@property (nonatomic, strong) IBOutlet NSButton *previewCommandButton3;
@property (nonatomic, strong) IBOutlet NSButton *previewCommandButton4;
@property (nonatomic, strong) IBOutlet NSTextView *previewTextView;
@property (nonatomic) BOOL installUtilities;
@property (nonatomic, strong) IBOutlet NSViewController *popoverViewController;
@property (nonatomic, strong) IBOutlet NSPopover *popover;
@end

@implementation iTermShellIntegrationPasteShellCommandsViewController
- (void)setStage:(int)stage {
    _stage = stage;
    if (stage <= 0) {
        self.shell = nil;
    }
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSInteger indexToBold = NSNotFound;
    NSString *step;
    NSString *prefix;

    if (stage < 0) {
        prefix = @"1. Discover";
    } else if (stage == 0) {
        prefix = @"➡ Select “Continue” to discover";
        indexToBold = lines.count;
    } else if (stage > 0) {
        prefix = @"✅ Discovered";
    }
    step = [NSString stringWithFormat:@"%@ which shell you use", prefix];
    if (stage > 0) {
        step = [step stringByAppendingFormat:@": you use “%@”.", self.shell];
    } else {
        step = [step stringByAppendingString:@"."];
    }
    [lines addObject:step];

    if (stage < 1) {
        prefix = @"Step 2. Modify";
    } else if (stage == 1) {
        prefix = @"➡ Select “Continue” to modify";
        indexToBold = lines.count;
    } else if (stage > 1) {
        prefix = @"✅ Modfied";
    }
    step = [NSString stringWithFormat:@"%@ your shell’s startup scripts.", prefix];
    [lines addObject:step];

    int i = 2;
    if (self.installUtilities) {
        i += 1;
        if (stage < 2) {
            prefix = @"Step 3. Install";
        } else if (stage == 2) {
            prefix = @"➡ Select “Continue” to install";
            indexToBold = lines.count;
        } else {
            prefix = @"✅ Installed";
        }
        step = [NSString stringWithFormat:@"%@ iTerm2 utility scripts.", prefix];
        [lines addObject:step];
    }

    if (stage < i) {
        prefix = [NSString stringWithFormat:@"Step %d. Add", i + 1];
    } else if (stage == i) {
        prefix = [NSString stringWithFormat:@"➡ Select “Continue” to add"];
        indexToBold = lines.count;
    } else if (stage > i) {
        prefix = @"✅ Added";
    }
    step =
    [NSString stringWithFormat:@"%@ script files under your home directory.", prefix];
    [lines addObject:step];
    
    if (stage > i) {
        [lines addObject:@""];
        [lines addObject:@"Done! Select “Continue” to proceed."];
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
    NSString *ctrlD = [NSString stringWithFormat:@"%c", 4];
    preview = [preview stringByReplacingOccurrencesOfString:ctrlD withString:@"^D\n"];
    NSArray<NSButton *> *buttons = self.previewCommandButtons;
    for (NSInteger i = 0; i < self.previewCommandButtons.count; i++){
        buttons[i].hidden = (i != stage) || preview == nil;
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
    if (_stage == 0) {
        [self.shellInstallerDelegate shellIntegrationInstallerBack];
    } else {
        self.stage = self.stage - 1;
    }
}
@end

@interface iTermShellIntegrationFinishedViewController: NSViewController<iTermShellIntegrationInstallerViewController>
@end

@implementation iTermShellIntegrationFinishedViewController
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
@property (nonatomic, strong) IBOutlet NSViewController<iTermShellIntegrationInstallerViewController> *downloadAndRunViewController;
@property (nonatomic, strong) IBOutlet iTermShellIntegrationPasteShellCommandsViewController *sendShellCommandsViewController;
@property (nonatomic, strong) IBOutlet NSViewController<iTermShellIntegrationInstallerViewController> *finishedViewController;

@property (nonatomic) BOOL installUtilities;
@property (nonatomic, copy) NSString *shell;
@property (nonatomic) iTermShellIntegrationInstallationState state;
@end

@implementation iTermShellIntegrationWindowController

- (void)windowDidLoad {
    [super windowDidLoad];
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
    _state = state;
    [self.currentViewController.view removeFromSuperview];
    self.currentViewController = [self viewControllerForState:state];
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
    NSRect rect = self.window.frame;
    const CGFloat originalMaxY = NSMaxY(rect);
    rect.size = self.currentViewController.view.bounds.size;
    rect.size.height += self.header.bounds.size.height;
    rect = [NSWindow frameRectForContentRect:rect styleMask:self.window.styleMask];
    rect.origin.y = originalMaxY - NSHeight(rect);
    [self.window setFrame:rect display:YES animate:YES];
}

- (void)setShell:(NSString *)shell {
    _shell = [shell copy];
    self.sendShellCommandsViewController.shell = shell;
}

- (void)setInstallUtilities:(BOOL)installUtilities {
    _installUtilities = installUtilities;
    self.sendShellCommandsViewController.installUtilities = installUtilities;
}

#pragma mark - Common Actions

- (IBAction)cancel:(id)sender {
    [self close];
}

- (IBAction)next:(id)sender {
    [self setState:[self nextState]];
}

- (IBAction)back:(id)sender {
    [self setState:[self previousState]];
}

#pragma mark - Helpers

- (NSString *)dotfileBaseName {
    if ([self.shell isEqualToString:@"tcsh"]) {
        return @".login";
    } else if ([self.shell isEqualToString:@"zsh"]) {
        return @".zshrc";
    } else if ([self.shell isEqualToString:@"bash"]) {
        return @".profile or .bash_profile";
    } else if ([self.shell isEqualToString:@"fish"]) {
        return @"config.fish";
    } else {
        assert(NO);
    }
    return @"?";
}

- (void)performSubstitutionsInTextField:(NSTextField *)label {
    NSString *string = label.identifier ?: label.stringValue;
    if (!label.identifier) {
        // Save a backup copy
        label.identifier = string;
    }
    NSDictionary *subs = @{ @"$DOTFILE": [self dotfileBaseName] };
    for (NSString *key in subs) {
        NSString *value = subs[key];
        string = [string stringByReplacingOccurrencesOfString:key withString:value];
    }
    label.stringValue = string;
}

- (NSString *)shellIntegrationPath {
    return [NSString stringWithFormat:@"~/.iterm2_shell_integration.%@", self.shell];
}

- (NSString *)scriptForCurrentShell {
    return @"TODO - SHELL INTEGRATION SCRIPT GOES HERE";
}

- (NSString *)curlPipeBashCommand {
    if (self.installUtilities) {
        return @"curl -L https://iterm2.com/shell_integration/install_shell_integration_and_utilities.sh | bash\n";
    }
    return @"curl -L https://iterm2.com/shell_integration/install_shell_integration.sh | bash\n";
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
        if ([self.shell isEqualToString:@"tcsh"]) {
            script = @"~/.login";
        } else if ([self.shell isEqualToString:@"zsh"]) {
            script = @"~/.zshrc";
        } else if ([self.shell isEqualToString:@"bash"]) {
            script = bashDotFile;
        } else if ([self.shell isEqualToString:@"fish"]) {
            script = @"~/.config/fish/config.fish";
            home_prefix=@"{$HOME}";
            shell_and=@"; and";
            shell_or=@"; or";
        } else {
            assert(NO);
        }
        NSString *relative_filename = [NSString stringWithFormat:@"%@/.iterm2_shell_integration.%@",
                                       home_prefix, self.shell];

    return [NSString stringWithFormat:@"test -e %@%@%@ %@ source %@%@%@ %@ true\n",
            quote, relative_filename, quote, shell_and, quote, relative_filename, quote, shell_or];
}

- (NSString *)amendDotFileWithCompletion:(void (^)(void))completion {
    const BOOL reallySend = (completion != nil);
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    NSString *script = nil;
    if ([self.shell isEqualToString:@"tcsh"]) {
        script = @"~/.login";
    } else if ([self.shell isEqualToString:@"zsh"]) {
        script = @"~/.zshrc";
    } else if ([self.shell isEqualToString:@"bash"]) {
        NSString *assignment = @"IT2_INSTALLER_DOTFILE=$(test -f \"~/.bash_profile\" && SCRIPT=\"~/.bash_profile\" || SCRIPT=\"~/.profile\")\n";
        [strings addObject:assignment];
        script = @"\"$IT2_INSTALLER_DOTFILE\"";
    } else if ([self.shell isEqualToString:@"fish"]) {
        [strings addObject:@"mkdir -p \"~/.config/fish\"\n"];
        script = @"~/.config/fish/config.fish";
    } else {
        assert(NO);
    }
    const bool switchToBash = ![self.shell isEqualToString:@"bash"];
    if (switchToBash) {
        [strings addObject:@"bash\n"];
    }
    [strings addObject: @"if ! grep iterm2_shell_integration "];
    [strings addObject:script];
    [strings addObject:@" > /dev/null 2>&1; then\n"];
    [strings addObject:@"    cat <<-EOF >> "];
    [strings addObject:script];
    [strings addObject:@"\n"];
    [strings addObject:[self dotfileCommandWithBashDotfile:@"$IT2_INSTALLER_DOTFILE"]];
    [strings addObject:@"EOF\n"];
    [strings addObject:@"fi\n"];
    if (switchToBash) {
        [strings addObject:@"exit\n"];
    }
    NSString *joined = [strings componentsJoinedByString:@""];
    [self sendText:joined reallySend:reallySend];
    if (completion) {
        completion();
    }
    return joined;
}

#pragma mark - iTermShellIntegrationInstallerDelegate

- (void)shellIntegrationInstallerConfirmDownloadAndRun {
    [self setState:iTermShellIntegrationInstallationStateDownloadAndRunConfirm];
}

- (void)shellIntegrationInstallerReallyDownloadAndRun {
    [self.delegate shellIntegrationWindowControllerSendText:[self curlPipeBashCommand]];
    [self next:nil];
}

- (NSString *)discoverShell:(BOOL)reallySend {
    void (^completion)(NSString * _Nonnull) = ^(NSString * _Nonnull shell) {
    #warning TOOD: Handle unrecognized shells
            self.shell = shell;
            if (shell) {
                self.sendShellCommandsViewController.stage = 1;
            }
    };
    return [self.delegate shellIntegrationInferShellWithCompletion:reallySend ? completion : nil];
}

- (NSString *)addScriptFiles:(BOOL)reallySend {
    NSString *result = [self catToScript:reallySend];
    if (reallySend) {
        self.sendShellCommandsViewController.stage = 2;
    }
    return result;
}

- (NSString *)installUtilityScripts:(BOOL)reallySend {
    NSMutableString *result = [NSMutableString string];
    [result appendString:[self sendText:@"mkdir ~/.iterm2\n" reallySend:reallySend]];
    [result appendString:[self catToUtilities:reallySend]];
    if (reallySend) {
        self.sendShellCommandsViewController.stage = 3;
    }
    return result;
}

- (NSString *)modifyStartupScriptsAndProceedTo:(int)nextStage
                                    reallySend:(BOOL)reallySend {
    void (^completion)(void) = ^{
        self.sendShellCommandsViewController.stage = nextStage;
    };
    return [self amendDotFileWithCompletion:reallySend ? completion : nil];
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

- (NSString *)catString:(NSString *)string to:(NSString *)path reallySend:(BOOL)reallySend {
    NSMutableString *result = [NSMutableString string];
    [result appendString:[self sendText:[NSString stringWithFormat:@"cat > %@\n", path]
                             reallySend:reallySend]];
    [result appendString:[self sendText:string
                             reallySend:reallySend]];
    [result appendString:[self sendText:[NSString stringWithFormat:@"\n%c", 4]
                             reallySend:reallySend]];
    return result;
}

- (NSString *)catToScript:(BOOL)reallySend {
    NSMutableString *result = [NSMutableString string];
    [result appendString:[self catString:[self scriptForCurrentShell] to:[self shellIntegrationPath]
                              reallySend:reallySend]];
    [result appendString:[self sendText:[NSString stringWithFormat:@"chmod +x %@\n", [self shellIntegrationPath]]
                             reallySend:reallySend]];
    return result;
}

- (NSString *)sendText:(NSString *)text reallySend:(BOOL)reallySend {
    if (reallySend) {
        [self.delegate shellIntegrationWindowControllerSendText:text];
    }
    return text;
}

- (NSString *)catToUtilities:(BOOL)reallySend {
    NSMutableString *result = [NSMutableString string];
    [result appendString:[self sendText:@"base64 -D | tar xfz -\n" reallySend:reallySend]];
    [result appendString:[self sendText:@"TODO - UTILITIES TARBALL\n" reallySend:reallySend]];
    [result appendString:[self sendText:[NSString stringWithFormat:@"%c", 4] reallySend:reallySend]];
    return result;
}

@end
