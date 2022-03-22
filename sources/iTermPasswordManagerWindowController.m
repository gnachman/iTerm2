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

    NSArray<id<PasswordManagerAccount>> *_entries;
    NSString *_accountNameToSelectAfterAuthentication;
    id _eventMonitor;
    NSOpenPanel *_panel;
    id<PasswordManagerDataSource> _dataSource;
}

+ (NSArray<NSString *> *)combinedAccountNameUserNamesWithFilter:(NSString *)maybeEmptyFilter {
    return [[self accountsWithFilter:maybeEmptyFilter] mapWithBlock:^id _Nonnull(id<PasswordManagerAccount>  _Nonnull account) {
        return account.displayString;
    }];
}

+ (NSArray<id<PasswordManagerAccount>> *)accountsWithFilter:(NSString *)maybeEmptyFilter {
    return [[[[iTermPasswordManagerDataSourceProvider dataSource] accounts] filteredArrayUsingBlock:^BOOL(id<PasswordManagerAccount> account) {
        return [account matchesFilter:maybeEmptyFilter ?: @""];
    }] sortedArrayUsingComparator:^NSComparisonResult(id<PasswordManagerAccount> _Nonnull obj1,
                                                      id<PasswordManagerAccount> _Nonnull obj2) {
        return [obj1.displayString localizedCaseInsensitiveCompare:obj2.displayString];
    }] ?: @[];
}

- (instancetype)init {
    self = [self initWithWindowNibName:@"iTermPasswordManager"];
    if (self) {
        [self authenticate];
        [[iTermPasswordManagerDataSourceProvider dataSource] resetErrors];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reloadAccounts)
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
    _broadcastButton.state = NSControlStateValueOff;
    [_tableView setDoubleAction:@selector(doubleClickOnTableView:)];
    if (iTermPasswordManagerDataSourceProvider.authenticated &&
        ![self.currentDataSource checkAvailability]) {
        [self dataSourceDidBecomeUnavailable];
    } else {
        [self reloadAccounts];
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
    const NSUInteger index = [self indexOfDisplayName:name];
    if (index != NSNotFound) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index]
                byExtendingSelection:NO];
    } else if (!iTermPasswordManagerDataSourceProvider.authenticated) {
        _accountNameToSelectAfterAuthentication = [name copy];
    }
}

#pragma mark - Keychain

- (void)updateConfiguration {
    if (iTermPasswordManagerDataSourceProvider.authenticated) {
        [self reloadAccounts];
    }
}

#pragma mark - Actions

- (IBAction)reloadItems:(id)sender {
    if (!iTermPasswordManagerDataSourceProvider.authenticated) {
        return;
    }
    [self.currentDataSource reload];
    [self reloadAccounts];
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
        [_newAccountPanel it_shakeNo];
        return;
    }
    if ([self indexOfAccountName:_newAccount.stringValue userName:_newUserName.stringValue ?: @""] != NSNotFound) {
        [_newAccountPanel it_shakeNo];
        return;
    }
    NSError *error = nil;
    id<PasswordManagerAccount> newAccount = [[self currentDataSource] addUserName:_newUserName.stringValue ?: @""
                                                                      accountName:_newAccount.stringValue ?: @""
                                                                         password:_newPassword.stringValue ?: @""
                                                                            error:&error];
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
    _newPassword.stringValue = @"";
    _newUserName.stringValue = @"";
    _newAccount.stringValue = @"";
    [self.window endSheet:_newAccountPanel];
    [_newAccountPanel orderOut:nil];
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
        NSError *error = nil;
        [_entries[selectedRow] delete:&error];
        if (error) {
            DLog(@"%@", error);
            return;
        }
        [self reloadAccounts];
        [self passwordsDidChange];
    }
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
            [alert addButtonWithTitle:@"Cancel"];

            NSSecureTextField *newPassword = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
            newPassword.editable = YES;
            newPassword.selectable = YES;
            alert.accessoryView = newPassword;
            [alert layout];
            [[alert window] makeFirstResponder:newPassword];

            if ([self runModal:alert] == NSAlertFirstButtonReturn) {
                NSError *error = nil;
                [_entries[row] setPassword:newPassword.stringValue ?: @"" error:&error];
                if (!error) {
                    [self passwordsDidChange];
                } else {
                    DLog(@"%@", error);
                }
            }
        }
    }
}

- (IBAction)enterPassword:(id)sender {
    DLog(@"enterPassword");
    NSString *password = [self selectedPassword];
    if (password) {
        DLog(@"enterPassword: giving password to delegate");
        NSString *twoFactorCode = [_twoFactorCode.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [_delegate iTermPasswordManagerEnterPassword:[password stringByAppendingString:twoFactorCode]
                                           broadcast:_broadcastButton.state == NSControlStateValueOn];
        DLog(@"enterPassword: closing sheet");
        [self closeOrEndSheet];
    }
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
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = [NSString stringWithFormat:@"Password for %@", accountName];
            NSString *password = [self clickedPassword];
            if (!password) {
                // Already showed an error.
                return;
            } else {
                alert.informativeText = password;
            }
            [alert addButtonWithTitle:@"OK"];
            [alert addButtonWithTitle:@"Copy"];

            if ([self runModal:alert] == NSAlertSecondButtonReturn) {
                NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
                [pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:self];
                [pasteboard setString:password forType:NSPasteboardTypeString];
            }
        }
    }
}

- (IBAction)copyPassword:(id)sender {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:self];
    [pasteboard setString:[self clickedPassword] forType:NSPasteboardTypeString];
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
    // When a sheet is attached to a hotkey window another app becomes active after the auth dialog
    // is dismissed, leaving the hotkey behind another app.
    [NSApp activateIgnoringOtherApps:YES];
    [self.window.sheetParent makeKeyAndOrderFront:nil];

    if (success) {
        if (![self.currentDataSource checkAvailability]) {
            [self dataSourceDidBecomeUnavailable];
        } else {
            [self reloadAccounts];
            if (_accountNameToSelectAfterAuthentication) {
                [self selectAccountName:_accountNameToSelectAfterAuthentication];
                _accountNameToSelectAfterAuthentication = nil;
            } else {
                [[self window] makeFirstResponder:_searchField];
            }
        }
    } else {
        DLog(@"Auth failed. Close window.");
        [self closeOrEndSheet];
    }
}

- (NSString *)clickedPassword {
    DLog(@"clickedPassword");
    NSInteger index = [_tableView clickedRow];
    return [self passwordForRow:index];
}

- (NSString *)selectedPassword {
    DLog(@"selectedPassword");
    NSInteger index = [_tableView selectedRow];
    return [self passwordForRow:index];
}

- (NSString *)passwordForRow:(NSInteger)index {
    DLog(@"row=%@", @(index));
    if (!iTermPasswordManagerDataSourceProvider.authenticated) {
        DLog(@"passwordForRow: return nil, not authenticated");
        return nil;
    }
    if (index < 0) {
        DLog(@"passwordForRow: return nil, negative index");
        return nil;
    }
    if (index >= _entries.count) {
        DLog(@"index too big");
        return nil;
    }
    NSError *error = nil;
    NSString *password = [_entries[index] password:&error];
    if (error) {
        DLog(@"passwordForRow: return nil, keychain gave error %@", error);

        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat:@"Could not get password. Keychain query failed: %@",
                             error.localizedDescription];
        [alert addButtonWithTitle:@"OK"];
        [self runModal:alert];

        return nil;
    } else {
        DLog(@"passwordForRow: return nonnil password");
        return password ?: @"";
    }
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

- (void)reloadAccounts {
    NSString *filter = [_searchField stringValue];
    if (iTermPasswordManagerDataSourceProvider.authenticated) {
        _entries = [[self class] accountsWithFilter:filter];
    } else {
        _entries = @[];
    }
    [_tableView reloadData];
    [self update];
}

- (void)passwordsDidChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:kPasswordManagersShouldReloadData object:nil];
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

        NSError *error = nil;
        NSString *password = [entry password:&error];
        if (!error) {
            if (!password) {
                password = @"";
            }
            if ([entry delete:&error]) {
                id<PasswordManagerAccount> replacement = [[self currentDataSource] addUserName:userName
                                                                                   accountName:accountName
                                                                                      password:password
                                                                                         error:&error];
                DLog(@"%@", error);
                [self reloadAccounts];

                const NSUInteger index = [self indexOfAccountName:replacement.accountName userName:userName];
                if (index != NSNotFound) {
                    [aTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
                }
            }
        }
    }
    [self passwordsDidChange];
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
        [self reloadAccounts];
    }
    if ([self numberOfRowsInTableView:_tableView] == 1) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
}

@end
