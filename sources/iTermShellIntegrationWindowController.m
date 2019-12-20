//
//  iTermShellIntegrationWindowController.m
//  iTerm2
//
//  Created by George Nachman on 12/18/19.
//

#import "iTermShellIntegrationWindowController.h"

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
- (void)shellIntegrationInstallerManualInstall;
- (void)shellIntegrationInstallerSetShell:(NSString *)shell;

- (void)shellIntegrationInstallerCopyPath;
- (void)shellIntegrationInstallerCopyScript;
- (void)shellIntegrationInstallerCatScript;
- (void)shellIntegrationInstallerCopyDotfileCommand;
- (void)shellIntegrationInstallerAmendDotfile;

- (void)shellIntegrationInstallerCopyUntar;
- (void)shellIntegrationInstallerCopyUtilitiesTarball;
- (void)shellIntegrationInstallerUntarUtilities;
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
- (IBAction)manualInstall:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerManualInstall];
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
@property (nonatomic) BOOL installUtilities;
@end

@implementation iTermShellIntegrationPasteShellCommandsViewController
- (void)setStage:(int)stage {
    _stage = stage;
    if (stage <= 0) {
        self.shell = nil;
    }
    NSString *newString =
    [NSString stringWithFormat:
@"This will send commands into the current terminal window to:\n"
@"\n"
@"%@ Discover which shell you use%@\n"
@"%@ Modify your shell’s startup scripts.\n",
     stage > 0 ? @"✅": @"1.",
     stage > 0 ? [NSString stringWithFormat:@": You use “%@”.", self.shell] : @".",
     stage > 1 ? @"✅": @"2."];
    int i = 2;
    if (self.installUtilities) {
        i += 1;
        newString = [newString stringByAppendingFormat:@"%@ Install iTerm2 utility scripts.\n",
                     stage > 2 ? @"✅": @"3."];
    }
    newString =
    [newString stringByAppendingFormat:
     @"%@ Add script files under your home directory.",
     stage > i ? @"✅": [[@(i + 1) stringValue] stringByAppendingString:@"."]];

    self.textField.stringValue = newString;
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

@interface iTermShellIntegrationChooseShellViewController : NSViewController<iTermShellIntegrationInstallerViewController>
@property (nonatomic, strong) IBOutlet NSPopUpButton *shells;
@property (nonatomic, weak) IBOutlet id<iTermShellIntegrationInstallerDelegate> shellInstallerDelegate;
@end

@implementation iTermShellIntegrationChooseShellViewController
- (IBAction)next:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerSetShell:self.shells.selectedItem.identifier];
}
@end

@interface iTermShellIntegrationWriteScriptViewController: NSViewController<iTermShellIntegrationInstallerViewController>
@property (nonatomic, weak) IBOutlet id<iTermShellIntegrationInstallerDelegate> shellInstallerDelegate;
@end

@implementation iTermShellIntegrationWriteScriptViewController
- (IBAction)copyPath:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerCopyPath];
}
- (IBAction)copyScript:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerCopyScript];
}
- (IBAction)doItForMe:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerCatScript];
}
@end

@interface iTermShellIntegrationUpdateDotfileViewController: NSViewController<iTermShellIntegrationInstallerViewController>
@property (nonatomic, weak) IBOutlet id<iTermShellIntegrationInstallerDelegate> shellInstallerDelegate;
@end

@implementation iTermShellIntegrationUpdateDotfileViewController
- (IBAction)copyCommand:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerCopyDotfileCommand];
}
- (IBAction)doItForMe:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerAmendDotfile];
}
@end

@interface iTermShellIntegrationInstallUtilitiesViewController: NSViewController<iTermShellIntegrationInstallerViewController>
@property (nonatomic, weak) IBOutlet id<iTermShellIntegrationInstallerDelegate> shellInstallerDelegate;
@end

@implementation iTermShellIntegrationInstallUtilitiesViewController
- (IBAction)copyUntarCommand:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerCopyUntar];
}
- (IBAction)copyTarball:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerCopyUtilitiesTarball];
}
- (IBAction)doItForMe:(id)sender {
    [self.shellInstallerDelegate shellIntegrationInstallerUntarUtilities];
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
    iTermShellIntegrationInstallationStateManualInstallChooseShell,
    iTermShellIntegrationInstallationStateManualInstallWriteScript,
    iTermShellIntegrationInstallationStateManualInstallUpdateDotfile,
    iTermShellIntegrationInstallationStateManualInstallUtilities,
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
@property (nonatomic, strong) IBOutlet NSViewController<iTermShellIntegrationInstallerViewController> *chooseShellViewController;
@property (nonatomic, strong) IBOutlet NSViewController<iTermShellIntegrationInstallerViewController> *updateDotfileViewController;
@property (nonatomic, strong) IBOutlet NSViewController<iTermShellIntegrationInstallerViewController> *installUtilitiesViewController;
@property (nonatomic, strong) IBOutlet NSViewController<iTermShellIntegrationInstallerViewController> *finishedViewController;

@property (nonatomic) BOOL installUtilities;
@property (nonatomic, copy) NSString *shell;
@property (nonatomic) iTermShellIntegrationInstallationState state;
@end

@implementation iTermShellIntegrationWindowController

- (void)windowDidLoad {
    [super windowDidLoad];
    self.containerView.autoresizesSubviews = YES;
    [self setState:iTermShellIntegrationInstallationStateFirstPage];
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

        case iTermShellIntegrationInstallationStateManualInstallChooseShell:
            return iTermShellIntegrationInstallationStateManualInstallWriteScript;
        case iTermShellIntegrationInstallationStateManualInstallWriteScript:
            return iTermShellIntegrationInstallationStateManualInstallUpdateDotfile;
        case iTermShellIntegrationInstallationStateManualInstallUpdateDotfile:
            if (self.installUtilities) {
                return iTermShellIntegrationInstallationStateManualInstallUtilities;
            } else {
                return iTermShellIntegrationInstallationStateConfirmation;
            }
        case iTermShellIntegrationInstallationStateManualInstallUtilities:
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
        case iTermShellIntegrationInstallationStateManualInstallChooseShell:
            return iTermShellIntegrationInstallationStateSecondPage;
        case iTermShellIntegrationInstallationStateManualInstallWriteScript:
            return iTermShellIntegrationInstallationStateManualInstallChooseShell;
        case iTermShellIntegrationInstallationStateManualInstallUpdateDotfile:
            return iTermShellIntegrationInstallationStateManualInstallWriteScript;
        case iTermShellIntegrationInstallationStateManualInstallUtilities:
            return iTermShellIntegrationInstallationStateManualInstallUpdateDotfile;
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
        case iTermShellIntegrationInstallationStateManualInstallChooseShell:
            return self.chooseShellViewController;
        case iTermShellIntegrationInstallationStateManualInstallWriteScript:
            return self.updateDotfileViewController;
        case iTermShellIntegrationInstallationStateManualInstallUpdateDotfile:
            return self.updateDotfileViewController;
        case iTermShellIntegrationInstallationStateManualInstallUtilities:
            return self.installUtilitiesViewController;
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

- (int)step {
    switch (self.state) {
        case iTermShellIntegrationInstallationStateFirstPage:
        case iTermShellIntegrationInstallationStateSecondPage:
        case iTermShellIntegrationInstallationStateDownloadAndRunConfirm:
        case iTermShellIntegrationInstallationStateSendShellCommandsConfirm:
        case iTermShellIntegrationInstallationStateConfirmation:
            return 0;

        case iTermShellIntegrationInstallationStateManualInstallChooseShell:
            return 1;
        case iTermShellIntegrationInstallationStateManualInstallWriteScript:
            return 2;
        case iTermShellIntegrationInstallationStateManualInstallUpdateDotfile:
            return 3;
        case iTermShellIntegrationInstallationStateManualInstallUtilities:
            return 4;
    }
}

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
    NSDictionary *subs = @{ @"$STEP": [@([self step]) stringValue],
                            @"$N": self.installUtilities ? @"4" : @"3",
                            @"$DOTFILE": [self dotfileBaseName] };
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

- (void)amendDotFileWithCompletion:(void (^)(void))completion {
    NSString *script = nil;
    if ([self.shell isEqualToString:@"tcsh"]) {
        script = @"~/.login";
    } else if ([self.shell isEqualToString:@"zsh"]) {
        script = @"~/.zshrc";
    } else if ([self.shell isEqualToString:@"bash"]) {
        NSString *assignment = @"IT2_INSTALLER_DOTFILE=$(test -f \"~/.bash_profile\" && SCRIPT=\"~/.bash_profile\" || SCRIPT=\"~/.profile\")\n";
        [self.delegate shellIntegrationWindowControllerSendText:assignment];
        script = @"\"$IT2_INSTALLER_DOTFILE\"";
    } else if ([self.shell isEqualToString:@"fish"]) {
        [self.delegate shellIntegrationWindowControllerSendText:@"mkdir -p \"~/.config/fish\"\n"];
        script = @"~/.config/fish/config.fish";
    } else {
        assert(NO);
    }
    const bool switchToBash = ![self.shell isEqualToString:@"bash"];
    if (switchToBash) {
        [self.delegate shellIntegrationWindowControllerSendText:@"bash\n"];
    }
    [self.delegate shellIntegrationWindowControllerSendText:
     @"if ! grep iterm2_shell_integration "];
    [self.delegate shellIntegrationWindowControllerSendText:
     script];
    [self.delegate shellIntegrationWindowControllerSendText:
     @" > /dev/null 2>&1; then\n"];
    [self.delegate shellIntegrationWindowControllerSendText:
     @"    cat <<-EOF >> "];
    [self.delegate shellIntegrationWindowControllerSendText:
     script];
    [self.delegate shellIntegrationWindowControllerSendText:
     @"\n"];
    [self.delegate shellIntegrationWindowControllerSendText:
     [self dotfileCommandWithBashDotfile:@"$IT2_INSTALLER_DOTFILE"]];
    [self.delegate shellIntegrationWindowControllerSendText:
     @"EOF\n"];
    [self.delegate shellIntegrationWindowControllerSendText:
     @"fi\n"];
    if (switchToBash) {
        [self.delegate shellIntegrationWindowControllerSendText:
         @"exit\n"];
    }
    completion();
}

#pragma mark - iTermShellIntegrationInstallerDelegate

- (void)shellIntegrationInstallerConfirmDownloadAndRun {
    [self setState:iTermShellIntegrationInstallationStateDownloadAndRunConfirm];
}

- (void)shellIntegrationInstallerReallyDownloadAndRun {
    [self.delegate shellIntegrationWindowControllerSendText:[self curlPipeBashCommand]];
    [self next:nil];
}

- (void)discoverShell {
    [self.delegate shellIntegrationInferShellWithCompletion:^(NSString * _Nonnull shell) {
        self.shell = shell;
        if (shell) {
            self.sendShellCommandsViewController.stage = 1;
        }
    }];
}

- (void)addScriptFiles {
    [self catToScript];
    self.sendShellCommandsViewController.stage = 2;
}

- (void)installUtilityScripts {
    [self.delegate shellIntegrationWindowControllerSendText:@"mkdir ~/.iterm2\n"];
    [self catToUtilities];
    self.sendShellCommandsViewController.stage = 4;
}

- (void)modifyStartupScriptsAndProceedTo:(int)nextStage {
    [self amendDotFileWithCompletion:^{
        self.sendShellCommandsViewController.stage = nextStage;
    }];
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
                [self discoverShell];
                break;
            }
            case 1:
                [self addScriptFiles];
                break;
            case 2: {
                if (self.installUtilities) {
                    [self installUtilityScripts];
                } else {
                    [self modifyStartupScriptsAndProceedTo:stage+1];
                }
                break;
            }
            case 3:
                if (self.installUtilities) {
                    [self modifyStartupScriptsAndProceedTo:stage+1];
                } else {
                    [self finishSendShellCommandsInstall];
                }
                break;
            case 4:
                [self finishSendShellCommandsInstall];
        }
    }
}

- (void)shellIntegrationInstallerManualInstall {
    [self setState:iTermShellIntegrationInstallationStateManualInstallChooseShell];
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

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [self doesNotRecognizeSelector:_cmd];
}

- (void)shellIntegrationInstallerSetShell:(NSString *)shell {
    self.shell = shell;
}

- (void)shellIntegrationInstallerCopyPath {
    [self copyString:[self shellIntegrationPath]];
}
- (void)shellIntegrationInstallerCopyScript {
    [self copyString:[self scriptForCurrentShell]];
}

- (void)catString:(NSString *)string to:(NSString *)path {
    [self.delegate shellIntegrationWindowControllerSendText:[NSString stringWithFormat:@"cat > %@\n", path]];
    [self.delegate shellIntegrationWindowControllerSendText:string];
    [self.delegate shellIntegrationWindowControllerSendText:[NSString stringWithFormat:@"\n%c", 4]];
}

- (void)catToScript {
    [self catString:[self scriptForCurrentShell] to:[self shellIntegrationPath]];
    [self.delegate shellIntegrationWindowControllerSendText:[NSString stringWithFormat:@"chmod +x %@\n", [self shellIntegrationPath]]];
}

- (void)catToUtilities {
    [self catString:@"TODO UTILITIES" to:@"/tmp/TODO"];
}

- (void)shellIntegrationInstallerCatScript {
    [self catToScript];
}

- (void)shellIntegrationInstallerCopyDotfileCommand {
    [self copyString:[[self dotfileCommandWithBashDotfile:@"~/.bash_profile"] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]];
}

- (void)shellIntegrationInstallerAmendDotfile {
    [self amendDotFileWithCompletion:^{}];
}

- (void)shellIntegrationInstallerCopyUntar {
    [self copyString:@"base64 -D | tar xfz -"];
}

- (void)shellIntegrationInstallerCopyUtilitiesTarball {
    [self copyString:@"TODO - UTILITIES TARBALL"];
}

- (void)shellIntegrationInstallerUntarUtilities {
    [self.delegate shellIntegrationWindowControllerSendText:@"base64 -D | tar xfz -\n"];
    [self.delegate shellIntegrationWindowControllerSendText:@"TODO - UTILITIES TARBALL\n"];
    [self.delegate shellIntegrationWindowControllerSendText:[NSString stringWithFormat:@"%c", 4]];
    [self.delegate shellIntegrationWindowControllerSendText:@"chmod +x imgcat imgls it2api it2attention it2check it2copy it2dl it2getvar it2git it2setcolor it2setkeylabel it2ul it2universion\n"];
}


@end
