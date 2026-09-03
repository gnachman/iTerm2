//
//  iTermPasswordManagerWindowController.m
//  iTerm
//
//  Created by George Nachman on 5/14/14.
//
//

#import "iTermPasswordManagerWindowController.h"
#import "iTermModalSheetRunner.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "iTermSearchField.h"
#import "iTermSystemVersion.h"
#import "iTermUserDefaults.h"
#import "NSAlert+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSImage+iTerm.h"
#import "SFSymbolEnum/SFSymbolEnum.h"
#import "NSStringITerm.h"
#import "NSTextField+iTerm.h"
#import "NSWindow+iTerm.h"

static NSString *const kPasswordManagersShouldReloadData = @"kPasswordManagersShouldReloadData";
// Looks nice and is unlikely to be used already
static NSString *const iTermPasswordManagerAccountNameUserNameSeparator = @"\u2002—\u2002";
NSString *const iTermPasswordManagerDidLoadAccounts = @"iTermPasswordManagerDidLoadAccounts";
static const CGFloat kNewAccountPanelWidth = 330;
static const CGFloat kNewAccountPanelHeightWithoutToggle = 136;
static const CGFloat kNewAccountPanelHeightWithToggle = 196;

static void iTermFixViewY(NSView *view, CGFloat y) {
    if (view == nil) {
        return;
    }
    view.autoresizingMask = NSViewNotSizable;
    NSRect frame = view.frame;
    frame.origin.y = y;
    view.frame = frame;
}

static void iTermSetNewAccountPanelContentHeight(NSPanel *panel, CGFloat height) {
    NSRect frame = panel.frame;
    NSRect contentRect = [panel contentRectForFrameRect:frame];
    contentRect.size.width = kNewAccountPanelWidth;
    contentRect.size.height = height;
    frame = [panel frameRectForContentRect:contentRect];
    // AppKit resizes the content view to fill the content area, so there is no
    // need to set contentView.frame ourselves.
    [panel setFrame:frame display:NO];
}

// A right-aligned, non-editable field label, matching the xib's Account/User name/Password
// labels (system appearance font, label color).
static NSTextField *iTermPWMakeRightLabel(NSString *title, NSRect frame) {
    NSTextField *label = [NSTextField labelWithString:title];
    label.frame = frame;
    label.alignment = NSTextAlignmentRight;
    label.lineBreakMode = NSLineBreakByClipping;
    label.focusRingType = NSFocusRingTypeNone;
    label.autoresizingMask = NSViewNotSizable;
    return label;
}

// Configures an editable, bezeled text field (or secure field) to match the xib entry fields.
static NSTextField *iTermPWConfigureField(NSTextField *field, NSRect frame) {
    field.frame = frame;
    field.bezeled = YES;
    field.editable = YES;
    field.selectable = YES;
    field.drawsBackground = YES;
    field.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    field.focusRingType = NSFocusRingTypeNone;
    field.autoresizingMask = NSViewNotSizable;
    NSTextFieldCell *cell = field.cell;
    cell.scrollable = YES;
    cell.wraps = NO;
    cell.lineBreakMode = NSLineBreakByClipping;
    cell.sendsActionOnEndEditing = YES;
    return field;
}

static NSButton *iTermPWMakePushButton(NSString *title, NSRect frame, NSString *keyEquivalent, id target, SEL action) {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.bezelStyle = NSBezelStyleRounded;
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    button.keyEquivalent = keyEquivalent;
    button.target = target;
    button.action = action;
    button.autoresizingMask = NSViewNotSizable;
    return button;
}

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
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSControlTextEditingDelegate,
    NSTextFieldDelegate,
    NSWindowDelegate,
    NSMenuItemValidation,
    NSMenuDelegate>
@property (nonatomic, class, strong) NSArray<NSString *> *cachedCombinedAccountNames;
@end

@implementation iTermPasswordManagerWindowController {
    IBOutlet NSTableColumn *_accountNameColumn;
    IBOutlet NSTableColumn *_userNameColumn;
    IBOutlet NSTableColumn *_passwordColumn;
    IBOutlet NSButton *_removeButton;
    IBOutlet NSButton *_editButton;
    IBOutlet NSButton *_addButton;

    // I have to do this becuase you can't change the default button (the one whose key equivalent is Enter)
    IBOutlet NSButton *_defaultButton;  // generally "enter password"
    IBOutlet NSButton *_secondaryButton;  // general "enter user name"

    IBOutlet NSButton *_closeButton;
    IBOutlet NSButton *_broadcastButton;
    IBOutlet NSTextField *_twoFactorCode;
    // The New Account / Edit panel and its controls are built programmatically (see
    // -ensureNewAccountPanel), not loaded from the xib, because the panel is dynamic: plugins
    // can contribute an Add Account toggle row that changes its height and field layout.
    NSPanel *_newAccountPanel;
    NSTextField *_newPassword;
    NSTextField *_newUserName;
    NSTextField *_newAccount;
    NSButton *_newAccountOkButton;
    NSSecureTextField *_newAccountPassword;
    NSTextField *_newAccountLabel;
    NSTextField *_newUserNameLabel;
    NSTextField *_newPasswordLabel;
    NSButton *_generatePasswordButton;
    NSButton *_addAccountToggleCheckbox;
    NSTextField *_addAccountToggleLabel;
    // Shown in place of the password field while the Edit panel fetches the current password.
    NSProgressIndicator *_passwordSpinner;
    // True while the Edit panel is fetching the current password. OK is disabled during this
    // window so the user cannot commit before the password (and its baseline) are known.
    BOOL _passwordPrefetchInFlight;
    IBOutlet NSView *_scrim;
    IBOutlet NSProgressIndicator *_progressIndicator;

    NSArray<id<PasswordManagerAccount>> *_entries;
    NSArray<id<PasswordManagerAccount>> *_unfilteredEntries;
    // Non-nil while the New Account panel is reused to edit an existing account.
    id<PasswordManagerAccount> _editingAccount;
    // The current password prefilled into the edit panel, so a commit only changes the
    // password when the user actually edited it. nil until the async prefetch lands.
    NSString *_editingPasswordAtOpen;
    id _eventMonitor;
    id<PasswordManagerDataSource> _dataSource;
    NSInteger _busyCount;
    NSInteger _cancelCount;
    BOOL _awakeFromNibAvailabilityCheckFailed;
    iTermPasswordManagerReload _reloadPolicy;

    @protected
    NSString *_accountNameToSelectAfterAuthentication;
    IBOutlet NSTableView *_tableView;
    IBOutlet iTermSearchField *_searchField;
    IBOutlet NSMenu *_searchFieldMenu;
    IBOutlet NSMenuItem *_probeMenuItem;
    IBOutlet NSMenuItem *_sendReturnMenuItem;
    IBOutlet NSMenuItem *_separatorMenuItem;

    IBOutlet NSPopUpButton *_settingsButton;
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
    [[self dataSource] fetchAccountsWithContext:[[RecipeExecutionContext alloc] initWithWindow:window]
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
    // Warm the data source's availability inputs off the main thread first (e.g. 1Password's
    // op version lookup) so the synchronous checkAvailability below does not spawn a subprocess
    // on the run loop. Sources with nothing to warm run the completion synchronously. This also
    // primes the cache before the later post-auth check in authenticationDidComplete. Capture
    // the exact source warmed and check that same instance in the completion (which may run a
    // later run-loop turn for an async warm-up): re-reading currentDataSource could run the
    // check on a different, unwarmed source if the picker changed in between.
    __weak __typeof(self) weakSelf = self;
    id<PasswordManagerDataSource> preparedDataSource = self.currentDataSource;
    [preparedDataSource prepareAvailability:^{
        [weakSelf performInitialAvailabilityCheckForDataSource:preparedDataSource];
    }];
    self.window.backgroundColor = [NSColor clearColor];
    self.window.contentView.layer.cornerRadius = 4;
    [_searchField setArrowHandler:_tableView];
#if ITERM_DEBUG
    {
        NSMenu *menu = _settingsButton.menu;
        NSInteger index = [menu indexOfItemWithTarget:self andAction:@selector(useBitwarden:)];
        if (index != -1) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:ITLocalize(@"PasswordManagerWindowController_Menu_TestAdapterDev", @"Test Adapter (Dev)", @"menu item title")
                                                          action:@selector(useTestAdapter:)
                                                   keyEquivalent:@""];
            item.tag = 1;
            item.target = self;
            [menu insertItem:item atIndex:index + 1];
        }
    }
#endif
    // Only create event monitor once. This is out of paranioa because there are weird cases where
    // awakeFromNib is called more than once.
    if (!_eventMonitor) {
        _eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
            return [weakSelf caughtKeyDownEvent:event];
        }];
    }
}

// The initial availability check, run after prepareAvailability has warmed dataSource's caches
// so checkAvailability does not block the main thread. dataSource is the instance that was
// warmed; the check runs against it rather than a possibly-changed currentDataSource.
- (void)performInitialAvailabilityCheckForDataSource:(id<PasswordManagerDataSource>)dataSource {
    if ([[self.class dataSourceProvider] authenticated] &&
        ![dataSource checkAvailability]) {
        _awakeFromNibAvailabilityCheckFailed = YES;
        [self dataSourceDidBecomeUnavailable];
    } else {
        _awakeFromNibAvailabilityCheckFailed = NO;
        [self reloadAccounts:^{}];
        [self update];
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
        _defaultButton.title = ITLocalize(@"PasswordManagerWindowController_EnterUserName", @"Enter User Name", @"Button title in updateKeyEquivalents");
    } else {
        _secondaryButton.hidden = NO;
        if (_didSendUserName) {
            _defaultButton.title = ITLocalize(@"PasswordManagerWindowController_EnterUsernamePassword", @"Enter Username & Password", @"Button title in updateKeyEquivalents");
        } else {
            _defaultButton.title = ITLocalize(@"PasswordManagerWindowController_EnterPassword", @"Enter Password", @"Button title in updateKeyEquivalents");
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
    // Always editable when a row is selected: name and user name can always be edited,
    // even for data sources that cannot change the password.
    [_editButton setEnabled:([_tableView selectedRow] != -1)];
    _addButton.enabled = available;
    _twoFactorCode.enabled = !self.selectedAccount.sendOTP;
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
        RLog(@"set _accountNameToSelectAfterAuthentication to %@", name);
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
    const iTermWarningSelection selection = [iTermWarning showWarningWithTitle:ITLocalize(@"PasswordManagerWindowController_ThisWillEraseITerm2SConfiguration", @"This will erase iTerm2’s configuration settings for this password manager. The actual passwords will remain unaffected. You’ll have to go through some setup steps to use it again. This action cannot be undone.", @"Alert title in resetIntegrationConfiguration:")
                                                                       actions:@[ ITLocalize(@"COMMON_OK", @"OK", @"Action title in resetIntegrationConfiguration:"), ITLocalize(@"COMMON_CANCEL", @"Cancel", @"Title in resetIntegrationConfiguration:") ]
                                                                     accessory:nil
                                                                    identifier:nil
                                                                   silenceable:kiTermWarningTypePersistent
                                                                       heading:ITLocalize(@"PasswordManagerWindowController_AreYouSure", @"Are you sure?",@"Alert heading in resetIntegrationConfiguration:(id)sender")
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
    [self updateConfiguration];
}

#if ITERM_DEBUG
- (IBAction)useTestAdapter:(id)sender {
    [self.dataSourceProvider enableTestAdapter];
    [self.currentDataSource resetErrors];
    if (![self.currentDataSource checkAvailability]) {
        [self useKeychain:nil];
    }
    [self update];
    [self updateConfiguration];
}
#endif

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

// Builds the New Account / Edit panel and its controls programmatically, once. The panel is
// not in the xib because it is dynamic: an Add Account toggle row (contributed by a plugin data
// source) changes its height and field layout. Field frames set here are the xib's; their Y
// positions are recomputed on each open by configureNewAccountPanelFieldLayoutShowingToggle:.
- (void)ensureNewAccountPanel {
    if (_newAccountPanel) {
        return;
    }
    NSRect contentRect = NSMakeRect(0, 0, kNewAccountPanelWidth, kNewAccountPanelHeightWithToggle);
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:contentRect
                                                styleMask:NSWindowStyleMaskTitled
                                                  backing:NSBackingStoreBuffered
                                                    defer:YES];
    panel.releasedWhenClosed = NO;
    panel.title = @"New Account";
    NSView *content = panel.contentView;

    _newAccountLabel = iTermPWMakeRightLabel(@"Account:", NSMakeRect(34, 165, 58, 16));
    [content addSubview:_newAccountLabel];

    _newAccount = iTermPWConfigureField([[NSTextField alloc] init], NSMakeRect(98, 162, 216, 21));
    _newAccount.placeholderString = ITLocalize(@"PasswordManagerWindowController_Placeholder_Required", @"Required", @"Placeholder text for the new account name field");
    _newAccount.delegate = self;
    [content addSubview:_newAccount];

    _newUserNameLabel = iTermPWMakeRightLabel(@"User name:", NSMakeRect(18, 138, 74, 16));
    [content addSubview:_newUserNameLabel];

    _newUserName = iTermPWConfigureField([[NSTextField alloc] init], NSMakeRect(98, 135, 216, 21));
    [content addSubview:_newUserName];

    _newPasswordLabel = iTermPWMakeRightLabel(@"Password:", NSMakeRect(18, 111, 74, 16));
    [content addSubview:_newPasswordLabel];

    _newAccountPassword = (NSSecureTextField *)iTermPWConfigureField([[NSSecureTextField alloc] init], NSMakeRect(98, 108, 183, 21));
    // Two names for one control, matching the old xib, which wired both outlets to it.
    _newPassword = _newAccountPassword;
    [content addSubview:_newAccountPassword];

    // Sits where the password field is (positioned in the layout pass); shown while the Edit
    // panel fetches the current password so the field can't be focused until it is filled.
    _passwordSpinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _passwordSpinner.style = NSProgressIndicatorStyleSpinning;
    _passwordSpinner.controlSize = NSControlSizeSmall;
    _passwordSpinner.displayedWhenStopped = NO;
    _passwordSpinner.hidden = YES;
    _passwordSpinner.autoresizingMask = NSViewNotSizable;
    [content addSubview:_passwordSpinner];

    _generatePasswordButton = [[NSButton alloc] initWithFrame:NSMakeRect(289, 105, 21.5, 28)];
    _generatePasswordButton.bezelStyle = NSBezelStyleRounded;
    [_generatePasswordButton setButtonType:NSButtonTypeMomentaryPushIn];
    _generatePasswordButton.image = [NSImage it_imageForSymbolName:SFSymbolGetString(SFSymbolDice)
                                             accessibilityDescription:ITLocalize(@"PasswordManagerWindowController_Accessibility_GeneratePassword", @"Generate password", @"Accessibility description for the generate password button")];
    _generatePasswordButton.imagePosition = NSImageOnly;
    _generatePasswordButton.imageScaling = NSImageScaleProportionallyDown;
    _generatePasswordButton.toolTip = ITLocalize(@"PasswordManagerWindowController_ToolTip_GenerateRandomPassword", @"Generate a random password. Hold Option to use only alphanumerics.", @"Tooltip for the generate password button");
    _generatePasswordButton.target = self;
    _generatePasswordButton.action = @selector(generatePassword:);
    _generatePasswordButton.autoresizingMask = NSViewNotSizable;
    [content addSubview:_generatePasswordButton];

    _addAccountToggleCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(96, 78, 220, 18)];
    [_addAccountToggleCheckbox setButtonType:NSButtonTypeSwitch];
    _addAccountToggleCheckbox.title = @"Toggle";
    _addAccountToggleCheckbox.autoresizingMask = NSViewNotSizable;
    [content addSubview:_addAccountToggleCheckbox];

    _addAccountToggleLabel = [NSTextField wrappingLabelWithString:@""];
    _addAccountToggleLabel.frame = NSMakeRect(115, 51, 200, 26);
    _addAccountToggleLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    _addAccountToggleLabel.textColor = [NSColor secondaryLabelColor];
    _addAccountToggleLabel.selectable = YES;
    _addAccountToggleLabel.focusRingType = NSFocusRingTypeNone;
    _addAccountToggleLabel.autoresizingMask = NSViewNotSizable;
    [content addSubview:_addAccountToggleLabel];

    _newAccountOkButton = iTermPWMakePushButton(@"OK", NSMakeRect(257, 13, 53, 32), @"\r", self, @selector(reallyAdd:));
    [content addSubview:_newAccountOkButton];

    NSButton *cancelButton = iTermPWMakePushButton(@"Cancel", NSMakeRect(169, 13, 76, 32), @"\033", self, @selector(cancelNewAccount:));
    [content addSubview:cancelButton];

    panel.initialFirstResponder = _newAccount;
    panel.autorecalculatesKeyViewLoop = YES;
    _newAccountPanel = panel;
}

- (IBAction)add:(id)sender {
    if (!self.dataSourceProvider.authenticated) {
        return;
    }
    [self ensureNewAccountPanel];
    _editingAccount = nil;
    _editingPasswordAtOpen = nil;
    _newAccountPanel.title = ITLocalize(@"PASSWORD_MANAGER_NEW_ACCOUNT", @"New Account", @"Sheet title when creating a password manager account");
    _newAccount.stringValue = self.defaultAccountName ?: @"";
    // Add never prefetches a password; make sure the field is visible and the spinner is off in
    // case the panel was last used for an Edit.
    _passwordPrefetchInFlight = NO;
    _newAccountPassword.hidden = NO;
    [_passwordSpinner stopAnimation:nil];
    _passwordSpinner.hidden = YES;
    [self updateNewAccountOkButtonEnabled];
    if (self.currentDataSource.autogeneratedPasswordsOnly) {
        _newAccountPassword.enabled = NO;
        _newAccountPassword.stringValue = @"";
        _newAccountPassword.placeholderString = ITLocalize(@"PASSWORD_MANAGER_AUTOGENERATED", @"Autogenerated", @"Placeholder indicating the password will be generated automatically");
        // The source generates the password itself; disable Generate so a user-chosen random
        // value is not injected into the disabled field (mirrors the Edit path's guard).
        _generatePasswordButton.enabled = NO;
    } else {
        _newAccountPassword.enabled = YES;
        _newAccountPassword.stringValue = @"";
        _newAccountPassword.placeholderString = nil;
        // Re-enable (a prior Edit on a read-only-password source may have disabled it).
        _generatePasswordButton.enabled = YES;
    }
    [self configureFirstAddAccountToggle];
    NSWindow *newAccountPanel = _newAccountPanel;
    [self.window beginSheet:newAccountPanel completionHandler:^(NSModalResponse response){
        // Fires a run-loop turn later, after iTermRunModalForWindowAbortingIfParentCloses
        // may have aborted our session (parent closed). Only stop if we're still the
        // current modal, so we don't stop an unrelated modal that is live by then.
        if (NSApp.modalWindow == newAccountPanel) {
            [NSApp stopModal];
        }
    }];
    // beginSheet can reset subview frames via autoresizing; apply layout again.
    [self configureFirstAddAccountToggle];
    iTermRunModalForWindowAbortingIfParentCloses(newAccountPanel, self.window);
}

- (NSDictionary *)firstAddAccountToggleDescription {
    id<PasswordManagerDataSource> ds = self.currentDataSource;
    NSArray<NSDictionary *> *toggles = ds.addAccountToggleDescriptions;
    if (toggles.count == 0) {
        return nil;
    }
    if (toggles.count > 1) {
        DLog(@"Data source declared %@ add-account toggles; only the first is rendered.", @(toggles.count));
    }
    return toggles.firstObject;
}

- (void)configureNewAccountPanelFieldLayoutShowingToggle:(BOOL)showingToggle {
    const CGFloat fieldHeight = 27;
    const CGFloat labelOffset = 3;
    const CGFloat topMargin = 34;
    const CGFloat toggleGap = 5;
    const CGFloat panelHeight = showingToggle ? kNewAccountPanelHeightWithToggle
                                              : kNewAccountPanelHeightWithoutToggle;

    CGFloat y = panelHeight - topMargin;
    iTermFixViewY(_newAccount, y);
    iTermFixViewY(_newAccountLabel, y + labelOffset);
    y -= fieldHeight;

    iTermFixViewY(_newUserName, y);
    iTermFixViewY(_newUserNameLabel, y + labelOffset);
    y -= fieldHeight;

    iTermFixViewY(_newAccountPassword, y);
    iTermFixViewY(_newPasswordLabel, y + labelOffset);
    iTermFixViewY(_generatePasswordButton, y - labelOffset);
    // Spinner sits at the left of where the password field is, vertically centered on it.
    const NSRect pwFrame = _newAccountPassword.frame;
    const CGFloat spinnerSize = 16;
    _passwordSpinner.frame = NSMakeRect(NSMinX(pwFrame) + 2,
                                        NSMidY(pwFrame) - spinnerSize / 2,
                                        spinnerSize,
                                        spinnerSize);

    if (!showingToggle) {
        return;
    }
    y -= fieldHeight + toggleGap;
    iTermFixViewY(_addAccountToggleCheckbox, y);
    y -= fieldHeight;
    iTermFixViewY(_addAccountToggleLabel, y);
}

- (void)configureFirstAddAccountToggle {
    // No add-account toggle when editing an existing account; the vault is fixed.
    NSDictionary *toggle = _editingAccount ? nil : [self firstAddAccountToggleDescription];
    const BOOL hidden = (toggle == nil);
    _addAccountToggleCheckbox.hidden = hidden;
    _addAccountToggleLabel.hidden = hidden;
    const CGFloat height = hidden ? kNewAccountPanelHeightWithoutToggle
                                  : kNewAccountPanelHeightWithToggle;
    iTermSetNewAccountPanelContentHeight(_newAccountPanel, height);
    [self configureNewAccountPanelFieldLayoutShowingToggle:!hidden];
    if (hidden) {
        return;
    }
    NSString *label = toggle[@"label"];
    NSString *note = toggle[@"note"];
    NSNumber *defaultValue = toggle[@"defaultValue"];
    _addAccountToggleCheckbox.title = label.length > 0 ? label : @"";
    _addAccountToggleLabel.stringValue = note.length > 0 ? note : @"";
    _addAccountToggleCheckbox.state = (defaultValue.boolValue
                                       ? NSControlStateValueOn
                                       : NSControlStateValueOff);
}

- (NSDictionary<NSString *, NSNumber *> *)collectAddAccountFlags {
    NSDictionary *toggle = [self firstAddAccountToggleDescription];
    if (toggle == nil) {
        return nil;
    }
    NSString *key = toggle[@"key"];
    if (key.length == 0) {
        return nil;
    }
    const BOOL on = (_addAccountToggleCheckbox.state == NSControlStateValueOn);
    return @{ key: @(on) };
}

- (IBAction)cancelNewAccount:(id)sender {
    _editingAccount = nil;
    _editingPasswordAtOpen = nil;
    _passwordPrefetchInFlight = NO;
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
    if (_passwordPrefetchInFlight) {
        // The Edit panel is still fetching the current password; committing now would act on an
        // unknown password state. OK is disabled during this window, but guard here too.
        DLog(@"Ignoring commit while password is still loading");
        [_newAccountPanel it_shakeNo];
        return;
    }
    if (_editingAccount != nil) {
        NSString *targetName = _newAccount.stringValue ?: @"";
        NSString *targetUser = _newUserName.stringValue ?: @"";
        // Only delete-then-re-add sources are keyed by (name, user) and can clobber another
        // account by renaming onto its key; these sources have no vault concept, so (name, user)
        // is unique and there are no legitimate twins. In-place sources keep distinct records
        // (and can hold cross-vault twins), so skip the check there. Compare against the edited
        // account's own (name, user) rather than a pointer: a pointer goes stale if a reload
        // rebuilds _entries during the modal, and name+user twins in other vaults would make a
        // pointer/first-index match reject a legitimate edit.
        if (![self currentDataSource].supportsInPlaceEdit) {
            const BOOL isRename = ![targetName isEqualToString:_editingAccount.accountName] ||
                                  ![targetUser isEqualToString:_editingAccount.userName];
            if (isRename && [self indexOfAccountName:targetName userName:targetUser] != NSNotFound) {
                DLog(@"Edit renames onto an existing account's (name, user)");
                [_newAccountPanel it_shakeNo];
                return;
            }
        }
        [self commitEditWithAccountName:targetName userName:targetUser];
        return;
    }
    if (self.currentDataSource.requiresPasswordForAdd && _newPassword.stringValue.length == 0) {
        DLog(@"New account password is required but empty");
        // Point the user at the empty password field (this source no longer auto-generates), so
        // the shake is not unexplained; the dice button is right there to generate one.
        _newAccountPassword.placeholderString = ITLocalize(@"PasswordManagerWindowController_Placeholder_EnterOrGenerateAPassword", @"Enter or generate a password", @"Placeholder text for the new account password field");
        [_newAccountPanel makeFirstResponder:_newAccountPassword];
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
    NSString *userName = _newUserName.stringValue ?: @"";
    NSString *accountName = _newAccount.stringValue ?: @"";
    NSString *password = _newPassword.stringValue ?: @"";
    void (^onComplete)(id<PasswordManagerAccount>, NSError *) = ^(id<PasswordManagerAccount> _Nullable newAccount,
                                                                  NSError * _Nullable error) {
        [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
            [weakSelf didAddAccount:newAccount withError:error];
            [weakSelf decrBusy];
        }];
    };
    id<PasswordManagerDataSource> currentDataSource = self.currentDataSource;
    NSDictionary *flags = [self collectAddAccountFlags] ?: @{};
    [currentDataSource addUserName:userName
                       accountName:accountName
                          password:password
                             flags:flags
                           context:self.recipeExecutionContext
                        completion:onComplete];
    _newPassword.stringValue = @"";
    _newUserName.stringValue = @"";
    _newAccount.stringValue = @"";
    [self.window endSheet:_newAccountPanel];
    [_newAccountPanel orderOut:nil];
}

// Surfaces a failed edit/rename/password-change. The Edit panel is a deliberate action and its
// completion reverts the row to the old values on failure; without this the revert reads as a
// successful edit.
- (void)presentEditError:(NSError *)error {
    if (!error) {
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = ITLocalize(@"PasswordManagerWindowController_Alert_CouldNotSaveChanges", @"Could Not Save Changes", @"Alert title in presentEditError:");
    alert.informativeText = error.localizedDescription.length > 0 ? error.localizedDescription
                                                                  : ITLocalize(@"PasswordManagerWindowController_AlertExplanatory_PasswordManagerReportedAnError", @"The password manager reported an error.", @"Alert explanatory text in presentEditError:");
    [alert addButtonWithTitle:ITLocalize(@"COMMON_OK", @"OK", @"Button title in presentEditError:")];
    [alert runSheetModalForWindow:self.window];
}

- (void)didAddAccount:(id<PasswordManagerAccount>)newAccount withError:(NSError *)error {
    if (newAccount) {
        __weak __typeof(self) weakSelf = self;
        // Select the new row inside the reload completion: the fetch is async (adapters go over
        // the network), so looking it up synchronously would search the stale pre-add _entries
        // and miss it.
        [self reloadAccounts:^{
            [weakSelf selectAccount:newAccount userName:newAccount.userName];
        }];
        // Notify OTHER windows only: this window already reloaded above (with selection), so
        // posting object:self lets its own reloadAccountsNotification: skip the redundant second
        // fetch (which would also drop the just-made selection).
        [self notifyOtherWindowsPasswordsDidChange];
    }
    if (error) {
        DLog(@"%@", error);
    }
}

// Like passwordsDidChange but tagged with self so this window's own observer skips the reload
// (used when the caller has already reloaded this window explicitly).
- (void)notifyOtherWindowsPasswordsDidChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:kPasswordManagersShouldReloadData object:self];
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
        const NSInteger cancelCount = [self incrBusy];
        [_tableView reloadData];
        __weak __typeof(self) weakSelf = self;
        [_entries[selectedRow] deleteWithContext:self.recipeExecutionContext
                                      completion:^(NSError * _Nullable error) {
            [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
                [weakSelf decrBusy];
                if (error) {
                    DLog(@"%@", error);
                    return;
                }
                [weakSelf didRemoveEntry];
            }];
        }];
    }
}

- (void)didRemoveEntry {
    [self passwordsDidChange];
}

- (BOOL)shouldRemoveSelection {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = ITLocalize(@"PasswordManagerWindowController_AreYouSureYouWantToDelete", @"Are you sure you want to delete this password?", @"Alert title in shouldRemoveSelection");
    [alert addButtonWithTitle:ITLocalize(@"COMMON_OK", @"OK", @"Button title in shouldRemoveSelection")];
    [alert addButtonWithTitle:ITLocalize(@"COMMON_CANCEL", @"Cancel", @"Button title in shouldRemoveSelection")];
    return [alert runSheetModalForWindow:self.window] == NSAlertFirstButtonReturn;
}

- (IBAction)edit:(id)sender {
    const NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= _entries.count) {
        return;
    }
    // The panel always opens, for every data source. The data source's capability only
    // changes how the commit happens (in-place update vs delete-then-re-add), not whether
    // the panel appears. The panel opens immediately; the current password is fetched
    // asynchronously and prefilled, so it never blocks on a slow or wedged backend.
    [self presentEditPanelForEntry:_entries[row]];
}

- (void)presentEditPanelForEntry:(id<PasswordManagerAccount>)entry {
    [self ensureNewAccountPanel];
    _editingAccount = entry;
    _editingPasswordAtOpen = nil;
    _newAccount.stringValue = entry.accountName ?: @"";
    _newUserName.stringValue = entry.userName ?: @"";
    _newAccountPassword.stringValue = @"";
    _newAccountPassword.hidden = NO;
    _passwordPrefetchInFlight = NO;
    [_passwordSpinner stopAnimation:nil];
    _passwordSpinner.hidden = YES;
    if (!self.currentDataSource.canEditPassword) {
        _newAccountPassword.enabled = NO;
        _newAccountPassword.placeholderString = ITLocalize(@"PasswordManagerWindowController_Placeholder_CannotChangePasswordHere", @"Cannot change password here", @"Placeholder text for a password that cannot be edited");
        // Generate writes into the same secure field; disable it too, otherwise the user
        // could inject a password into a data source that just declared it cannot set one.
        _generatePasswordButton.enabled = NO;
    } else {
        _newAccountPassword.placeholderString = nil;
        // Hide the field and show a spinner until the current password is fetched, so the user
        // cannot focus/type into a field that is about to be replaced by the fetched value.
        [self beginPasswordPrefetchUI];
        [self prefillPasswordForEntry:entry];
    }
    [self updateNewAccountOkButtonEnabled];
    _newAccountPanel.title = ITLocalize(@"PASSWORD_MANAGER_EDIT_ACCOUNT", @"Edit Account", @"Sheet title when editing a password manager account");
    [self configureFirstAddAccountToggle];
    NSWindow *panel = _newAccountPanel;
    [self.window beginSheet:panel completionHandler:^(NSModalResponse response) {
        if (NSApp.modalWindow == panel) {
            [NSApp stopModal];
        }
    }];
    [self configureFirstAddAccountToggle];
    iTermRunModalForWindowAbortingIfParentCloses(panel, self.window);
}

// Fetches the current password asynchronously so the panel opens instantly and never blocks on
// a slow backend. While the fetch is in flight the password field is hidden and non-focusable
// (see beginPasswordPrefetchUI) and a spinner shows in its place; the field is restored, filled,
// and made editable only once the value is in hand, so the user can never focus/type into a
// field that is about to be replaced.
- (void)prefillPasswordForEntry:(id<PasswordManagerAccount>)entry {
    __weak __typeof(self) weakSelf = self;
    [entry fetchPasswordWithContext:self.recipeExecutionContext
                         completion:^(NSString *maybePassword, NSString *maybeOTP, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || strongSelf->_editingAccount != entry) {
                return;
            }
            // Fetch finished (success or failure): reveal and enable the field either way so the
            // user is never left staring at a permanent spinner.
            [strongSelf endPasswordPrefetchUI];
            if (error) {
                // Leave the field empty and editable; commit treats an untouched empty field as
                // "leave the password unchanged".
                return;
            }
            NSString *password = maybePassword ?: @"";
            strongSelf->_newAccountPassword.stringValue = password;
            strongSelf->_editingPasswordAtOpen = password;
        });
    }];
}

// Hide the password field (so it cannot take keyboard focus) and show a spinner in its place
// while the current password is being fetched.
- (void)beginPasswordPrefetchUI {
    _passwordPrefetchInFlight = YES;
    _newAccountPassword.enabled = NO;
    _newAccountPassword.hidden = YES;
    _generatePasswordButton.enabled = NO;
    _passwordSpinner.hidden = NO;
    [_passwordSpinner startAnimation:nil];
    // Disable OK/Return until the password is loaded: committing now would act on an unknown
    // password state (no baseline yet).
    [self updateNewAccountOkButtonEnabled];
}

// Restore the password field and hide the spinner once the fetch completes.
- (void)endPasswordPrefetchUI {
    _passwordPrefetchInFlight = NO;
    [_passwordSpinner stopAnimation:nil];
    _passwordSpinner.hidden = YES;
    _newAccountPassword.hidden = NO;
    _newAccountPassword.enabled = YES;
    _generatePasswordButton.enabled = YES;
    [self updateNewAccountOkButtonEnabled];
}

// OK requires a non-empty account name and is disabled while the Edit panel is still fetching
// the current password.
- (void)updateNewAccountOkButtonEnabled {
    _newAccountOkButton.enabled = (_newAccount.stringValue.length > 0) && !_passwordPrefetchInFlight;
}

- (void)commitEditWithAccountName:(NSString *)accountName userName:(NSString *)userName {
    id<PasswordManagerAccount> entry = _editingAccount;
    NSString *typed = _newPassword.stringValue ?: @"";
    // Only change the password if the user edited the prefilled value.
    NSString *baseline = _editingPasswordAtOpen;
    NSString *newPassword;
    if (typed.length == 0) {
        // Empty means "leave the password unchanged", never "blank it". Backends are
        // inconsistent about an empty value (Keeper omits it, but 1Password/LastPass would
        // overwrite the stored secret with ""), so clearing must be a no-op. Deliberately
        // blanking a password would need its own explicit, confirmed action.
        newPassword = nil;
    } else if (baseline != nil) {
        // Prefetch landed: change only if the user actually edited the prefilled value.
        newPassword = [typed isEqualToString:baseline] ? nil : typed;
    } else {
        // Prefetch has not landed; a non-empty field is a deliberate new password.
        newPassword = typed;
    }
    _editingAccount = nil;
    _editingPasswordAtOpen = nil;
    _newPassword.stringValue = @"";
    _newUserName.stringValue = @"";
    _newAccount.stringValue = @"";
    [self.window endSheet:_newAccountPanel];
    [_newAccountPanel orderOut:nil];
    if (entry == nil) {
        return;
    }
    const BOOL nameOrUserChanged = ![accountName isEqualToString:entry.accountName] ||
                                   ![userName isEqualToString:entry.userName];
    if (nameOrUserChanged) {
        [self renameEntry:entry toAccountName:accountName userName:userName newPassword:newPassword];
        return;
    }
    if (newPassword == nil) {
        return;  // Nothing changed.
    }
    // Password-only change: use the in-place set-password path so data sources with a
    // lossless set (LastPass, Keychain, Keeper) do not fall back to delete-then-re-add.
    __weak __typeof(self) weakSelf = self;
    const NSInteger cancelCount = [self incrBusy];
    [entry setPasswordWithContext:self.recipeExecutionContext
                         password:newPassword
                       completion:^(NSError * _Nullable error) {
        [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
            [weakSelf decrBusy];
            DLog(@"edit set password: %@", error);
            [weakSelf passwordsDidChange];
            [weakSelf presentEditError:error];
        }];
    }];
}


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
        // In send-both mode. First send the username.
        [self enterUsername];

        // Now run the completion block, which can set focus on the password field.
        void (^didSendUserName)(void) = self.didSendUserName;
        self.didSendUserName = nil;
        didSendUserName();
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
    DLog(@"enterUserName");
    if (!self.dataSourceProvider.authenticated) {
        return;
    }
    NSString *userName = [self selectedUserName];
    if (userName.length > 0) {
        [_delegate iTermPasswordManagerEnterUserName:userName
                                            broadcast:_broadcastButton.state == NSControlStateValueOn];
        if (_sendUserByDefault && !self.didSendUserName) {
            DLog(@"enterPassword: closing sheet");
            [self closeOrEndSheet];
        }
    }
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

// MARK: - Generic Adapter Settings Sheet

- (IBAction)adapterSettings:(id)sender {
    id<PasswordManagerDataSource> ds = [self currentDataSource];
    if (![(id)ds conformsToProtocol:@protocol(iTermAdapterCapabilities)]) {
        return;
    }
    id<iTermAdapterCapabilities> adapter = (id<iTermAdapterCapabilities>)ds;
    if (!adapter.hasSettingsFields) {
        return;
    }
    [self showAdapterSettingsSheet:adapter forWindow:self.window completion:^{
        [self reloadItems:nil];
    }];
}

- (void)showAdapterSettingsSheet:(id<iTermAdapterCapabilities>)adapter
                       forWindow:(NSWindow *)parentWindow
                      completion:(void (^)(void))onOK {
    NSArray<NSDictionary *> *fields = adapter.settingsFieldDescriptions;
    if (!fields.count) {
        return;
    }
    NSWindow *sheetParent = parentWindow ?: self.window;
    if (!sheetParent) {
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:ITLocalize(@"PasswordManagerWindowController_Settings_FORMAT", @"%1$@ Settings", @"Alert title in showAdapterSettingsSheet:"), [self currentDataSource].name];
    [alert addButtonWithTitle:ITLocalize(@"COMMON_OK", @"OK", @"Button title in showAdapterSettingsSheet:")];
    [alert addButtonWithTitle:ITLocalize(@"COMMON_CANCEL", @"Cancel", @"Button title in showAdapterSettingsSheet:")];

    const CGFloat width = 560;
    const CGFloat rowHeight = 22;
    const CGFloat labelWidth = 90;
    const CGFloat rowSpacing = 12;
    const CGFloat noteHeight = 14;
    const CGFloat noteSpacing = 4;
    const CGFloat margin = 16;
    const CGFloat eyeButtonWidth = 28;

    // Calculate total height
    CGFloat totalHeight = margin;
    for (NSDictionary *field in fields) {
        totalHeight += rowHeight + rowSpacing;
        if (field[@"note"]) {
            totalHeight += noteHeight + noteSpacing;
        }
    }
    totalHeight += margin;

    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, totalHeight)];
    NSMutableDictionary<NSString *, NSTextField *> *textFieldMap = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSSecureTextField *> *secureFieldMap = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSTextField *> *plainFieldMap = [NSMutableDictionary dictionary];
    // Retained by the accessory view's lifetime via the completion block closure.
    NSMutableArray *revealHelpers = [NSMutableArray array];

    // Build rows from bottom to top
    CGFloat y = margin;
    for (NSDictionary *field in [fields reverseObjectEnumerator].allObjects) {
        NSString *key = field[@"key"];
        NSString *label = field[@"label"];
        BOOL isSecret = [field[@"isSecret"] boolValue];
        NSString *placeholder = field[@"placeholder"] ?: @"";
        NSString *note = field[@"note"];

        NSString *savedValue = [adapter settingsValueForKey:key] ?: @"";

        if (note) {
            NSTextField *noteLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(labelWidth + 8, y, width - labelWidth - 8, noteHeight)];
            noteLabel.stringValue = note;
            noteLabel.bezeled = NO;
            noteLabel.drawsBackground = NO;
            noteLabel.editable = NO;
            noteLabel.selectable = NO;
            noteLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
            noteLabel.textColor = [NSColor secondaryLabelColor];
            [accessory addSubview:noteLabel];
            y += noteHeight + noteSpacing;
        }

        NSTextField *fieldLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, y, labelWidth, rowHeight)];
        fieldLabel.stringValue = label;
        fieldLabel.bezeled = NO;
        fieldLabel.drawsBackground = NO;
        fieldLabel.editable = NO;
        fieldLabel.selectable = NO;
        fieldLabel.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        [accessory addSubview:fieldLabel];

        if (isSecret) {
            const CGFloat fieldWidth = width - labelWidth - 8 - eyeButtonWidth - 4;
            NSRect fieldFrame = NSMakeRect(labelWidth + 8, y, fieldWidth, rowHeight);

            NSSecureTextField *secure = [[NSSecureTextField alloc] initWithFrame:fieldFrame];
            secure.placeholderString = placeholder;
            secure.stringValue = savedValue;
            secure.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
            [accessory addSubview:secure];
            secureFieldMap[key] = secure;

            NSTextField *plain = [[NSTextField alloc] initWithFrame:fieldFrame];
            plain.placeholderString = placeholder;
            plain.stringValue = savedValue;
            plain.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
            plain.hidden = YES;
            [accessory addSubview:plain];
            plainFieldMap[key] = plain;

            iTermAdapterSettingsRevealHelper *helper = [[iTermAdapterSettingsRevealHelper alloc] initWithSecureField:secure plainField:plain];
            [revealHelpers addObject:helper];

            NSButton *reveal = [[NSButton alloc] initWithFrame:NSMakeRect(labelWidth + 8 + fieldWidth + 4, y, eyeButtonWidth, rowHeight)];
            reveal.bezelStyle = NSBezelStyleRegularSquare;
            reveal.bordered = YES;
            reveal.image = [NSImage imageWithSystemSymbolName:@"eye" accessibilityDescription:ITLocalize(@"PasswordManagerWindowController_Show", @"Show", @"Accessibility description for the Show password button")];
            reveal.imagePosition = NSImageOnly;
            reveal.buttonType = NSButtonTypeMomentaryPushIn;
            reveal.target = helper;
            reveal.action = @selector(toggleReveal:);
            [accessory addSubview:reveal];
        } else {
            NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(labelWidth + 8, y, width - labelWidth - 8, rowHeight)];
            tf.placeholderString = placeholder;
            tf.stringValue = savedValue;
            tf.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
            [accessory addSubview:tf];
            textFieldMap[key] = tf;
        }

        y += rowHeight + rowSpacing;
    }

    alert.accessoryView = accessory;
    [alert layout];

    [alert beginSheetModalForWindow:sheetParent completionHandler:^(NSModalResponse response) {
        // Prevent revealHelpers from being deallocated while the sheet is open.
        (void)revealHelpers;
        if (response != NSAlertFirstButtonReturn) {
            return;
        }
        for (NSDictionary *field in fields) {
            NSString *key = field[@"key"];
            BOOL isSecret = [field[@"isSecret"] boolValue];
            NSString *value;
            if (isSecret) {
                NSSecureTextField *secure = secureFieldMap[key];
                NSTextField *plain = plainFieldMap[key];
                value = plain.hidden ? (secure.stringValue ?: @"") : (plain.stringValue ?: @"");
            } else {
                value = textFieldMap[key].stringValue ?: @"";
            }
            [adapter setSettingsValue:value forKey:key];
        }
        if (onOK) {
            onOK();
        }
    }];
}

// MARK: - Generic Custom Commands

- (void)runAdapterCustomCommand:(NSString *)commandName {
    id<PasswordManagerDataSource> ds = [self currentDataSource];
    if (![(id)ds conformsToProtocol:@protocol(iTermAdapterCapabilities)]) {
        return;
    }
    id<iTermAdapterCapabilities> adapter = (id<iTermAdapterCapabilities>)ds;
    const NSInteger cancelCount = [self incrBusy];
    __weak __typeof(self) weakSelf = self;
    [adapter runCustomCommand:commandName window:self.window completion:^(NSString *message, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
                [weakSelf decrBusy];
                if (error) {
                    NSMutableString *info = [NSMutableString stringWithString:error.localizedDescription ?: ITLocalize(@"PasswordManagerWindowController_AnErrorOccurred", @"An error occurred.", @"Fallback text when an error has no description")];
                    if (message.length > 0) {
                        [info appendFormat:@"\n\n%@", message];
                    }
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = ITLocalize(@"PasswordManagerWindowController_CommandFailed", @"Command Failed", @"Alert title in runAdapterCustomCommand:");
                    alert.informativeText = info;
                    [alert addButtonWithTitle:ITLocalize(@"COMMON_OK", @"OK", @"Button title in runAdapterCustomCommand:")];
                    [alert runModal];
                } else {
                    [weakSelf reloadItems:nil];
                    if (message.length > 0) {
                        NSAlert *alert = [[NSAlert alloc] init];
                        alert.messageText = commandName;
                        alert.informativeText = message;
                        [alert addButtonWithTitle:ITLocalize(@"COMMON_OK", @"OK", @"Button title in runAdapterCustomCommand:")];
                        [alert runModal];
                    }
                }
            }];
        });
    }];
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
    alert.messageText = [NSString stringWithFormat:ITLocalize(@"PasswordManagerWindowController_PasswordFor_FORMAT", @"Password for %1$@", @"Alert title in revealPassword:"), accountName];
    alert.informativeText = password;
    [alert addButtonWithTitle:ITLocalize(@"COMMON_OK", @"OK", @"Button title in revealPassword:")];
    [alert addButtonWithTitle:ITLocalize(@"COMMON_COPY", @"Copy", @"Button title in revealPassword:")];

    __weak __typeof(self) weakSelf = self;
    [self runModal:alert completion:^(NSModalResponse response) {
        if (response == NSAlertSecondButtonReturn) {
            [weakSelf copyPasswordToClipboard:password];
        }
    }];
}

- (void)copyPasswordToClipboard:(NSString *)password {
    if (!password) {
        return;
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:self];
    [pasteboard setString:password forType:NSPasteboardTypeString];
}

// Handle ⌘C. The old `copy:` method expected an NSString argument, but
// AppKit sends the NSMenuItem as `sender`, causing a crash in
// -[NSPasteboard setString:forType:].
- (void)copy:(id)sender {
    [self copyPassword:sender];
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
    [self copyPasswordToClipboard:password];
}

- (BOOL)shouldProbe {
    return ([iTermUserDefaults probeForPassword] && [iTermAdvancedSettingsModel echoProbeDuration] > 0);
}

static NSInteger const kDynamicMenuItemTag = 9999;

- (void)menuNeedsUpdate:(NSMenu *)menu {
    // Only modify the gear/settings popup menu, not other menus we may be a delegate of.
    if (menu != _settingsButton.menu) {
        return;
    }

    // Remove previously added dynamic items.
    for (NSMenuItem *item in [menu.itemArray filteredArrayUsingBlock:^BOOL(NSMenuItem *item) {
        return item.tag == kDynamicMenuItemTag;
    }]) {
        [menu removeItem:item];
    }

    id<PasswordManagerDataSource> ds = [self currentDataSource];
    if (![(id)ds conformsToProtocol:@protocol(iTermAdapterCapabilities)]) {
        return;
    }
    id<iTermAdapterCapabilities> adapter = (id<iTermAdapterCapabilities>)ds;

    // Insert after "Switch Account".
    NSInteger insertionIndex = [menu indexOfItemWithTarget:nil andAction:@selector(switchAccount:)];
    if (insertionIndex == -1) {
        insertionIndex = menu.numberOfItems;
    } else {
        insertionIndex += 1;
    }

    BOOL addedAny = NO;

    if (adapter.hasSettingsFields) {
        NSMenuItem *settingsItem = [[NSMenuItem alloc] initWithTitle:ITLocalize(@"PasswordManagerWindowController_Menu_Settings", @"Settings…", @"menu item title")
                                                              action:@selector(adapterSettings:)
                                                       keyEquivalent:@""];
        settingsItem.target = self;
        settingsItem.tag = kDynamicMenuItemTag;
        [menu insertItem:settingsItem atIndex:insertionIndex];
        insertionIndex += 1;
        addedAny = YES;
    }

    for (NSDictionary<NSString *, NSString *> *cmd in adapter.customCommandDescriptions) {
        NSString *label = cmd[@"label"];
        NSString *name = cmd[@"name"];
        if (!label || !name) {
            continue;
        }
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:label
                                                      action:@selector(runDynamicCustomCommand:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = name;
        item.tag = kDynamicMenuItemTag;
        [menu insertItem:item atIndex:insertionIndex];
        insertionIndex += 1;
        addedAny = YES;
    }

    if (addedAny) {
        NSMenuItem *sep = [NSMenuItem separatorItem];
        sep.tag = kDynamicMenuItemTag;
        NSInteger firstDynamic = [menu.itemArray indexOfObjectPassingTest:^BOOL(NSMenuItem *item, NSUInteger idx, BOOL *stop) {
            return item.tag == kDynamicMenuItemTag && !item.isSeparatorItem;
        }];
        if (firstDynamic != NSNotFound && firstDynamic > 0) {
            [menu insertItem:sep atIndex:firstDynamic];
        }
    }
}

- (void)runDynamicCustomCommand:(NSMenuItem *)sender {
    NSString *commandName = sender.representedObject;
    if (commandName) {
        [self runAdapterCustomCommand:commandName];
    }
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
    }
#if ITERM_DEBUG
    else if (menuItem.action == @selector(useTestAdapter:)) {
        menuItem.state = self.dataSourceProvider.testAdapterEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    }
#endif
    else if (menuItem.action == @selector(resetIntegrationConfiguration:)) {
        const BOOL allowed = [[self currentDataSource] canResetConfiguration];
        if (allowed) {
            menuItem.title = [NSString stringWithFormat:ITLocalize(@"PasswordManagerWindowController_ResetConfiguration_FORMAT", @"Reset %1$@ Configuration", @"menu item title"), [[self currentDataSource] name]];
        } else {
            menuItem.title = ITLocalize(@"PasswordManagerWindowController_ResetIntegrationConfiguration", @"Reset Integration Configuration", @"menu item title");
        }
        return allowed;
    } else if (menuItem.action == @selector(copyPassword:) ||
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
            RLog(@"Auth failed. Close window.");
            [self closeOrEndSheet];
        }
    }];
}

- (void)didBecomeReady {
    DLog(@"didBecomeReady");
    if (_accountNameToSelectAfterAuthentication) {
        RLog(@"will select %@", _accountNameToSelectAfterAuthentication);
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
                RLog(@"passwordForRow: return nil, keychain gave error %@", error);

                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = [NSString stringWithFormat:ITLocalize(@"PasswordManagerWindowController_CouldNotGetPasswordKeychainQueryFailed_FORMAT", @"Could not get password. Keychain query failed: %1$@", @"Alert title in fetchPasswordForRow:"),
                                     error.localizedDescription];
                [alert addButtonWithTitle:ITLocalize(@"COMMON_OK", @"OK", @"Button title in fetchPasswordForRow:")];
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
    NSString *const kNewAccountName = ITLocalize(@"PasswordManagerWindowController_NewAccount", @"New Account", @"Text shown in nameForNewAccount: New Account");
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
            return [NSString stringWithFormat:ITLocalize(@"PasswordManagerWindowController_NewAccount_FORMAT", @"New Account %1$@",@"Formatted user-facing text in nameForNewAccount"), formattedDate];
        }
    }
    return name;
}

- (NSString *)accountNameForRow:(NSInteger)rowIndex {
    if (rowIndex < 0 || rowIndex >= _entries.count) {
        return nil;
    }
    id<PasswordManagerAccount> entry = _entries[rowIndex];
    NSString *name = entry.accountName;
    return [iTermPasswordManagerAccountFormatting displayNameForAccountName:name sourceLabel:entry.sourceLabel];
}

- (NSString *)userNameForRow:(NSInteger)rowIndex {
    if (rowIndex < 0 || rowIndex >= _entries.count) {
        return nil;
    }
    return _entries[rowIndex].userName;
}

- (void)reloadAccountsNotification:(NSNotification *)notification {
    if (notification.object == self) {
        // This window posted the notification to refresh OTHER windows; it already reloaded
        // itself, so skip a redundant second fetch here.
        return;
    }
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
        // Always run the completion, even when unauthenticated. Callers nest cleanup (e.g.
        // decrBusy) inside it; dropping it here would leak the busy count and wedge the scrim
        // if authentication is revoked (e.g. screen lock) while an edit is in flight.
        completion();
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

// Renames the account's name and user name. When the data source can edit in place
// (supportsInPlaceEdit), it does so with a single update that keeps the record and its
// OTP/custom fields. Otherwise it falls back to fetch-password, delete, re-add, which
// preserves the vault (Classic vs Nested) but drops other metadata.
- (void)renameEntry:(id<PasswordManagerAccount>)entry
      toAccountName:(NSString *)accountName
           userName:(NSString *)userName
        newPassword:(NSString *)newPassword {
    RecipeExecutionContext *context = self.recipeExecutionContext;
    __weak __typeof(self) weakSelf = self;

    if ([self currentDataSource].supportsInPlaceEdit) {
        // Send only the fields the user actually changed; pass nil for the rest so an unchanged
        // field is never rewritten. This matters when the displayed value differs from the
        // stored value (e.g. Keeper strips the “ @ host” suffix from the user name for display):
        // re-sending the displayed value would overwrite the real stored login.
        NSString *changedAccountName = [accountName isEqualToString:entry.accountName] ? nil : accountName;
        NSString *changedUserName = [userName isEqualToString:entry.userName] ? nil : userName;
        const NSInteger cancelCount = [self incrBusy];
        [entry editInPlaceWithAccountName:changedAccountName
                                 userName:changedUserName
                                 password:newPassword
                                  context:context
                               completion:^(NSError * _Nullable error) {
            [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
                DLog(@"editInPlace: %@", error);
                [weakSelf reloadAccounts:^{
                    [weakSelf decrBusy];
                }];
                // Notify OTHER windows only: this window already reloaded above, so posting
                // object:self lets its own observer skip a redundant second fetch (which would
                // also race the selecting reload). Doing it now (not before the edit completed)
                // means their reload sees fresh, cache-invalidated data.
                [weakSelf notifyOtherWindowsPasswordsDidChange];
                [weakSelf presentEditError:error];
            }];
        }];
        return;
    }

    const NSInteger cancelCount = [self incrBusy]; // 1
    [entry fetchPasswordWithContext:context
                         completion:^(NSString *maybePassword,
                                      NSString *maybeOTP,
                                      NSError *error) {
        [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
            if (error) {
                if (newPassword != nil) {
                    // A new password was supplied, so the old one is not needed; ignore the
                    // fetch error and rename with newPassword (maybePassword stays nil).
                } else {
                    // No new password, so we needed the existing one to re-add and could not
                    // get it. Surface the failure instead of silently reverting the row.
                    [weakSelf decrBusy]; // (1)
                    [weakSelf presentEditError:error];
                    return;
                }
            }
            if (newPassword == nil && maybePassword == nil) {
                // A pure rename must preserve the existing password, but we could not recover
                // it (fetch returned nil with no error). This path deletes then re-adds, so
                // re-adding with "" would destroy the stored secret. Abort before deleting.
                [weakSelf decrBusy]; // (1)
                [weakSelf presentEditError:[NSError errorWithDomain:@"PasswordManager"
                                                               code:-1
                                                           userInfo:@{NSLocalizedDescriptionKey: @"Could not read the current password, so the account was not renamed. Renaming this account recreates it, which would lose the password."}]];
                return;
            }
            // Use the typed password when the Edit panel provided one; otherwise keep the
            // current password by re-adding with the fetched value.
            NSString *password = newPassword ?: maybePassword;
            const NSInteger cancelCount = [weakSelf incrBusy]; // 2
            [weakSelf decrBusy];  // (1)
            [entry deleteWithContext:context
                          completion:^(NSError * _Nullable error) {
                [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
                    const NSInteger cancelCount = [weakSelf incrBusy]; // 3
                    [weakSelf decrBusy];  // (2)
                    // Preserve the vault across delete-then-re-add. supportsInPlaceEdit is a
                    // per-adapter handshake flag, so an adapter that has a vault but does not
                    // report in-place edit (e.g. a Keeper binary whose handshake omits
                    // canEditInPlace) reaches this path; re-adding with empty flags would route a
                    // Classic record to the Nested vault (nsf-record-add) and silently change its
                    // vault. Map the record's source back to the add flag so the rename keeps it
                    // in place. Sources with no vault report a nil sourceLabel and get no flags.
                    NSDictionary *readdFlags = @{};
                    NSString *source = entry.sourceLabel;
                    if ([source caseInsensitiveCompare:@"Classic"] == NSOrderedSame) {
                        readdFlags = @{ @"useClassicPermission": @YES };
                    } else if ([source caseInsensitiveCompare:@"Nested"] == NSOrderedSame) {
                        readdFlags = @{ @"useClassicPermission": @NO };
                    }
                    void (^onReaddComplete)(id<PasswordManagerAccount>, NSError *) =
                        ^(id<PasswordManagerAccount> _Nullable replacement, NSError * _Nullable error) {
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
                            // Notify OTHER windows only: this window already reloaded above (with
                            // selection via didUpdateAccount), so posting object:self lets its own
                            // observer skip a redundant second fetch that could also drop the
                            // just-selected row. Their reload sees fresh, cache-invalidated data.
                            [weakSelf notifyOtherWindowsPasswordsDidChange];
                            [weakSelf presentEditError:error];
                        }];
                    };
                    id<PasswordManagerDataSource> ds = [weakSelf currentDataSource];
                    [ds addUserName:userName
                        accountName:accountName
                           password:password
                              flags:readdFlags
                            context:context
                         completion:onReaddComplete];
                }];
            }];
        }];
    }];
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
    // Editing is done through the Edit panel (see edit: / presentEditPanelForEntry:), not
    // inline in the table.
    return NO;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [_removeButton setEnabled:([_tableView selectedRow] != -1)];
    [self update];
}

- (NSCell *)tableView:(NSTableView *)tableView
dataCellForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    // Display-only cells; editing happens in the Edit panel, not inline (see
    // shouldEditTableColumn).
    if (tableColumn == _accountNameColumn) {
        return [[NSTextFieldCell alloc] initTextCell:@"name"];
    } else if (tableColumn == _userNameColumn) {
        return [[NSTextFieldCell alloc] initTextCell:@"userName"];
    } else if (tableColumn == _passwordColumn) {
        return [[NSTextFieldCell alloc] initTextCell:@"password"];
    } else {
        return nil;
    }
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification {
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
        // Keep OK disabled while the password is still loading, even as the name is typed.
        [self updateNewAccountOkButtonEnabled];
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
        RLog(@"set _accountNameToSelectAfterAuthentication to %@", name);
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
