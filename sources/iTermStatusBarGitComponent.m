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
#import "iTermAdvancedSettingsModel.h"
#import "iTermCommandRunner.h"
#import "iTermController.h"
#import "iTermGitPollWorker.h"
#import "iTermGitPoller.h"
#import "iTermGitState+MainApp.h"
#import "iTermSlowOperationGateway.h"
#import "iTermTextPopoverViewController.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "iTermVariableScope+Session.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSDate+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSHost+iTerm.h"
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
    iTermRemoteGitStateObserver *_remoteObserver;
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
        _pwdRef = [[iTermVariableReference alloc] initWithPath:iTermVariableKeySessionPath vendor:scope];
        _pwdRef.onChangeBlock = ^{
            [weakSelf pwdDidChange];
        };
        _hostRef = [[iTermVariableReference alloc] initWithPath:iTermVariableKeySessionHostname vendor:scope];
        _hostRef.onChangeBlock = ^{
            DLog(@"Hostname changed, update git poller enabled");
            [weakSelf updatePollerEnabled];
        };
        _lastCommandRef = [[iTermVariableReference alloc] initWithPath:iTermVariableKeySessionLastCommand vendor:scope];
        _lastCommandRef.onChangeBlock = ^{
            [weakSelf bumpIfLastCommandWasGit];
        };
        _remoteObserver = [[iTermRemoteGitStateObserver alloc] initWithScope:scope
                                                                       block:^{
                                                                           DLog(@"Remote git state changed; update enabled");
                                                                           [weakSelf updatePollerEnabled];
                                                                           [weakSelf statusBarComponentUpdate];
                                                                       }];
        gitPoller.currentDirectory = [scope valueForVariableName:iTermVariableKeySessionPath];
        [self updatePollerEnabled];
        DLog(@"Initializing git component %@ for scope of session with ID %@. poller is %@", self, scope.ID, gitPoller);
    };
    return self;
}

+ (ProfileType)compatibleProfileTypes {
    return ProfileTypeTerminal;
}

- (void)pwdDidChange {
    DLog(@"PWD changed, update git poller directory");
    _gitPoller.currentDirectory = [self.scope valueForVariableName:iTermVariableKeySessionPath];
}

- (void)setDelegate:(id<iTermStatusBarComponentDelegate> _Nullable)delegate {
    [super setDelegate:delegate];
    [self statusBarComponentUpdate];
}

- (nullable NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconGitBranch" forClass:[self class]];
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
    knobs = [knobs arrayByAddingObjectsFromArray:[super statusBarComponentKnobs]];
    knobs = [knobs arrayByAddingObjectsFromArray:self.minMaxWidthKnobs];
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
    return @"⎇ main";
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (BOOL)truncatesTail {
    return YES;
}

- (NSArray<NSAttributedString *> *)attributedStringVariants {
    NSArray<NSAttributedString *> *result = [[[self variantsOfCurrentStateBranch] mapWithBlock:^id(NSString *branch) {
        return [self attributedStringValueForBranch:branch];
    }] sortedArrayUsingComparator:^NSComparisonResult(NSAttributedString * _Nonnull obj1, NSAttributedString * _Nonnull obj2) {
        return [@(obj1.length) compare:@(obj2.length)];
    }];
    if (result.count == 0) {
        return @[ [self attributedStringWithString:@""] ];
    }
    return result;
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

- (CGFloat)statusBarComponentMinimumWidth {
    return [self widthForAttributedString:[self attributedStringValueForBranch:@"M"]];
}

- (BOOL)onLocalhost {
    NSString *localhostName = [NSHost fullyQualifiedDomainName];
    NSString *currentHostname = self.scope.hostname;
    DLog(@"git poller current hostname is %@, localhost is %@", currentHostname, localhostName);
    return [localhostName isEqualToString:currentHostname];
}

- (iTermGitState *)currentState {
    if ([self onLocalhost]) {
        return _gitPoller.state;
    } else {
        return [[iTermGitState alloc] initWithScope:self.scope];
    }
}

- (BOOL)pollerReady {
    return self.currentState && _gitPoller.enabled;
}

- (NSArray<NSString *> *)variantsOfBranch:(NSString *)branch {
    NSIndexSet *dividers = [branch indicesOfCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-_./+,"]];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    [dividers enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        const NSRange composedRange = [branch rangeOfComposedCharacterSequenceAtIndex:idx];
        const NSInteger limit = NSMaxRange(composedRange);
        NSString *const branchPrefix = [branch substringToIndex:limit];
        [result addObject:[branchPrefix stringByAppendingString:@"…"]];
    }];
    [result addObject:branch];
    return [result uniq];
}

- (nullable NSArray<NSString *> *)variantsOfCurrentStateBranch {
    NSString *branch = self.currentState.branch;
    if (!branch) {
        return nil;
    }
    return @[ branch ];
}

- (nullable NSAttributedString *)attributedStringValueForBranch:(NSString *)branchString {
    if (_status) {
        return [self attributedStringWithString:_status];
    }
    if (!self.pollerReady) {
        return nil;
    }
    switch (self.currentState.repoState) {
        case iTermGitRepoStateNone:
            break;
        case iTermGitRepoStateMerge:
            return [self attributedStringWithString:@"Merging"];
        case iTermGitRepoStateRevert:
            return [self attributedStringWithString:@"Reverting"];
        case iTermGitRepoStateCherrypick:
            return [self attributedStringWithString:@"Cherrypicking"];
        case iTermGitRepoStateBisect:
            return [self attributedStringWithString:@"Bisecting"];
        case iTermGitRepoStateRebase:
            return [self attributedStringWithString:@"Rebasing"];
        case iTermGitRepoStateApply:
            return [self attributedStringWithString:@"Applying"];
    }
    static NSAttributedString *upImage;
    static NSAttributedString *downImage;
    static NSAttributedString *dirtyImage;
    static NSAttributedString *enSpace;
    static NSAttributedString *thinSpace;
    static NSAttributedString *adds;
    static NSAttributedString *deletes;
    static NSAttributedString *addsAndDeletes;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        upImage = [self attributedStringWithImageNamed:@"gitup"];
        downImage = [self attributedStringWithImageNamed:@"gitdown"];
        dirtyImage = [self attributedStringWithImageNamed:@"gitdirty"];
        enSpace = [self attributedStringWithString:@"\u2002"];
        thinSpace = [self attributedStringWithString:@"\u2009"];
        adds = [self attributedStringWithString:@"+"];
        deletes = [self attributedStringWithString:@"-"];
        addsAndDeletes = [self attributedStringWithString:@"±"];
    });

    if (self.currentState.xcode.length > 0) {
        return [self attributedStringWithString:@"⚠️"];
    }
    NSAttributedString *branch = branchString ? [self attributedStringWithString:branchString] : nil;
    if (!branch) {
        return nil;
    }

    NSAttributedString *upCount = self.currentState.pushArrow.integerValue > 0 ? [self attributedStringWithString:self.currentState.pushArrow] : nil;
    NSAttributedString *downCount = self.currentState.pullArrow.integerValue > 0 ? [self attributedStringWithString:self.currentState.pullArrow] : nil;

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result appendAttributedString:branch];

    if (self.currentState.adds && self.currentState.deletes) {
        [result appendAttributedString:thinSpace];
        [result appendAttributedString:addsAndDeletes];
    } else {
        if (self.currentState.adds) {
            [result appendAttributedString:thinSpace];
            [result appendAttributedString:adds];
        }
        if (self.currentState.deletes) {
            [result appendAttributedString:thinSpace];
            [result appendAttributedString:deletes];
        }
    }
    if (self.currentState.dirty) {
        [result appendAttributedString:thinSpace];
        [result appendAttributedString:dirtyImage];
    }

    if (self.currentState.pushArrow.integerValue > 0) {
        [result appendAttributedString:enSpace];
        [result appendAttributedString:upImage];
        [result appendAttributedString:upCount];
    }

    if (self.currentState.pullArrow.integerValue > 0) {
        [result appendAttributedString:enSpace];
        [result appendAttributedString:downImage];
        [result appendAttributedString:downCount];
    }

    return result;
}

- (NSTimeInterval)cadenceInDictionary:(NSDictionary *)knobValues {
    return [knobValues[iTermStatusBarGitComponentPollingIntervalKey] doubleValue] ?: 1;
}

- (BOOL)gitPollerShouldBeEnabled {
    if (self.onLocalhost) {
        DLog(@"Enable git poller: on localhost");
        return YES;
    }

    if ([[iTermGitState alloc] initWithScope:self.scope]) {
        DLog(@"Enable git poller: can construct git state");
        return YES;
    }

    DLog(@"DISABLE GIT POLLER");
    return NO;
}

- (void)updatePollerEnabled {
    _gitPoller.enabled = [self gitPollerShouldBeEnabled];
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

- (BOOL)statusBarComponentIsEmpty {
    return (self.currentState.branch.length == 0);
}

- (void)killSession:(id)sender {
    [[[iTermController sharedInstance] terminalWithSession:_session] closeSessionWithoutConfirmation:_session];
}

- (void)revealSession:(id)sender {
    [_session reveal];
}

- (void)statusBarComponentMouseDownWithView:(NSView *)view {
    [self openMenuWithView:view];
}

- (BOOL)statusBarComponentHandlesMouseDown {
    return YES;
}

- (void)openMenuWithView:(NSView *)view {
    NSView *containingView = view.superview;
    if (!containingView.window) {
        return;
    }
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

    if (self.currentState.xcode.length > 0) {
        [iTermWarning showWarningWithTitle:[self.currentState.xcode stringByReplacingOccurrencesOfString:@"\t" withString:@"\n"]
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"GitPollerXcodeWarning"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Problem Running git"
                                    window:containingView.window];
        return;
    }

    if (self.currentState.branch.length == 0) {
        NSMenu *menu = [[NSMenu alloc] init];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Show Debug Info" action:@selector(debug) keyEquivalent:@""];
        item.target = self;
        [menu addItem:item];
        [menu popUpMenuPositioningItem:menu.itemArray.firstObject atLocation:NSMakePoint(0, 0) inView:containingView];
        return;
    }
    iTermGitState *state = self.currentState.copy;
    NSString *directory = _gitPoller.currentDirectory;
    __weak __typeof(self) weakSelf = self;
    const NSInteger maxCount = 7;
    [self fetchRecentBranchesWithTimeout:0.5 count:maxCount + 1 completion:^(NSArray<NSString *> *branches) {
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
        addItem(@"Log", @selector(log:), YES);
        addItem([NSString stringWithFormat:@"Push origin %@", state.branch],
                @selector(push:),
                state.pushArrow.intValue > 0 || [state.pushArrow isEqualToString:@"error"]);
        addItem([NSString stringWithFormat:@"Pull origin %@", state.branch],
                @selector(pull:),
                !state.dirty);
        [menu addItem:[NSMenuItem separatorItem]];
        for (NSString *branch in [branches it_arrayByKeepingFirstN:maxCount]) {
            if (branch.length == 0) {
                continue;
            }
            if ([branch isEqualToString:state.branch]) {
                continue;
            }
            addItem([NSString stringWithFormat:@"Check out %@", branch], @selector(checkout:), YES).userData = branch;
        }
        [menu addItem:[NSMenuItem separatorItem]];
        addItem(@"Show Debug Info", @selector(debug), YES);
        [menu popUpMenuPositioningItem:menu.itemArray.firstObject atLocation:NSMakePoint(0, 0) inView:containingView];
    }];
}

- (NSString *)pathToGit {
    NSString *custom = [iTermAdvancedSettingsModel gitSearchPath];
    NSString *path = [[custom componentsSeparatedByString:@":"] firstObject];
    if (path.length) {
        return [path stringByAppendingPathComponent:@"git"];
    }
    return @"/usr/bin/git";
}

- (void)runGitCommandWithArguments:(NSArray<NSString *> *)args
                           timeout:(NSTimeInterval)timeout
                        completion:(void (^)(NSString * _Nullable output, int status))completion {
    iTermBufferedCommandRunner *runner = [[iTermBufferedCommandRunner alloc] initWithCommand:[self pathToGit]
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

- (void)fetchRecentBranchesWithTimeout:(NSTimeInterval)timeout
                                 count:(NSInteger)maxCount
                            completion:(void (^)(NSArray<NSString *> *branches))completion {
    if (!self.onLocalhost) {
        completion(@[]);
        return;
    }
    [[iTermSlowOperationGateway sharedInstance] fetchRecentBranchesAt:_gitPoller.currentDirectory
                                                                count:maxCount
                                                           completion:^(NSArray<NSString *> * _Nonnull branches) {
        completion(branches);
    }];
}

- (void)showPopover {
    _popoverVC = [[iTermTextPopoverViewController alloc] initWithNibName:@"iTermTextPopoverViewController"
                                                                  bundle:[NSBundle bundleForClass:self.class]];
    _popoverVC.popover.behavior = NSPopoverBehaviorTransient;
    [_popoverVC view];
    if ([self.delegate statusBarComponentTerminalBackgroundColorIsDark:self]) {
        _popoverVC.view.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
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

    NSArray<NSString *> *args = @[ @"log" ];
    if (!self.onLocalhost) {
        [self runGitOnRemoteHost:args];
        return;
    }
    [self showPopover];
    NSMenuItem *menuItem = sender;
    iTermGitMenuItemContext *context = menuItem.representedObject;
    _logRunner = [[iTermCommandRunner alloc] initWithCommand:[self pathToGit]
                                               withArguments:args
                                                        path:context.directory];
    iTermTextPopoverViewController *popoverVC = _popoverVC;
    __weak __typeof(_logRunner) weakLogRunner = _logRunner;
    __block BOOL stopped = NO;
    _logRunner.outputHandler = ^(NSData *data, void (^completion)(void)) {
        if (stopped) {
            completion();
            return;
        }
        [popoverVC appendString:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
        if (popoverVC.textView.textStorage.length > 100000) {
            stopped = YES;
            [popoverVC appendString:@"\n[Truncated]\n"];
            [weakLogRunner terminate];
        }
        completion();
    };
    [_logRunner runWithTimeout:5];
}

- (void)commit:(id)sender {
    NSMenuItem *menuItem = sender;
    iTermGitMenuItemContext *context = menuItem.representedObject;
    [self runGitInWindowWithArguments:@[ @"commit" ] pwd:context.directory status:@"Committing…" bury:NO];
}

- (void)debug {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Debug Info";
    alert.informativeText = [NSString stringWithFormat:
                             @"Directory: %@\n"
                             @"Polling cadence: %@ sec\n"
                             @"Polling enabled: %@\n"
                             @"Last polled %@ seconds ago\n"
                             @"Repo state: %@\n"
                             @"%@",
                             _gitPoller.currentDirectory,
                             @(_gitPoller.cadence),
                             _gitPoller.enabled ? @"Yes" : @"No",
                             @(-[_gitPoller lastPollTime].timeIntervalSinceNow),
                             [_gitPoller.state prettyDescription],
                             [[iTermGitPollWorker sharedInstance] debugInfoForDirectory:_gitPoller.currentDirectory]];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Copy"];
    if ([alert runModal] == NSAlertSecondButtonReturn) {
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        [pasteboard setString:alert.informativeText forType:NSPasteboardTypeString];
    }
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

- (void)runGitOnRemoteHost:(NSArray<NSString *> *)args {
    NSArray<NSString *> *quotedArgs = [args mapWithBlock:^id(NSString *arg) {
        return [arg stringWithEscapedShellCharactersIncludingNewlines:YES];
    }];
    NSString *command = [NSString stringWithFormat:@"git %@", [quotedArgs componentsJoinedByString:@" "]];
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"Looks like you're sshed somewhere. OK to send the command “%@”?", command]
                               actions:@[ @"OK", @"Cancel" ]
                             accessory:nil
                            identifier:@"GitPollerSshWarning"
                           silenceable:kiTermWarningTypePermanentlySilenceable
                               heading:@"Send Command?"
                                window:self.statusBarComponentView.window];
    if (selection == kiTermWarningSelection0) {
        [self.delegate statusBarComponent:self writeString:[command stringByAppendingString:@"\n"]];
    }
}

- (void)runGitInWindowWithArguments:(NSArray<NSString *> *)args pwd:(NSString *)pwd status:(NSString *)status bury:(BOOL)bury {
    if (_status) {
        DLog(@"Not running command because status is %@", _status);
        return;
    }

    if (!self.onLocalhost) {
        [self runGitOnRemoteHost:args];
        return;
    }

    _status = status;
    [self updateTextFieldIfNeeded];
    NSString *gitWrapper = [[NSBundle bundleForClass:self.class] pathForResource:@"iterm2_git_wrapper" ofType:@"sh"];
    __weak __typeof(self) weakSelf = self;
    iTermSingleUseWindowOptions options = (iTermSingleUseWindowOptionsCloseOnTermination |
                                           iTermSingleUseWindowOptionsShortLived);
    if (bury) {
        options |= iTermSingleUseWindowOptionsInitiallyBuried;
    }
    [[iTermController sharedInstance] openSingleUseWindowWithCommand:gitWrapper
                                                           arguments:args
                                                              inject:nil
                                                         environment:nil
                                                                 pwd:pwd
                                                             options:options
                                                      didMakeSession:^(PTYSession *newSession) { self->_session = newSession; }
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

- (BOOL)gitPollerShouldPoll:(iTermGitPoller *)poller after:(NSDate * _Nullable)lastPoll {
    if ([self.delegate statusBarComponentIsInSetupUI:self]) {
        DLog(@"Don't poll: in setup UI");
        return NO;
    }
    if (![self.delegate statusBarComponentIsVisible:self]) {
        DLog(@"Don't poll: not visible");
        return NO;
    }
    if (lastPoll == nil) {
        DLog(@"First poll. Return YES.");
        return YES;
    }

    const iTermActivityInfo activityInfo = [self.delegate statusBarComponentActivityInfo:self];
    NSDate *lastNewline = [NSDate it_dateWithTimeSinceBoot:activityInfo.lastNewline];
    // Add a 3 second grace period since git takes a moment to update. You might only pick up
    // the change on the second check after pressing enter.
    if ([lastNewline compare:[lastPoll dateByAddingTimeInterval:-3]] == NSOrderedDescending) {
        DLog(@"Newline sent since last poll-3: returning YES");
        return YES;
    }
    const NSTimeInterval pollIntervalWhenInactive = 60;
    NSDate *lastActivity = [NSDate it_dateWithTimeSinceBoot:activityInfo.lastActivity];
    if ([[NSDate date] timeIntervalSinceDate:lastPoll] > pollIntervalWhenInactive &&
        [lastActivity compare:lastPoll] == NSOrderedDescending) {
        DLog(@"Activity since last poll more than %@ seconds ago: return YES", @(pollIntervalWhenInactive));
        return YES;
    }
    DLog(@"Don't poll. lastPoll=%@ lastNewline=%@ lastActivity=%@", lastPoll, lastNewline, lastActivity);
    return NO;
}

@end

NS_ASSUME_NONNULL_END
