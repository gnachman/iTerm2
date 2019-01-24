//
//  iTermStatusBarGitComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/22/18.
//
// This is loosely based on hyperline git-status

#import "iTermStatusBarGitComponent.h"

#import "DebugLogging.h"
#import "FontSizeEstimator.h"
#import "iTermCommandRunner.h"
#import "iTermController.h"
#import "iTermGitPoller.h"
#import "iTermGitState.h"
#import "iTermLocalHostNameGuesser.h"
#import "iTermTextPopoverViewController.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSDate+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSStringITerm.h"
#import "NSObject+iTerm.h"
#import "NSTimer+iTerm.h"
#import "PTYSession.h"
#import "PseudoTerminal.h"
#import "RegexKitLite.h"

@interface NSObject(BogusSelector)
- (void)bogusSelector;
@end

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermStatusBarGitComponentPollingIntervalKey = @"iTermStatusBarGitComponentPollingIntervalKey";
static const NSTimeInterval iTermStatusBarGitComponentDefaultCadence = 2;

@interface iTermGitMenuItemContext : NSObject
@property (nonatomic, copy) iTermGitState *state;
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, strong) id userData;
@end

@implementation iTermGitMenuItemContext
@end

@interface iTermStatusBarGitComponent()<iTermGitPollerDelegate>
@end

@implementation iTermStatusBarGitComponent {
    iTermGitPoller *_gitPoller;
    iTermVariableReference *_pwdRef;
    iTermVariableReference *_hostRef;
    iTermVariableReference *_lastCommandRef;
    NSString *_status;
    BOOL _hidden;
    PTYSession *_session;
    iTermCommandRunner *_logRunner;
    iTermTextPopoverViewController *_popoverVC;
    NSView *_view;
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    self = [super initWithConfiguration:configuration scope:scope];
    if (self) {
        const NSTimeInterval cadence = [self cadenceInDictionary:configuration[iTermStatusBarComponentConfigurationKeyKnobValues]];
        __weak __typeof(self) weakSelf = self;
        iTermGitPoller *gitPoller = [[iTermGitPoller alloc] initWithCadence:cadence update:^{
            [weakSelf statusBarComponentUpdate];
        }];
        gitPoller.delegate = self;
        _gitPoller = gitPoller;
        _pwdRef = [[iTermVariableReference alloc] initWithPath:iTermVariableKeySessionPath scope:scope];
        _pwdRef.onChangeBlock = ^{
            gitPoller.currentDirectory = [scope valueForVariableName:iTermVariableKeySessionPath];
        };
        _hostRef = [[iTermVariableReference alloc] initWithPath:iTermVariableKeySessionHostname scope:scope];
        _hostRef.onChangeBlock = ^{
            [weakSelf updatePollerEnabled];
        };
        _lastCommandRef = [[iTermVariableReference alloc] initWithPath:iTermVariableKeySessionLastCommand scope:scope];
        _lastCommandRef.onChangeBlock = ^{
            [weakSelf bumpIfLastCommandWasGit];
        };
        gitPoller.currentDirectory = [scope valueForVariableName:iTermVariableKeySessionPath];
        [self updatePollerEnabled];
    };
    return self;
}

- (void)setDelegate:(id<iTermStatusBarComponentDelegate>)delegate {
    [super setDelegate:delegate];
    [self statusBarComponentUpdate];
}

- (NSImage *)statusBarComponentIcon {
    return [NSImage it_imageNamed:@"StatusBarIconGitBranch" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return @"git state";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Shows a summary of the git state of the current directory.";
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    NSArray<iTermStatusBarComponentKnob *> *knobs;

    iTermStatusBarComponentKnob *formatKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Polling Interval (seconds):"
                                                      type:iTermStatusBarComponentKnobTypeDouble
                                               placeholder:nil
                                              defaultValue:@(iTermStatusBarGitComponentDefaultCadence)
                                                       key:iTermStatusBarGitComponentPollingIntervalKey];

    knobs = @[ formatKnob ];
    knobs = [knobs arrayByAddingObjectsFromArray:self.minMaxWidthKnobs];
    knobs = [knobs arrayByAddingObjectsFromArray:[super statusBarComponentKnobs]];
    return knobs;
}

+ (NSDictionary *)statusBarComponentDefaultKnobs {
    NSDictionary *knobs = [super statusBarComponentDefaultKnobs];
    knobs = [knobs dictionaryByMergingDictionary:@{ iTermStatusBarGitComponentPollingIntervalKey: @(iTermStatusBarGitComponentDefaultCadence) }];
    knobs = [knobs dictionaryByMergingDictionary:self.defaultMinMaxWidthKnobValues];
    return knobs;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return [self clampedWidth:[super statusBarComponentPreferredWidth]];
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return @"⎇ master";
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (NSArray<NSAttributedString *> *)attributedStringVariants {
    return @[ self.attributedStringValue ?: [self attributedStringWithString:@""] ];
}

- (NSParagraphStyle *)paragraphStyle {
    static NSMutableParagraphStyle *paragraphStyle;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
    });

    return paragraphStyle;
}

- (NSAttributedString *)attributedStringWithImageNamed:(NSString *)imageName {
    NSTextAttachment *textAttachment = [[NSTextAttachment alloc] init];
    textAttachment.image = [NSImage it_imageNamed:imageName forClass:self.class];
    return [NSAttributedString attributedStringWithAttachment:textAttachment];
}

- (NSAttributedString *)attributedStringWithString:(NSString *)string {
    NSDictionary *attributes = @{ NSFontAttributeName: self.advancedConfiguration.font ?: [iTermStatusBarAdvancedConfiguration defaultFont],
                                  NSForegroundColorAttributeName: [self textColor],
                                  NSParagraphStyleAttributeName: self.paragraphStyle };
    return [[NSAttributedString alloc] initWithString:string ?: @"" attributes:attributes];
}

- (BOOL)pollerReady {
    return _gitPoller.state && _gitPoller.enabled;
}

- (nullable NSAttributedString *)attributedStringValue {
    if (_status) {
        return [self attributedStringWithString:_status];
    }
    if (!self.pollerReady) {
        return nil;
    }
    static NSAttributedString *upImage;
    static NSAttributedString *downImage;
    static NSAttributedString *dirtyImage;
    static NSAttributedString *enSpace;
    static NSAttributedString *thinSpace;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        upImage = [self attributedStringWithImageNamed:@"gitup"];
        downImage = [self attributedStringWithImageNamed:@"gitdown"];
        dirtyImage = [self attributedStringWithImageNamed:@"gitdirty"];
        enSpace = [self attributedStringWithString:@"\u2002"];
        thinSpace = [self attributedStringWithString:@"\u2009"];
    });

    NSAttributedString *branch = _gitPoller.state.branch ? [self attributedStringWithString:_gitPoller.state.branch] : nil;
    if (!branch) {
        return nil;
    }

    NSAttributedString *upCount = _gitPoller.state.pushArrow.length ? [self attributedStringWithString:_gitPoller.state.pushArrow] : nil;
    NSAttributedString *downCount = _gitPoller.state.pullArrow.length ? [self attributedStringWithString:_gitPoller.state.pullArrow] : nil;

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result appendAttributedString:branch];

    if (_gitPoller.state.dirty) {
        [result appendAttributedString:thinSpace];
        [result appendAttributedString:dirtyImage];
    }

    if (_gitPoller.state.pushArrow.integerValue > 0) {
        [result appendAttributedString:enSpace];
        [result appendAttributedString:upImage];
        [result appendAttributedString:upCount];
    }

    if (_gitPoller.state.pullArrow.integerValue > 0) {
        [result appendAttributedString:enSpace];
        [result appendAttributedString:downImage];
        [result appendAttributedString:downCount];
    }

    return result;
}

- (NSTimeInterval)cadenceInDictionary:(NSDictionary *)knobValues {
    return [knobValues[iTermStatusBarGitComponentPollingIntervalKey] doubleValue] ?: 1;
}

- (void)updatePollerEnabled {
    NSString *currentHostname = [self.scope valueForVariableName:iTermVariableKeySessionHostname];
    NSString *localhostName = [[iTermLocalHostNameGuesser sharedInstance] name];
    DLog(@"git poller current hostname is %@, localhost is %@", currentHostname, localhostName);
    _gitPoller.enabled = [localhostName isEqualToString:currentHostname];
}

- (void)statusBarComponentSetKnobValues:(NSDictionary *)knobValues {
    _gitPoller.cadence = [self cadenceInDictionary:knobValues];
    [super statusBarComponentSetKnobValues:knobValues];
}

- (void)statusBarComponentDidMoveToWindow {
    [super statusBarComponentDidMoveToWindow];
    [self bump];
}

- (void)bump {
    [_gitPoller bump];
}

- (void)bumpIfLastCommandWasGit {
    NSString *wholeCommand = _lastCommandRef.value;
    NSInteger space = [wholeCommand rangeOfString:@" "].location;
    if (space == NSNotFound) {
        return;
    }
    NSString *command = [wholeCommand substringToIndex:space];
    NSInteger lastSlash = [command rangeOfString:@"/" options:NSBackwardsSearch].location;
    if (lastSlash != NSNotFound) {
        command = [command substringFromIndex:lastSlash + 1];
    }
    if ([command isEqualToString:@"git"]) {
        DLog(@"Bump because command %@ looks like git", wholeCommand);
        [self bump];
    }
}
- (BOOL)statusBarComponentHandlesClicks {
    return YES;
}

- (void)killSession:(id)sender {
    [[[iTermController sharedInstance] terminalWithSession:_session] closeSessionWithoutConfirmation:_session];
}

- (void)revealSession:(id)sender {
    [_session reveal];
}

- (void)statusBarComponentDidClickWithView:(NSView *)view {
    [self openMenuWithView:view];
}

- (void)statusBarComponentMouseDownWithView:(NSView *)view {
    [self openMenuWithView:view];
}

- (void)openMenuWithView:(NSView *)view {
    NSView *containingView = view.superview;
    if (_session) {
        NSMenu *menu = [[NSMenu alloc] init];
        NSString *actionName = [_status stringByReplacingOccurrencesOfString:@"…" withString:@""];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Cancel %@", actionName] action:@selector(killSession:) keyEquivalent:@""];
        item.target = self;
        [menu addItem:item];

        item = [[NSMenuItem alloc] initWithTitle:@"Reveal" action:@selector(revealSession:) keyEquivalent:@""];
        item.target = self;
        [menu addItem:item];
        [menu popUpMenuPositioningItem:menu.itemArray.firstObject atLocation:NSMakePoint(0, 0) inView:containingView];
        return;
    }

    if (_gitPoller.state.branch.length == 0) {
        return;
    }
    iTermGitState *state = _gitPoller.state.copy;
    NSString *directory = _gitPoller.currentDirectory;
    __weak __typeof(self) weakSelf = self;
    [self fetchRecentBranchesWithTimeout:0.5 completion:^(NSArray<NSString *> *branches) {
        NSMenu *menu = [[NSMenu alloc] init];
        iTermGitMenuItemContext *(^addItem)(NSString *, SEL, BOOL) = ^iTermGitMenuItemContext *(NSString *title, SEL selector, BOOL enabled) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                          action:enabled ? selector : @selector(bogusSelector)
                                                   keyEquivalent:@""];
            item.target = weakSelf;
            iTermGitMenuItemContext *context = [[iTermGitMenuItemContext alloc] init];
            context.state = state;
            context.directory = directory;
            item.representedObject = context;
            [menu addItem:item];
            return context;
        };
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf->_view = view;
        addItem(@"Commit", @selector(commit:), state.dirty);
        addItem(@"Add & Commit", @selector(addAndCommit:), state.dirty);
        addItem(@"Stash", @selector(stash:), state.dirty);
        addItem(@"Log", @selector(log:), state.dirty);
        addItem([NSString stringWithFormat:@"Push origin %@", state.branch], @selector(push:), state.pushArrow.intValue > 0);
        addItem([NSString stringWithFormat:@"Pull origin %@", state.branch], @selector(pull:), !state.dirty);
        [menu addItem:[NSMenuItem separatorItem]];
        for (NSString *branch in [branches it_arrayByKeepingFirstN:7]) {
            if (branch.length == 0) {
                continue;
            }
            if ([branch isEqualToString:state.branch]) {
                continue;
            }
            addItem([NSString stringWithFormat:@"Check out %@", branch], @selector(checkout:), YES).userData = branch;
        }
        [menu popUpMenuPositioningItem:menu.itemArray.firstObject atLocation:NSMakePoint(0, 0) inView:containingView];
    }];
}

- (void)runGitCommandWithArguments:(NSArray<NSString *> *)args
                           timeout:(NSTimeInterval)timeout
                        completion:(void (^)(NSString * _Nullable output, int status))completion {
    iTermBufferedCommandRunner *runner = [[iTermBufferedCommandRunner alloc] initWithCommand:@"/usr/bin/git"
                                                                               withArguments:args
                                                                                        path:_gitPoller.currentDirectory];
    __weak iTermBufferedCommandRunner *weakRunner = runner;
    runner.completion = ^(int status) {
        iTermBufferedCommandRunner *strongRunner = weakRunner;
        if (!strongRunner) {
            completion(nil, -1);
        }
        NSString *output = [[NSString alloc] initWithData:strongRunner.output  encoding:NSUTF8StringEncoding];
        completion(output, status);
    };
    [runner runWithTimeout:timeout];
}

static NSArray<NSString *> *NonEmptyLinesInString(NSString *output) {
    NSArray<NSString *> *branches = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    return [branches mapWithBlock:^id(NSString *branch) {
        NSString *trimmed = [branch stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) {
            return nil;
        }
        return trimmed;
    }];
}

- (void)fetchRecentBranchesWithTimeout:(NSTimeInterval)timeout completion:(void (^)(NSArray<NSString *> *branches))completion {
    NSArray *args = @[ @"for-each-ref",
                       @"--count=30",
                       @"--sort=-committerdate",
                       @"refs/heads/",
                       @"--format=%(refname:short)" ];
    [self runGitCommandWithArguments:args
                             timeout:timeout
                          completion:
     ^(NSString * _Nullable output, int status) {
         if (status != 0 || output == nil) {
             completion(@[]);
             return;
         }
         completion(NonEmptyLinesInString(output));
     }];
}

- (void)showPopover {
    _popoverVC = [[iTermTextPopoverViewController alloc] initWithNibName:@"iTermTextPopoverViewController"
                                                                  bundle:[NSBundle bundleForClass:self.class]];
    _popoverVC.popover.behavior = NSPopoverBehaviorTransient;
    [_popoverVC view];
    if ([self.delegate statusBarComponentTerminalBackgroundColorIsDark:self]) {
        if (@available(macOS 10.14, *)) {
            _popoverVC.view.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        } else {
            _popoverVC.view.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
        }
    } else {
        _popoverVC.view.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    }
    _popoverVC.textView.font = [self.delegate statusBarComponentTerminalFont:self];
    NSRect frame = _popoverVC.view.frame;
    NSSize inset = _popoverVC.textView.textContainerInset;
    frame.size.width = [FontSizeEstimator fontSizeEstimatorForFont:_popoverVC.textView.font].size.width * 60 + iTermTextPopoverViewControllerHorizontalMarginWidth * 2 + inset.width * 2;
    _popoverVC.view.frame = frame;
    NSView *view = _view.subviews.firstObject ?: _view;
    NSRect rect = view.bounds;
    rect.size.width = [self statusBarComponentMinimumWidth];
    [_popoverVC.popover showRelativeToRect:rect
                                    ofView:view
                             preferredEdge:NSRectEdgeMaxY];
}

- (void)log:(id)sender {
    if (_logRunner) {
        [_logRunner terminate];
    }

    [self showPopover];
    NSMenuItem *menuItem = sender;
    iTermGitMenuItemContext *context = menuItem.representedObject;
    _logRunner = [[iTermCommandRunner alloc] initWithCommand:@"/usr/bin/git"
                                               withArguments:@[ @"log" ]
                                                        path:context.directory];
    iTermTextPopoverViewController *popoverVC = _popoverVC;
    __weak __typeof(_logRunner) weakLogRunner = _logRunner;
    __block BOOL stopped = NO;
    _logRunner.outputHandler = ^(NSData *data) {
        if (stopped) {
            return;
        }
        [popoverVC appendString:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
        if (popoverVC.textView.textStorage.length > 100000) {
            stopped = YES;
            [popoverVC appendString:@"\n[Truncated]\n"];
            [weakLogRunner terminate];
        }
    };
    [_logRunner runWithTimeout:5];
}
- (void)commit:(id)sender {
    NSMenuItem *menuItem = sender;
    iTermGitMenuItemContext *context = menuItem.representedObject;
    [self runGitInWindowWithArguments:@[ @"commit" ] pwd:context.directory status:@"Committing…" bury:NO];
}

- (void)addAndCommit:(id)sender {
    NSMenuItem *menuItem = sender;
    iTermGitMenuItemContext *context = menuItem.representedObject;
    [self runGitInWindowWithArguments:@[ @"commit", @"-a" ] pwd:context.directory status:@"Committing…" bury:NO];
}

- (void)stash:(id)sender {
    NSMenuItem *menuItem = sender;
    iTermGitMenuItemContext *context = menuItem.representedObject;
    [self runGitInWindowWithArguments:@[ @"stash" ] pwd:context.directory status:@"Stashing…" bury:YES];
}

- (void)push:(id)sender {
    NSMenuItem *menuItem = sender;
    iTermGitMenuItemContext *context = menuItem.representedObject;
    [self runGitInWindowWithArguments:@[ @"push", @"origin", context.state.branch ]
                                  pwd:context.directory
                               status:@"Pushing…"
                                 bury:YES];
}

- (void)pull:(id)sender {
    NSMenuItem *menuItem = sender;
    iTermGitMenuItemContext *context = menuItem.representedObject;
    [self runGitInWindowWithArguments:@[ @"pull", @"origin", context.state.branch ]
                                  pwd:context.directory
                               status:@"Pulling…"
                                 bury:YES];
}

- (void)checkout:(id)sender {
    NSMenuItem *menuItem = sender;
    iTermGitMenuItemContext *context = menuItem.representedObject;
    [self runGitInWindowWithArguments:@[ @"checkout", context.userData ]
                                  pwd:context.directory
                               status:@"Checking out…"
                                 bury:YES];
}

- (void)runGitInWindowWithArguments:(NSArray<NSString *> *)args pwd:(NSString *)pwd status:(NSString *)status bury:(BOOL)bury {
    if (_status) {
        return;
    }
    _status = status;
    [self updateTextFieldIfNeeded];
    NSArray<NSString *> *escaped = [args mapWithBlock:^id(NSString *arg) {
        return [arg stringWithEscapedShellCharactersIncludingNewlines:YES];
    }];
    NSString *gitWrapper = [[NSBundle bundleForClass:self.class] pathForResource:@"iterm2_git_wrapper" ofType:@"sh"];
    NSString *command = [NSString stringWithFormat:@"%@ %@", gitWrapper, [escaped componentsJoinedByString:@" "]];
    __weak __typeof(self) weakSelf = self;
    iTermSingleUseWindowOptions options = (iTermSingleUseWindowOptionsCloseOnTermination |
                                           iTermSingleUseWindowOptionsShortLived);
    if (bury) {
        options |= iTermSingleUseWindowOptionsInitiallyBuried;
    }
    _session = [[iTermController sharedInstance] openSingleUseWindowWithCommand:command
                                                                         inject:nil
                                                                    environment:nil
                                                                            pwd:pwd
                                                                        options:options
                                                                     completion:^{
                                                                         [weakSelf didFinishCommand];
                                                                     }];
}

- (void)didFinishCommand {
    _status = nil;
    _session = nil;
    [self bump];
    [self updateTextFieldIfNeeded];
}

#pragma mark - iTermGitPollerDelegate

- (BOOL)gitPollerShouldPoll:(iTermGitPoller *)poller {
    return (![self.delegate statusBarComponentIsInSetupUI:self] &&
            [self.delegate statusBarComponentIsVisible:self]);
}

@end

NS_ASSUME_NONNULL_END
