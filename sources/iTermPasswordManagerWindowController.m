//
//  iTermPasswordManagerWindowController.m
//  iTerm
//
//  Created by George Nachman on 5/14/14.
//
//

#import "iTermPasswordManagerWindowController.h"
#import "iTermSearchField.h"
#import <SSKeychain.h>
#import <Security/Security.h>

static NSString *const kServiceName = @"iTerm2";
static NSString *const kPasswordManagersShouldReloadData = @"kPasswordManagersShouldReloadData";

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
}

+ (NSArray *)accountNamesWithFilter:(NSString *)filter {
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
    return [[array sortedArrayUsingSelector:@selector(compare:)] retain];
}

- (instancetype)init {
    self = [self initWithWindowNibName:@"iTermPasswordManager"];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reloadAccounts)
                                                     name:kPasswordManagersShouldReloadData
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [_accounts release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)awakeFromNib {
    [_tableView setDoubleAction:@selector(doubleClickOnTableView:)];
    [self reloadAccounts];
    [self update];
    [_searchField setArrowHandler:_tableView];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [[self window] makeFirstResponder:_searchField];
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
    }
}

#pragma mark - Actions

- (IBAction)closeCurrentSession:(id)sender {
    [self orderOutOrEndSheet];
}

- (void)orderOutOrEndSheet {
    if (self.window.isSheet) {
        [NSApp endSheet:self.window];
    } else {
        [[self window] orderOut:nil];
    }
}

- (void)doubleClickOnTableView:(id)sender {
    if ([_tableView clickedColumn] == 1) {
        if (!_passwordBeingShown && [_tableView selectedRow] >= 0) {
            [self setPasswordBeingShown:[self selectedPassword] onRow:[_tableView selectedRow]];
            [_tableView reloadData];
        }
    } else if ([_tableView selectedRow] >= 0) {
        [self enterPassword:nil];
    }
}

- (IBAction)add:(id)sender {
    NSString *name = [self nameForNewAccount];
    if ([SSKeychain setPassword:@"" forService:kServiceName account:name]) {
        [self reloadAccounts];
        NSUInteger index = [self indexOfAccountName:name];
        if (index != NSNotFound) {
            [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
        }
    }
    [self passwordsDidChange];
}

- (IBAction)remove:(id)sender {
    NSInteger selectedRow = [_tableView selectedRow];
    NSString *selectedAccountName = [self accountNameForRow:selectedRow];
    [SSKeychain deletePasswordForService:kServiceName account:selectedAccountName];
    [self reloadAccounts];
    [self passwordsDidChange];
}

- (IBAction)edit:(id)sender {
    if ([_tableView selectedRow] >= 0) {
        [_tableView editColumn:[[_tableView tableColumns] indexOfObject:_passwordColumn]
                           row:[_tableView selectedRow]
                     withEvent:nil
                        select:YES];
    }
}

- (IBAction)enterPassword:(id)sender {
    NSString *password = [self selectedPassword];
    if (password) {
        [_delegate iTermPasswordManagerEnterPassword:password];
        [self closeOrEndSheet];
    }
}

- (void)closeOrEndSheet {
    if (self.window.isSheet) {
        [NSApp endSheet:self.window];
    } else {
        [self.window close];
    }
}

#pragma mark - Private

- (void)setPasswordBeingShown:(NSString *)password onRow:(NSInteger)row {
    [_passwordBeingShown release];
    _passwordBeingShown = [password retain];
    _rowForPasswordBeingShown = row;
}

- (void)clearPasswordBeingShown {
    [_passwordBeingShown release];
    _passwordBeingShown = nil;
    _rowForPasswordBeingShown = -1;
}

- (NSString *)selectedPassword {
    NSInteger index = [_tableView selectedRow];
    if (index < 0) {
        return nil;
    }
    NSError *error = nil;
    NSString *password = [SSKeychain passwordForService:kServiceName
                                                account:_accounts[index]
                                                  error:&error];
    if (error) {
        return nil;
    } else {
        return password ?: @"";
    }
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
    [_accounts release];
    NSString *filter = [_searchField stringValue];
    _accounts = [[self class] accountNamesWithFilter:filter];
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
        if (_passwordBeingShown && [aTableView selectedRow] == rowIndex) {
            password = _passwordBeingShown;
        }
        return password ?: @"••••••••";
    }
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex {
    NSString *accountName = [self accountNameForRow:rowIndex];
    if (aTableColumn == _accountNameColumn) {
        NSError *error = nil;
        NSString *password = [SSKeychain passwordForService:kServiceName
                                                    account:accountName
                                                      error:&error];
        if (!error) {
            if (!password) {
                password = @"";
            }
            if ([SSKeychain deletePasswordForService:kServiceName account:accountName]) {
                [SSKeychain setPassword:password forService:kServiceName account:anObject];
                [self reloadAccounts];
            }
        }
    } else {
        [self clearPasswordBeingShown];
        [SSKeychain setPassword:anObject forService:kServiceName account:accountName];
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
        NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:@"name"] autorelease];
        [cell setEditable:YES];
        return cell;
    } else if (tableColumn == _passwordColumn) {
        if ([_tableView editedRow] == row) {
            NSSecureTextFieldCell *cell = [[[NSSecureTextFieldCell alloc] initTextCell:@"editPassword"] autorelease];
            [cell setEditable:YES];
            [cell setEchosBullets:YES];
            return cell;
        } else {
            NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:@"password"] autorelease];
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
