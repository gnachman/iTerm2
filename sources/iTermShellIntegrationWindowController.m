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
#import "iTermShellIntegrationFirstPageViewController.h"
#import "iTermShellIntegrationSecondPageViewController.h"
#import "iTermShellIntegrationDownloadAndRunViewController.h"
#import "iTermShellIntegrationPasteShellCommandsViewController.h"
#import "iTermShellIntegrationFinishedViewController.h"

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
@property (nonatomic, copy) NSString *dotdir;
@property (nonatomic) iTermShellIntegrationInstallationState state;
@end

@implementation iTermShellIntegrationWindowController {
    NSMutableArray<iTermExpectation *> *_pendingExpectations;
}

#pragma mark - NSWindowController

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    [self doesNotRecognizeSelector:_cmd];
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

#pragma mark - State Machine

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
        [self.currentViewController willAppear];
    }
    [self.containerView addSubview:self.currentViewController.view];
    NSRect frame = self.currentViewController.view.frame;
    frame.origin.x = 0;
    frame.origin.y = self.containerView.bounds.size.height - frame.size.height;
    self.currentViewController.view.frame = frame;
    self.downloadAndRunViewController.installUtilities = self.installUtilities;
    NSRect rect = self.window.frame;
    const CGFloat originalMaxY = NSMaxY(rect);
    rect.size = self.currentViewController.view.bounds.size;
    rect.size.height += self.header.bounds.size.height;
    rect = [NSWindow frameRectForContentRect:rect styleMask:self.window.styleMask];
    rect.origin.y = originalMaxY - NSHeight(rect);
    [self.window setFrame:rect display:YES animate:YES];
}

#pragma mark - Accessors

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

#pragma mark - Expectations

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
        if (text) {
            [weakSelf.delegate shellIntegrationWindowControllerSendText:text];
        }
    }
                       completion:completion];
    if (!*expectation) {
        *expectation = newExpectation;
    }
    return text;
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
                                                           deadline:nil
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

- (void)cancelAllExpectations {
    [_pendingExpectations enumerateObjectsUsingBlock:^(iTermExpectation * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [[self.delegate shellIntegrationExpect] cancelExpectation:obj];
    }];
    [_pendingExpectations removeAllObjects];
    [self.currentViewController setBusy:NO];
}

#pragma mark - Actions

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

#pragma mark - String Builders

- (NSString *)shellIntegrationPath {
    return [NSString stringWithFormat:@"%@/.iterm2_shell_integration.%@",
            self.dotdir, iTermShellIntegrationShellString(self.shell)];
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
                return [NSString stringWithFormat:@"alias %@=%@/.iterm2/%@", command, self.dotdir, command];
            case iTermShellIntegrationShellTcsh:
                return [NSString stringWithFormat:@"alias %@ %@/.iterm2/%@", command, self.dotdir, command];
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

- (NSString *)dotfileCommandWithBashDotfile:(NSString *)bashDotFile {
    NSString *shell_and = @"&&";
    NSString *shell_or = @"||";
    NSString *quote = @"";
    switch (self.shell) {
        case iTermShellIntegrationShellTcsh:
        case iTermShellIntegrationShellZsh:
        case iTermShellIntegrationShellBash:
            break;
        case iTermShellIntegrationShellFish:
            shell_and=@"; and";
            shell_or=@"; or";
            break;
        case iTermShellIntegrationShellUnknown:
            assert(NO);
        }
    NSString *relative_filename = [NSString stringWithFormat:@"%@/.iterm2_shell_integration.%@",
                                   self.dotdir, iTermShellIntegrationShellString(self.shell)];
    
    return [NSString stringWithFormat:@"test -e %@%@%@ %@ source %@%@%@ %@ true\n",
            quote, relative_filename, quote, shell_and, quote, relative_filename, quote, shell_or];
}

#pragma mark - AppKit Helpers

- (void)copyString:(NSString *)string {
    NSPasteboard *generalPasteboard = [NSPasteboard generalPasteboard];
    [generalPasteboard declareTypes:@[ NSPasteboardTypeString ] owner:nil];
    [generalPasteboard setString:string forType:NSPasteboardTypeString];
}

#pragma mark - Text Sending

- (NSString *)discoverShell:(BOOL)reallySend completion:(void (^)(NSString *shell, NSString *dotdir))completion {
    iTermExpectation *expectation = nil;
    NSString *result = @"echo My shell is $SHELL\n";
    [self sendText:result
        reallySend:reallySend
        afterRegex:@"^My shell is (.+)"
       expectation:&expectation
        completion:^(NSArray<NSString *> *captures) {
        NSString *shell = [captures[1] lastPathComponent];
        if ([shell isEqualToString:@"zsh"]) {
            [self sendText:@"echo My dotfiles go in ${ZDOTDIR:-$HOME}\n" reallySend:reallySend];
            iTermExpectation *expectation = nil;
            [self sendText:nil
                reallySend:reallySend
                afterRegex:@"^My dotfiles go in (.*)"
               expectation:&expectation
                completion:^(NSArray<NSString *> *dotdirCaptures) {
                completion(shell, dotdirCaptures[1]);
            }];
        } else if ([shell isEqualToString:@"fish"]) {
            completion(shell, @"$HOME");
        } else {
            completion(shell, @"~");
        }
    }];
    return result;
}

- (NSString *)amendDotFileWithExpectation:(inout iTermExpectation **)expectation
                               completion:(void (^)(void))completion {
    const BOOL reallySend = (completion != nil);
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    NSArray<NSString *> *parts = [[[self launchBashString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsSeparatedByString:@"\n"];
    parts = [parts mapWithBlock:^id(NSString *anObject) {
        return [anObject stringByAppendingString:@"\n"];
    }];
    [strings addObjectsFromArray:parts];

    NSString *script = nil;
    switch (self.shell) {
        case iTermShellIntegrationShellTcsh:
            script = @"~/.login";
            break;
        case iTermShellIntegrationShellZsh:
            script = [self.dotdir stringByAppendingPathComponent:@".zshrc"];
            break;
        case iTermShellIntegrationShellBash: {
            NSString *assignment = @"IT2_INSTALLER_DOTFILE=$(test -f ~/.bash_profile && echo -n ~/.bash_profile || echo -n ~/.profile)\n";
            [strings addObject:assignment];
            script = @"\"$IT2_INSTALLER_DOTFILE\"";
            break;
        }
        case iTermShellIntegrationShellFish:
            [strings addObject:@"mkdir -p ~/.config/fish\n"];
            script = @"~/.config/fish/config.fish";
            break;
        case iTermShellIntegrationShellUnknown:
            assert(NO);
    }
    [self sendText:[strings componentsJoinedByString:@""] reallySend:reallySend];
    NSString *joined = [strings componentsJoinedByString:@""];
    [strings removeAllObjects];

    [strings addObject:[self sendText:[NSString stringWithFormat:@"if ! grep iterm2_shell_integration %@  > /dev/null 2>&1; then\n", script]
                           reallySend:reallySend
                           afterRegex:@"^>> "
                          expectation:expectation]];
    [strings addObject:[self sendText:[NSString stringWithFormat:@"    cat <<-EOF >> %@\n\n", script]
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
    [strings addObject:[self sendText:self.exitBashString
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

- (NSString *)launchBashString {
    return @"bash --noprofile --norc\nINPUTRC='/dev/null' bash --noprofile --norc\n PS1='>> '; PS2='> '\n";
}

- (NSString *)exitBashString {
    return @"exit\nexit\n";
}

- (NSString *)switchToBash:(BOOL)reallySend
               expectation:(inout iTermExpectation **)expectation {
    return [self sendText:self.launchBashString
               reallySend:reallySend
               afterRegex:@"."
              expectation:expectation];
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
    [result appendString:[self sendText:self.exitBashString
                             reallySend:reallySend
                          afterRegex:@"> EOF"
                            expectation:expectation]];
    return result;
}

- (NSString *)catToScript:(BOOL)reallySend
               completion:(void (^)(void))completion {
    NSString *scriptForShell = [self scriptForCurrentShell];
    if (!scriptForShell) {
        return @"# Error: your shell could not be determined or is unsupported.";
    }
    NSMutableString *result = [NSMutableString string];
    iTermExpectation *expectation = nil;
    [result appendString:[self switchToBash:reallySend expectation:&expectation]];
    [result appendString:[self catString:scriptForShell
                                      to:[self shellIntegrationPath]
                              reallySend:reallySend
                             expectation:&expectation]];
    [result appendString:[self sendText:[NSString stringWithFormat:@"chmod +x %@\n", [self shellIntegrationPath]]
                             reallySend:reallySend
                             afterRegex:@"^>> "
                            expectation:&expectation]];
    [result appendString:[self sendText:self.exitBashString
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
    NSString *folder = [self.dotdir stringByAppendingPathComponent:@".iterm2"];
    [result appendString:[self switchToBash:reallySend expectation:expectation]];
    [result appendString:[self sendText:[NSString stringWithFormat:@"mkdir %@; echo ok\n", folder]
                             reallySend:reallySend
                             afterRegex:@"."
                            expectation:expectation]];
    [result appendString:[self sendText:[NSString stringWithFormat:@"cd %@; echo ok\n", folder]
                             reallySend:reallySend
                             afterRegex:@"^ok$"
                            expectation:expectation]];
    [result appendString:[self sendText:@"base64 --decode <<'EOF'| tar xfz -\n"
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
    [result appendString:[self sendText:self.exitBashString
                             reallySend:reallySend
                             afterRegex:@"> EOF"
                            expectation:expectation
                             completion:^(NSArray<NSString *> *captures) {
        completion();
    }]];
    return result;
}

#pragma mark - Orchestration

- (NSString *)discoverShell:(BOOL)reallySend {
    __weak __typeof(self) weakSelf = self;
    return [self discoverShell:reallySend completion:^(NSString *shell, NSString *dotdir) {
        [weakSelf didDiscoverShell:shell dotdir:dotdir];
    }];
}

- (void)didDiscoverShell:(NSString *)shell dotdir:(NSString *)dotdir {
    NSDictionary<NSString *, NSNumber *> *map = @{ @"tcsh": @(iTermShellIntegrationShellTcsh),
                                                   @"bash": @(iTermShellIntegrationShellBash),
                                                   @"zsh": @(iTermShellIntegrationShellZsh),
                                                   @"fish": @(iTermShellIntegrationShellFish) };
    NSNumber *number = map[shell ?: @""];
    self.dotdir = dotdir;
    if (number) {
        self.shell = number.integerValue;
    } else {
        self.shell = iTermShellIntegrationShellUnknown;
    }
    self.sendShellCommandsViewController.stage = 1;
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

#pragma mark - iTermShellIntegrationInstallerDelegate

- (void)shellIntegrationInstallerConfirmDownloadAndRun {
    [self setState:iTermShellIntegrationInstallationStateDownloadAndRunConfirm];
}

- (void)shellIntegrationInstallerReallyDownloadAndRun {
    [self.delegate shellIntegrationWindowControllerSendText:[self curlPipeBashCommand]];
    __weak __typeof(self) weakSelf = self;

    [self expectRegularExpression:@"(^Done.$)|(^Your shell, .*, is not supported yet)"
                            after:nil
                       willExpect:nil
                       completion:^(NSArray<NSString *> * _Nonnull captureGroups) {
        if ([captureGroups[0] hasPrefix:@"Your shell"]) {
            [self.downloadAndRunViewController showShellUnsupportedError];
        } else {
            [weakSelf next:nil];
        }
    }];
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

- (void)shellIntegrationInstallerSkipStage {
    const int stage = self.sendShellCommandsViewController.stage;
    
    const int lastStage = self.installUtilities ? 4 : 3;
    if (stage + 1 > lastStage) {
        return;
    }
    self.sendShellCommandsViewController.stage = stage + 1;
}

- (void)shellIntegrationInstallerCancelExpectations {
    [self cancelAllExpectations];
}

@end
