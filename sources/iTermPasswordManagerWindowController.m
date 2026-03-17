//
//  iTermPasswordManagerWindowController.m
//  iTerm
//
//  Created by George Nachman on 5/14/14.
//
//

#import "iTermPasswordManagerWindowController.h"

#import <objc/runtime.h>

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "iTermSearchField.h"
#import "iTermSystemVersion.h"
#import "iTermUserDefaults.h"
#import "NSAlert+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"
#import "NSTextField+iTerm.h"
#import "NSWindow+iTerm.h"

static NSString *const kPasswordManagersShouldReloadData = @"kPasswordManagersShouldReloadData";
// Looks nice and is unlikely to be used already
static NSString *const iTermPasswordManagerAccountNameUserNameSeparator = @"\u2002—\u2002";
NSString *const iTermPasswordManagerDidLoadAccounts = @"iTermPasswordManagerDidLoadAccounts";

static NSString *const iTerm2KeeperConnectionDidFailNotification = @"iTerm2KeeperConnectionDidFail";
static NSString *const iTerm2KeeperConnectionDidSucceedNotification = @"iTerm2KeeperConnectionDidSucceed";

static void *const kKeeperSettingsAccessoryContextKey = (void *)&kKeeperSettingsAccessoryContextKey;
static void *const kKeeperSettingsSyncContextKey = (void *)&kKeeperSettingsSyncContextKey;

@interface iTermKeeperSettingsSyncContext : NSObject
@property (nonatomic, weak) NSSecureTextField *secureField;
@property (nonatomic, weak) NSTextField *plainField;
@property (nonatomic, weak) NSTextField *urlField;
@property (nonatomic, weak) id dataSource;
@property (nonatomic, copy) void (^onSyncStarted)(void);   // Dismiss sheet and show loading
@property (nonatomic, copy) void (^onSyncComplete)(void); // Hide loading (called on success or failure)
@property (nonatomic, copy) void (^onSyncSuccess)(void);  // Reload list (called only on success)
@property (nonatomic, weak) NSButton *syncButton;
- (void)syncTapped:(id)sender;
@end

@implementation iTermKeeperSettingsSyncContext
- (void)syncTapped:(id)sender {
    NSString *key = _plainField.hidden ? (_secureField.stringValue ?: @"") : (_plainField.stringValue ?: @"");
    NSString *url = _urlField.stringValue ?: @"";
    key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    url = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (key.length == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"API Key Required";
        alert.informativeText = @"Enter your Keeper Commander API key above before syncing.";
        [alert runModal];
        return;
    }
    // Save key/URL to data source so the reload after sync uses the same credentials
    [(id)_dataSource setKeeperSettingsAPIKey:key];
    [(id)_dataSource setKeeperSettingsAPIURL:url];

    // Dismiss the settings sheet immediately
    NSWindow *sheetWindow = _syncButton.window;
    NSWindow *parent = sheetWindow.sheetParent;
    if (parent) {
        [parent endSheet:sheetWindow returnCode:NSModalResponseCancel];
    }

    // Show loading (scrim + spinner)
    if (_onSyncStarted) {
        _onSyncStarted();
    }

    void (^onComplete)(void) = _onSyncComplete;
    void (^onSuccess)(void) = _onSyncSuccess;
    [(id)_dataSource runKeeperSyncDownWithApiKey:key apiURL:url completion:^(BOOL success, NSString * _Nullable errorMessage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (onComplete) {
                onComplete();
            }
            if (success) {
                if (onSuccess) {
                    onSuccess();
                }
            } else {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Sync Failed";
                alert.informativeText = errorMessage ?: @"The sync-down command failed.";
                [alert runModal];
            }
        });
    }];
}
@end

@interface iTermKeeperSettingsAccessoryContext : NSObject
@property (nonatomic, weak) NSSecureTextField *secureField;
@property (nonatomic, weak) NSTextField *plainField;
@property (nonatomic, weak) NSButton *revealButton;
- (void)toggleReveal:(id)sender;
@end

@implementation iTermKeeperSettingsAccessoryContext
- (void)toggleReveal:(id)sender {
    if (_plainField.hidden) {
        _plainField.stringValue = _secureField.stringValue ?: @"";
        _secureField.hidden = YES;
        _plainField.hidden = NO;
        _plainField.nextKeyView = _secureField.nextKeyView;
        [_plainField.window makeFirstResponder:_plainField];
        _revealButton.image = [NSImage imageWithSystemSymbolName:@"eye.slash" accessibilityDescription:@"Hide API key"];
    } else {
        _secureField.stringValue = _plainField.stringValue ?: @"";
        _plainField.hidden = YES;
        _secureField.hidden = NO;
        [_secureField.window makeFirstResponder:_secureField];
        _revealButton.image = [NSImage imageWithSystemSymbolName:@"eye" accessibilityDescription:@"Show API key"];
    }
}
@end

typedef NS_ENUM(NSUInteger, iTermPasswordManagerReload) {
    iTermPasswordManagerReloadUnlimited,
    iTermPasswordManagerReloadOnce,
    iTermPasswordManagerReloadAssumeCurrent
};

@implementation iTermPasswordManagerPanel

- (NSTimeInterval)animationResizeTime:(NSRect)newFrame {
    BOOL noAnimations = [iTermAdvancedSettingsModel disablePasswordManagerAnimations];
    if (noAnimations) {
        return 0;
    }
    return [super animationResizeTime:newFrame];
}

@end

@interface iTermPasswordManagerWindowController () <
    KeeperCredentialsRequestDelegate,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSControlTextEditingDelegate,
    NSWindowDelegate,
    NSMenuItemValidation>
@property (nonatomic, class, strong) NSArray<NSString *> *cachedCombinedAccountNames;
@end

@implementation iTermPasswordManagerWindowController {
    IBOutlet NSTableColumn *_accountNameColumn;
    IBOutlet NSTableColumn *_userNameColumn;
    IBOutlet NSTableColumn *_passwordColumn;
    IBOutlet NSButton *_removeButton;
    IBOutlet NSButton *_editButton;
    IBOutlet NSButton *_addButton;
    IBOutlet NSButton *_keeperSettingsButton;
    NSButton *_keeperSyncButton;  // Created in code, placed next to settings button; refresh icon only

    // I have to do this becuase you can't change the default button (the one whose key equivalent is Enter)
    IBOutlet NSButton *_defaultButton;  // generally "enter password"
    IBOutlet NSButton *_secondaryButton;  // general "enter user name"

    IBOutlet NSButton *_closeButton;
    IBOutlet NSButton *_broadcastButton;
    IBOutlet NSTextField *_twoFactorCode;
    IBOutlet NSPanel *_newAccountPanel;
    IBOutlet NSTextField *_newPassword;
    IBOutlet NSTextField *_newUserName;
    IBOutlet NSTextField *_newAccount;
    IBOutlet NSButton *_newAccountOkButton;
    IBOutlet NSSecureTextField *_newAccountPassword;
    IBOutlet NSView *_scrim;
    IBOutlet NSProgressIndicator *_progressIndicator;

    NSArray<id<PasswordManagerAccount>> *_entries;
    NSArray<id<PasswordManagerAccount>> *_unfilteredEntries;
    id _eventMonitor;
    id<PasswordManagerDataSource> _dataSource;
    NSInteger _busyCount;
    NSInteger _cancelCount;
    BOOL _awakeFromNibAvailabilityCheckFailed;
    iTermPasswordManagerReload _reloadPolicy;
    BOOL _keeperConfigurationAttemptInProgress;  // Show connection success/failure alert only after config attempt

    @protected
    NSString *_accountNameToSelectAfterAuthentication;
    IBOutlet NSTableView *_tableView;
    IBOutlet iTermSearchField *_searchField;
    IBOutlet NSMenu *_searchFieldMenu;
    IBOutlet NSMenuItem *_probeMenuItem;
    IBOutlet NSMenuItem *_sendReturnMenuItem;
    IBOutlet NSMenuItem *_separatorMenuItem;
}

static NSArray<NSString *> *gTerminalCachedCombinedAccountNames;
+ (NSArray<NSString *> *)cachedCombinedAccountNames {
    return gTerminalCachedCombinedAccountNames;
}

+ (void)setCachedCombinedAccountNames:(NSArray<NSString *> *)names {
    gTerminalCachedCombinedAccountNames = names;
    // Note the browser subclass does not post this because we don't need it yet.
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermPasswordManagerDidLoadAccounts object:nil];
}

+ (iTermPasswordManagerDataSourceProvider *)dataSourceProvider {
    return [iTermPasswordManagerDataSourceProvider forTerminal];
}

- (iTermPasswordManagerDataSourceProvider *)dataSourceProvider {
    return [iTermPasswordManagerDataSourceProvider forTerminal];
}

+ (id<PasswordManagerDataSource>)dataSource {
    return [self.dataSourceProvider dataSource];
}

- (id<PasswordManagerDataSource>)dataSource {
    return [self.dataSourceProvider dataSource];
}

+ (void)fetchAccountsWithWindow:(NSWindow *)window
                     completion:(void (^)(NSArray<id<PasswordManagerAccount>> *))completion {
    RecipeExecutionContext *context = [[RecipeExecutionContext alloc] initWithWindow:window];
    context.skipKeeperTouchIDGate = YES;
    [[self dataSource] fetchAccountsWithContext:context
                                     completion:^(NSArray<id<PasswordManagerAccount>> * _Nonnull accounts) {
        // Sort accounts
        NSArray<id<PasswordManagerAccount>> *result =
        [accounts sortedArrayUsingComparator:^NSComparisonResult(id<PasswordManagerAccount> _Nonnull obj1,
                                                                 id<PasswordManagerAccount> _Nonnull obj2) {
            return [obj1.displayString localizedCaseInsensitiveCompare:obj2.displayString];
        }];

        // As a side-effect, save account names so the password trigger can access them.
        [self setCachedCombinedAccountNames:[result mapWithBlock:^id _Nonnull(id<PasswordManagerAccount>  _Nonnull account) {
            return [account displayString];
        }]];

        completion(result);
    }];
}

- (NSArray<id<PasswordManagerAccount>> *)accounts:(NSArray<id<PasswordManagerAccount>> *)accounts filteredBy:(NSString *)filter {
    return [accounts filteredArrayUsingBlock:^BOOL(id<PasswordManagerAccount> account) {
        return [account matchesFilter:filter];
    }];
}

- (instancetype)init {
    self = [self initWithWindowNibName:@"iTermPasswordManager"];
    if (self) {
        [self authenticate];
        [[[self class] dataSource] resetErrors];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reloadAccountsNotification:)
                                                     name:kPasswordManagersShouldReloadData
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keeperConnectionDidFail:)
                                                     name:iTerm2KeeperConnectionDidFailNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keeperConnectionDidSucceed:)
                                                     name:iTerm2KeeperConnectionDidSucceedNotification
                                                   object:nil];
    }
    return self;
}

- (void)awakeFromNib {
    [[NSDistributedNotificationCenter defaultCenter] addObserver:[self class]
                                                        selector:@selector(staticScreenDidLock:)
                                                            name:@"com.apple.screenIsLocked"
                                                          object:nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(instanceScreenDidLock:)
                                                            name:@"com.apple.screenIsLocked"
                                                          object:nil];

    _scrim.wantsLayer = YES;
    _scrim.layer = [[CALayer alloc] init];
    if (@available(macOS 26, *)) {
        NSView *inner = _scrim.subviews.firstObject;
        NSGlassEffectView *glass = [[NSGlassEffectView alloc] init];
        glass.style = NSGlassEffectViewStyleClear;
        glass.tintColor = [[NSColor controlBackgroundColor] colorWithAlphaComponent:0.25];
        glass.frame = _scrim.bounds;
        _scrim.autoresizesSubviews = YES;
        glass.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [_scrim addSubview:glass];
        NSView *content = [[NSView alloc] initWithFrame:_scrim.bounds];
        [content addSubview:inner];
        glass.contentView = content;
    } else {
        _scrim.layer.backgroundColor = [[[NSColor windowBackgroundColor] colorWithAlphaComponent:0.75] CGColor];
    }
    _scrim.alphaValue = 0;

    _broadcastButton.state = NSControlStateValueOff;
    [_tableView setDoubleAction:@selector(doubleClickOnTableView:)];
    if ([[self.class dataSourceProvider] authenticated] &&
        ![self.currentDataSource checkAvailability]) {
        _awakeFromNibAvailabilityCheckFailed = YES;
        [self dataSourceDidBecomeUnavailable];
    } else {
        _awakeFromNibAvailabilityCheckFailed = NO;
        [self reloadAccounts:^{}];
        [self update];
    }
    self.window.backgroundColor = [NSColor clearColor];
    self.window.contentView.layer.cornerRadius = 4;
    [_searchField setArrowHandler:_tableView];
    if (_keeperSettingsButton) {
        _keeperSettingsButton.bezelStyle = NSBezelStyleRounded;
        NSImage *gearImage = [NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:@"Keeper Settings"];
        if (gearImage) {
            gearImage = [gearImage imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithScale:NSImageSymbolScaleMedium]];
            _keeperSettingsButton.image = gearImage;
        }
        // Sync button (refresh icon only) placed after (to the right of) settings button — same rounded style
        const CGFloat gap = 6;
        const CGFloat btnWidth = 28;
        const CGFloat btnHeight = 24;
        NSRect settingsFrame = _keeperSettingsButton.frame;
        CGFloat syncX = settingsFrame.origin.x + settingsFrame.size.width + gap;
        NSRect syncFrame = NSMakeRect(syncX, settingsFrame.origin.y, btnWidth, btnHeight);
        _keeperSyncButton = [[NSButton alloc] initWithFrame:syncFrame];
        _keeperSyncButton.bezelStyle = NSBezelStyleRounded;
        _keeperSyncButton.bordered = YES;
        _keeperSyncButton.imagePosition = NSImageOnly;
        _keeperSyncButton.buttonType = NSButtonTypeMomentaryPushIn;
        NSImage *refreshImage = [NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:@"Sync from Keeper"];
        if (refreshImage) {
            refreshImage = [refreshImage imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithScale:NSImageSymbolScaleMedium]];
            _keeperSyncButton.image = refreshImage;
        }
        _keeperSyncButton.toolTip = @"Sync from Keeper";
        _keeperSyncButton.target = self;
        _keeperSyncButton.action = @selector(keeperSyncDown:);
        _keeperSyncButton.enabled = YES;
        _keeperSyncButton.autoresizingMask = _keeperSettingsButton.autoresizingMask;
        [_keeperSettingsButton.superview addSubview:_keeperSyncButton positioned:NSWindowAbove relativeTo:nil];
        _keeperSyncButton.hidden = YES;
    }
    __weak __typeof(self) weakSelf = self;

    // Only create event monitor once. This is out of paranioa because there are weird cases where
    // awakeFromNib is called more than once.
    if (!_eventMonitor) {
        _eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
            return [weakSelf caughtKeyDownEvent:event];
        }];
    }
}

- (void)dealloc {
    if (_eventMonitor) {
        [NSEvent removeMonitor:_eventMonitor];
    }
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setSendUserByDefault:(BOOL)sendUserByDefault {
    [self window];
    _sendUserByDefault = sendUserByDefault;
    [self updateKeyEquivalents];
}

- (void)updateKeyEquivalents {
    if (!_defaultButton || !_secondaryButton || !_closeButton) {
        // Outlets not connected yet, XIB may not be fully loaded
        return;
    }

    if (_sendUserByDefault && _didSendUserName == nil) {
        _secondaryButton.hidden = YES;
        _defaultButton.title = @"Enter User Name";
    } else {
        _secondaryButton.hidden = NO;
        if (_didSendUserName) {
            _defaultButton.title = @"Enter Username & Password";
        } else {
            _defaultButton.title = @"Enter Password";
        }
    }

    NSArray<NSButton *> *views = @[_defaultButton, _secondaryButton, _closeButton];
    NSButton *rightmostVisibleButton = [views objectPassingTest:^BOOL(NSButton *view, NSUInteger index, BOOL *stop) {
        return !view.isHidden;
    }];
    const CGFloat desiredMaxX = NSMaxX(rightmostVisibleButton.frame);
    CGFloat x = desiredMaxX;
    const CGFloat spacing = NSMinX(views[0].frame) - NSMaxX(views[1].frame);
    for (NSButton *view in views) {
        if (view.isHidden) {
            continue;
        }
        [view sizeToFit];
        NSRect frame = view.frame;
        frame.origin.x = x - NSWidth(frame);
        view.frame = frame;
        
        x -= NSWidth(frame) + spacing;
    }
}

- (void)setDidSendUserName:(void (^)(void))didSendUserName {
    [self window];
    _didSendUserName = [didSendUserName copy];
    [self updateKeyEquivalents];
}

- (void)dataSourceDidBecomeUnavailable {
    _entries = @[];
    _unfilteredEntries = @[];
    [_tableView reloadData];
    [self updateWithAvailability:NO];
}

- (BOOL)tabShouldSelectTwoFactorField {
    if (!self.isWindowLoaded) {
        return NO;
    }
    if (NSApp.keyWindow != self.window) {
        return NO;
    }
    if (NSApp.keyWindow.firstResponder == _tableView) {
        return YES;
    }
    if ([_searchField textFieldIsFirstResponder]) {
        return _entries.count == 1;
    }
    return NO;
}

- (BOOL)eventIsTab:(NSEvent *)event {
    if (![event.characters isEqualToString:@"\t"]) {
        return NO;
    }
    const NSEventModifierFlags mask = (NSEventModifierFlagCommand |
                                       NSEventModifierFlagOption |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagControl);
    return (event.modifierFlags & mask) == 0;
}

// Make tab jump to 2-factor field from search field when there is exactly one search result or from table view.
- (NSEvent *)caughtKeyDownEvent:(NSEvent *)event {
    if ([self eventIsTab:event] &&
        [self tabShouldSelectTwoFactorField] &&
        [_twoFactorCode acceptsFirstResponder]) {
        [NSApp.keyWindow makeFirstResponder:_twoFactorCode];
        return nil;
    }
    return event;
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    if (self.dataSourceProvider.authenticated) {
        [[self window] makeFirstResponder:_searchField];
    }
}

// Opening this window should not cause the hotkey window to hide.
- (BOOL)autoHidesHotKeyWindow {
    return NO;
}

#pragma mark - APIs

- (void)update {
    [self updateWithAvailability:[self.currentDataSource checkAvailability]];
}

- (void)updateWithAvailability:(BOOL)available {
    DLog(@"Selected rows: %@ from %@", _tableView.selectedRowIndexes.description, [[NSThread callStackSymbols] componentsJoinedByString:@" ; "]);
    _broadcastButton.enabled = [self.delegate iTermPasswordManagerCanBroadcast];
    const BOOL shouldEnableButtons = ([_tableView selectedRow] >= 0 &&
                                      [_delegate iTermPasswordManagerCanEnterPassword]);
    if (_didSendUserName) {
        const BOOL enable = (shouldEnableButtons &&
                             self.selectedUserName.length > 0 &&
                             [_delegate iTermPasswordManagerCanEnterUserName]);
        [_defaultButton setEnabled:enable];
        [_secondaryButton setEnabled:enable];
    } else {
        [_defaultButton setEnabled:shouldEnableButtons];
        [_secondaryButton setEnabled:(shouldEnableButtons &&
                                          self.selectedUserName.length > 0 &&
                                          [_delegate iTermPasswordManagerCanEnterUserName])];
    }
    const BOOL editable = !self.currentDataSource.autogeneratedPasswordsOnly;
    [_editButton setEnabled:([_tableView selectedRow] != -1) && editable];
    [_removeButton setEnabled:([_tableView selectedRow] != -1)];
    _addButton.enabled = available;
    _twoFactorCode.enabled = !self.selectedAccount.sendOTP;
    const BOOL showKeeperSettings = [self.currentDataSource.name isEqualToString:@"Keeper Security"];
    _keeperSettingsButton.hidden = !showKeeperSettings;
    if (_keeperSyncButton) {
        _keeperSyncButton.hidden = !showKeeperSettings;
    }
    if (showKeeperSettings) {
        [(id)self.currentDataSource setCredentialsDelegate:self];
        __weak __typeof(self) weakSelf = self;
        [KeeperDataSource setShowKeeperSettingsSheetHandler:^(NSWindow *window, void (^completion)(NSString * _Nullable)) {
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf showKeeperSettingsSheetWithEmptyAPIKey:YES forWindow:window onOK:nil keyCompletion:completion];
            } else {
                if (completion) completion(nil);
            }
        }];
    } else {
        [KeeperDataSource setShowKeeperSettingsSheetHandler:nil];
    }
}

- (void)keeperDataSourceRequestCredentialsForWindow:(NSWindow *)window
                                         completion:(void (^)(NSString * _Nullable))completion {
    [self showKeeperSettingsSheetWithEmptyAPIKey:YES
                                       forWindow:window
                                            onOK:nil
                                    keyCompletion:^(NSString * _Nullable key) {
        if (completion) {
            completion(key);
        }
    }];
}

- (id<PasswordManagerAccount>)selectedAccount {
    if (_tableView.selectedRow == -1) {
        return nil;
    }
    return _entries[_tableView.selectedRow];
}

- (void)selectAccountName:(NSString *)name {
    DLog(@"selectAccountName:%@", name);
    if (!name) {
        DLog(@"name is nil");
        return;
    }
    if (_entries) {
        [self reallySelectAccountName:name];
        return;
    }
    DLog(@"reload and then select");
    __weak __typeof(self) weakSelf = self;
    [self reloadAccounts:^{
        DLog(@"reload finished");
        [weakSelf reallySelectAccountName:name];
    }];
}

- (void)reallySelectAccountName:(NSString *)name {
    DLog(@"reallySelectAccountName:%@", name);
    const NSUInteger index = [self indexOfDisplayName:name];
    if (index != NSNotFound) {
        DLog(@"Select index %@", @(index));
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index]
                byExtendingSelection:NO];
        [_tableView scrollRowToVisible:index];
    } else if (!self.dataSourceProvider.authenticated) {
        DLog(@"set _accountNameToSelectAfterAuthentication to %@", name);
        _accountNameToSelectAfterAuthentication = [name copy];
    } else {
        DLog(@"failed to find %@ among %@", name, [[_entries mapWithBlock:^id _Nullable(id<PasswordManagerAccount>  _Nonnull anObject) {
            return [anObject displayString];
        }] componentsJoinedByString:@", "]);
    }
}

#pragma mark - Keychain

- (void)updateConfiguration {
    if (self.dataSourceProvider.authenticated) {
        [self reloadAccounts:^{}];
    }
}

+ (NSString *)randomPassword {
    NSString *characters;
    NSUInteger length = 16;
    if ([[iTermApplication sharedApplication] it_modifierFlags] & NSEventModifierFlagOption) {
        characters = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        length += 2;
    } else {
        characters = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+{}|:<>?,./;'[]-=";
    }
    NSMutableString *randomPassword = [NSMutableString string];

    for (NSUInteger i = 0; i < length; i++) {
        uint32_t rand = arc4random_uniform((uint32_t)characters.length);
        unichar character = [characters characterAtIndex:rand];
        [randomPassword appendFormat:@"%C", character];
    }
    return randomPassword;
}

#pragma mark - Actions

- (IBAction)toggleAutomaticallySendReturn:(id)sender {
    [iTermUserDefaults setShouldSendReturnAfterPassword:![iTermUserDefaults shouldSendReturnAfterPassword]];
}

- (IBAction)generatePassword:(id)sender {
    _newPassword.stringValue = [iTermPasswordManagerWindowController randomPassword];
}

- (IBAction)cancelAsyncOperation:(id)sender {
    _cancelCount += 1;
    _busyCount = 1;
    [self decrBusy];
}

- (IBAction)reloadItems:(id)sender {
    if (!self.dataSourceProvider.authenticated) {
        return;
    }
    __weak __typeof(self) weakSelf = self;
    const NSInteger cancelCount = [self incrBusy];
    [self.currentDataSource reload:^{
        [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
            [weakSelf reloadAccounts:^{}];
            [weakSelf decrBusy];
        }];
    }];
}

- (IBAction)reloadItemsWithCompletion:(void (^)(void))completion {
    if (!self.dataSourceProvider.authenticated) {
        completion();
        return;
    }
    __weak __typeof(self) weakSelf = self;
    const NSInteger cancelCount = [self incrBusy];
    [self.currentDataSource reload:^{
        [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
            [weakSelf reloadAccounts:completion];
            [weakSelf decrBusy];
        }];
    }];
}

- (IBAction)useKeychain:(id)sender {
    [self.dataSourceProvider enableKeychain];
    [self update];
    [self updateConfiguration];
}

- (IBAction)use1Password:(id)sender {
    [self.dataSourceProvider enable1Password];
    [self.currentDataSource resetErrors];
    if (![self.currentDataSource checkAvailability]) {
        [self useKeychain:nil];
    }
    [self update];
    [self updateConfiguration];
}

- (IBAction)useLastPass:(id)sender {
    [self.dataSourceProvider enableLastPass];
    [self.currentDataSource resetErrors];
    if (![self.currentDataSource checkAvailability]) {
        [self useKeychain:nil];
    }
    [self update];
    [self updateConfiguration];
}

- (IBAction)resetIntegrationConfiguration:(id)sender {
    const iTermWarningSelection selection = [iTermWarning showWarningWithTitle:@"This will erase iTerm2’s configuration settings for this password manager. The actual passwords will remain unaffected. You’ll have to go through some setup steps to use it again. This action cannot be undone."
                                                                       actions:@[ @"OK", @"Cancel" ]
                                                                     accessory:nil
                                                                    identifier:nil
                                                                   silenceable:kiTermWarningTypePersistent
                                                                       heading:@"Are you sure?"
                                                                        window:self.window];
    if (selection == kiTermWarningSelection0) {
        [self.currentDataSource resetConfiguration];
        [self reloadItems:nil];
    }
}

- (IBAction)useKeePassXC:(id)sender {
    [self.dataSourceProvider enableKeePassXC];
    [self.currentDataSource resetErrors];
    if (![self.currentDataSource checkAvailability]) {
        [self useKeychain:nil];
    }
    [self update];
    [self updateConfiguration];
}

- (IBAction)useBitwarden:(id)sender {
    [self.dataSourceProvider enableBitwarden];
    [self.currentDataSource resetErrors];
    if (![self.currentDataSource checkAvailability]) {
        [self useKeychain:nil];
    }
    [self update];
    [self updateConfiguration];
}

- (IBAction)useKeeper:(id)sender {
    [self.dataSourceProvider enableKeeper];
    [self.currentDataSource resetErrors];
    if (![self.currentDataSource checkAvailability]) {
        [self useKeychain:nil];
    }
    [self update];
    // Only show the settings sheet when the user doesn’t already have an API key in memory (e.g. switching back from macOS Keychain).
    if ([(id)self.currentDataSource keeperHasAPIKeyInMemory]) {
        [self updateConfiguration];
    } else {
        __weak __typeof(self) weakSelf = self;
        [self showKeeperSettingsSheetWithEmptyAPIKey:YES
                                           forWindow:nil
                                                onOK:^{ [weakSelf updateConfiguration]; }
                                        keyCompletion:nil];
    }
}

- (IBAction)closeCurrentSession:(id)sender {
    [self orderOutOrEndSheet];
}

- (void)orderOutOrEndSheet {
    [self sendWillClose];
    if (self.window.isSheet) {
        [self.window.sheetParent endSheet:self.window];
    } else {
        [[self window] orderOut:nil];
    }
    [self sendDidClose];
}

- (void)doubleClickOnTableView:(id)sender {
    if ([_tableView selectedRow] >= 0) {
        if (_tableView.clickedColumn == 1) {
            [self edit:nil];
        } else {
            [self performDefaultAction:nil];
        }
    }
}

- (IBAction)add:(id)sender {
    if (!self.dataSourceProvider.authenticated) {
        return;
    }
    _newAccount.stringValue = self.defaultAccountName ?: @"";
    _newAccountOkButton.enabled = _newAccount.stringValue.length > 0;
    if (self.currentDataSource.autogeneratedPasswordsOnly) {
        _newAccountPassword.enabled = NO;
        _newAccountPassword.stringValue = @"";
        _newAccountPassword.placeholderString = @"Autogenerated";
    } else {
        _newAccountPassword.enabled = YES;
        _newAccountPassword.stringValue = @"";
        _newAccountPassword.placeholderString = nil;
    }
    [self.window beginSheet:_newAccountPanel completionHandler:^(NSModalResponse response){
        [NSApp stopModal];
    }];
    [NSApp runModalForWindow:_newAccountPanel];
}

- (IBAction)cancelNewAccount:(id)sender {
    _newPassword.stringValue = @"";
    _newUserName.stringValue = @"";
    _newAccount.stringValue = @"";
    [self.window endSheet:_newAccountPanel];
    [_newAccountPanel orderOut:nil];
}

- (IBAction)reallyAdd:(id)sender {
    if (_newAccount.stringValue.length == 0) {
        DLog(@"New account name is empty");
        [_newAccountPanel it_shakeNo];
        return;
    }
    const NSUInteger index = [self indexOfAccountName:_newAccount.stringValue userName:_newUserName.stringValue ?: @""];
    if (index != NSNotFound) {
        DLog(@"Already have an account at index %@ for name=%@ user=%@", @(index), _newAccount.stringValue, _newUserName.stringValue);
        [_newAccountPanel it_shakeNo];
        return;
    }
    __weak __typeof(self) weakSelf = self;
    const NSInteger cancelCount = [self incrBusy];
    [[self currentDataSource] addUserName:_newUserName.stringValue ?: @""
                              accountName:_newAccount.stringValue ?: @""
                                 password:_newPassword.stringValue ?: @""
                                  context:self.recipeExecutionContext
                               completion:^(id<PasswordManagerAccount> _Nullable newAccount, NSError * _Nullable error) {
        [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
            [weakSelf didAddAccount:newAccount withError:error];
            [weakSelf decrBusy];
        }];
    }];
    _newPassword.stringValue = @"";
    _newUserName.stringValue = @"";
    _newAccount.stringValue = @"";
    [self.window endSheet:_newAccountPanel];
    [_newAccountPanel orderOut:nil];
}

- (void)didAddAccount:(id<PasswordManagerAccount>)newAccount withError:(NSError *)error {
    if (newAccount) {
        // passwordsDidChange has the side-effect of doing reloadAccounts.
        [self passwordsDidChange];
        NSUInteger index = [self indexOfAccountName:newAccount.accountName userName:newAccount.userName];
        if (index != NSNotFound) {
            [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
        }
        [self showRecordAddedSuccessForAccountName:newAccount.accountName];
    }
    if (error) {
        DLog(@"%@", error);
        [self showKeeperOperationErrorWithTitle:@"Add failed" error:error];
    }
}

- (IBAction)remove:(id)sender {
    if (self.dataSourceProvider.authenticated) {
        NSInteger selectedRow = [_tableView selectedRow];
        if (selectedRow < 0 || selectedRow >= _entries.count) {
            return;
        }
        if (![self shouldRemoveSelection]) {
            return;
        }
        [_tableView reloadData];
        __weak __typeof(self) weakSelf = self;
        const NSInteger cancelCount = [self incrBusy];
        NSString *accountName = [self accountNameForRow:selectedRow] ?: @"";
        [_entries[selectedRow] deleteWithContext:self.recipeExecutionContext
                                      completion:^(NSError * _Nullable error) {
            [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
                [weakSelf decrBusy];
                if (error) {
                    DLog(@"%@", error);
                    [weakSelf showKeeperOperationErrorWithTitle:@"Delete failed" error:error];
                    return;
                }
                [weakSelf didRemoveEntry];
                [weakSelf showRecordDeletedSuccessForAccountName:accountName];
            }];
        }];
    }
}

- (void)didRemoveEntry {
    [self passwordsDidChange];
}

- (BOOL)shouldRemoveSelection {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Are you sure you want to delete this password?";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    return [alert runSheetModalForWindow:self.window] == NSAlertFirstButtonReturn;
}

- (IBAction)edit:(id)sender {
    const NSInteger row = _tableView.selectedRow;
    if (row >= 0 && row < _entries.count) {
        NSString *accountName = [self accountNameForRow:row];
        if (!accountName) {
            return;
        }

        @autoreleasepool {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = [NSString stringWithFormat:@"Enter password for %@:", accountName];
            [alert addButtonWithTitle:@"OK"];
            [alert addButtonWithTitle:@"Generate"];
            [alert addButtonWithTitle:@"Cancel"];

            NSSecureTextField *newPassword = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
            newPassword.editable = YES;
            newPassword.selectable = YES;
            alert.accessoryView = newPassword;
            [alert layout];
            [[alert window] makeFirstResponder:newPassword];

            __weak __typeof(self) weakSelf = self;
            [self runModal:alert completion:^(NSModalResponse response) {
                [weakSelf handleEditPasswordCompletion:response row:row newPassword:newPassword];
            }];
        }
    }
}

- (void)handleEditPasswordCompletion:(NSModalResponse)response
                                 row:(NSInteger)row
                         newPassword:(NSSecureTextField *)newPassword {
    __weak __typeof(self) weakSelf = self;
    switch (response) {
        case NSAlertFirstButtonReturn: {
            const NSInteger cancelCount = [self incrBusy];
            NSString *accountName = [self accountNameForRow:row] ?: @"";
            [_entries[row] setPasswordWithContext:self.recipeExecutionContext
                                         password:newPassword.stringValue
                                       completion:^(NSError * _Nullable error) {
                [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
                    [weakSelf decrBusy];
                    if (error) {
                        DLog(@"%@", error);
                        [weakSelf showKeeperOperationErrorWithTitle:@"Update failed" error:error];
                        return;
                    }
                    [weakSelf passwordsDidChange];
                    [weakSelf showPasswordUpdateSuccessForAccountName:accountName];
                }];
            }];
            break;
        }
        case NSAlertSecondButtonReturn: {
            __weak __typeof(self) weakSelf = self;
            const NSInteger cancelCount = [self incrBusy];
            NSString *accountName = [self accountNameForRow:row] ?: @"";
            [_entries[row] setPasswordWithContext:self.recipeExecutionContext
                                         password:[iTermPasswordManagerWindowController randomPassword]
                                       completion:^(NSError * _Nullable error) {
                [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
                    [weakSelf decrBusy];
                    if (error) {
                        DLog(@"%@", error);
                        [weakSelf showKeeperOperationErrorWithTitle:@"Update failed" error:error];
                        return;
                    }
                    [weakSelf passwordsDidChange];
                    [weakSelf showPasswordUpdateSuccessForAccountName:accountName];
                }];
            }];
            break;
        }
    }}

- (IBAction)performDefaultAction:(id)sender {
    if (_sendUserByDefault && _didSendUserName == nil) {
        [self enterUsername];
    } else {
        [self enterPassword];
    }
}

- (void)enterPassword {
    DLog(@"enterPassword");
    __weak __typeof(self) weakSelf = self;
    [self fetchSelectedPassword:^(NSString *password, NSString *otp) {
        if (!password) {
            return;
        }
        [weakSelf didFetchPasswordToEnter:password otp:otp];
    }];
}

- (NSString *)combinedPassword:(NSString *)password otp:(NSString *)otp {
    NSString *secondFactor = _twoFactorCode.stringValue;
    if (otp && [secondFactor length] == 0) {
        secondFactor = otp;
    }
    NSString *twoFactorCode = [secondFactor stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return [password stringByAppendingString:twoFactorCode];
}

- (void)didFetchPasswordToEnter:(NSString *)password otp:(NSString *)otp {
    DLog(@"didFetchPasswordToEnter giving password to delegate");
    if (self.didSendUserName) {
        // In send-both mode. First send the username (async for Keeper), then password and close.
        __weak __typeof(self) weakSelf = self;
        [self enterUsernameWithCompletion:^{
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            void (^didSendUserName)(void) = strongSelf.didSendUserName;
            strongSelf.didSendUserName = nil;
            if (didSendUserName) {
                didSendUserName();
            }
            [strongSelf.delegate iTermPasswordManagerEnterPassword:[strongSelf combinedPassword:password otp:otp]
                                                         broadcast:strongSelf->_broadcastButton.state == NSControlStateValueOn];
            DLog(@"enterPassword: closing sheet");
            [strongSelf closeOrEndSheet];
        }];
        return;
    }
    [_delegate iTermPasswordManagerEnterPassword:[self combinedPassword:password otp:otp]
                                       broadcast:_broadcastButton.state == NSControlStateValueOn];
    DLog(@"enterPassword: closing sheet");
    [self closeOrEndSheet];
}

- (IBAction)performSecondaryAction:(id)sender {
    [self enterUsername];
}

- (void)enterUsername {
    [self enterUsernameWithCompletion:nil];
}

- (void)enterUsernameWithCompletion:(void (^)(void))afterSend {
    DLog(@"enterUserName");
    id<PasswordManagerAccount> account = [self selectedAccount];
    if (!account) {
        if (afterSend) {
            afterSend();
        }
        return;
    }
    const NSInteger cancelCount = [self incrBusy];
    RecipeExecutionContext *context = [self recipeExecutionContext];
    __weak __typeof(self) weakSelf = self;
    [account usernameForTerminalWithContext:context completion:^(NSString * _Nullable username) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            [strongSelf ifCancelCountUnchanged:cancelCount perform:^{
                [strongSelf decrBusy];
                if (username.length > 0) {
                    [strongSelf.delegate iTermPasswordManagerEnterUserName:username
                                                                broadcast:strongSelf->_broadcastButton.state == NSControlStateValueOn];
                    DLog(@"enterUsername: closing sheet");
                }
                if (afterSend) {
                    afterSend();
                } else {
                    [strongSelf closeOrEndSheet];
                }
            }];
        });
    }];
}

- (void)closeOrEndSheet {
    [self sendWillClose];
    if (self.window.isSheet) {
        DLog(@"Ask parent to end sheet");
        [self.window.sheetParent endSheet:self.window];
    } else {
        DLog(@"Close window");
        [self.window close];
    }
    [self sendDidClose];
}

- (IBAction)editAccountName:(id)sender {
    const NSInteger row = _tableView.clickedRow;
    if (row < 0) {
        return;
    }
    [_tableView editColumn:0 row:row withEvent:nil select:YES];
}

- (void)showKeeperSettingsSheetWithEmptyAPIKey:(BOOL)emptyAPIKey
                                     forWindow:(NSWindow *)window
                                          onOK:(void (^)(void))onOK
                                  keyCompletion:(void (^)(NSString * _Nullable))keyCompletion {
    if (![self.currentDataSource.name isEqualToString:@"Keeper Security"]) {
        return;
    }
    NSWindow *sheetParent = window ?: self.window;
    if (!sheetParent) {
        if (keyCompletion) keyCompletion(nil);
        return;
    }
    id ds = self.currentDataSource;
    // When opening from the gear (edit): fetch from Keychain so user can see/update saved values. When opening from “select Keeper”: no Keychain read, empty key and default URL.
    NSString *savedKey = emptyAPIKey ? @"" : ([(id)ds keeperSettingsAPIKeyForEditing] ?: @"");
    NSString *savedURL = emptyAPIKey ? @"" : ([(id)ds keeperSettingsAPIURLForEditing] ?: @"");

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Keeper Security Settings";
    alert.informativeText = @"Add or update your Keeper Commander API key and service URL. Both are stored in macOS Keychain; the API key is protected by Touch ID, Face ID, or device passcode when available.";
    [alert addButtonWithTitle:@"Connect"];
    [alert addButtonWithTitle:@"Cancel"];

    const CGFloat width = 560;
    const CGFloat rowHeight = 22;
    const CGFloat labelWidth = 70;
    const CGFloat margin = 20;
    const CGFloat rowSpacing = 18;  // Vertical gap between API URL and API Key rows
    const CGFloat noteHeight = 14;
    const CGFloat noteSpacing = 4;  // Gap between API URL field and note
    const CGFloat accessoryHeight = margin + (2 * rowHeight) + rowSpacing + noteHeight + noteSpacing + margin;
    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, accessoryHeight)];
    accessory.frame = NSMakeRect(0, 0, width, accessoryHeight);

    // Row 0 (top): API URL
    const CGFloat urlRowY = margin + rowHeight + rowSpacing + noteHeight + noteSpacing;
    NSTextField *urlLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, urlRowY, labelWidth, rowHeight)];
    urlLabel.stringValue = @"API URL:";
    urlLabel.bezeled = NO;
    urlLabel.drawsBackground = NO;
    urlLabel.editable = NO;
    urlLabel.selectable = NO;
    urlLabel.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    [accessory addSubview:urlLabel];

    NSTextField *urlField = [[NSTextField alloc] initWithFrame:NSMakeRect(labelWidth + 8, urlRowY, width - labelWidth - 8, rowHeight)];
    urlField.placeholderString = @"e.g. http://127.0.0.1:8900/api/v2/";
    urlField.stringValue = savedURL ?: @"";
    urlField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    [accessory addSubview:urlField];

    // Note below API URL: suggest using /api/v2
    const CGFloat noteRowY = margin + rowHeight + rowSpacing;
    NSTextField *urlNote = [[NSTextField alloc] initWithFrame:NSMakeRect(labelWidth + 8, noteRowY, width - labelWidth - 8, noteHeight)];
    urlNote.stringValue = @"Note: Append /api/v2 in your API URL.";
    urlNote.bezeled = NO;
    urlNote.drawsBackground = NO;
    urlNote.editable = NO;
    urlNote.selectable = NO;
    urlNote.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    urlNote.textColor = [NSColor secondaryLabelColor];
    [accessory addSubview:urlNote];

    // Row 1 (bottom): API Key
    const CGFloat keyRowY = margin;
    NSTextField *keyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, keyRowY, labelWidth, rowHeight)];
    keyLabel.stringValue = @"API Key:";
    keyLabel.bezeled = NO;
    keyLabel.drawsBackground = NO;
    keyLabel.editable = NO;
    keyLabel.selectable = NO;
    keyLabel.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    [accessory addSubview:keyLabel];

    const CGFloat eyeButtonWidth = 28;
    const CGFloat keyFieldWidth = width - labelWidth - 8 - eyeButtonWidth - 4;
    const NSRect keyFieldFrame = NSMakeRect(labelWidth + 8, keyRowY, keyFieldWidth, rowHeight);

    NSSecureTextField *keyFieldSecure = [[NSSecureTextField alloc] initWithFrame:keyFieldFrame];
    keyFieldSecure.placeholderString = @"Enter Keeper Commander API key";
    keyFieldSecure.stringValue = savedKey ?: @"";
    keyFieldSecure.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    [accessory addSubview:keyFieldSecure];

    NSTextField *keyFieldPlain = [[NSTextField alloc] initWithFrame:keyFieldFrame];
    keyFieldPlain.placeholderString = @"Enter Keeper Commander API key";
    keyFieldPlain.stringValue = savedKey ?: @"";
    keyFieldPlain.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    keyFieldPlain.hidden = YES;
    [accessory addSubview:keyFieldPlain];

    NSButton *revealButton = [[NSButton alloc] initWithFrame:NSMakeRect(labelWidth + 8 + keyFieldWidth + 4, keyRowY, eyeButtonWidth, rowHeight)];
    revealButton.bezelStyle = NSBezelStyleRegularSquare;
    revealButton.bordered = YES;
    revealButton.image = [NSImage imageWithSystemSymbolName:@"eye" accessibilityDescription:@"Show API key"];
    revealButton.imagePosition = NSImageOnly;
    revealButton.buttonType = NSButtonTypeMomentaryPushIn;
    [accessory addSubview:revealButton];

    iTermKeeperSettingsAccessoryContext *context = [[iTermKeeperSettingsAccessoryContext alloc] init];
    context.secureField = keyFieldSecure;
    context.plainField = keyFieldPlain;
    context.revealButton = revealButton;
    objc_setAssociatedObject(accessory, kKeeperSettingsAccessoryContextKey, context, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    revealButton.target = context;
    revealButton.action = @selector(toggleReveal:);

    alert.accessoryView = accessory;
    [alert layout];

    [alert beginSheetModalForWindow:sheetParent completionHandler:^(NSModalResponse response) {
        objc_setAssociatedObject(accessory, kKeeperSettingsAccessoryContextKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (response != NSAlertFirstButtonReturn) {
            if (keyCompletion) {
                keyCompletion(nil);
            }
            return;
        }
        if (!keyFieldPlain.hidden) {
            keyFieldSecure.stringValue = keyFieldPlain.stringValue ?: @"";
        }
        NSString *key = [keyFieldSecure.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *url = [urlField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [ds setKeeperSettingsAPIKey:key];
        [ds setKeeperSettingsAPIURL:url];
        // This sheet is only shown when current data source is Keeper Security (checked at method start).
        self->_keeperConfigurationAttemptInProgress = YES;
        if (keyCompletion) {
            keyCompletion(key.length ? key : nil);
        }
        if (onOK) {
            onOK();
        }
    }];
}

- (IBAction)keeperSettings:(id)sender {
    __weak __typeof(self) weakSelf = self;
    [self showKeeperSettingsSheetWithEmptyAPIKey:NO
                                       forWindow:nil
                                            onOK:^{ [weakSelf reloadItems:nil]; }
                                    keyCompletion:nil];
}

- (IBAction)keeperSyncDown:(id)sender {
    if (![self.currentDataSource.name isEqualToString:@"Keeper Security"]) {
        return;
    }
    id ds = self.currentDataSource;
    if (![ds respondsToSelector:@selector(keeperSettingsAPIKeyForEditing)] ||
        ![ds respondsToSelector:@selector(runKeeperSyncDownWithApiKey:apiURL:completion:)]) {
        return;
    }
    NSString *key = [(id)ds keeperSettingsAPIKeyForEditing];
    NSString *url = [(id)ds keeperSettingsAPIURLForEditing] ?: ([ds respondsToSelector:@selector(keeperSettingsAPIURL)] ? [ds keeperSettingsAPIURL] : nil) ?: @"";
    key = [(key ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    url = [(url ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!key.length) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"API Key Required";
        alert.informativeText = @"Open Keeper Settings (gear) and enter your API key before syncing.";
        [alert runModal];
        return;
    }
    [self incrBusy];
    __weak __typeof(self) weakSelf = self;
    [(id)ds runKeeperSyncDownWithApiKey:key apiURL:url completion:^(BOOL success, NSString * _Nullable errorMessage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf decrBusy];
            if (success) {
                [weakSelf reloadItems:nil];
            } else {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Sync Failed";
                alert.informativeText = errorMessage ?: @"The sync-down command failed.";
                [alert runModal];
            }
        });
    }];
}

// If the error message is JSON (e.g. {"error":"Please provide a valid api key","status":"error"}), extract the "error" value for display.
static NSString *keeperDisplayMessageFromErrorString(NSString *message) {
    if (!message.length) { return nil; }
    if (![message containsString:@"{\""] && ![message containsString:@"\"error\""]) {
        return message;
    }
    NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) { return message; }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) { return message; }
    NSString *error = [(NSDictionary *)json objectForKey:@"error"];
    if ([error isKindOfClass:[NSString class]] && error.length > 0) {
        return error;
    }
    NSString *msg = [(NSDictionary *)json objectForKey:@"message"];
    if ([msg isKindOfClass:[NSString class]] && msg.length > 0) {
        return msg;
    }
    return message;
}

- (void)showKeeperOperationErrorWithTitle:(NSString *)title error:(NSError *)error {
    NSString *message = error.localizedDescription ?: @"";
    message = keeperDisplayMessageFromErrorString(message) ?: message;
    if (!message.length) {
        message = @"An error occurred.";
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert runSheetModalForWindow:self.window];
}

- (void)showPasswordUpdateSuccessForAccountName:(NSString *)accountName {
    NSString *name = accountName.length ? accountName : @"Unknown";
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Password updated";
    alert.informativeText = [NSString stringWithFormat:@"The password for “%@” was updated successfully.", name];
    [alert addButtonWithTitle:@"OK"];
    [alert runSheetModalForWindow:self.window];
}

- (void)showRecordAddedSuccessForAccountName:(NSString *)accountName {
    NSString *name = accountName.length ? accountName : @"Unknown";
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Record added";
    alert.informativeText = [NSString stringWithFormat:@"The record “%@” was added successfully.", name];
    [alert addButtonWithTitle:@"OK"];
    [alert runSheetModalForWindow:self.window];
}

- (void)showRecordDeletedSuccessForAccountName:(NSString *)accountName {
    NSString *name = accountName.length ? accountName : @"Unknown";
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Record deleted";
    alert.informativeText = [NSString stringWithFormat:@"The record “%@” was deleted successfully.", name];
    [alert addButtonWithTitle:@"OK"];
    [alert runSheetModalForWindow:self.window];
}

- (void)keeperConnectionDidFail:(NSNotification *)notification {
    if (![self.currentDataSource.name isEqualToString:@"Keeper Security"]) {
        return;
    }
    _keeperConfigurationAttemptInProgress = NO;
    NSString *message = notification.userInfo[@"error"];
    message = keeperDisplayMessageFromErrorString(message) ?: message;
    if (!message.length) {
        message = @"Could not connect to Keeper. Check your API key and service URL, and ensure the Keeper Commander service is running.";
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Keeper Connection Failed";
    alert.informativeText = message;
    [alert addButtonWithTitle:@"Reconfigure"];
    [alert addButtonWithTitle:@"Cancel"];
    const NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        __weak __typeof(self) weakSelf = self;
        [self showKeeperSettingsSheetWithEmptyAPIKey:NO
                                           forWindow:self.window
                                                onOK:^{ [weakSelf updateConfiguration]; }
                                        keyCompletion:nil];
    }
    // Cancel: leave password manager selection unchanged; user can switch provider manually.
}

- (void)keeperConnectionDidSucceed:(NSNotification *)notification {
    if (![self.currentDataSource.name isEqualToString:@"Keeper Security"]) {
        return;
    }
    if (!_keeperConfigurationAttemptInProgress) {
        return;  // Only show success alert after a configuration attempt (e.g. OK on settings sheet).
    }
    _keeperConfigurationAttemptInProgress = NO;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Keeper Connected";
    alert.informativeText = @"Connected to Keeper successfully. Your records are now available.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (id<PasswordManagerAccount>)clickedAccount {
    NSInteger index = [_tableView clickedRow];
    if (index < 0) {
        DLog(@"return nil, negative index");
        return nil;
    }
    if (index >= _entries.count) {
        DLog(@"Index out of bounds");
        return nil;
    }
    return _entries[index];
}

- (RecipeExecutionContext *)recipeExecutionContext {
    return [[RecipeExecutionContext alloc] initWithWindow:self.window];
}

- (IBAction)switchAccount:(id)sender {
    [[self currentDataSource] switchAccountWithCompletion:^{
        [self reloadItems:nil];
    }];
}

- (IBAction)appendOTP:(id)sender {
    if (!self.dataSourceProvider.authenticated) {
        return;
    }
    id<PasswordManagerAccount> account = [self clickedAccount];
    if (account) {
        __weak __typeof(self) weakSelf = self;
        const NSInteger cancelCount = [self incrBusy];
        [self.currentDataSource toggleShouldSendOTPWithContext:self.recipeExecutionContext
                                                    forAccount:account
                                                    completion:^(id<PasswordManagerAccount> _Nullable replacement,
                                                                 NSError *error) {
            [weakSelf reloadItemsWithCompletion:^{
                [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
                    [self decrBusy];
                    if (replacement) {
                        [weakSelf selectAccount:replacement userName:replacement.userName];
                    } else {
                        DLog(@"%@", error);
                    }
                }];
            }];
        }];
    }
}

- (IBAction)editUserName:(id)sender {
    const NSInteger row = _tableView.clickedRow;
    if (row < 0) {
        return;
    }
    [_tableView editColumn:1 row:row withEvent:nil select:YES];
}

- (IBAction)revealPassword:(id)sender {
    const NSInteger row = _tableView.clickedRow;
    if (row >= 0) {
        @autoreleasepool {
            NSString *accountName = [self accountNameForRow:row];
            if (!accountName) {
                return;
            }
            __weak __typeof(self) weakSelf = self;
            [self fetchClickedPassword:^(NSString *password, NSString *otp) {
                NSString *formatted;
                if (otp) {
                    formatted = [NSString stringWithFormat:@"%@\n%@", password, otp];
                } else {
                    formatted = password;
                }
                [weakSelf revealPassword:formatted forAccountName:accountName];
            }];
        }
    }
}

- (void)revealPassword:(NSString *)password forAccountName:(NSString *)accountName {
    if (!password) {
        // Already showed an error.
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Password for %@", accountName];
    alert.informativeText = password;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Copy"];

    __weak __typeof(self) weakSelf = self;
    [self runModal:alert completion:^(NSModalResponse response) {
        if (response == NSAlertSecondButtonReturn) {
            [weakSelf copy:password];
        }
    }];
}

- (void)copy:(NSString *)password {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:self];
    [pasteboard setString:password forType:NSPasteboardTypeString];
}

- (IBAction)copyPassword:(id)sender {
    __weak __typeof(self) weakSelf = self;
    [self fetchClickedPassword:^(NSString *password, NSString *otp) {
        if (!password) {
            return;
        }
        if (otp) {
            [weakSelf didFetchPasswordToCopy:[password stringByAppendingString:otp]];
        } else {
            [weakSelf didFetchPasswordToCopy:password];
        }
    }];
}

- (void)didFetchPasswordToCopy:(NSString *)password {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:self];
    [pasteboard setString:password forType:NSPasteboardTypeString];
}

- (BOOL)shouldProbe {
    return ([iTermUserDefaults probeForPassword] && [iTermAdvancedSettingsModel echoProbeDuration] > 0);
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (!self.dataSourceProvider.authenticated) {
        return NO;
    }
    if (menuItem.action == @selector(toggleRequireAuthenticationAfterScreenLocks:)) {
        const BOOL allowed = iTermSecureUserDefaults.instance.requireAuthToOpenPasswordManager;
        if (!allowed) {
            return NO;
        }
        menuItem.state = [iTermUserDefaults requireAuthenticationAfterScreenLocks] ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (menuItem.action == @selector(toggleRequireAuthenticationToOpenPasswordManager:)) {
        const BOOL state = iTermSecureUserDefaults.instance.requireAuthToOpenPasswordManager;
        menuItem.state = state ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (menuItem.action == @selector(toggleProbe:)) {
        menuItem.state = self.shouldProbe ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (menuItem.action == @selector(useKeychain:)) {
        menuItem.state = self.dataSourceProvider.keychainEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (menuItem.action == @selector(use1Password:)) {
        menuItem.state = self.dataSourceProvider.onePasswordEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (menuItem.action == @selector(useLastPass:)) {
        menuItem.state = self.dataSourceProvider.lastPassEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (menuItem.action == @selector(useKeePassXC:)) {
        menuItem.state = self.dataSourceProvider.keePassXCEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (menuItem.action == @selector(useBitwarden:)) {
        menuItem.state = self.dataSourceProvider.bitwardenEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (menuItem.action == @selector(useKeeper:)) {
        menuItem.state = self.dataSourceProvider.keeperEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (menuItem.action == @selector(resetIntegrationConfiguration:)) {
        const BOOL allowed = [[self currentDataSource] canResetConfiguration];
        if (allowed) {
            menuItem.title = [NSString stringWithFormat:@"Reset %@ Configuration", [[self currentDataSource] name]];
        } else {
            menuItem.title = @"Reset Integration Configuration";
        }
        return allowed;
    } else if (menuItem.action == @selector(editAccountName:) ||
               menuItem.action == @selector(editUserName:) ||
               menuItem.action == @selector(copyPassword:) ||
               menuItem.action == @selector(revealPassword:)) {
        return _tableView.clickedRow != -1;
    } else if (menuItem.action == @selector(appendOTP:)) {
        if (_tableView.clickedRow < 0 || _tableView.clickedRow >= _entries.count) {
            menuItem.state = NSControlStateValueOff;
            return NO;
        }
        if (!_entries[_tableView.clickedRow].hasOTP) {
            menuItem.state = NSControlStateValueOff;
            return NO;
        }
        menuItem.state = _entries[_tableView.clickedRow].sendOTP ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    } else if (menuItem.action == @selector(toggleAutomaticallySendReturn:)) {
        menuItem.state = [iTermUserDefaults shouldSendReturnAfterPassword] ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    } else if (menuItem.action == @selector(switchAccount:)) {
        return self.dataSourceProvider.authenticated && [[self currentDataSource] supportsMultipleAccounts];
    }
    return YES;
}

- (IBAction)toggleRequireAuthenticationToOpenPasswordManager:(id)sender {
    iTermSecureUserDefaults.instance.requireAuthToOpenPasswordManager = !iTermSecureUserDefaults.instance.requireAuthToOpenPasswordManager;
}

- (IBAction)toggleRequireAuthenticationAfterScreenLocks:(id)sender {
    [iTermUserDefaults setRequireAuthenticationAfterScreenLocks:![iTermUserDefaults requireAuthenticationAfterScreenLocks]];
}

- (IBAction)toggleProbe:(id)sender {
    [iTermUserDefaults setProbeForPassword:!self.shouldProbe];
}

// Gotta have this so that validateMenuItem will get called.
- (IBAction)settingsMenu:(id)sender {
}

#pragma mark - Notifications

+ (void)staticScreenDidLock:(NSNotification *)notification {
    if ([iTermUserDefaults requireAuthenticationAfterScreenLocks]) {
        [self.dataSourceProvider revokeAuthentication];
    }
}

- (void)instanceScreenDidLock:(NSNotification *)notification {
    if (iTermSecureUserDefaults.instance.requireAuthToOpenPasswordManager &&
        [iTermUserDefaults requireAuthenticationAfterScreenLocks]) {
        for (NSWindow *sheet in [self.window.sheets copy]) {
            [self.window endSheet:sheet];
        }
        [self closeCurrentSession:nil];
    }
}

#pragma mark - Private

- (id<PasswordManagerDataSource>)currentDataSource {
    return self.class.dataSource;
}

- (void)authenticate {
    DLog(@"Request auth if possible");
    if (self.dataSourceProvider.authenticated) {
        DLog(@"Already authenticated");
        return;
    }

    __weak __typeof(self) weakSelf = self;
    [self.dataSourceProvider requestAuthenticationIfNeeded:^(BOOL authenticated) {
        [weakSelf authenticationDidComplete:authenticated];
    }];
}

- (void)authenticationDidComplete:(BOOL)success {
    DLog(@"begin");
    // When a sheet is attached to a hotkey window another app becomes active after the auth dialog
    // is dismissed, leaving the hotkey behind another app.
    _awakeFromNibAvailabilityCheckFailed = NO;
    [NSApp activateIgnoringOtherApps:YES];
    [self consolidateReloads:^{
        [self.window.sheetParent makeKeyAndOrderFront:nil];

        if (success && !_awakeFromNibAvailabilityCheckFailed) {
            if (![self.currentDataSource checkAvailability]) {
                [self dataSourceDidBecomeUnavailable];
            } else {
                __weak __typeof(self) weakSelf = self;
                [self reloadAccounts:^{
                    [weakSelf didBecomeReady];
                }];
            }
        } else {
            DLog(@"Auth failed. Close window.");
            [self closeOrEndSheet];
        }
    }];
}

- (void)didBecomeReady {
    DLog(@"didBecomeReady");
    if (_accountNameToSelectAfterAuthentication) {
        DLog(@"will select %@", _accountNameToSelectAfterAuthentication);
        [self selectAccountName:_accountNameToSelectAfterAuthentication];
        _accountNameToSelectAfterAuthentication = nil;
    } else {
        DLog(@"make search field first responder");
        [[self window] makeFirstResponder:_searchField];
    }
}

- (void)fetchClickedPassword:(void (^)(NSString *password, NSString *otp))completion {
    DLog(@"clickedPassword");
    [self fetchPasswordForRow:[_tableView clickedRow] completion:completion];
}

- (void)fetchSelectedPassword:(void (^)(NSString *password, NSString *otp))completion {
    DLog(@"selectedPassword");
    NSInteger index = [_tableView selectedRow];
    [self fetchPasswordForRow:index completion:completion];
}

- (void)fetchPasswordForRow:(NSInteger)index completion:(void (^)(NSString *password, NSString *otp))completion {
    DLog(@"row=%@", @(index));
    if (!self.dataSourceProvider.authenticated) {
        DLog(@"passwordForRow: return nil, not authenticated");
        completion(nil, nil);
        return;
    }
    if (index < 0) {
        DLog(@"passwordForRow: return nil, negative index");
        completion(nil, nil);
        return;
    }
    if (index >= _entries.count) {
        DLog(@"index too big");
        completion(nil, nil);
        return;
    }

    const NSInteger cancelCount = [self incrBusy];
    __weak __typeof(self) weakSelf = self;
    const BOOL sendOTP = _entries[index].sendOTP;
    [_entries[index] fetchPasswordWithContext:self.recipeExecutionContext
                                   completion:^(NSString *password,
                                                NSString *otp,
                                                NSError *error) {
        [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
            [weakSelf decrBusy];
            if (error) {
                DLog(@"passwordForRow: return nil, keychain gave error %@", error);

                NSAlert *alert = [[NSAlert alloc] init];
                NSString *message;
                if ([error.domain isEqualToString:@"KeeperDataSource"]) {
                    message = [NSString stringWithFormat:@"Could not get password, Make sure you have Password created in keeper for this record. %@", error.localizedDescription];
                } else {
                    message = [NSString stringWithFormat:@"Could not get password. Keychain query failed: %@",
                               error.localizedDescription];
                }
                alert.messageText = message;
                [alert addButtonWithTitle:@"OK"];
                [self runModal:alert completion:^(NSModalResponse response) { }];
                completion(nil, nil);
            } else {
                DLog(@"passwordForRow: return nonnil password");
                completion(password ?: @"", sendOTP ? otp : nil);
            }
        }];
    }];
}

- (void)runModal:(NSAlert *)alert completion:(void (^)(NSModalResponse))completion {
    if (self.windowLoaded && self.window.isVisible) {
        [NSApp activateIgnoringOtherApps:YES];
        [alert beginSheetModalForWindow:self.window completionHandler:completion];
    } else {
        const NSModalResponse response = [alert runModal];
        completion(response);
    }
}

- (NSString *)selectedUserName {
    DLog(@"selectedUserName");
    if (!self.dataSourceProvider.authenticated) {
        DLog(@"selectedUserName: return nil, not authenticated");
        return nil;
    }
    NSInteger index = [_tableView selectedRow];
    if (index < 0) {
        DLog(@"selectedPassword: return nil, negative index");
        return nil;
    }
    if (index >= _entries.count) {
        DLog(@"Index out of bounds");
        return nil;
    }
    return _entries[index].userName;
}

- (NSUInteger)indexOfDisplayName:(NSString *)name {
    return [_entries indexOfObjectPassingTest:^BOOL(id<PasswordManagerAccount> _Nonnull entry, NSUInteger idx, BOOL * _Nonnull stop) {
        return [entry.displayString isEqualToString:name];
    }];
}

- (NSUInteger)indexOfAccountName:(NSString *)name {
    return [_entries indexOfObjectPassingTest:^BOOL(id<PasswordManagerAccount> _Nonnull entry, NSUInteger idx, BOOL * _Nonnull stop) {
        return [entry.accountName isEqualToString:name];
    }];
}

- (NSUInteger)indexOfAccountName:(NSString *)name userName:(NSString *)userName {
    return [_entries indexOfObjectPassingTest:^BOOL(id<PasswordManagerAccount> _Nonnull entry, NSUInteger idx, BOOL * _Nonnull stop) {
        return [entry.accountName isEqualToString:name] && [entry.userName isEqualToString:userName];
    }];
}

- (NSString *)nameForNewAccount {
    static NSString *const kNewAccountName = @"New Account";
    int number = 0;
    NSString *name = kNewAccountName;
    while ([self indexOfAccountName:name] != NSNotFound) {
        ++number;
        name = [NSString stringWithFormat:@"%@ %d", kNewAccountName, number];
        if (number == 10) {
            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
            dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"MM-dd-yyyy HH:mm:ss"
                                                                       options:0
                                                                        locale:[NSLocale currentLocale]];
            NSString *formattedDate = [dateFormatter stringFromDate:[NSDate date]];
            return [NSString stringWithFormat:@"New Account %@", formattedDate];
        }
    }
    return name;
}

- (NSString *)accountNameForRow:(NSInteger)rowIndex {
    if (rowIndex < 0 || rowIndex >= _entries.count) {
        return nil;
    }
    return _entries[rowIndex].accountName;
}

- (NSString *)userNameForRow:(NSInteger)rowIndex {
    if (rowIndex < 0 || rowIndex >= _entries.count) {
        return nil;
    }
    return _entries[rowIndex].userName;
}

- (void)reloadAccountsNotification:(NSNotification *)notification {
    [self reloadAccounts:^{}];
}

- (void)reloadAccounts:(void (^)(void))completion {
    switch (_reloadPolicy) {
        case iTermPasswordManagerReloadUnlimited:
            break;
        case iTermPasswordManagerReloadAssumeCurrent:
            completion();
            return;
        case iTermPasswordManagerReloadOnce:
            _reloadPolicy = iTermPasswordManagerReloadAssumeCurrent;
            break;
    }

    NSString *filter = [_searchField stringValue];
    if (self.dataSourceProvider.authenticated) {
        if ([self.currentDataSource.name isEqualToString:@"Keeper Security"]) {
            [(id)self.currentDataSource setCredentialsDelegate:self];
            __weak __typeof(self) weakSelf = self;
            [KeeperDataSource setShowKeeperSettingsSheetHandler:^(NSWindow *window, void (^completion)(NSString * _Nullable)) {
                __strong __typeof(weakSelf) strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf showKeeperSettingsSheetWithEmptyAPIKey:YES forWindow:window onOK:nil keyCompletion:completion];
                } else {
                    if (completion) completion(nil);
                }
            }];
        }
        __weak __typeof(self) weakSelf = self;
        const NSInteger cancelCount = [self incrBusy];
        [self.class fetchAccountsWithWindow:self.window
                                 completion:^(NSArray<id<PasswordManagerAccount>> *accounts) {
            [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
                [weakSelf decrBusy];
                [weakSelf setAccounts:accounts
                             filtered:[weakSelf accounts:accounts filteredBy:filter]];
                completion();
            }];
        }];
    } else {
        [self setAccounts:@[] filtered:@[]];
    }
}

- (void)consolidateReloads:(void (^ NS_NOESCAPE)(void))block {
    const iTermPasswordManagerReload saved = _reloadPolicy;
    _reloadPolicy = iTermPasswordManagerReloadOnce;
    [self.dataSourceProvider consolidateAvailabilityChecks:^{
        block();
    }];
    _reloadPolicy = saved;
}

- (void)setAccounts:(NSArray<id<PasswordManagerAccount>> *)accounts
           filtered:(NSArray<id<PasswordManagerAccount>> *)filteredAccounts {
    _unfilteredEntries = accounts;
    _entries = filteredAccounts;
    [_tableView reloadData];
    [self update];
}

- (void)passwordsDidChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:kPasswordManagersShouldReloadData object:nil];
}

- (NSInteger)incrBusy {
    _busyCount += 1;
    if (_busyCount == 1) {
        _scrim.alphaValue = 1;
        [_progressIndicator startAnimation:nil];
    }
    return _cancelCount;
}

- (void)decrBusy {
    _busyCount -= 1;
    assert(_busyCount >= 0);
    if (_busyCount == 0) {
        _scrim.animator.alphaValue = 0;
        [_progressIndicator stopAnimation:nil];
    }
}

- (void)ifCancelCountUnchanged:(NSInteger)count perform:(void (^)(void))block {
    if (_cancelCount != count) {
        return;
    }
    block();
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return [_entries count];
}

- (id)tableView:(NSTableView *)aTableView
objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(NSInteger)rowIndex {
    if (rowIndex >= [self numberOfRowsInTableView:aTableView]) {
        // Sanity check.
        return nil;
    }

    if (aTableColumn == _accountNameColumn) {
        return [self accountNameForRow:rowIndex];
    } else if (aTableColumn == _userNameColumn) {
        return [self userNameForRow:rowIndex];
    } else {
        return @"••••••••";
    }
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex {
    if (!self.dataSourceProvider.authenticated) {
        return;
    }
    if (rowIndex < 0 || rowIndex >= _entries.count) {
        ITCriticalError(NO, @"Row index %@ out of bounds [0, %@)", @(rowIndex), @(_entries.count));
    }
    if (aTableColumn == _accountNameColumn || aTableColumn == _userNameColumn) {
        RecipeExecutionContext *context = self.recipeExecutionContext;
        id<PasswordManagerAccount> entry = _entries[rowIndex];
        NSString *userName = entry.userName;
        NSString *accountName = entry.accountName;
        if (aTableColumn == _accountNameColumn) {
            accountName = anObject;
        } else if (aTableColumn == _userNameColumn) {
            userName = anObject;
        }

        __weak __typeof(self) weakSelf = self;
        const NSInteger cancelCount = [self incrBusy]; // 1
        [entry fetchPasswordWithContext:context
                             completion:^(NSString *maybePassword,
                                          NSString *maybeOTP,
                                          NSError *error) {
            [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
                if (error) {
                    [weakSelf decrBusy]; // (1)
                    return;
                }
                NSString *password = maybePassword ?: @"";
                const NSInteger cancelCount = [weakSelf incrBusy]; // 2
                [weakSelf decrBusy];  // (1)
                [entry deleteWithContext:context
                              completion:^(NSError * _Nullable error) {
                    [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
                        const NSInteger cancelCount = [weakSelf incrBusy]; // 3
                        [weakSelf decrBusy];  // (2)
                        [[weakSelf currentDataSource] addUserName:userName
                                                      accountName:accountName
                                                         password:password
                                                          context:context
                                                       completion:^(id<PasswordManagerAccount> _Nullable replacement, NSError * _Nullable error) {
                            [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
                                DLog(@"%@", error);
                                const NSInteger cancelCount = [weakSelf incrBusy]; // 4
                                [weakSelf decrBusy];  // (3)
                                [weakSelf reloadAccounts:^{
                                    [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
                                        if (replacement) {
                                            [weakSelf didUpdateAccount:replacement userName:userName];
                                        }
                                        [weakSelf decrBusy]; // (4)
                                    }];
                                }];
                            }];
                        }];
                    }];
                }];
            }];
        }];
    }
    [self passwordsDidChange];
}

- (void)didUpdateAccount:(id<PasswordManagerAccount>)replacement userName:(NSString *)userName {
    __weak __typeof(self) weakSelf = self;
    [self reloadAccounts:^{
        [weakSelf selectAccount:replacement userName:userName];
    }];
}

- (void)selectAccount:(id<PasswordManagerAccount>)replacement userName:(NSString *)userName {
    const NSUInteger index = [self indexOfAccountName:replacement.accountName userName:userName];
    if (index != NSNotFound) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    }
}

#pragma mark - NSTableViewDelegate

- (BOOL)tableView:(NSTableView *)aTableView
shouldEditTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex {
    if (aTableColumn == _accountNameColumn || aTableColumn == _userNameColumn) {
        return YES;
    } else {
        return NO;
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [_removeButton setEnabled:([_tableView selectedRow] != -1)];
    [self update];
}

- (NSCell *)tableView:(NSTableView *)tableView
dataCellForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    if (tableColumn == _accountNameColumn) {
        NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@"name"];
        [cell setEditable:YES];
        return cell;
    } else if (tableColumn == _userNameColumn) {
        NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@"userName"];
        [cell setEditable:YES];
        return cell;
    } else if (tableColumn == _passwordColumn) {
        if ([_tableView editedRow] == row) {
            NSSecureTextFieldCell *cell = [[NSSecureTextFieldCell alloc] initTextCell:@"editPassword"];
            [cell setEditable:YES];
            [cell setEchosBullets:YES];
            return cell;
        } else {
            NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@"password"];
            [cell setEditable:YES];
            return cell;
        }
    } else {
        return nil;
    }
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification {
    if ([self.currentDataSource.name isEqualToString:@"Keeper Security"]) {
        [KeeperDataSource setShowKeeperSettingsSheetHandler:nil];
    }
    _twoFactorCode.stringValue = @"";
    [_tableView reloadData];
    [self sendWillClose];
    [self sendDidClose];
}

- (void)sendDidClose {
    if ([self.delegate respondsToSelector:@selector(iTermPasswordManagerDidClose)]) {
        [self.delegate iTermPasswordManagerDidClose];
    }
}

- (void)sendWillClose {
    if ([self.delegate respondsToSelector:@selector(iTermPasswordManagerWillClose)]) {
        [self.delegate iTermPasswordManagerWillClose];
    }
}

#pragma mark - Search field delegate

- (void)controlTextDidChange:(NSNotification *)aNotification {
    NSTextView *fieldEditor = [aNotification userInfo][@"NSFieldEditor"];
    if (aNotification.object == _newAccount || (id)[fieldEditor delegate] == _newAccount) {
        _newAccountOkButton.enabled = _newAccount.stringValue.length > 0;
        return;
    }
    if ((id)[fieldEditor delegate] == _searchField) {
        [self updateFilter];
    }
    if ([self numberOfRowsInTableView:_tableView] == 1) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
}

- (void)updateFilter {
    [self setAccounts:_unfilteredEntries filtered:[self accounts:_unfilteredEntries filteredBy:[_searchField stringValue]]];
}

@end

@implementation iTermBrowserPasswordManagerWindowController
static NSArray<NSString *> *gBrowserCachedCombinedAccountNames;
+ (NSArray<NSString *> *)cachedCombinedAccountNames {
    return gBrowserCachedCombinedAccountNames;
}

+ (void)setCachedCombinedAccountNames:(NSArray<NSString *> *)names {
    gBrowserCachedCombinedAccountNames = names;
}

+ (id<PasswordManagerDataSource>)dataSource {
    return [self.dataSourceProvider dataSource];
}
+ (iTermPasswordManagerDataSourceProvider *)dataSourceProvider {
    return [iTermPasswordManagerDataSourceProvider forBrowser];
}
- (id<PasswordManagerDataSource>)dataSource {
    return [self.dataSourceProvider dataSource];
}
- (iTermPasswordManagerDataSourceProvider *)dataSourceProvider {
    return [iTermPasswordManagerDataSourceProvider forBrowser];
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [_searchFieldMenu removeItem:_probeMenuItem];
    [_searchFieldMenu removeItem:_sendReturnMenuItem];
    [_searchFieldMenu removeItem:_separatorMenuItem];
}

- (void)reallySelectAccountName:(NSString *)name {
    if (!self.dataSourceProvider.authenticated) {
        DLog(@"set _accountNameToSelectAfterAuthentication to %@", name);
        _accountNameToSelectAfterAuthentication = [name copy];
        return;
    }
    _searchField.stringValue = name;
    [self updateFilter];
    if (_tableView.numberOfRows == 1) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                byExtendingSelection:NO];
        [_tableView scrollRowToVisible:0];
    }
}

@end


@interface iTermPasswordManagerScrim: NSView
@end

@implementation iTermPasswordManagerScrim

- (NSView *)hitTest:(NSPoint)point {
    if (self.alphaValue == 0) {
        return nil;
    }
    return [super hitTest:point];
}

@end
