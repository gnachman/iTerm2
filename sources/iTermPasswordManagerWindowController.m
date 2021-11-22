//
//  iTermPasswordManagerWindowController.m
//  iTerm
//
//  Created by George Nachman on 5/14/14.
//
//

#import "iTermPasswordManagerWindowController.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "iTermSearchField.h"
#import "iTermSystemVersion.h"
#import "iTermUserDefaults.h"
#import "NSAlert+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"
#import "NSTextField+iTerm.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import <SSKeychain.h>
#import <Security/Security.h>

static NSString *const kServiceName = @"iTerm2";
static NSString *const kPasswordManagersShouldReloadData = @"kPasswordManagersShouldReloadData";
static BOOL sAuthenticated;
// Looks nice and is unlikely to be used already
static NSString *const iTermPasswordManagerAccountNameUserNameSeparator = @"\u2002—\u2002";

@implementation iTermPasswordEntry

- (instancetype)initWithMaybeCombinedAccountName:(NSString *)maybeCombinedAccountName {
    self = [super init];
    if (self) {
        const NSRange range = [maybeCombinedAccountName rangeOfString:iTermPasswordManagerAccountNameUserNameSeparator];
        if (range.location == NSNotFound) {
            _accountName = [maybeCombinedAccountName copy];
            _userName = @"";
        } else {
            _accountName = [maybeCombinedAccountName substringToIndex:range.location];
            _userName = [maybeCombinedAccountName substringFromIndex:NSMaxRange(range)];
        }
    }
    return self;
}

- (BOOL)matchesFilter:(NSString * _Nullable)filter {
    if (!filter) {
        return YES;
    }
    return [self.combinedAccountNameUserName rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound;
}

- (NSString *)combinedAccountNameUserName {
    if (self.userName.length == 0) {
        return self.accountName;
    }
    return [NSString stringWithFormat:@"%@%@%@", self.accountName, iTermPasswordManagerAccountNameUserNameSeparator, self.userName ?: @""];
}

- (void)setAccountName:(NSString *)accountName {
    _accountName = [accountName stringByReplacingOccurrencesOfString:iTermPasswordManagerAccountNameUserNameSeparator
                                                          withString:@""];
}

- (void)setUserName:(NSString *)userName {
    _userName = [userName stringByReplacingOccurrencesOfString:iTermPasswordManagerAccountNameUserNameSeparator
                                                    withString:@""];
}

@end

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
    NSWindowDelegate>
@end

@implementation iTermPasswordManagerWindowController {
    IBOutlet NSTableView *_tableView;
    IBOutlet NSTableColumn *_accountNameColumn;
    IBOutlet NSTableColumn *_userNameColumn;
    IBOutlet NSTableColumn *_passwordColumn;
    IBOutlet NSButton *_removeButton;
    IBOutlet NSButton *_editButton;
    IBOutlet NSButton *_enterPasswordButton;
    IBOutlet NSButton *_enterUserNameButton;
    IBOutlet iTermSearchField *_searchField;
    IBOutlet NSButton *_broadcastButton;
    IBOutlet NSTextField *_twoFactorCode;
    NSArray<iTermPasswordEntry *> *_entries;
    NSString *_accountNameToSelectAfterAuthentication;
    id _eventMonitor;
}

+ (NSArray<iTermPasswordEntry *> *)entriesWithFilter:(NSString *)maybeEmptyFilter {
    if (!sAuthenticated) {
        return @[ ];
    }

    NSString *filter = maybeEmptyFilter;
    if (!filter.length) {
        filter = nil;
    }

    NSArray<iTermPasswordEntry *> *unsortedEntries =
    [[SSKeychain accountsForService:kServiceName] mapWithBlock:^iTermPasswordEntry *(NSDictionary *account) {
        NSString *maybeCombinedAccountName = account[(NSString *)kSecAttrAccount];
        if (!maybeCombinedAccountName) {
            return nil;
        }
        iTermPasswordEntry *passwordEntry = [[iTermPasswordEntry alloc] initWithMaybeCombinedAccountName:maybeCombinedAccountName];
        if (![passwordEntry matchesFilter:filter]) {
            return nil;
        }
        return passwordEntry;
    }];

    return [unsortedEntries sortedArrayUsingComparator:^NSComparisonResult(iTermPasswordEntry * _Nonnull obj1, iTermPasswordEntry * _Nonnull obj2) {
        return [obj1.accountName localizedCaseInsensitiveCompare:obj2.accountName];
    }];
}

+ (void)authenticateWithPolicy:(LAPolicy)policy context:(LAContext *)myContext reply:(void(^)(BOOL success, NSError * __nullable error))reply {
    DLog(@"Requesting authentication with policy %@", @(policy));

    NSString *myLocalizedReasonString = @"open the password manager";
    // You're supposed to hold a reference to the context until it's done doing its thing.
    if (policy == LAPolicyDeviceOwnerAuthentication) {
        [[iTermApplication sharedApplication] setLocalAuthenticationDialogOpen:YES];
    }
    [myContext evaluatePolicy:policy
              localizedReason:myLocalizedReasonString
                        reply:^(BOOL success, NSError *error) {
        DLog(@"Policy evaluation success=%@ error=%@", @(success), error);
        LAContext *theContext NS_VALID_UNTIL_END_OF_SCOPE;
        theContext = myContext;
        if (policy == LAPolicyDeviceOwnerAuthentication) {
            [[iTermApplication sharedApplication] setLocalAuthenticationDialogOpen:NO];
        }
        if (success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                sAuthenticated = YES;
                reply(success, error);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                sAuthenticated = NO;
                if (error.code != LAErrorSystemCancel &&
                    error.code != LAErrorAppCancel) {
                    BOOL isTouchID = (policy == LAPolicyDeviceOwnerAuthenticationWithBiometrics);
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"Authentication Failed";
                    alert.informativeText = [NSString stringWithFormat:@"Authentication failed because %@", [self reasonForAuthenticationError:error touchID:isTouchID]];
                    [alert addButtonWithTitle:@"OK"];
                    [alert runModal];
                }
                reply(success, error);
            });
        }
    }];
}

+ (NSString *)reasonForAuthenticationError:(NSError *)error touchID:(BOOL)touchID {
    switch (error.code) {
        case LAErrorAuthenticationFailed:
            return @"valid credentials weren't supplied.";

        case LAErrorUserCancel:
            return touchID ? @"touch ID was cancelled." : @"password entry was cancelled.";

        case LAErrorUserFallback:
            return @"password authentication was requested.";

        case LAErrorSystemCancel:
            return touchID ? @"the system cancelled the Touch ID request." : @"the system cancelled the authentication request.";

        case LAErrorPasscodeNotSet:
            return @"no passcode is set.";

        case kLAErrorTouchIDNotAvailable:
            return @"touch ID is not available.";

        case LAErrorBiometryNotEnrolled:
            return @"touch ID doesn't have any fingers enrolled.";

        case LAErrorBiometryLockout:
            return @"there were too many failed Touch ID attempts.";

        case LAErrorAppCancel:
            return touchID ? @"touch ID was cancelled by iTerm2." : @"authentication was cancelled by iTerm2.";

        case LAErrorInvalidContext:
            return @"the context is invalid. This is a bug in iTerm2. Please report it.";
    }
    return [error localizedDescription];
}

- (instancetype)init {
    self = [self initWithWindowNibName:@"iTermPasswordManager"];
    if (self) {
        [self requestAuthenticationIfPossible];
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
    [self reloadAccounts];
    [self update];
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
    if (sAuthenticated) {
        [[self window] makeFirstResponder:_searchField];
    }
}

// Opening this window should not cause the hotkey window to hide.
- (BOOL)autoHidesHotKeyWindow {
    return NO;
}

#pragma mark - APIs

- (void)update {
    _broadcastButton.enabled = [self.delegate iTermPasswordManagerCanBroadcast];
    const BOOL shouldEnableButtons = ([_tableView selectedRow] >= 0 &&
                                      [_delegate iTermPasswordManagerCanEnterPassword]);
    [_enterPasswordButton setEnabled:shouldEnableButtons];
    [_enterUserNameButton setEnabled:(shouldEnableButtons &&
                                      self.selectedUserName.length > 0 &&
                                      [_delegate iTermPasswordManagerCanEnterUserName])];
}

- (void)selectAccountName:(NSString *)name {
    if (!name) {
        return;
    }
    const NSUInteger index = [self indexOfAccountName:name];
    if (index != NSNotFound) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index]
                byExtendingSelection:NO];
    } else if (!sAuthenticated) {
        _accountNameToSelectAfterAuthentication = [name copy];
    }
}

#pragma mark - Actions

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
    if (sAuthenticated) {
        NSString *name = [self nameForNewAccount];
        if ([[self keychain] setPassword:@"" forService:kServiceName account:name]) {
            [self reloadAccounts];
            NSUInteger index = [self indexOfAccountName:name];
            if (index != NSNotFound) {
                [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
            }
        }
        [self passwordsDidChange];
    }
}

- (IBAction)remove:(id)sender {
    if (sAuthenticated) {
        NSInteger selectedRow = [_tableView selectedRow];
        if (selectedRow < 0 || selectedRow >= _entries.count) {
            return;
        }
        if (![self shouldRemoveSelection]) {
            return;
        }
        [_tableView reloadData];
        [[self keychain] deletePasswordForService:kServiceName account:_entries[selectedRow].combinedAccountNameUserName];
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
                [[self keychain] setPassword:newPassword.stringValue
                                  forService:kServiceName
                                     account:_entries[row].combinedAccountNameUserName];
                [self passwordsDidChange];
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
    const NSInteger row = _tableView.selectedRow;
    if (row < 0) {
        return;
    }
    [_tableView editColumn:0 row:row withEvent:nil select:YES];
}

- (IBAction)editUserName:(id)sender {
    const NSInteger row = _tableView.selectedRow;
    if (row < 0) {
        return;
    }
    [_tableView editColumn:1 row:row withEvent:nil select:YES];
}

- (IBAction)revealPassword:(id)sender {
    const NSInteger row = _tableView.selectedRow;
    if (row >= 0) {
        @autoreleasepool {
            NSString *accountName = [self accountNameForRow:row];
            if (!accountName) {
                return;
            }
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = [NSString stringWithFormat:@"Password for %@", accountName];
            NSString *password = [self selectedPassword];
            if (!password) {
                return;
            }
            alert.informativeText = password;
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
    [pasteboard setString:[self selectedPassword] forType:NSPasteboardTypeString];
}

- (BOOL)shouldProbe {
    return ([iTermUserDefaults probeForPassword] && [iTermAdvancedSettingsModel echoProbeDuration] > 0);
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(toggleRequireAuthenticationAfterScreenLocks:)) {
        menuItem.state = [iTermUserDefaults requireAuthenticationAfterScreenLocks] ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (menuItem.action == @selector(toggleProbe:)) {
        menuItem.state = self.shouldProbe ? NSControlStateValueOn : NSControlStateValueOff;
    }
    return YES;
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
        sAuthenticated = NO;
    }
}

- (void)instanceScreenDidLock:(NSNotification *)notification {
    if ([iTermUserDefaults requireAuthenticationAfterScreenLocks]) {
        for (NSWindow *sheet in [self.window.sheets copy]) {
            [self.window endSheet:sheet];
        }
        [self closeCurrentSession:nil];
    }
}

#pragma mark - Private

- (Class)keychain {
    if (sAuthenticated) {
        return [SSKeychain class];
    } else {
        return nil;
    }
}

- (void)requestAuthenticationIfPossible {
    DLog(@"Request auth if possible");
    if (sAuthenticated) {
        DLog(@"Already authenticated");
        return;
    }

    LAContext *myContext = [[LAContext alloc] init];
    NSString *reason = nil;
    if (![self tryToAuthenticateWithPolicy:LAPolicyDeviceOwnerAuthentication context:myContext reason:&reason]) {
        DLog(@"There are no auth policies that can succeed on this machine. Giving up. %@", reason);
        sAuthenticated = YES;
    }
}

- (BOOL)policyAvailableOnThisOSVersion:(LAPolicy)policy {
    switch (policy) {
        case LAPolicyDeviceOwnerAuthenticationWithBiometrics:
            return IsTouchBarAvailable();

        case LAPolicyDeviceOwnerAuthentication:
            return YES;

        default:
            return NO;
    }
}

- (BOOL)tryToAuthenticateWithPolicy:(LAPolicy)policy context:(LAContext *)myContext reason:(NSString **)reason {
    DLog(@"Try to auth with %@", @(policy));
    NSError *authError = nil;
    if (![self policyAvailableOnThisOSVersion:policy]) {
        *reason = @"Policy not available on this OS version";
        return NO;
    }
    if ([myContext canEvaluatePolicy:policy error:&authError]) {
        DLog(@"It says we can evaluate this policy");
        [self authenticateWithPolicy:policy context:myContext];
        return YES;
    } else {
        *reason = [NSString stringWithFormat:@"Can't authenticate with policy %@: %@", @(policy), authError];
        return NO;
    }
}

- (void)authenticateWithPolicy:(LAPolicy)policy context:(LAContext *)myContext {
    __weak __typeof(self) weakSelf = self;
    [[self class] authenticateWithPolicy:policy context:myContext reply:^(BOOL success, NSError * _Nullable error) {
        DLog(@"Authentication completed with succes=%@ error=%@", @(success), error);
        [weakSelf didAuthenticateWithContext:myContext
                                     success:success
                                       error:error];
    }];
}

- (void)didAuthenticateWithContext:(LAContext *)myContext success:(BOOL)success error:(NSError * _Nullable)error {
    id temp NS_VALID_UNTIL_END_OF_SCOPE;
    temp = myContext;
    // When a sheet is attached to a hotkey window another app becomes active after the auth dialog
    // is dismissed, leaving the hotkey behind another app.
    [NSApp activateIgnoringOtherApps:YES];
    [self.window.sheetParent makeKeyAndOrderFront:nil];

    if (success) {
        [self reloadAccounts];
        if (_accountNameToSelectAfterAuthentication) {
            [self selectAccountName:_accountNameToSelectAfterAuthentication];
            _accountNameToSelectAfterAuthentication = nil;
        } else {
            [[self window] makeFirstResponder:_searchField];
        }
    } else {
        DLog(@"Auth failed. Close window.");
        [self closeOrEndSheet];
    }
}

- (NSString *)selectedPassword {
    DLog(@"selectedPassword");
    if (!sAuthenticated) {
        DLog(@"selectedPassword: return nil, not authenticated");
        return nil;
    }
    NSInteger index = [_tableView selectedRow];
    if (index < 0) {
        DLog(@"selectedPassword: return nil, negative index");
        return nil;
    }
    if (index >= _entries.count) {
        DLog(@"index too bvig");
        return nil;
    }
    NSError *error = nil;
    NSString *password = [[self keychain] passwordForService:kServiceName
                                                     account:_entries[index].combinedAccountNameUserName
                                                       error:&error];
    if (error) {
        DLog(@"selectedPassword: return nil, keychain gave error %@", error);
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = [NSString stringWithFormat:@"Could not get password. Keychain query failed: %@", error];
            [alert addButtonWithTitle:@"OK"];
            [self runModal:alert];
        });
        return nil;
    } else {
        DLog(@"selectedPassword: return nonnil password");
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
    if (!sAuthenticated) {
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

- (NSUInteger)indexOfAccountName:(NSString *)name {
    NSUInteger result =
    [_entries indexOfObjectPassingTest:^BOOL(iTermPasswordEntry * _Nonnull entry, NSUInteger idx, BOOL * _Nonnull stop) {
        return [entry.combinedAccountNameUserName isEqualToString:name];
    }];
    if (result != NSNotFound) {
        return result;
    }
    return [_entries indexOfObjectPassingTest:^BOOL(iTermPasswordEntry * _Nonnull entry, NSUInteger idx, BOOL * _Nonnull stop) {
        return [entry.accountName isEqualToString:name];
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
    if (sAuthenticated) {
        _entries = [[self class] entriesWithFilter:filter];
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
    if (!sAuthenticated) {
        return;
    }
    if (rowIndex < 0 || rowIndex >= _entries.count) {
        ITCriticalError(NO, @"Row index %@ out of bounds [0, %@)", @(rowIndex), @(_entries.count));
    }
    if (aTableColumn == _accountNameColumn || aTableColumn == _userNameColumn) {
        NSString *const existingAccountName = _entries[rowIndex].combinedAccountNameUserName;

        iTermPasswordEntry *entry = [[iTermPasswordEntry alloc] init];
        entry.accountName = (aTableColumn == _accountNameColumn) ? anObject : [self accountNameForRow:rowIndex];
        entry.userName = (aTableColumn == _userNameColumn) ? anObject : [self userNameForRow:rowIndex];

        NSError *error = nil;
        NSString *password = [[self keychain] passwordForService:kServiceName
                                                         account:existingAccountName
                                                           error:&error];
        if (!error) {
            if (!password) {
                password = @"";
            }
            if ([[self keychain] deletePasswordForService:kServiceName account:existingAccountName]) {
                [[self keychain] setPassword:password
                                  forService:kServiceName
                                     account:entry.combinedAccountNameUserName
                                       error:nil];
                [self reloadAccounts];

                const NSUInteger index = [self indexOfAccountName:entry.accountName];
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
    [_editButton setEnabled:([_tableView selectedRow] != -1)];
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
    if ((id)[fieldEditor delegate] == _searchField) {
        [self reloadAccounts];
    }
    if ([self numberOfRowsInTableView:_tableView] == 1) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
}

@end
