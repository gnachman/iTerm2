//
//  iTermPasswordManagerWindowController.m
//  iTerm
//
//  Created by George Nachman on 5/14/14.
//
//

#import "iTermPasswordManagerWindowController.h"

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
    NSWindowDelegate>
@end

@implementation iTermPasswordManagerWindowController {
    IBOutlet NSTableView *_tableView;
    IBOutlet NSTableColumn *_accountNameColumn;
    IBOutlet NSTableColumn *_userNameColumn;
    IBOutlet NSTableColumn *_passwordColumn;
    IBOutlet NSButton *_removeButton;
    IBOutlet NSButton *_editButton;
    IBOutlet NSButton *_addButton;
    IBOutlet NSButton *_enterPasswordButton;
    IBOutlet NSButton *_enterUserNameButton;
    IBOutlet iTermSearchField *_searchField;
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
    NSString *_accountNameToSelectAfterAuthentication;
    id _eventMonitor;
    NSOpenPanel *_panel;
    id<PasswordManagerDataSource> _dataSource;
    NSInteger _busyCount;
    NSInteger _cancelCount;
    BOOL _awakeFromNibAvailabilityCheckFailed;
    iTermPasswordManagerReload _reloadPolicy;
}

static NSArray<NSString *> *gCachedCombinedAccountNames;

+ (NSArray<NSString *> *)cachedCombinedAccountNames {
    return gCachedCombinedAccountNames;
}

+ (void)updateCombinedAccountNamesCache {
    const BOOL wait = (gCachedCombinedAccountNames == nil);
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    [self fetchAccountsWithCompletion:^(NSArray<NSString *> *names) {}];
    if (wait) {
        dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)));
    }
}

+ (void)setCachedCombinedAccountNames:(NSArray<NSString *> *)names {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gCachedCombinedAccountNames = @[];
    });
    gCachedCombinedAccountNames = names;
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermPasswordManagerDidLoadAccounts object:nil];
}

+ (void)fetchAccountsWithCompletion:(void (^)(NSArray<id<PasswordManagerAccount>> *))completion {
    [[iTermPasswordManagerDataSourceProvider dataSource] fetchAccounts:^(NSArray<id<PasswordManagerAccount>> * _Nonnull accounts) {
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
        [[iTermPasswordManagerDataSourceProvider dataSource] resetErrors];
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
    _scrim.layer.backgroundColor = [[[NSColor windowBackgroundColor] colorWithAlphaComponent:0.75] CGColor];
    _scrim.alphaValue = 0;

    _broadcastButton.state = NSControlStateValueOff;
    [_tableView setDoubleAction:@selector(doubleClickOnTableView:)];
    if (iTermPasswordManagerDataSourceProvider.authenticated &&
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
    if (iTermPasswordManagerDataSourceProvider.authenticated) {
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
    _broadcastButton.enabled = [self.delegate iTermPasswordManagerCanBroadcast];
    const BOOL shouldEnableButtons = ([_tableView selectedRow] >= 0 &&
                                      [_delegate iTermPasswordManagerCanEnterPassword]);
    [_enterPasswordButton setEnabled:shouldEnableButtons];
    [_enterUserNameButton setEnabled:(shouldEnableButtons &&
                                      self.selectedUserName.length > 0 &&
                                      [_delegate iTermPasswordManagerCanEnterUserName])];
    const BOOL editable = !self.currentDataSource.autogeneratedPasswordsOnly;
    [_editButton setEnabled:([_tableView selectedRow] != -1) && editable];
    _addButton.enabled = available;
}

- (void)selectAccountName:(NSString *)name {
    if (!name) {
        return;
    }
    if (_entries) {
        [self reallySelectAccountName:name];
        return;
    }
    __weak __typeof(self) weakSelf = self;
    [self reloadAccounts:^{
        [weakSelf reallySelectAccountName:name];
    }];
}

- (void)reallySelectAccountName:(NSString *)name {
    const NSUInteger index = [self indexOfDisplayName:name];
    if (index != NSNotFound) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index]
                byExtendingSelection:NO];
        [_tableView scrollRowToVisible:index];
    } else if (!iTermPasswordManagerDataSourceProvider.authenticated) {
        _accountNameToSelectAfterAuthentication = [name copy];
    }
}

#pragma mark - Keychain

- (void)updateConfiguration {
    if (iTermPasswordManagerDataSourceProvider.authenticated) {
        [self reloadAccounts:^{}];
    }
}

+ (NSString *)randomPassword {
    NSString *characters;
    NSUInteger length = 16;
    if ([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagOption) {
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

- (IBAction)generatePassword:(id)sender {
    _newPassword.stringValue = [iTermPasswordManagerWindowController randomPassword];
}

- (IBAction)cancelAsyncOperation:(id)sender {
    _cancelCount += 1;
    _busyCount = 1;
    [self decrBusy];
}

- (IBAction)reloadItems:(id)sender {
    if (!iTermPasswordManagerDataSourceProvider.authenticated) {
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

- (IBAction)useKeychain:(id)sender {
    [iTermPasswordManagerDataSourceProvider enableKeychain];
    [self update];
    [self updateConfiguration];
}

- (IBAction)use1Password:(id)sender {
    [iTermPasswordManagerDataSourceProvider enable1Password];
    [self.currentDataSource resetErrors];
    if (![self.currentDataSource checkAvailability]) {
        [self useKeychain:nil];
    }
    [self update];
    [self updateConfiguration];
}

- (IBAction)useLastPass:(id)sender {
    [iTermPasswordManagerDataSourceProvider enableLastPass];
    [self.currentDataSource resetErrors];
    if (![self.currentDataSource checkAvailability]) {
        [self useKeychain:nil];
    }
    [self update];
    [self updateConfiguration];
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
            [self enterPassword:nil];
        }
    }
}

- (IBAction)add:(id)sender {
    if (!iTermPasswordManagerDataSourceProvider.authenticated) {
        return;
    }
    _newAccountOkButton.enabled = NO;
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
    }
    if (error) {
        DLog(@"%@", error);
    }
}

- (IBAction)remove:(id)sender {
    if (iTermPasswordManagerDataSourceProvider.authenticated) {
        NSInteger selectedRow = [_tableView selectedRow];
        if (selectedRow < 0 || selectedRow >= _entries.count) {
            return;
        }
        if (![self shouldRemoveSelection]) {
            return;
        }
        [_tableView reloadData];
        __weak __typeof(self) weakSelf = self;
        [_entries[selectedRow] delete:^(NSError * _Nullable error) {
            if (error) {
                DLog(@"%@", error);
                return;
            }
            [weakSelf didRemoveEntry];
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

            switch ([self runModal:alert]) {
                case NSAlertFirstButtonReturn: {
                    __weak __typeof(self) weakSelf = self;
                    const NSInteger cancelCount = [self incrBusy];
                    [_entries[row] setPassword:newPassword.stringValue completion:^(NSError * _Nullable error) {
                        [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
                            [weakSelf decrBusy];
                            if (error) {
                                DLog(@"%@", error);
                                return;
                            }
                            [weakSelf passwordsDidChange];
                        }];
                    }];
                    break;
                }
                case NSAlertSecondButtonReturn: {
                    __weak __typeof(self) weakSelf = self;
                    const NSInteger cancelCount = [self incrBusy];
                    [_entries[row] setPassword:[iTermPasswordManagerWindowController randomPassword] completion:^(NSError * _Nullable error) {
                        [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
                            [weakSelf decrBusy];
                            if (error) {
                                DLog(@"%@", error);
                                return;
                            }
                            [weakSelf passwordsDidChange];
                        }];
                    }];
                    break;
                }
            }
        }
    }
}

- (IBAction)enterPassword:(id)sender {
    DLog(@"enterPassword");
    __weak __typeof(self) weakSelf = self;
    [self fetchSelectedPassword:^(NSString *password, NSString *otp) {
        if (!password) {
            return;
        }
        [weakSelf didFetchPasswordToEnter:password otp:otp];
    }];
}

- (void)didFetchPasswordToEnter:(NSString *)password otp:(NSString *)otp {
    DLog(@"enterPassword: giving password to delegate");
    NSString *secondFactor = _twoFactorCode.stringValue;
    if (otp && [secondFactor length] == 0) {
        secondFactor = otp;
    }
    NSString *twoFactorCode = [secondFactor stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    [_delegate iTermPasswordManagerEnterPassword:[password stringByAppendingString:twoFactorCode]
                                       broadcast:_broadcastButton.state == NSControlStateValueOn];
    DLog(@"enterPassword: closing sheet");
    [self closeOrEndSheet];
}

- (IBAction)enterUserName:(id)sender {
    DLog(@"enterUserName");
    NSString *userName = [self selectedUserName];
    if (userName.length > 0) {
        [_delegate iTermPasswordManagerEnterUserName:userName
                                           broadcast:_broadcastButton.state == NSControlStateValueOn];
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

- (IBAction)editAccountName:(id)sender {
    const NSInteger row = _tableView.clickedRow;
    if (row < 0) {
        return;
    }
    [_tableView editColumn:0 row:row withEvent:nil select:YES];
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

    if ([self runModal:alert] == NSAlertSecondButtonReturn) {
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:self];
        [pasteboard setString:password forType:NSPasteboardTypeString];
    }
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
    if (!iTermPasswordManagerDataSourceProvider.authenticated) {
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
        menuItem.state = iTermPasswordManagerDataSourceProvider.keychainEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (menuItem.action == @selector(use1Password:)) {
        menuItem.state = iTermPasswordManagerDataSourceProvider.onePasswordEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (menuItem.action == @selector(useLastPass:)) {
        menuItem.state = iTermPasswordManagerDataSourceProvider.lastPassEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (menuItem.action == @selector(editAccountName:) ||
               menuItem.action == @selector(editUserName:) ||
               menuItem.action == @selector(copyPassword:) ||
               menuItem.action == @selector(revealPassword:)) {
        return _tableView.clickedRow != -1;
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
        [iTermPasswordManagerDataSourceProvider revokeAuthentication];
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
    return iTermPasswordManagerDataSourceProvider.dataSource;
}

- (void)authenticate {
    DLog(@"Request auth if possible");
    if (iTermPasswordManagerDataSourceProvider.authenticated) {
        DLog(@"Already authenticated");
        return;
    }

    __weak __typeof(self) weakSelf = self;
    [iTermPasswordManagerDataSourceProvider requestAuthenticationIfNeeded:^(BOOL authenticated) {
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
    if (_accountNameToSelectAfterAuthentication) {
        [self selectAccountName:_accountNameToSelectAfterAuthentication];
        _accountNameToSelectAfterAuthentication = nil;
    } else {
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
    if (!iTermPasswordManagerDataSourceProvider.authenticated) {
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
    [_entries[index] fetchPassword:^(NSString * _Nullable password, NSString * _Nullable otp, NSError * _Nullable error) {
        [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
            [weakSelf decrBusy];
            if (error) {
                DLog(@"passwordForRow: return nil, keychain gave error %@", error);

                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = [NSString stringWithFormat:@"Could not get password. Keychain query failed: %@",
                                     error.localizedDescription];
                [alert addButtonWithTitle:@"OK"];
                [self runModal:alert];
                completion(nil, nil);
            } else {
                DLog(@"passwordForRow: return nonnil password");
                completion(password ?: @"", otp);
            }
        }];
    }];
}

- (NSModalResponse)runModal:(NSAlert *)alert {
    if (self.windowLoaded && self.window.isVisible) {
        return [alert runSheetModalForWindow:self.window];
    } else {
        return [alert runModal];
    }
}

- (NSString *)selectedUserName {
    DLog(@"selectedUserName");
    if (!iTermPasswordManagerDataSourceProvider.authenticated) {
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
    if (iTermPasswordManagerDataSourceProvider.authenticated) {
        __weak __typeof(self) weakSelf = self;
        const NSInteger cancelCount = [self incrBusy];
        [self.class fetchAccountsWithCompletion:^(NSArray<id<PasswordManagerAccount>> *accounts) {
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
    [iTermPasswordManagerDataSourceProvider consolidateAvailabilityChecks:^{
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
    if (!iTermPasswordManagerDataSourceProvider.authenticated) {
        return;
    }
    if (rowIndex < 0 || rowIndex >= _entries.count) {
        ITCriticalError(NO, @"Row index %@ out of bounds [0, %@)", @(rowIndex), @(_entries.count));
    }
    if (aTableColumn == _accountNameColumn || aTableColumn == _userNameColumn) {
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
        [entry fetchPassword:^(NSString * _Nullable maybePassword, NSString * _Nullable maybeOTP, NSError * _Nullable error) {
            [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
                if (error) {
                    [weakSelf decrBusy]; // (1)
                    return;
                }
                NSString *password = maybePassword ?: @"";
                const NSInteger cancelCount = [weakSelf incrBusy]; // 2
                [weakSelf decrBusy];  // (1)
                [entry delete:^(NSError * _Nullable error) {
                    [weakSelf ifCancelCountUnchanged:cancelCount perform:^{
                        const NSInteger cancelCount = [weakSelf incrBusy]; // 3
                        [weakSelf decrBusy];  // (2)
                        [[weakSelf currentDataSource] addUserName:userName
                                                      accountName:accountName
                                                         password:password
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
        [self setAccounts:_unfilteredEntries filtered:[self accounts:_unfilteredEntries filteredBy:[_searchField stringValue]]];
    }
    if ([self numberOfRowsInTableView:_tableView] == 1) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
}

@end
