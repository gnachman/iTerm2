//
//  iTermAPIPermissionsWindowController.m
//  iTerm2
//
//  Created by George Nachman on 09/03/19.
//

#import "iTermAPIPermissionsWindowController.h"
#import "iTermAPIAuthorizationController.h"
#import "iTermTuple.h"
#import "NSArray+iTerm.h"
#import "NSTextField+iTerm.h"

@interface iTermAPIPermissionsWindowController ()<NSTableViewDataSource, NSTableViewDelegate>

@end

@implementation iTermAPIPermissionsWindowController {
    IBOutlet NSTableView *_tableView;
    IBOutlet NSButton *_removeButton;
    // (key, human readable name) sorted by second object.
    NSArray<iTermTuple<NSString *, NSString *> *> *_entries;
}

- (void)awakeFromNib {
    _removeButton.enabled = NO;
    [self modelDidChange];
    __weak __typeof(self) weakSelf = self;
    [iTermAPIAuthorizationDidChange subscribe:self block:^(iTermBaseNotification * _Nonnull notification) {
        [weakSelf modelDidChange];
    }];
}

- (void)modelDidChange {
    [self reload];
    [_tableView reloadData];
}

- (void)reload {
    NSDictionary<NSString *, NSString *> *dict = [iTermAPIAuthorizationController keyToHumanReadableNameForAllowedPrograms];
    _entries = [[dict.allKeys mapWithBlock:^id(NSString *key) {
        return [iTermTuple tupleWithObject:key andObject:dict[key]];
    }] sortedArrayUsingComparator:^NSComparisonResult(iTermTuple<NSString *, NSString *> * _Nonnull obj1, iTermTuple<NSString *, NSString *> * _Nonnull obj2) {
        return [obj1.secondObject localizedCaseInsensitiveCompare:obj2.secondObject];
    }];
}

#pragma mark - Action

- (IBAction)remove:(id)sender {
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= _entries.count) {
        return;
    }
    NSString *key = _entries[row].firstObject;
    [iTermAPIAuthorizationController resetAccessForKey:key];
    if (_tableView.selectedRow < 0) {
        _removeButton.enabled = NO;
    }
}

- (IBAction)ok:(id)sender {
    [self.window.sheetParent endSheet:self.window];
}

- (IBAction)removeAll:(id)sender {
    [iTermAPIAuthorizationController resetPermissions];
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = _tableView.selectedRow;
    _removeButton.enabled = (row >= 0);
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _entries.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    static NSString *const identifier = @"APIPermissionsTable";
    NSTextField *result = [tableView makeViewWithIdentifier:identifier owner:self];
    if (result == nil) {
        result = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        result.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    }

    if (tableColumn == tableView.tableColumns[0]) {
        result.stringValue = _entries[row].secondObject;
        return result;
    }

    NSString *key = _entries[row].firstObject;
    const BOOL allowed = [iTermAPIAuthorizationController settingForKey:key];
    if (allowed) {
        result.stringValue = @"Allowed";
    } else {
        result.stringValue = @"Denied";
    }
    return result;
}

@end
