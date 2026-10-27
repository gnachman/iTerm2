//
//  iTermShellIntegrationWindowController.m
//  iTerm2
//
//  Created by George Nachman on 12/18/19.
//

#import "iTermShellIntegrationWindowController.h"

#import "DebugLogging.h"
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
        case iTermShellIntegrationShellBash:
            return @"bash";
        case iTermShellIntegrationShellFish:
            return @"fish";
        case iTermShellIntegrationShellTcsh:
            return @"tcsh";
        case iTermShellIntegrationShellXonsh:
            return @"xonsh";
        case iTermShellIntegrationShellNu:
            return @"nu";
        case iTermShellIntegrationShellZsh:
            return @"zsh";
        case iTermShellIntegrationShellUnknown:
            return @"an unsupported shell";
    }
}

BOOL iTermShellIntegrationShellLoadsScriptAutomatically(iTermShellIntegrationShell shell) {
    switch (shell) {
        case iTermShellIntegrationShellXonsh:
        case iTermShellIntegrationShellNu:
            return YES;
        case iTermShellIntegrationShellBash:
        case iTermShellIntegrationShellTcsh:
        case iTermShellIntegrationShellZsh:
        case iTermShellIntegrationShellFish:
        case iTermShellIntegrationShellUnknown:
            return NO;
    }
    return NO;
}

// Asks nu where it autoloads per-user scripts from, keeps the answer in the helper shell, and
// creates that directory. nushell 0.102 and later read $nu.user-autoload-dirs; 0.100 and 0.101
// only read the vendor directories, so there the per-user one under the data directory is used,
// which later versions read too. The website installers run the same query. The command ends by
// printing a line that iTermShellIntegrationNuAutoloadDirReadyRegex matches. The empty quotes
// keep the echo of the typed command from matching it. nu need not be $SHELL (discovery goes by
// the shell reading the commands), so it is looked up in PATH unless $SHELL is nu.
static NSString *const iTermShellIntegrationNuAutoloadDirCommand =
    @"IT2_NU_AUTOLOAD_DIR=$(case \"${SHELL##*/}\" in (nu) IT2_NU=\"$SHELL\";; (*) IT2_NU=$(command -v nu);; esac; \"$IT2_NU\" --no-config-file -c 'print ($nu.user-autoload-dirs? | default [($nu.data-dir | path join vendor autoload)] | first)'); mkdir -p \"$IT2_NU_AUTOLOAD_DIR\"; echo iTerm2-nu-autoload-dir-\"\"ready\n";
static NSString *const iTermShellIntegrationNuAutoloadDirReadyRegex = @"^iTerm2-nu-autoload-dir-ready$";

// Files go to the helper sh base64-encoded, in short lines, which a read loop in sh takes from the
// tty into a file (see receiveText:withCommand:name:resultRegex:success:expectation:completion:).
// These are the pieces of the commands that do that. OpenBSD has no base64 command, but it has
// b64decode. The loop stops at a line that is just EOF, which base64 never produces (its lines are
// multiples of four characters).
#define iTermShellIntegrationChooseBase64Decoder \
    @"if command -v base64 >/dev/null 2>&1; then IT2_B64D='base64 -d'; else IT2_B64D='b64decode -r'; fi; "
#define iTermShellIntegrationReadLinesUntilEOF \
    @"while IFS= read -r IT2_LINE && test \"$IT2_LINE\" != EOF; do printf '%s\\n' \"$IT2_LINE\"; done; "

// Typed into the helper sh in the utilities folder. Reads the base64 archive from the tty up to
// a line that is just EOF into a file (with read, so not through a line editor), decodes it
// into a second file, extracts that, and removes both files.
//
// It prints it2-receiving-utilities only once the file the archive goes into is open, so the
// archive can't be typed into sh's prompt. The redirection is on the group that prints it, so
// if the file can't be created (say the folder isn't writable) the group doesn't run and sh
// prints it2-cannot-receive-utilities instead. fd 3 is sh's own stdout, since the group's goes
// to the file.
//
// Then it prints it2-utilities-installed only if decoding succeeded, tar succeeded, and a file
// from the archive is there; otherwise it2-utilities-failed. Each step's status is checked
// separately because there is no pipefail in POSIX sh, and tar given no input at all succeeds.
// tar reads the whole archive once before extracting anything, which checks gzip's CRC, so a
// damaged or partial archive (as when Cancel stops typing it) doesn't overwrite any utility
// with part of a file.
//
// The archive also carries iTerm2's Python it2 in it2-files: the wrapper for ~/.iterm2/bin/it2
// and the interpreter it names. Those belong in $HOME's .iterm2 even when the utilities go under
// $ZDOTDIR, because the shell-integration scripts, Claude Code hooks and the wrapper look there.
// They get no alias (see utilities-manifest.txt): the wrapper itself decides between them and the
// native it2 on this Mac. Copying them is part of the same command, so the installer's sequence of
// expected output is unchanged, and a failed copy reports the install as failed.
//
// The empty quotes keep the echo of the command from matching any of these.
static NSString *const iTermShellIntegrationReceiveUtilitiesCommand =
    iTermShellIntegrationChooseBase64Decoder
    @"if { echo it2-\"\"receiving-utilities >&3; "
    iTermShellIntegrationReadLinesUntilEOF @"} 3>&1 > .it2-utilities.b64; then "
    @"if $IT2_B64D < .it2-utilities.b64 > .it2-utilities.tgz && tar tfz .it2-utilities.tgz > /dev/null && "
    @"tar xfz .it2-utilities.tgz && test -s it2check && "
    @"mkdir -p ~/.iterm2/bin && cp -p it2-files/bin/it2 ~/.iterm2/bin/it2 && cp -p it2-files/it2.*.py ~/.iterm2/; "
    @"then echo it2-\"\"utilities-installed; else echo it2-\"\"utilities-failed; fi; "
    @"else echo it2-\"\"cannot-receive-utilities; fi; "
    @"rm -f .it2-utilities.b64 .it2-utilities.tgz; rm -rf it2-files\n";

// Typed into the helper sh to write the shell integration script to the path {path} (IT2_F, so
// the command stays short with a long path), the way the utilities archive is received: the
// script is typed base64-encoded after sh says it is reading it into $IT2_F.it2-b64, with the
// same answers but for “script” in place of “utilities”. sh then decodes it into $IT2_F.it2-new,
// and only if that is the whole script, as POSIX cksum (whose first two words, without the blanks
// and file name some versions print, must be {cksum}) says, copies it over $IT2_F (through a symlink, keeping
// its owner) and makes that executable. It prints it2-script-written if all of that succeeded and
// it2-script-failed otherwise, so a script cut short, as by Cancel, never replaces the one there.
// Both temporary files are removed.
static NSString *const iTermShellIntegrationReceiveScriptCommandTemplate =
    @"IT2_F={path}; "
    iTermShellIntegrationChooseBase64Decoder
    @"if { echo it2-\"\"receiving-script >&3; "
    iTermShellIntegrationReadLinesUntilEOF @"} 3>&1 > \"$IT2_F.it2-b64\"; then "
    @"if $IT2_B64D < \"$IT2_F.it2-b64\" > \"$IT2_F.it2-new\" && set -- $(cksum < \"$IT2_F.it2-new\") && test \"$1 $2\" = '{cksum}' && "
    @"cat \"$IT2_F.it2-new\" > \"$IT2_F\" && chmod +x \"$IT2_F\"; "
    @"then echo it2-\"\"script-written; else echo it2-\"\"script-failed; fi; "
    @"else echo it2-\"\"cannot-receive-script; fi; "
    @"rm -f \"$IT2_F.it2-b64\" \"$IT2_F.it2-new\"\n";

// The prompt of the innermost helper sh (PS1 in launchHelperShellString), at the start of a row
// or right after iTermShellIntegrationHelpersReadyMarker. A line editor that breaks the echo of a
// long command line can start a row with the >> in PS1=">> " or PS1='>> ', which must not count.
//
// The marker is there because an sh without a line editor, such as dash (the sh of Debian and
// Ubuntu), doesn't echo the lines of the launch that were typed ahead while the user's shell
// read the first one. So the helper prompt goes on the row where the helpers' own default
// prompts (or an exported PS1) are, after them, and that row doesn't start with it. The line that
// sets PS1 prints the marker with no newline, so the helper prompt follows it on the same row.
// The marker is written with empty quotes in that line, so the line's echo doesn't contain it.
#define iTermShellIntegrationHelpersReadyMarker @"it2-helpers-ready "
static NSString *const iTermShellIntegrationHelperPromptRegex = @"(?:^|" iTermShellIntegrationHelpersReadyMarker @")>> (?![\"'])";

// Typed into the innermost helper sh to learn when it reads commands again. The answer includes
// the helper's PS1, so if the helpers were somehow gone the user's shell would not give it. The
// empty quotes keep the echo of the command from matching iTermShellIntegrationHelpersIdleRegex.
static NSString *const iTermShellIntegrationHelpersIdleCommand = @"echo \"it2-\"\"helpers-$PS1-idle\"\n";
static NSString *const iTermShellIntegrationHelpersIdleRegex = @"it2-helpers->> -idle";

// How long to wait after a cancel for helpers whose launch was typed to prompt, so they can be
// exited. They prompt once the user's shell has run the line that starts them, which can take a
// while: a heavy preexec hook or a busy machine delays it by seconds, not minutes. The longer
// the wait, the likelier a “>> ” at the start of a row comes from something else the user does
// after they are back at their own shell, and exits typed then would end it, so it is not much
// longer than that. Waiting less only means the helpers are left running, as if never awaited.
static const NSTimeInterval iTermShellIntegrationCanceledHelperLaunchTimeout = 30;

// Asks a shell how many helper sh it is nested in (IT2_INSTALLER_HELPER, which each helper
// launchHelperShellString starts sets one higher than its parent's). The empty quotes keep the
// echo of the command from matching iTermShellIntegrationHelperDepthRegex. Typed into a shell
// other than sh, it prints something else or an error.
static NSString *const iTermShellIntegrationHelperDepthCommand = @"echo \"it2-\"\"helper-depth-${IT2_INSTALLER_HELPER:-0}-\"\n";
static NSString *const iTermShellIntegrationHelperDepthRegex = @"it2-helper-depth-([0-9]+)-";

// What iTerm2 knows about the helper sh processes the installer starts in the session. It is
// updated from their output, never just from what was typed, because exit typed into the user's
// own shell would end it. Text typed into a helper after a single-line command is read as the
// next command, so the helpers are idle until something that reads more than one line is typed.
typedef NS_ENUM(NSUInteger, iTermShellIntegrationHelperState) {
    // No helper is running, as far as the installer knows: what is typed goes to the user's shell.
    iTermShellIntegrationHelperStateNone,
    // The helpers were launched and have not prompted yet.
    iTermShellIntegrationHelperStateLaunching,
    // _helperShellDepth helpers are running and the innermost reads the next line as a command.
    iTermShellIntegrationHelperStateIdle,
    // The innermost helper is in its loop that reads the utilities archive or the shell
    // integration script.
    iTermShellIntegrationHelperStateReceivingFile,
    // Something was typed whose end won't be, such as part of an if statement whose remaining
    // lines were canceled, or nothing is known.
    iTermShellIntegrationHelperStateUnknown,
};

typedef NS_ENUM(NSUInteger, iTermShellIntegrationInstallationState) {
    iTermShellIntegrationInstallationStateFirstPage,
    iTermShellIntegrationInstallationStateSecondPage,
    iTermShellIntegrationInstallationStateDownloadAndRunConfirm,
    iTermShellIntegrationInstallationStateSendShellCommandsConfirm,
    iTermShellIntegrationInstallationStateConfirmation
};

@interface iTermShellIntegrationWindowController ()
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
    // Incremented by cancelAllExpectations, so a command whose typing was already queued when
    // its expectation was canceled is not typed.
    NSUInteger _cancellationGeneration;
    iTermShellIntegrationHelperState _helperState;
    // How many helper sh are running when _helperState says they are known to run: 0, or
    // helperShellLevels once their prompt or their answer to a command has been seen.
    NSInteger _helperShellDepth;
    // Completes once the innermost helper reads commands again, when that is awaited after a
    // cancel. Steps sent in the meantime are chained after it. It is not canceled with the
    // installer's other expectations, since what it types is what makes the helpers usable.
    iTermExpectation *_helpersIdleExpectation;
    // Exit the helpers when _helpersIdleExpectation completes, as after Cancel.
    BOOL _exitHelpersWhenIdle;
    // Run once _helpersIdleExpectation has typed the exits, to type into the user's shell.
    void (^_afterHelpersExit)(void);
    // How many texts the installer has typed. See typeText:.
    NSUInteger _typedTextCount;
    // The last text typed was one whose expectation's match shows the helpers read commands, so
    // when the next command's expectation becomes active (which happens only on that match) they
    // are idle, even if the match's completion has not run yet.
    BOOL _lastTextIsIdleOnMatch;
    // An installer for the same session that this one replaced, while it may still have helper
    // shells to exit. See takeOverHelperShellsFromInstaller:.
    iTermShellIntegrationWindowController *_previousInstaller;
    // Identifies the current wait of awaitCanceledHelperLaunchTypingNewline:, for its timer.
    NSUInteger _canceledHelperLaunchWaitID;
    // See cancelHelpersIdleExpectation.
    NSUInteger _helpersIdleExpectationGeneration;
    // While the helper receives a file, whether typing the file itself (rather than the command
    // that receives it) has begun. See helpersIdleExpectation.
    BOOL _receivedTextTyped;
}

- (instancetype)initWithWindow:(NSWindow *)window {
    self = [super initWithWindow:window];
    if (self) {
        _canceledHelperLaunchTimeout = iTermShellIntegrationCanceledHelperLaunchTimeout;
    }
    return self;
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
    if (state != iTermShellIntegrationInstallationStateSendShellCommandsConfirm) {
        [self exitHelperShellsWhenPossible];
    }
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
    [self fitWindowToCurrentView];
}

- (void)fitWindowToCurrentView {
    NSRect rect = self.window.frame;
    const CGFloat originalMaxY = NSMaxY(rect);
    rect.size = self.currentViewController.view.bounds.size;
    rect.size.height += self.header.bounds.size.height;
    rect = [NSWindow frameRectForContentRect:rect styleMask:self.window.styleMask];
    rect.origin.y = originalMaxY - NSHeight(rect);
    [self.window setFrame:rect display:YES animate:YES];
}

#pragma mark - Accessors

- (int)sendShellCommandsStage {
    return self.sendShellCommandsViewController.stage;
}

- (NSTextField *)sendShellCommandsStepListField {
    return self.sendShellCommandsViewController.stepListField;
}

- (BOOL)sendShellCommandsWriteFailed {
    return self.sendShellCommandsViewController.writeFailed;
}

+ (NSString *)receiveUtilitiesCommand {
    return iTermShellIntegrationReceiveUtilitiesCommand;
}

+ (NSString *)helperPromptRegex {
    return iTermShellIntegrationHelperPromptRegex;
}

// The archive is unpacked in the current directory, so the answer says whether cd worked (it
// fails when ~/.iterm2 is a file, for example). The empty quotes keep the echo of the command
// from looking like either answer.
+ (NSString *)commandToEnterUtilitiesFolder:(NSString *)folder {
    return [NSString stringWithFormat:@"cd %@ && echo it2-\"\"cd-done || echo it2-\"\"cd-failed\n", folder];
}

- (BOOL)showingDownloadAndRunPage {
    return self.state == iTermShellIntegrationInstallationStateDownloadAndRunConfirm;
}

- (BOOL)showingSendShellCommandsPage {
    return self.state == iTermShellIntegrationInstallationStateSendShellCommandsConfirm;
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
    return [self sendText:text
               reallySend:reallySend
               afterRegex:regex
              expectation:expectation
                  didSend:nil
               completion:completion];
}

// didSend is called right after text is typed.
- (NSString *)sendText:(NSString *)text
            reallySend:(BOOL)reallySend
            afterRegex:(NSString *)regex
           expectation:(inout iTermExpectation **)expectation
               didSend:(void (^)(void))didSend
            completion:(void (^)(NSArray<NSString *> *))completion {
    return [self sendText:text
               reallySend:reallySend
               afterRegex:regex
              expectation:expectation
                  didSend:didSend
              idleOnMatch:NO
               completion:completion];
}

// If idleOnMatch, a match of regex shows the helpers read commands. That is recorded only if
// nothing was typed since text: the completion can run after the next text in the chain was
// typed (iTermExpect may run it after the successor's callback), and that text, such as the start
// of a here-document, may have made them busy again.
- (NSString *)sendText:(NSString *)text
            reallySend:(BOOL)reallySend
            afterRegex:(NSString *)regex
           expectation:(inout iTermExpectation **)expectation
               didSend:(void (^)(void))didSend
           idleOnMatch:(BOOL)idleOnMatch
            completion:(void (^)(NSArray<NSString *> *))completion {
    if (!reallySend) {
        return text;
    }

    __weak __typeof(self) weakSelf = self;
    const NSUInteger generation = _cancellationGeneration;
    // How many texts had been typed once this one was, or NSNotFound before it is typed.
    __block NSUInteger typedCount = NSNotFound;
    iTermExpectation *newExpectation =
    [self expectRegularExpression:regex
                            after:(*expectation).lastExpectation
                       willExpect:^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_cancellationGeneration != generation) {
            DLog(@"Not sending text for a canceled expectation");
            return;
        }
        if (strongSelf->_lastTextIsIdleOnMatch) {
            [strongSelf helperShellsBecameIdle];
        }
        strongSelf->_lastTextIsIdleOnMatch = NO;
        if (text) {
            [strongSelf typeText:text];
        }
        if (didSend) {
            didSend();
        }
        typedCount = strongSelf->_typedTextCount;
        if (idleOnMatch) {
            strongSelf->_lastTextIsIdleOnMatch = YES;
        }
    }
                       completion:^(NSArray<NSString *> *captures) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (idleOnMatch && strongSelf && strongSelf->_typedTextCount == typedCount) {
            [strongSelf helperShellsBecameIdle];
        }
        if (completion) {
            completion(captures);
        }
    }];
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
    _cancellationGeneration += 1;
    [_pendingExpectations enumerateObjectsUsingBlock:^(iTermExpectation * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [[self.delegate shellIntegrationExpect] cancelExpectation:obj];
    }];
    [_pendingExpectations removeAllObjects];
    _afterHelpersExit = nil;
    _lastTextIsIdleOnMatch = NO;
    if (_helperState == iTermShellIntegrationHelperStateReceivingFile) {
        // Stops typing the file and ends sh's read loop. See helpersIdleExpectation.
        [self helpersIdleExpectation];
    }
    [self.currentViewController setBusy:NO];
}

#pragma mark - Helper Shells

// How many helper sh launchHelperShellString starts.
- (NSInteger)helperShellLevels {
    if (self.shell == iTermShellIntegrationShellXonsh || self.shell == iTermShellIntegrationShellNu) {
        return 1;
    }
    return 2;
}

// The innermost helper was seen reading commands.
- (void)helperShellsBecameIdle {
    _receivedTextTyped = NO;
    _helperState = iTermShellIntegrationHelperStateIdle;
    _helperShellDepth = [self helperShellLevels];
    DLog(@"Helper shells are idle at depth %@", @(_helperShellDepth));
}

// Types one exit for each helper known to be running, ending at the user's shell. Only valid
// while the helpers are idle.
- (void)exitIdleHelperShells {
    if (_helperState != iTermShellIntegrationHelperStateIdle) {
        DLog(@"Not exiting helper shells in state %@", @(_helperState));
        return;
    }
    NSMutableString *exits = [NSMutableString string];
    for (NSInteger i = 0; i < _helperShellDepth; i++) {
        [exits appendString:@"exit\n"];
    }
    DLog(@"Exit %@ helper shells", @(_helperShellDepth));
    _helperState = iTermShellIntegrationHelperStateNone;
    _helperShellDepth = 0;
    if (exits.length > 0) {
        [self typeText:exits];
    }
}

// An expectation that completes once the helpers, which are running but busy, read commands
// again, or nil when that can't be awaited. It types what it takes to get there:
// - While they launch, an empty line, so a prompt follows even if their first one went by.
// - While sh reads the utilities archive (which takes a minute or more to type) or the shell
//   integration script, typing it stops and the line that ends sh's read loop is typed, as the
//   file would have ended. Otherwise sh would keep taking whatever is typed next into its file.
//   The newline first ends a line the stop may have cut. sh then finds that what it got is not
//   the whole file, removes its temporary files, and prompts. This is safe because sh checks the
//   whole archive before unpacking any of it, and the script's checksum before writing it, so a
//   partial one installs nothing. If sh has not read the receive command yet, its loop reads
//   just these lines and ends the same way.
// Then a command whose answer shows the helper reads commands, typed only once this expectation
// is in place so the answer can't go by unseen.
- (iTermExpectation *)helpersIdleExpectation {
    if (_helpersIdleExpectation) {
        return _helpersIdleExpectation;
    }
    NSString *text = nil;
    NSString *regex = iTermShellIntegrationHelpersIdleRegex;
    switch (_helperState) {
        case iTermShellIntegrationHelperStateNone:
        case iTermShellIntegrationHelperStateIdle:
        case iTermShellIntegrationHelperStateUnknown:
            return nil;
        case iTermShellIntegrationHelperStateLaunching:
            text = @"\n";
            regex = iTermShellIntegrationHelperPromptRegex;
            break;
        case iTermShellIntegrationHelperStateReceivingFile:
            // Typing is stopped only once the file is being typed. Before that, what is still
            // being typed is the receive command, and stopping it partway could leave sh waiting
            // for the rest of an if statement or a quoted string. Typed whole, it is followed by
            // the lines below, which end its loop.
            if (_receivedTextTyped) {
                [self.delegate shellIntegrationWindowControllerStopSendingText];
            }
            text = [@"\nEOF\n" stringByAppendingString:iTermShellIntegrationHelpersIdleCommand];
            break;
    }
    DLog(@"Wait for helper shells to become idle in state %@", @(_helperState));
    __weak __typeof(self) weakSelf = self;
    __block NSUInteger typedCount = NSNotFound;
    const NSUInteger expectationGeneration = _helpersIdleExpectationGeneration;
    _helpersIdleExpectation =
    [[self.delegate shellIntegrationExpect] expectRegularExpression:regex
                                                              after:nil
                                                           deadline:nil
                                                         willExpect:^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_helpersIdleExpectationGeneration != expectationGeneration) {
            return;
        }
        [strongSelf typeText:text];
        typedCount = strongSelf->_typedTextCount;
        // A step chained after this expectation runs only once it matched.
        strongSelf->_lastTextIsIdleOnMatch = YES;
    }
                                                         completion:^(NSArray<NSString *> * _Nonnull captureGroups) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf->_helpersIdleExpectation = nil;
        if (strongSelf->_typedTextCount != typedCount) {
            // A step chained after this one already typed into the helpers (this completion
            // can run after its callback), so they may be busy again. Its own commands track
            // them from here.
            DLog(@"Text was typed since the helpers became idle");
            strongSelf->_exitHelpersWhenIdle = NO;
            [strongSelf runAfterHelpersExit];
            return;
        }
        [strongSelf helperShellsBecameIdleAfterWaiting];
    }];
    return _helpersIdleExpectation;
}

// The helpers, which were awaited, read commands. Exit them if that is what was awaited.
- (void)helperShellsBecameIdleAfterWaiting {
    [self helperShellsBecameIdle];
    if (!_exitHelpersWhenIdle) {
        return;
    }
    _exitHelpersWhenIdle = NO;
    [self exitIdleHelperShells];
    [self runAfterHelpersExit];
}

// Leaves the helpers for the user's shell when it is known to be safe: right away if they are
// idle, or once they are if that can be awaited. Otherwise nothing is typed, since an exit
// that reached the user's shell would end it.
- (void)exitHelperShellsWhenPossible {
    if (_helperState == iTermShellIntegrationHelperStateIdle) {
        [self exitIdleHelperShells];
        return;
    }
    if (_helperState == iTermShellIntegrationHelperStateLaunching) {
        // Their launch was not confirmed, so they may not be running. Wait (for a while) to find
        // out instead. A wait a step started for them (as for Send Again) has no time limit, so
        // it is replaced. Its prompt may have gone by, so the new wait asks for another with an
        // empty line, as that one did; that is harmless in the user's shell, too.
        _exitHelpersWhenIdle = YES;
        if (!_waitingForCanceledHelperLaunch) {
            const BOOL replacing = (_helpersIdleExpectation != nil);
            [self cancelHelpersIdleExpectation];
            [self awaitCanceledHelperLaunchTypingNewline:replacing];
        }
        return;
    }
    if ([self helpersIdleExpectation]) {
        _exitHelpersWhenIdle = YES;
    }
}

// Waits for helpers whose launch was typed but whose prompt has not been seen, as when Cancel is
// clicked while the user's shell is slow to start them, so they can be exited. A “>> ” prompt
// alone doesn't show how many helpers run: it could be the user's own prompt, or one helper
// could have started without the other (say, after Control-C). So once a prompt shows up, the
// shell that printed it is asked how many helpers it is nested in (IT2_INSTALLER_HELPER, see
// launchHelperShellString), and the exits are typed only if that is how many were launched.
// Asking is safe: in the user's shell the command prints something else, or an error.
// After canceledHelperLaunchTimeout the wait ends without typing anything more. The timeout only
// limits how long a prompt is trusted, so a slow machine can at worst leave the helpers running,
// as if they had not been awaited.
// If typeNewline, an empty line is typed once the wait is in place, to get a fresh prompt.
- (void)awaitCanceledHelperLaunchTypingNewline:(BOOL)typeNewline {
    DLog(@"Wait for the prompt of helper shells whose launch was canceled");
    _canceledHelperLaunchWaitID += 1;
    const NSUInteger waitID = _canceledHelperLaunchWaitID;
    __weak __typeof(self) weakSelf = self;
    // NSNotFound until the empty line, if any, is typed.
    __block NSUInteger typedCount = typeNewline ? NSNotFound : _typedTextCount;
    const NSUInteger expectationGeneration = _helpersIdleExpectationGeneration;
    _helpersIdleExpectation =
    [[self.delegate shellIntegrationExpect] expectRegularExpression:iTermShellIntegrationHelperPromptRegex
                                                              after:nil
                                                           deadline:nil
                                                         willExpect:^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!typeNewline ||
            !strongSelf ||
            strongSelf->_helpersIdleExpectationGeneration != expectationGeneration) {
            return;
        }
        [strongSelf typeText:@"\n"];
        typedCount = strongSelf->_typedTextCount;
    }
                                                         completion:^(NSArray<NSString *> * _Nonnull captureGroups) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (strongSelf->_typedTextCount != typedCount) {
            // Nothing else is typed while this waits, but if something was, the prompt says
            // nothing about where the helpers are now.
            DLog(@"Text was typed while waiting for canceled helper shells to prompt");
            [strongSelf endCanceledHelperLaunchWait];
            return;
        }
        [strongSelf askCanceledHelpersForTheirDepth];
    }];
    _waitingForCanceledHelperLaunch = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_canceledHelperLaunchTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf ||
            !strongSelf->_waitingForCanceledHelperLaunch ||
            strongSelf->_canceledHelperLaunchWaitID != waitID) {
            // It ended, or a step took over the wait.
            return;
        }
        DLog(@"Stop waiting for canceled helper shells");
        [strongSelf endCanceledHelperLaunchWait];
    });
}

// The second part of awaitCanceledHelperLaunchTypingNewline:, once a prompt was seen.
- (void)askCanceledHelpersForTheirDepth {
    DLog(@"Ask the shell that prompted how many helper shells it is in");
    __weak __typeof(self) weakSelf = self;
    // Typed only once the expectation is in place, so a fast answer can't go by unseen.
    __block NSUInteger typedCount = NSNotFound;
    const NSUInteger expectationGeneration = _helpersIdleExpectationGeneration;
    _helpersIdleExpectation =
    [[self.delegate shellIntegrationExpect] expectRegularExpression:iTermShellIntegrationHelperDepthRegex
                                                              after:nil
                                                           deadline:nil
                                                         willExpect:^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_helpersIdleExpectationGeneration != expectationGeneration) {
            return;
        }
        [strongSelf typeText:iTermShellIntegrationHelperDepthCommand];
        typedCount = strongSelf->_typedTextCount;
    }
                                                         completion:^(NSArray<NSString *> * _Nonnull captureGroups) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        const NSInteger depth = captureGroups.count > 1 ? [captureGroups[1] integerValue] : 0;
        if (strongSelf->_typedTextCount != typedCount || depth != [strongSelf helperShellLevels]) {
            DLog(@"Not exiting canceled helper shells: depth %@ expected %@, typed since: %@",
                 @(depth), @([strongSelf helperShellLevels]), @(strongSelf->_typedTextCount != typedCount));
            [strongSelf endCanceledHelperLaunchWait];
            return;
        }
        strongSelf->_helpersIdleExpectation = nil;
        strongSelf->_waitingForCanceledHelperLaunch = NO;
        [strongSelf helperShellsBecameIdleAfterWaiting];
    }];
}

// Ends the wait of awaitCanceledHelperLaunchTypingNewline: without knowing about the helpers, typing nothing
// more, and runs what waited for them to exit (such as discovery, which then finds out itself
// whether it runs in one).
- (void)endCanceledHelperLaunchWait {
    [self cancelHelpersIdleExpectation];
    _waitingForCanceledHelperLaunch = NO;
    _helperState = iTermShellIntegrationHelperStateUnknown;
    _helperShellDepth = 0;
    _exitHelpersWhenIdle = NO;
    [self runAfterHelpersExit];
}

- (void)runAfterHelpersExit {
    void (^afterExit)(void) = _afterHelpersExit;
    _afterHelpersExit = nil;
    if (afterExit) {
        afterExit();
    }
}

// Ends the wait of awaitCanceledHelperLaunchTypingNewline: so a step can take over: it waits for the helpers as
// for any launch in progress, which types a line to get a fresh prompt.
- (void)takeOverCanceledHelperLaunchWait {
    if (!_waitingForCanceledHelperLaunch) {
        return;
    }
    DLog(@"A step takes over the wait for canceled helper shells");
    [self cancelHelpersIdleExpectation];
    _waitingForCanceledHelperLaunch = NO;
}

// Cancels _helpersIdleExpectation. Its willExpect callback may already be queued, so callbacks
// check _helpersIdleExpectationGeneration and do nothing once it changed.
- (void)cancelHelpersIdleExpectation {
    _helpersIdleExpectationGeneration += 1;
    if (_helpersIdleExpectation) {
        [[self.delegate shellIntegrationExpect] cancelExpectation:_helpersIdleExpectation];
        _helpersIdleExpectation = nil;
    }
}

// Called by an installer that replaced this one when it stops waiting for this one's helpers:
// this one gives up on them without typing anything more, so it can't type exits later, when
// another installer may be using the session.
- (void)abandonHelperShells {
    DLog(@"Abandon helper shells");
    [self cancelHelpersIdleExpectation];
    _waitingForCanceledHelperLaunch = NO;
    _exitHelpersWhenIdle = NO;
    _afterHelpersExit = nil;
    _helperState = iTermShellIntegrationHelperStateUnknown;
    _helperShellDepth = 0;
    [_previousInstaller abandonHelperShells];
    _previousInstaller = nil;
}

// An installer, this one or one it replaced, that is waiting to exit helper shells, or nil.
- (iTermShellIntegrationWindowController *)installerAwaitingHelperShellExit {
    if (_helpersIdleExpectation && _exitHelpersWhenIdle) {
        return self;
    }
    return [_previousInstaller installerAwaitingHelperShellExit];
}

- (void)takeOverHelperShellsFromInstaller:(iTermShellIntegrationWindowController *)previous {
    _previousInstaller = [previous installerAwaitingHelperShellExit];
}

// Runs block once the helpers this installer waits to exit have exited or it stops waiting.
- (void)performAfterHelperShellsExit:(void (^)(void))block {
    _afterHelpersExit = [block copy];
}

// Starts the helper sh for a step, or reuses the ones already running. Text sent after this goes
// to the innermost helper.
- (NSString *)enterHelperShell:(BOOL)reallySend
                   expectation:(inout iTermExpectation **)expectation {
    if (!reallySend) {
        return self.launchHelperShellString;
    }
    _exitHelpersWhenIdle = NO;
    _afterHelpersExit = nil;
    [self takeOverCanceledHelperLaunchWait];
    if (_helperState == iTermShellIntegrationHelperStateIdle) {
        DLog(@"Reuse idle helper shells");
        return @"";
    }
    iTermExpectation *idle = [self helpersIdleExpectation];
    if (idle) {
        // As after Send Again while the helpers were busy: wait for them rather than start
        // more, which the step's exits would not end.
        DLog(@"Reuse helper shells once they are idle");
        ITAssertWithMessage(*expectation == nil, @"The helpers must be entered first");
        *expectation = idle;
        return @"";
    }
    // nushell and xonsh read typeahead in bulk, so a command sent before the helper sh prompts
    // would be read by them instead of sh, and xonsh runs it once sh exits. Other shells leave
    // typeahead in the tty for sh to read. Either way the prompt is what shows the helpers run.
    return [self sendText:self.launchHelperShellString
               reallySend:YES
               afterRegex:iTermShellIntegrationHelperPromptRegex
              expectation:expectation
                  didSend:[self setHelperStateWhenSent:iTermShellIntegrationHelperStateLaunching]
              idleOnMatch:YES
               completion:nil];
}

// Types the exits that end a step. It must follow a command whose regex matches the helper's
// prompt: this runs once that matched, so the helpers read commands, even if that command's
// completion has not run yet.
- (NSString *)exitHelperShells:(BOOL)reallySend
                    afterRegex:(NSString *)regex
                   expectation:(inout iTermExpectation **)expectation
                    completion:(void (^)(NSArray<NSString *> *))completion {
    NSString *preview = self.exitHelperShellString;
    if (!reallySend) {
        return preview;
    }
    __weak __typeof(self) weakSelf = self;
    [self sendText:nil
        reallySend:YES
        afterRegex:regex
       expectation:expectation
           didSend:^{
        [weakSelf helperShellsBecameIdle];
        [weakSelf exitIdleHelperShells];
    }
        completion:completion];
    return preview;
}

// A didSend block that records the helpers' state once text that changes it has been typed.
- (void (^)(void))setHelperStateWhenSent:(iTermShellIntegrationHelperState)state {
    __weak __typeof(self) weakSelf = self;
    return ^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf->_helperState = state;
        strongSelf->_receivedTextTyped = NO;
        if (state != iTermShellIntegrationHelperStateIdle &&
            state != iTermShellIntegrationHelperStateReceivingFile) {
            strongSelf->_helperShellDepth = 0;
        }
    };
}

#pragma mark - Actions

- (IBAction)cancel:(id)sender {
    [self cancelAllExpectations];
    [self exitHelperShellsWhenPossible];
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
    if (self.shell == iTermShellIntegrationShellXonsh) {
        // Xonsh auto-loads scripts from rc.d, so put it there directly
        return @"~/.config/xonsh/rc.d/iterm2.xsh";
    }
    if (self.shell == iTermShellIntegrationShellNu) {
        // nushell sources the script from its autoload directory, which
        // catToNuScript:reallySend:completion: asks nu for. Quoted because on macOS it is under ~/Library/Application Support.
        return @"\"$IT2_NU_AUTOLOAD_DIR/iterm2_shell_integration.nu\"";
    }
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

    // For xonsh, add utilities directory to PATH instead of aliases
    if (self.shell == iTermShellIntegrationShellXonsh) {
        string = [string stringByAppendingString:@"\n"];
        return [string stringByAppendingString:@"$PATH.insert(0, $HOME + '/.iterm2')"];
    }
    if (self.shell == iTermShellIntegrationShellNu) {
        string = [string stringByAppendingString:@"\n"];
        return [string stringByAppendingString:@"$env.PATH = ($env.PATH | prepend ($env.HOME | path join \".iterm2\"))"];
    }

    // Add aliases for other shells
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
            case iTermShellIntegrationShellXonsh:
            case iTermShellIntegrationShellNu:
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
        case iTermShellIntegrationShellXonsh:
        case iTermShellIntegrationShellNu:
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

+ (NSDictionary<NSString *, NSNumber *> *)shellsByName {
    return @{ @"tcsh": @(iTermShellIntegrationShellTcsh),
              @"bash": @(iTermShellIntegrationShellBash),
              @"zsh": @(iTermShellIntegrationShellZsh),
              @"fish": @(iTermShellIntegrationShellFish),
              @"xonsh": @(iTermShellIntegrationShellXonsh),
              @"nu": @(iTermShellIntegrationShellNu) };
}

// A process name as ps prints it, or nil if it isn't a shell the installer supports.
+ (NSString *)supportedShellNameForProcessName:(NSString *)processName {
    NSString *name = [[processName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lastPathComponent];
    if ([name hasPrefix:@"-"]) {
        // A login shell's argv[0] starts with "-".
        name = [name substringFromIndex:1];
    }
    if ([name isEqualToString:@"csh"]) {
        // macOS's /bin/csh is tcsh.
        name = @"tcsh";
    }
    if (name.length > 0 && self.shellsByName[name]) {
        return name;
    }
    return nil;
}

// The parent process is the shell actually reading the installer's commands, so it wins when
// it is one the installer supports. parentProcess is its executable name (ucomm) followed by its
// argv[0] (comm), or comm alone where ps lacks ucomm. ucomm comes first because tcsh overwrites
// the first character of its argv[0] with "-", so `tcsh` shows up as "-csh" and `csh` as "-sh".
// comm is next because xonsh runs under python but names itself in its process title, which
// also carries its arguments, so comm's first word is tried too. Otherwise (ps is unavailable,
// or the shell is an interpreter without a title) fall back to $SHELL.
+ (NSString *)shellNameForParentProcess:(NSString *)parentProcess shell:(NSString *)shell {
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
    NSString *trimmed = [parentProcess stringByTrimmingCharactersInSet:whitespace];
    const NSRange space = [trimmed rangeOfCharacterFromSet:whitespace];
    NSString *ucomm = space.location == NSNotFound ? trimmed : [trimmed substringToIndex:space.location];
    NSString *comm = space.location == NSNotFound ? @"" : [trimmed substringFromIndex:NSMaxRange(space)];
    NSString *commFirstWord = [comm componentsSeparatedByCharactersInSet:whitespace].firstObject ?: @"";
    NSString *name = ([self supportedShellNameForProcessName:ucomm] ?:
                      [self supportedShellNameForProcessName:comm] ?:
                      [self supportedShellNameForProcessName:commFirstWord]);
    if (name) {
        return name;
    }
    return [[shell stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lastPathComponent];
}

- (NSString *)discoverShell:(BOOL)reallySend completion:(void (^)(NSString *shell, NSString *dotdir))completion {
    iTermExpectation *expectation = nil;
    if (reallySend) {
        // An installer this one replaced may still be waiting to exit its helpers.
        iTermShellIntegrationWindowController *previous = [_previousInstaller installerAwaitingHelperShellExit];
        _previousInstaller = previous;
        if (previous) {
            DLog(@"Discover once the previous installer's helper shells exit");
            __weak __typeof(self) weakSelf = self;
            const NSUInteger generation = _cancellationGeneration;
            __block BOOL done = NO;
            // Runs once, when the previous installer is done or after a while, whichever comes
            // first: its wait may be one with no time limit, for helpers that are gone. If they
            // aren't, discovery says so.
            void (^discover)(BOOL) = ^(BOOL timedOut) {
                __strong __typeof(self) strongSelf = weakSelf;
                if (done || !strongSelf || strongSelf->_cancellationGeneration != generation) {
                    return;
                }
                done = YES;
                if (timedOut) {
                    DLog(@"Stop waiting for the previous installer");
                }
                [strongSelf->_previousInstaller abandonHelperShells];
                strongSelf->_previousInstaller = nil;
                [strongSelf discoverShell:YES completion:completion];
            };
            [previous performAfterHelperShellsExit:^{
                discover(NO);
            }];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_canceledHelperLaunchTimeout * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                discover(YES);
            });
            [self.currentViewController setBusy:YES];
            return @"";
        }
        // Discovery asks the user's shell, so first leave any helpers a canceled step left
        // running, once that is known to be safe.
        [self exitHelperShellsWhenPossible];
        if (_exitHelpersWhenIdle) {
            __weak __typeof(self) weakSelf = self;
            _afterHelpersExit = ^{
                [weakSelf discoverShell:YES completion:completion];
            };
            [self.currentViewController setBusy:YES];
            return @"";
        }
    }
    // Through sh rather than a bare echo: nushell keeps the environment under $env and has no
    // $SHELL, so echo would be a parse error there, while sh is what the rest of the installer
    // runs its commands in anyway.
    // The shell the commands are typed into is sh's parent, which need not be $SHELL (say, tcsh
    // started from a zsh login shell), so report its executable name and argv[0] too, or just
    // argv[0] where ps lacks ucomm. The line ends in a marker so a partially received line can't
    // match. It also says whether it runs in helper shells the installer started (see
    // launchHelperShellString), as a canceled step can leave behind: their parent is sh, which
    // on macOS is bash, so it would be taken for the user's shell.
    NSString *result = @"sh -c 'echo My shell is $(ps -o ucomm=,comm= -p $PPID 2>/dev/null || ps -o comm= -p $PPID 2>/dev/null) or $SHELL, ${IT2_INSTALLER_HELPER:+in an installer helper shell, }end'\n";
    [self sendText:result
        reallySend:reallySend
        afterRegex:@"^My shell is (.*) or (.*?), (in an installer helper shell, )?end$"
       expectation:&expectation
        completion:^(NSArray<NSString *> *captures) {
        NSString *helperMarker = captures.count > 3 ? captures[3] : nil;
        if ([helperMarker isKindOfClass:[NSString class]] && helperMarker.length > 0) {
            DLog(@"Discovery ran in an installer helper shell");
            self.shell = iTermShellIntegrationShellUnknown;
            self.sendShellCommandsViewController.discoveryFoundHelperShell = YES;
            return;
        }
        NSString *shell = [iTermShellIntegrationWindowController shellNameForParentProcess:captures[1]
                                                                                     shell:captures[2]];
        if ([shell isEqualToString:@"zsh"]) {
            // Send the command only once the expectation is in place. Sending it first loses a
            // race with a fast shell: its output gets checked before the expectation exists.
            // The regex has no space before the capture because an empty value leaves none.
            // The line ends in a marker so one received only up to “go in” (on a slow link)
            // isn't taken for an empty directory.
            iTermExpectation *expectation = nil;
            [self sendText:@"echo My dotfiles go in ${ZDOTDIR:-$HOME}, end\n"
                reallySend:reallySend
                afterRegex:@"^My dotfiles go in(.*), end$"
               expectation:&expectation
                completion:^(NSArray<NSString *> *dotdirCaptures) {
                NSString *dotdir = [dotdirCaptures[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                completion(shell, dotdir.length > 0 ? dotdir : @"$HOME");
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
    NSString *launch = [self enterHelperShell:reallySend expectation:expectation];

    NSString *script = nil;
    switch (self.shell) {
        case iTermShellIntegrationShellTcsh:
            script = @"~/.login";
            break;
        case iTermShellIntegrationShellZsh:
            script = [self.dotdir stringByAppendingPathComponent:@".zshrc"];
            break;
        case iTermShellIntegrationShellBash: {
            NSString *assignment = @"IT2_INSTALLER_DOTFILE=$(if test -f ~/.bash_profile; then echo ~/.bash_profile; else echo ~/.profile; fi)\n";
            [strings addObject:assignment];
            script = @"\"$IT2_INSTALLER_DOTFILE\"";
            break;
        }
        case iTermShellIntegrationShellFish:
            [strings addObject:@"mkdir -p ~/.config/fish\n"];
            script = @"~/.config/fish/config.fish";
            break;
        case iTermShellIntegrationShellXonsh:
            [strings addObject:@"mkdir -p ~/.config/xonsh/rc.d\n"];
            script = @"~/.config/xonsh/rc.d/iterm2.xsh";
            break;
        case iTermShellIntegrationShellNu:
            // No dotfile: modifyStartupScriptsAndProceedTo:reallySend: skips this step for
            // shells that autoload the script.
        case iTermShellIntegrationShellUnknown:
            assert(NO);
    }
    // The commands before the if statement go with its first line. Once that is typed the helper
    // reads the if statement until its fi, so it is not known to read commands until the prompt
    // after fi.
    NSString *prefix = [strings componentsJoinedByString:@""];
    [strings removeAllObjects];
    NSString *ifLine = [NSString stringWithFormat:@"if ! grep iterm2_shell_integration %@  > /dev/null 2>&1; then\n", script];
    // Without a prefix, what matches is the if line's echo after the helper prompt, which follows
    // the ready marker on its row when the helpers were just launched.
    [self sendText:[prefix stringByAppendingString:ifLine]
        reallySend:reallySend
        afterRegex:iTermShellIntegrationHelperPromptRegex
       expectation:expectation
           didSend:[self setHelperStateWhenSent:iTermShellIntegrationHelperStateUnknown]
        completion:nil];
    NSString *joined = [[launch stringByAppendingString:prefix] stringByAppendingString:ifLine];

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
    // The answer shows sh read fi. Its prompt after fi may not start a row in dash, after
    // prompts for the lines before it that it prints only once the tty echoed this line.
    [strings addObject:[self sendText:@"fi; echo it2-\"\"dotfile-done\n"
                           reallySend:reallySend
                           afterRegex:@"it2-dotfile-done"
                          expectation:expectation
                              didSend:nil
                          idleOnMatch:YES
                           completion:nil]];
    [strings addObject:[self exitHelperShells:reallySend
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

// The installer runs its commands in a POSIX sh with known prompts rather than the user's
// shell. Use sh, not bash, because bash is not installed by default on BSDs. If the helper
// shell fails to launch, the heredocs run in the user's shell, and tcsh never terminates
// <<'EOF' on a plain EOF line.
- (NSString *)launchHelperShellString {
    if (self.shell == iTermShellIntegrationShellXonsh || self.shell == iTermShellIntegrationShellNu) {
        // For xonsh, use sh -c to set PS1/PS2 properly (env would include literal quotes).
        // The -c command sets prompts then runs an interactive sh.
        // nushell needs the single line for another reason: reedline reads typeahead in bulk,
        // so of the three lines below only `sh` would reach sh and the other two would run in
        // nushell once sh exits. bash and zsh read a byte at a time and don't have this problem.
        return @"sh -c 'ENV=/dev/null INPUTRC=/dev/null IT2_INSTALLER_HELPER=$((${IT2_INSTALLER_HELPER:-0}+1)) PS1=\">> \" PS2=\"> \" sh'\n";
    }
    // The first sh gives a known syntax for setting ENV, which an interactive sh would source.
    // IT2_INSTALLER_HELPER says how many helpers deep a shell is. It lets discovery tell that it
    // runs in one (see discoverShell:completion:) and awaitCanceledHelperLaunchTypingNewline: how many to exit.
    // env sets it in any shell. The inner sh adds one to what the line is read by, which is the
    // outer sh, or (if that one was killed) a shell where it is unset, or one that rejects it.
    // The last line prints iTermShellIntegrationHelpersReadyMarker before the first helper
    // prompt, which may not start a row (see iTermShellIntegrationHelperPromptRegex).
    return @"env IT2_INSTALLER_HELPER=1 sh\nENV=/dev/null INPUTRC=/dev/null IT2_INSTALLER_HELPER=$((${IT2_INSTALLER_HELPER:-0}+1)) sh\n PS1='>> '; PS2='> '; printf 'it2-''helpers-ready '\n";
}

// The exits that end the helpers launchHelperShellString starts.
- (NSString *)exitHelperShellString {
    NSMutableString *exits = [NSMutableString string];
    for (NSInteger i = 0; i < [self helperShellLevels]; i++) {
        [exits appendString:@"exit\n"];
    }
    return exits;
}

// The checksum POSIX cksum prints for data, followed by its length, as in “4294967295 0”.
+ (NSString *)posixChecksumOfData:(NSData *)data {
    __block uint32_t crc = 0;
    void (^add)(uint8_t) = ^(uint8_t byte) {
        crc ^= (uint32_t)byte << 24;
        for (int i = 0; i < 8; i++) {
            crc = (crc & 0x80000000) ? (crc << 1) ^ 0x04C11DB7 : (crc << 1);
        }
    };
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        add(bytes[i]);
    }
    // Then the length, least significant byte first, in as few bytes as it takes.
    for (unsigned long long length = data.length; length > 0; length >>= 8) {
        add(length & 0xff);
    }
    return [NSString stringWithFormat:@"%u %@", (unsigned int)~crc, @(data.length)];
}

// data as the installer types it to a read loop in the helper sh: base64 in lines of 76
// characters, far shorter than any tty keeps in canonical mode (1024 bytes on macOS and BSD,
// 4096 on Linux), followed by the line that ends the loop.
+ (NSString *)textToSendData:(NSData *)data {
    NSString *encoded = [data base64EncodedStringWithOptions:(NSDataBase64Encoding76CharacterLineLength | NSDataBase64EncodingEndLineWithLineFeed)];
    return [encoded stringByAppendingString:@"\nEOF\n"];
}

+ (NSData *)scriptDataForString:(NSString *)string {
    // The script ends with a newline after string, as when it was written with a here-document.
    return [[string stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
}

+ (NSString *)commandToReceiveScriptData:(NSData *)data atPath:(NSString *)path {
    // Not a format string, since the command has a printf format of its own. The checksum goes
    // in first, so a path can't add to what is replaced.
    NSString *command = [iTermShellIntegrationReceiveScriptCommandTemplate stringByReplacingOccurrencesOfString:@"{cksum}"
                                                                                                    withString:[self posixChecksumOfData:data]];
    return [command stringByReplacingOccurrencesOfString:@"{path}" withString:path];
}

// Writes string to path from the helper sh and then exits the helpers, as the utilities archive
// is received (see receiveText:withCommand:name:resultRegex:success:expectation:completion:),
// rather than in a here-document: some lines of the scripts are longer than a tty in canonical
// mode keeps, which is how sh reads a here-document when it has no line editor (as dash, the sh
// of Debian and Ubuntu), so their ends would be lost. completion says whether the whole script
// was written.
// expectation is inout, not out: ARC passes an out parameter a nil temporary, so the commands
// here would start a chain of their own and be typed alongside the caller's instead of after them.
- (NSString *)catString:(NSString *)string
                     to:(NSString *)path
             reallySend:(BOOL)reallySend
            expectation:(inout iTermExpectation **)expectation
             completion:(void (^)(BOOL written))completion {
    NSData *data = [iTermShellIntegrationWindowController scriptDataForString:string];
    NSString *command = [iTermShellIntegrationWindowController commandToReceiveScriptData:data atPath:path];
    NSString *text = [iTermShellIntegrationWindowController textToSendData:data];
    if (!reallySend) {
        return [[command stringByAppendingString:text] stringByAppendingString:self.exitHelperShellString];
    }
    [self receiveText:text
          withCommand:command
                 name:@"script"
          resultRegex:@"it2-script-(written|failed)"
              success:@"written"
          expectation:expectation
           completion:completion];
    return command;
}

// nushell sources every .nu file in its autoload directories at startup, after config.nu, so the
// script goes there and no dotfile is touched. The directory is asked from nu rather than
// guessed: it differs between macOS and Linux, honors XDG_CONFIG_HOME, and depends on the
// nushell version.
//
// Each command is sent only once output shows the previous one ran in the helper sh. nushell
// reads typeahead in bulk, so text typed before sh is reading would go to nushell. completion
// reports whether the file was written.
- (NSString *)catToNuScript:(NSString *)script
                 reallySend:(BOOL)reallySend
                 completion:(void (^)(BOOL written))completion {
    NSMutableString *result = [NSMutableString string];
    iTermExpectation *expectation = nil;
    // Each text below is typed when the regex of the one before it matches.
    // The helper sh has prompted.
    [result appendString:[self enterHelperShell:reallySend expectation:&expectation]];
    // The autoload directory was created (or mkdir said why not).
    [result appendString:[self sendText:iTermShellIntegrationNuAutoloadDirCommand
                             reallySend:reallySend
                             afterRegex:iTermShellIntegrationNuAutoloadDirReadyRegex
                            expectation:&expectation]];
    [result appendString:[self catString:script
                                      to:[self shellIntegrationPath]
                              reallySend:reallySend
                             expectation:&expectation
                              completion:completion]];
    return result;
}

- (NSString *)catToScript:(BOOL)reallySend
               completion:(void (^)(BOOL written))completion {
    NSString *scriptForShell = [self scriptForCurrentShell];
    if (!scriptForShell) {
        return @"# Error: your shell could not be determined or is unsupported.";
    }
    if (self.shell == iTermShellIntegrationShellNu) {
        return [self catToNuScript:scriptForShell reallySend:reallySend completion:completion];
    }
    NSMutableString *result = [NSMutableString string];
    iTermExpectation *expectation = nil;
    [result appendString:[self enterHelperShell:reallySend expectation:&expectation]];
    if (self.shell == iTermShellIntegrationShellXonsh) {
        // Create the rc.d directory for xonsh (scripts there are auto-loaded)
        [result appendString:[self sendText:@"mkdir -p ~/.config/xonsh/rc.d\n"
                                 reallySend:reallySend
                                 afterRegex:@"^>> "
                                expectation:&expectation]];
    }
    [result appendString:[self catString:scriptForShell
                                      to:[self shellIntegrationPath]
                              reallySend:reallySend
                             expectation:&expectation
                              completion:completion]];
    return result;
}

- (NSString *)sendText:(NSString *)text reallySend:(BOOL)reallySend {
    if (reallySend) {
        [self typeText:text];
    }
    return text;
}

// All text the installer types goes through here, so _typedTextCount says whether anything was
// typed since a given point.
- (void)typeText:(NSString *)text {
    _typedTextCount += 1;
    _lastTextIsIdleOnMatch = NO;
    [self.delegate shellIntegrationWindowControllerSendText:text];
}

- (NSString *)catToUtilities:(BOOL)reallySend
                 expectation:(inout iTermExpectation **)expectation
                  completion:(void (^)(BOOL installed))completion {
    NSMutableString *result = [NSMutableString string];
    NSString *folder = [self.dotdir stringByAppendingPathComponent:@".iterm2"];
    [result appendString:[self enterHelperShell:reallySend expectation:expectation]];
    // Each command waits for its own answer before the next is typed. The answers differ, and the
    // empty quotes keep the echo of a command from looking like its answer. Output a command
    // prints after the next line is typed can land in the middle of that line's echo, so an
    // answer is matched anywhere in a row, not only as a whole line.
    [result appendString:[self sendText:[NSString stringWithFormat:@"mkdir %@; echo it2-\"\"mkdir-done\n", folder]
                             reallySend:reallySend
                             afterRegex:@"it2-mkdir-done"
                            expectation:expectation]];
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"utilities" withExtension:@"tgz"];
    // If cd fails, nothing more may be typed but the exits.
    NSString *cdCommand = [iTermShellIntegrationWindowController commandToEnterUtilitiesFolder:folder];
    if (!url) {
        completion(NO);
        return result;
    }
    if (!reallySend) {
        [result appendString:cdCommand];
        [result appendString:iTermShellIntegrationReceiveUtilitiesCommand];
        [result appendString:[self encodedUtilitiesArchiveFromURL:url]];
        [result appendString:self.exitHelperShellString];
        return result;
    }
    // Whether to go on depends on sh's answer, so the rest is not chained after the command like
    // the other texts: the answer's completion types it, or gives up.
    __weak __typeof(self) weakSelf = self;
    const NSUInteger generation = _cancellationGeneration;
    [result appendString:[self sendText:cdCommand
                             reallySend:YES
                             afterRegex:@"it2-cd-(done|failed)"
                            expectation:expectation
                                didSend:nil
                             completion:^(NSArray<NSString *> *captures) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_cancellationGeneration != generation) {
            DLog(@"Not answering the utilities cd command after a cancel");
            return;
        }
        if (![captures[1] isEqualToString:@"done"]) {
            DLog(@"cd to the utilities folder failed");
            // sh printed the answer, so it is reading commands.
            [strongSelf helperShellsBecameIdle];
            [strongSelf exitIdleHelperShells];
            completion(NO);
            return;
        }
        [strongSelf receiveUtilitiesArchiveFromURL:url completion:completion];
    }]];
    return result;
}

- (NSString *)encodedUtilitiesArchiveFromURL:(NSURL *)url {
    return [iTermShellIntegrationWindowController textToSendData:[NSData dataWithContentsOfURL:url]];
}

// Typed into the helper sh once it is in the utilities folder.
- (void)receiveUtilitiesArchiveFromURL:(NSURL *)url
                            completion:(void (^)(BOOL installed))completion {
    // tar's exit status says whether the archive arrived intact, since gzip checks a CRC.
    iTermExpectation *expectation = nil;
    [self receiveText:[self encodedUtilitiesArchiveFromURL:url]
          withCommand:iTermShellIntegrationReceiveUtilitiesCommand
                 name:@"utilities"
          resultRegex:@"it2-utilities-(installed|failed)"
              success:@"installed"
          expectation:&expectation
           completion:completion];
}

// Types command, which makes the helper sh read lines from the tty up to one that is just EOF
// into a file and then use it, and then text, the lines it reads, followed by that EOF line.
// command prints it2-receiving-<name> once the file is open, or it2-cannot-receive-<name> if it
// can't be created, and then an answer that resultRegex matches, whose first capture is success
// if the file was used. Then the helpers exit, and completion says whether it was.
//
// Text typed into a here-document goes through sh's line editor, which switches the tty between
// raw and canonical mode for every line, and on a busy system lines got lost or spliced, most
// likely where input queued across a switch overflowed the tty's input buffer. An sh without a
// line editor, such as dash, reads it in canonical mode, where the tty drops what goes past its
// limit on a line. So a read loop in sh takes short lines instead: no line editor, and the tty
// stays in canonical mode, where a full input buffer makes the writer wait instead of dropping
// input. text is typed only once sh says the loop is reading into a file it created, so none of
// it can reach sh's prompt and run as a command.
- (void)receiveText:(NSString *)text
        withCommand:(NSString *)command
               name:(NSString *)name
        resultRegex:(NSString *)resultRegex
            success:(NSString *)success
        expectation:(inout iTermExpectation **)expectation
         completion:(void (^)(BOOL succeeded))completion {
    // Whether to type text depends on sh's answer, so it is not chained after the command like
    // the other texts: the answer's completion types it, or gives up.
    __weak __typeof(self) weakSelf = self;
    const NSUInteger generation = _cancellationGeneration;
    [self sendText:command
        reallySend:YES
        afterRegex:[NSString stringWithFormat:@"it2-(receiving|cannot-receive)-%@", name]
       expectation:expectation
           didSend:[self setHelperStateWhenSent:iTermShellIntegrationHelperStateReceivingFile]
        completion:^(NSArray<NSString *> *captures) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_cancellationGeneration != generation) {
            DLog(@"Not answering the %@ receive command after a cancel", name);
            return;
        }
        if (![captures[1] isEqualToString:@"receiving"]) {
            DLog(@"sh could not create the file to receive the %@ into", name);
            // It is reading commands.
            [strongSelf helperShellsBecameIdle];
            [strongSelf exitIdleHelperShells];
            if (completion) {
                completion(NO);
            }
            return;
        }
        iTermExpectation *textExpectation = nil;
        [strongSelf sendText:text
                  reallySend:YES
                  afterRegex:resultRegex
                 expectation:&textExpectation
                     didSend:^{
            __strong __typeof(self) innerSelf = weakSelf;
            if (innerSelf) {
                innerSelf->_receivedTextTyped = YES;
            }
        }
                  completion:^(NSArray<NSString *> *captures) {
            __strong __typeof(self) innerSelf = weakSelf;
            // sh printed the result, so it is reading commands again.
            [innerSelf helperShellsBecameIdle];
            [innerSelf exitIdleHelperShells];
            DLog(@"Receiving the %@ ended with %@", name, captures[1]);
            if (completion) {
                completion([captures[1] isEqualToString:success]);
            }
        }];
    }];
}

#pragma mark - Orchestration

- (NSString *)discoverShell:(BOOL)reallySend {
    __weak __typeof(self) weakSelf = self;
    return [self discoverShell:reallySend completion:^(NSString *shell, NSString *dotdir) {
        [weakSelf didDiscoverShell:shell dotdir:dotdir];
    }];
}

- (void)didDiscoverShell:(NSString *)shell dotdir:(NSString *)dotdir {
    NSNumber *number = [iTermShellIntegrationWindowController shellsByName][shell ?: @""];
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
    NSString *result = [self catToScript:reallySend completion:^(BOOL written) {
        if (!reallySend) {
            return;
        }
        if (written) {
            weakSelf.sendShellCommandsViewController.stage = 2;
        } else {
            weakSelf.sendShellCommandsViewController.writeFailed = YES;
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
                                   completion:^(BOOL installed) {
        if (!reallySend) {
            return;
        }
        [weakSelf.sendShellCommandsViewController setBusy:NO];
        if (installed) {
            weakSelf.sendShellCommandsViewController.stage = 3;
        } else {
            weakSelf.sendShellCommandsViewController.writeFailed = YES;
        }
    }]];
    if (reallySend) {
        [self.sendShellCommandsViewController setBusy:YES];
    }
    return result;
}

- (NSString *)modifyStartupScriptsAndProceedTo:(int)nextStage
                                    reallySend:(BOOL)reallySend {
    if (iTermShellIntegrationShellLoadsScriptAutomatically(self.shell)) {
        // The shell auto-loads the script, so no dotfile modification is needed.
        if (reallySend) {
            self.sendShellCommandsViewController.stage = nextStage;
        }
        return @"";
    }
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

// The install script served by iterm2.com is deployed separately from the app and may not yet
// support every shell the app's bundled scripts do. nushell support was added to the app before
// the website's installer, so when the website rejects nu, use the Internet-free installer.
+ (BOOL)internetFreeInstallerSupportsShellRejectedByWebsite:(NSString *)shell {
    return [shell isEqualToString:iTermShellIntegrationShellString(iTermShellIntegrationShellNu)];
}

- (void)shellIntegrationInstallerReallyDownloadAndRun {
    [self.delegate shellIntegrationWindowControllerSendText:[self curlPipeBashCommand]];
    __weak __typeof(self) weakSelf = self;

    [self expectRegularExpression:@"(^Done.$)|(^Your shell, (.*), is not supported yet)"
                            after:nil
                       willExpect:nil
                       completion:^(NSArray<NSString *> * _Nonnull captureGroups) {
        if ([captureGroups[0] hasPrefix:@"Your shell"]) {
            NSString *unsupportedShell = captureGroups.count > 3 ? captureGroups[3] : @"";
            DLog(@"Online installer says %@ is unsupported", unsupportedShell);
            if ([iTermShellIntegrationWindowController internetFreeInstallerSupportsShellRejectedByWebsite:unsupportedShell]) {
                // The Internet-free installer bundles the script, so it works regardless of
                // what the website's installer supports.
                [weakSelf shellIntegrationInstallerSendShellCommands:-1];
                return;
            }
            [weakSelf.downloadAndRunViewController showShellUnsupportedError];
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
                    // A shell that auto-loads the script needs no dotfile modification,
                    // so proceed directly to finish.
                    if (iTermShellIntegrationShellLoadsScriptAutomatically(self.shell)) {
                        [self finishSendShellCommandsInstall];
                    }
                }
                break;
            }
            case 3:
                if (self.installUtilities) {
                    [self modifyStartupScriptsAndProceedTo:stage+1
                                                reallySend:YES];
                    // A shell that auto-loads the script needs no dotfile modification,
                    // so proceed directly to finish.
                    if (iTermShellIntegrationShellLoadsScriptAutomatically(self.shell)) {
                        [self finishSendShellCommandsInstall];
                    }
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
    if (stage < 1) {
        // Every later stage needs the shell and dotfile directory that discovery finds.
        return;
    }
    const int lastStage = self.installUtilities ? 4 : 3;
    if (stage + 1 > lastStage) {
        return;
    }
    self.sendShellCommandsViewController.stage = stage + 1;
}

- (void)shellIntegrationInstallerCancelExpectations {
    [self cancelAllExpectations];
}

- (void)shellIntegrationInstallerContentSizeDidChange {
    if (!self.currentViewController || self.currentViewController.view.superview != self.containerView) {
        return;
    }
    [self fitWindowToCurrentView];
}

@end
