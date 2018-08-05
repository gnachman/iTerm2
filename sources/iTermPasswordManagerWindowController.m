//
//  iTermPasswordManagerWindowController.m
//  iTerm
//
//  Created by George Nachman on 5/14/14.
//
//

#import "iTermPasswordManagerWindowController.h"

#import "DebugLogging.h"
#import "iTermApplication.h"
#import "iTermSearchField.h"
#import "iTermSystemVersion.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import <SSKeychain.h>
#import <Security/Security.h>

static NSString *const kServiceName = @"iTerm2";
static NSString *const kPasswordManagersShouldReloadData = @"kPasswordManagersShouldReloadData";
static LAContext *sAuthenticatedContext;

@interface iTermPasswordManagerWindowController () <
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSWindowDelegate>
@end

@implementation iTermPasswordManagerWindowController {
    IBOutlet NSTableView *_tableView;
    IBOutlet NSTableColumn *_accountNameColumn;
    IBOutlet NSTableColumn *_passwordColumn;
    IBOutlet NSButton *_removeButton;
    IBOutlet NSButton *_editButton;
    IBOutlet NSButton *_enterPasswordButton;
    IBOutlet iTermSearchField *_searchField;
    NSArray *_accounts;
    NSString *_passwordBeingShown;
    NSInteger _rowForPasswordBeingShown;
    NSString *_accountNameToSelectAfterAuthentication;
}

+ (NSArray *)accountNamesWithFilter:(NSString *)filter {
    if (!sAuthenticatedContext) {
        return @[ ];
    }

    NSMutableArray *array = [NSMutableArray array];
    if (!filter.length) {
        filter = nil;
    }
    for (NSDictionary *account in [SSKeychain accountsForService:kServiceName]) {
        NSString *accountName = account[(NSString *)kSecAttrAccount];
        if (!accountName) {
            continue;
        }
        if (!filter ||
            [accountName rangeOfString:filter
                               options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [array addObject:accountName];
            }
    }
    return [array sortedArrayUsingSelector:@selector(compare:)];
}

+ (void)authenticateWithPolicy:(LAPolicy)policy context:(LAContext *)myContext reply:(void(^)(BOOL success, NSError * __nullable error))reply NS_AVAILABLE_MAC(10_11) {
    DLog(@"Requesting authentication with policy %@", @(policy));

    NSString *myLocalizedReasonString = @"open the password manager";
    // You're supposed to hold a reference to the context until it's done doing its thing.
    if (policy == LAPolicyDeviceOwnerAuthentication) {
        [[iTermApplication sharedApplication] setLocalAuthenticationDialogOpen:YES];
    }
    [myContext evaluatePolicy:policy
              localizedReason:myLocalizedReasonString
                        reply:^(BOOL success, NSError *error) {
                            if (policy == LAPolicyDeviceOwnerAuthentication) {
                                [[iTermApplication sharedApplication] setLocalAuthenticationDialogOpen:NO];
                            }
                            if (success) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    sAuthenticatedContext = myContext;
                                    reply(success, error);
                                });
                            } else {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    sAuthenticatedContext = nil;
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

+ (NSString *)reasonForAuthenticationError:(NSError *)error touchID:(BOOL)touchID NS_AVAILABLE_MAC(10_11) {
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

        case LAErrorTouchIDNotEnrolled:
            return @"touch ID doesn't have any fingers enrolled.";

        case LAErrorTouchIDLockout:
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

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)awakeFromNib {
    [_tableView setDoubleAction:@selector(doubleClickOnTableView:)];
    [self reloadAccounts];
    [self update];
    [_searchField setArrowHandler:_tableView];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    if (sAuthenticatedContext) {
        [[self window] makeFirstResponder:_searchField];
    }
}

// Opening this window should not cause the hotkey window to hide.
- (BOOL)autoHidesHotKeyWindow {
    return NO;
}

#pragma mark - APIs

- (void)update {
    [_enterPasswordButton setEnabled:([_tableView selectedRow] >= 0 &&
                                      [_delegate iTermPasswordManagerCanEnterPassword])];
}

- (void)selectAccountName:(NSString *)name {
    if (!name) {
        return;
    }
    NSUInteger index = [_accounts indexOfObject:name];
    if (index != NSNotFound) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index]
                byExtendingSelection:NO];
    } else if (!sAuthenticatedContext) {
        _accountNameToSelectAfterAuthentication = [name copy];
    }
}

#pragma mark - Actions

- (IBAction)closeCurrentSession:(id)sender {
    [self orderOutOrEndSheet];
}

- (void)orderOutOrEndSheet {
    if (self.window.isSheet) {
        [self.window.sheetParent endSheet:self.window];
    } else {
        [[self window] orderOut:nil];
    }
}

- (void)doubleClickOnTableView:(id)sender {
    if ([_tableView selectedRow] >= 0) {
        [self enterPassword:nil];
    }
}

- (IBAction)add:(id)sender {
    if (sAuthenticatedContext) {
        NSString *name = [self nameForNewAccount];
        if ([[self keychain] setPassword:@"" forService:kServiceName account:name context:sAuthenticatedContext error:nil]) {
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
    if (sAuthenticatedContext) {
        NSInteger selectedRow = [_tableView selectedRow];
        NSString *selectedAccountName = [self accountNameForRow:selectedRow];
        [_tableView reloadData];
        [[self keychain] deletePasswordForService:kServiceName account:selectedAccountName context:sAuthenticatedContext error:nil];
        [self reloadAccounts];
        [self passwordsDidChange];
    }
}

- (IBAction)edit:(id)sender {
    NSInteger row = _tableView.selectedRow;
    if (row >= 0) {
        __weak __typeof(self) weakSelf = self;
        [self requestPassword:^(NSString *password) {
            [weakSelf reallyEditRow:row password:password];
        }];
    }
}

- (void)reallyEditRow:(NSInteger)row password:(NSString *)password {
    if (row != _tableView.selectedRow) {
        return;
    }
    [self setPasswordBeingShown:password onRow:row];
    [_tableView editColumn:[[_tableView tableColumns] indexOfObject:_passwordColumn]
                       row:row
                 withEvent:nil
                    select:YES];
}

- (IBAction)enterPassword:(id)sender {
    DLog(@"enterPassword");
    __weak __typeof(self) weakSelf = self;
    [self requestPassword:^(NSString *password) {
        [weakSelf reallyEnterPassword:password];
    }];
}

- (void)reallyEnterPassword:(NSString *)password {
    if (password) {
        DLog(@"enterPassword: giving password to delegate");
        [_delegate iTermPasswordManagerEnterPassword:password];
        DLog(@"enterPassword: closing sheet");
        [self closeOrEndSheet];
    }
}

- (void)closeOrEndSheet {
    if (self.window.isSheet) {
        DLog(@"Ask parent to end sheet");
        [self.window.sheetParent endSheet:self.window];
    } else {
        DLog(@"Close window");
        [self.window close];
    }
}

- (IBAction)revealPassword:(id)sender {
    const NSInteger row = [_tableView selectedRow];
    if (!_passwordBeingShown && row >= 0) {
        __weak __typeof(self) weakSelf = self;
        NSString *account = [_accounts[row] copy];
        [self requestPassword:^(NSString *password) {
            [weakSelf reallyRevealPassword:password account:account row:row];
        }];
    }
}

- (void)reallyRevealPassword:(NSString *)password account:(NSString *)account row:(NSInteger)row {
    if ([_tableView selectedRow] != row) {
        return;
    }
    if (![account isEqualToString:_accounts[row]]) {
        return;
    }
    [self setPasswordBeingShown:password onRow:row];
    [_tableView reloadData];
}

- (IBAction)copyPassword:(id)sender {
    __weak __typeof(self) weakSelf = self;
    [self requestPassword:^(NSString *password) {
        if (weakSelf) {
            NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
            [pasteboard declareTypes:@[ NSStringPboardType ] owner:self];
            [pasteboard setString:password forType:NSStringPboardType];
        }
    }];
}

#pragma mark - Private

- (Class)keychain {
    if (sAuthenticatedContext) {
        return [SSKeychain class];
    } else {
        return nil;
    }
}

- (void)requestAuthenticationIfPossible {
    DLog(@"Request auth if possible");
    if (sAuthenticatedContext) {
        DLog(@"Already authenticated");
        return;
    }
    LAContext *myContext = [[LAContext alloc] init];
    [self authenticateWithPolicy:LAPolicyDeviceOwnerAuthentication context:myContext];
}

- (void)authenticateWithPolicy:(LAPolicy)policy context:(LAContext *)myContext NS_AVAILABLE_MAC(10_11) {
    __weak __typeof(self) weakSelf = self;
    [[self class] authenticateWithPolicy:policy context:myContext reply:^(BOOL success, NSError * _Nullable error) {
        [weakSelf didAuthenticateWithSuccess:success error:error];
    }];
}

- (void)didAuthenticateWithSuccess:(BOOL)success error:(NSError *)error {
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
        [self closeOrEndSheet];
    }
}

- (void)setPasswordBeingShown:(NSString *)password onRow:(NSInteger)row {
    _passwordBeingShown = password;
    _rowForPasswordBeingShown = row;
}

- (void)clearPasswordBeingShown {
    _passwordBeingShown = nil;
    _rowForPasswordBeingShown = -1;
}

- (void)requestPassword:(void (^)(NSString *password))block {
    DLog(@"selectedPassowrd");
    if (!sAuthenticatedContext) {
        DLog(@"selectedPassword: return nil, not authenticated");
        block(nil);
    }
    NSInteger index = [_tableView selectedRow];
    if (index < 0) {
        DLog(@"selectedPassowrd: return nil, negative index");
        block(nil);
    }
    NSString *account = [_accounts[index] copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSString *password = [[self keychain] passwordForService:kServiceName
                                                         account:account
                                                         context:sAuthenticatedContext
                                                           error:&error];
        if (error) {
            DLog(@"selectedPassword: return nil, keychain gave error %@", error);
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = [NSString stringWithFormat:@"Could not get password. Keychain query failed: %@", error];
                    [alert addButtonWithTitle:@"OK"];
                    [alert runModal];
                });
            });
            block(nil);
        } else {
            DLog(@"selectedPassowrd: return nonnil password");
            dispatch_async(dispatch_get_main_queue(), ^{
                block(password ?: @"");
            });
        }
    });
}

- (NSUInteger)indexOfAccountName:(NSString *)name {
    return [_accounts indexOfObject:name];
}

- (NSString *)nameForNewAccount {
    static NSString *const kNewAccountName = @"New Account";
    int number = 0;
    NSString *name = kNewAccountName;
    while ([self indexOfAccountName:name] != NSNotFound) {
        ++number;
        name = [NSString stringWithFormat:@"%@ %d", kNewAccountName, number];
    }
    return name;
}

- (NSString *)accountNameForRow:(NSInteger)rowIndex {
    return _accounts[rowIndex];
}

- (void)reloadAccounts {
    [self clearPasswordBeingShown];
    NSString *filter = [_searchField stringValue];
    if (sAuthenticatedContext) {
        _accounts = [[self class] accountNamesWithFilter:filter];
    } else {
        _accounts = @[];
    }
    [_tableView reloadData];
}

- (void)passwordsDidChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:kPasswordManagersShouldReloadData object:nil];
}


#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return [_accounts count];
}

- (id)tableView:(NSTableView *)aTableView
objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(NSInteger)rowIndex {
    if (rowIndex >= [self numberOfRowsInTableView:aTableView]) {
        // Sanity check.
        return nil;
    }

    NSString *accountName = [self accountNameForRow:rowIndex];
    if (aTableColumn == _accountNameColumn) {
        return accountName;
    } else {
        NSString *password = nil;
        if (_passwordBeingShown && [aTableView selectedRow] == rowIndex && rowIndex == _rowForPasswordBeingShown) {
            NSLog(@"Returning plaintext password because selected row %@ equals queried index %@", @(aTableView.selectedRow), @(rowIndex));
            password = _passwordBeingShown;
        }
        return password ?: @"••••••••";
    }
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex {
    if (!sAuthenticatedContext) {
        return;
    }
    if (rowIndex < 0 || rowIndex >= _accounts.count) {
        ITCriticalError(NO, @"Row index %@ out of bounds [0, %@)", @(rowIndex), @(_accounts.count));
    }
    NSString *accountName = [self accountNameForRow:rowIndex];
    if (aTableColumn == _accountNameColumn) {
        NSError *error = nil;
        NSString *password = [[self keychain] passwordForService:kServiceName
                                                         account:accountName
                                                         context:sAuthenticatedContext
                                                           error:&error];
        if (!error) {
            if (!password) {
                password = @"";
            }
            if ([[self keychain] deletePasswordForService:kServiceName account:accountName context:sAuthenticatedContext error:nil]) {
                [[self keychain] setPassword:password forService:kServiceName account:anObject context:sAuthenticatedContext error:nil];
                [self reloadAccounts];
            }
        }
    } else {
        [self clearPasswordBeingShown];
        [[self keychain] setPassword:anObject forService:kServiceName account:accountName context:sAuthenticatedContext error:nil];
    }
    [self passwordsDidChange];
}

#pragma mark - NSTableViewDelegate

- (BOOL)tableView:(NSTableView *)aTableView
shouldEditTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex {
    if (aTableColumn == _accountNameColumn) {
        return YES;
    } else {
        return (_rowForPasswordBeingShown == rowIndex && _passwordBeingShown != nil);
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [_removeButton setEnabled:([_tableView selectedRow] != -1)];
    [_editButton setEnabled:([_tableView selectedRow] != -1)];
    if (_passwordBeingShown) {
        [self clearPasswordBeingShown];
        [_tableView reloadData];
    }
    [self update];
}

- (NSCell *)tableView:(NSTableView *)tableView
dataCellForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    if (tableColumn == _accountNameColumn) {
        NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@"name"];
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
    [_tableView reloadData];
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
