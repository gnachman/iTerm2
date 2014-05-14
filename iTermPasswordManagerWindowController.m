//
//  iTermPasswordManagerWindowController.m
//  iTerm
//
//  Created by George Nachman on 5/14/14.
//
//

#import "iTermPasswordManagerWindowController.h"
#import "iTermSearchField.h"
#import "SSKeychain/SSKeychain.h"
#import <Security/Security.h>

static NSString *const kServiceName = @"iTerm2";

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
    IBOutlet NSButton *_enterPasswordButton;
    IBOutlet iTermSearchField *_searchField;
    BOOL _showPassword;
    NSArray *_accounts;
}

- (id)init {
    return [self initWithWindowNibName:@"iTermPasswordManager"];
}

- (void)dealloc {
    [_accounts release];
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

#pragma mark - Actions

- (IBAction)closeCurrentSession:(id)sender {
    [[self window] orderOut:sender];
}

- (void)doubleClickOnTableView:(id)sender {
    if (!_showPassword) {
        _showPassword = YES;
        [_tableView reloadData];
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
}

- (IBAction)remove:(id)sender {
    NSInteger selectedRow = [_tableView selectedRow];
    NSString *selectedAccountName = [self accountNameForRow:selectedRow];
    [SSKeychain deletePasswordForService:kServiceName account:selectedAccountName];
    [self reloadAccounts];
}

- (IBAction)enterPassword:(id)sender {
    NSString *password = [self selectedPassword];
    [_delegate iTermPasswordManagerEnterPassword:password];
    [[self window] close];
}

#pragma mark - Private

- (NSString *)selectedPassword {
    NSInteger index = [_tableView selectedRow];
    if (index < 0) {
        return nil;
    }
    return [SSKeychain passwordForService:kServiceName account:_accounts[index]];
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
    [_accounts release];
    NSMutableArray *array = [NSMutableArray array];
    NSString *filter = [_searchField stringValue];
    if (!filter.length) {
        filter = nil;
    }
    for (NSDictionary *account in [SSKeychain accountsForService:kServiceName]) {
        NSString *accountName = account[(NSString *)kSecAttrAccount];
        if (!filter ||
            [accountName rangeOfString:filter
                               options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [array addObject:accountName];
        }
    }
    _accounts = [[array sortedArrayUsingSelector:@selector(compare:)] retain];
    [_tableView reloadData];
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
        if (_showPassword && [aTableView selectedRow] == rowIndex) {
            NSError *error = nil;
            password = [SSKeychain passwordForService:kServiceName account:accountName error:&error];
            if (!password && error) {
                _showPassword = NO;
                [self reloadAccounts];
            } else if (!password) {
                // Empty passwords come back as nil
                password = @"";
            }
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
        [SSKeychain setPassword:anObject forService:kServiceName account:accountName];
        [aTableView reloadData];
    }
}

#pragma mark - NSTableViewDelegate

- (BOOL)tableView:(NSTableView *)aTableView
shouldEditTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex
{
    if (aTableColumn == _accountNameColumn) {
        return YES;
    } else {
        return _showPassword;
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [_removeButton setEnabled:([_tableView selectedRow] != -1)];
    if (_showPassword) {
        _showPassword = NO;
        [_tableView reloadData];
    }
    [self update];
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification {
    [_tableView reloadData];
}

#pragma mark - Search field delegate

- (void)controlTextDidChange:(NSNotification *)aNotification {
    [self reloadAccounts];
}

@end
