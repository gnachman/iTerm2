//
//  SmartSelection.m
//  iTerm
//
//  Created by George Nachman on 9/25/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "SmartSelectionController.h"

#import "DebugLogging.h"
#import "ProfileModel.h"
#import "iTermProfilePreferences.h"
#import "ITAddressBookMgr.h"
#import "FutureMethods.h"
#import "NSObject+iTerm.h"
#import "NSTextField+iTerm.h"

NSString *const kRegexKey = @"regex";
NSString *const kNotesKey = @"notes";
NSString *const kPrecisionKey = @"precision";
NSString *const kActionsKey = @"actions";

NSString *const kVeryLowPrecision = @"very_low";
NSString *const kLowPrecision = @"low";
NSString *const kNormalPrecision = @"normal";
NSString *const kHighPrecision = @"high";
NSString *const kVeryHighPrecision = @"very_high";

static NSString *const kLogDebugInfoKey = @"Log Smart Selection Debug Info";

static char iTermSmartSelectionControllerAssociatedObjectRowIndexKey;

@interface SmartSelectionController() <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
@end

@implementation SmartSelectionController {
    IBOutlet NSTableView *tableView_;
    IBOutlet NSTableColumn *regexColumn_;
    IBOutlet NSTableColumn *notesColumn_;
    IBOutlet NSTableColumn *precisionColumn_;
    IBOutlet ContextMenuActionPrefsController *contextMenuPrefsController_;
    IBOutlet NSButton *logDebugInfo_;
}

@synthesize guid = guid_;
@synthesize hasSelection = hasSelection_;
@synthesize delegate = delegate_;

+ (NSArray<NSString *> *)precisionKeys {
    return @[ kVeryLowPrecision,
              kLowPrecision,
              kNormalPrecision,
              kHighPrecision,
              kVeryHighPrecision ];
}

- (void)dealloc {
    tableView_.delegate = nil;
    tableView_.dataSource = nil;
}

- (void)awakeFromNib {
    [tableView_ setDoubleAction:@selector(onDoubleClick:)];
}

+ (NSArray *)defaultRules {
    static NSArray *rulesArray;
    if (!rulesArray) {
        NSString* plistFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"SmartSelectionRules"
                                                                               ofType:@"plist"];
        NSDictionary* rulesDict = [NSDictionary dictionaryWithContentsOfFile:plistFile];
        ITCriticalError(rulesDict != nil, @"Failed to parse SmartSelectionRules: %@", [NSString stringWithContentsOfFile:plistFile encoding:NSUTF8StringEncoding error:nil]);
        rulesArray = [rulesDict objectForKey:@"Rules"];
    }
    return rulesArray;
}

+ (NSArray *)actionsInRule:(NSDictionary *)rule {
    return [rule objectForKey:kActionsKey];
}

+ (NSString *)regexInRule:(NSDictionary *)rule {
    return [rule objectForKey:kRegexKey];
}

+ (double)precisionInRule:(NSDictionary *)rule {
    NSDictionary *precisionValues = @{ kVeryLowPrecision: @0.00001,
                                       kLowPrecision: @0.001,
                                       kNormalPrecision: @1.0,
                                       kHighPrecision: @1000.0,
                                       kVeryHighPrecision: @1000000.0 };

    NSString *precision = rule[kPrecisionKey];
    return [precisionValues[precision] doubleValue];
}

- (void)onDoubleClick:(id)sender {
    [self editActions:sender];
}

- (Profile *)bookmark {
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:self.guid];
    if (!bookmark) {
        bookmark = [[ProfileModel sessionsInstance] bookmarkWithGuid:self.guid];
    }
    return bookmark;
}

- (ProfileModel *)modelForBookmark:(Profile *)bookmark {
    if ([[ProfileModel sharedInstance] bookmarkWithGuid:[bookmark objectForKey:KEY_GUID]]) {
        return [ProfileModel sharedInstance];
    } else if ([[ProfileModel sessionsInstance] bookmarkWithGuid:[bookmark objectForKey:KEY_GUID]]) {
        return [ProfileModel sessionsInstance];
    } else {
        return nil;
    }
}

- (NSArray<NSDictionary *> *)rules {
    Profile *bookmark = [self bookmark];
    NSArray<NSDictionary *> *rules = [bookmark objectForKey:KEY_SMART_SELECTION_RULES];
    return rules ? rules : [SmartSelectionController defaultRules];
}

- (NSDictionary *)defaultRule {
    return @{ kRegexKey: @"",
              kPrecisionKey: kVeryLowPrecision };
}

- (void)setRule:(NSDictionary *)rule forRow:(NSInteger)rowIndex {
    NSMutableArray *rules = [self.rules mutableCopy];
    if (rowIndex < 0) {
        assert(rule);
        [rules addObject:rule];
    } else {
        if (rule) {
            [rules replaceObjectAtIndex:rowIndex withObject:rule];
        } else {
            [rules removeObjectAtIndex:rowIndex];
        }
    }
    Profile* bookmark = [self bookmark];
    [[self modelForBookmark:bookmark] setObject:rules forKey:KEY_SMART_SELECTION_RULES inBookmark:bookmark];
    [self reloadData];
    // This must flush user defaults for setUseInterpolatedStrings to work.
    [delegate_ smartSelectionChanged:nil];
}

- (IBAction)help:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.iterm2.com/smartselection.html"]];
}

- (IBAction)addRule:(id)sender {
    [self setRule:[self defaultRule] forRow:-1];
    [tableView_ selectRowIndexes:[NSIndexSet indexSetWithIndex:tableView_.numberOfRows - 1]
            byExtendingSelection:NO];
}

- (IBAction)removeRule:(id)sender {
    assert(tableView_.selectedRow >= 0);
    const NSInteger row = tableView_.selectedRow;
    if (row < 0) {
        return;
    }
    [self reloadData];
    [self setRule:nil forRow:row];
}

- (IBAction)loadDefaults:(id)sender {
    Profile *bookmark = [self bookmark];
    [[self modelForBookmark:bookmark] setObject:[SmartSelectionController defaultRules]
                                         forKey:KEY_SMART_SELECTION_RULES
                                     inBookmark:bookmark];
    [self reloadData];
    [delegate_ smartSelectionChanged:nil];
}

- (void)setGuid:(NSString *)guid {
    guid_ = [guid copy];
    [self reloadData];
}

- (NSString *)displayNameForPrecision:(NSString *)precision {
    NSDictionary *names = @{ kVeryLowPrecision: @"Very Low",
                             kLowPrecision: @"Low",
                             kNormalPrecision: @"Normal",
                             kHighPrecision: @"High",
                             kVeryHighPrecision: @"Very High" };
    return names[precision] ?: @"Undefined";
}

- (int)indexForPrecision:(NSString *)precision {
    NSUInteger index = [[SmartSelectionController precisionKeys] indexOfObject:precision];
    if (index == NSNotFound) {
        return 0;
    } else {
        return index;
    }
}

- (NSString *)precisionKeyWithIndex:(int)i {
    return [[SmartSelectionController precisionKeys] objectAtIndex:i];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    DLog(@"Reporting number of rows: %@", @(self.rules.count));
    DLog(@"%@", [NSThread callStackSymbols]);
    return self.rules.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    NSArray<NSDictionary *> *rules = self.rules;
    if (rowIndex < 0 || rowIndex >= rules.count) {
        DLog(@"Asked for row %@ out of %@", @(rowIndex), rules);
        return [self tableViewCellWithString:@"BUG"
                                 placeholder:nil
                                   tableView:tableView
                                         row:rowIndex
                                  identifier:@"bug"
                                  fixedPitch:NO];
    }
    NSDictionary *rule = rules[rowIndex];
    if (aTableColumn == regexColumn_) {
        return [self tableViewCellWithString:rule[kRegexKey]
                                 placeholder:@"Enter Regular Expression"
                                   tableView:tableView
                                         row:rowIndex
                                  identifier:kRegexKey
                                  fixedPitch:YES];
    } else if (aTableColumn == notesColumn_) {
        return [self tableViewCellWithString:rule[kNotesKey]
                                 placeholder:@"Enter Description"
                                   tableView:tableView
                                         row:rowIndex
                                  identifier:kNotesKey
                                  fixedPitch:NO];
    } else {
        NSString *precision = rule[kPrecisionKey];
        return [self tableViewPrecisionMenuWithSelectedIndex:[self indexForPrecision:precision]
                                                         row:rowIndex
                                                   tableView:tableView];
    }
}

- (NSView *)tableViewCellWithString:(NSString *)string
                        placeholder:(NSString *)placeholder
                          tableView:(NSTableView *)tableView
                                row:(NSInteger)rowIndex
                         identifier:(NSString *)identifier
                         fixedPitch:(BOOL)fixedPitch {
    NSTableCellView *view = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!view) {
        view = [[NSTableCellView alloc] init];

        NSTextField *textField = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        textField.placeholderString = placeholder;
        textField.delegate = self;
        textField.editable = YES;
        textField.selectable = YES;
        textField.textColor = [NSColor labelColor];
        textField.usesSingleLineMode = YES;
        if (fixedPitch) {
            textField.font = [NSFont userFixedPitchFontOfSize:[NSFont systemFontSize]];
        } else {
            textField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        }
        textField.continuous = YES;
        [textField it_setAssociatedObject:@(rowIndex) forKey:&iTermSmartSelectionControllerAssociatedObjectRowIndexKey];
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
        view.textField = textField;
        [view addSubview:textField];
        textField.frame = view.bounds;
        textField.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
    }
    view.textField.stringValue = string ?: @"";
    return view;
}

- (NSView *)tableViewPrecisionMenuWithSelectedIndex:(NSInteger)index
                                                row:(NSInteger)row
                                          tableView:(NSTableView *)tableView {
    NSPopUpButton *button = [tableView makeViewWithIdentifier:@"SmartSelectionControllerPrecision" owner:self];
    if (!button) {
        button = [[NSPopUpButton alloc] init];
        [button it_setAssociatedObject:@(row) forKey:&iTermSmartSelectionControllerAssociatedObjectRowIndexKey];
        [button setTarget:self];
        [button setAction:@selector(changePrecision:)];
        button.identifier = @"precision";
        button.bordered = NO;
        [button.menu removeAllItems];
        for (NSString *precisionKey in [SmartSelectionController precisionKeys]) {
            [button addItemWithTitle:[self displayNameForPrecision:precisionKey]];
        }
        [button sizeToFit];
    }
    [button selectItemAtIndex:index];

    return button;
}

- (void)changePrecision:(NSPopUpButton *)sender {
    const NSInteger rowIndex = [[sender it_associatedObjectForKey:&iTermSmartSelectionControllerAssociatedObjectRowIndexKey] integerValue];
    const NSInteger index = sender.indexOfSelectedItem;
    NSMutableDictionary *rule = [self.rules[rowIndex] mutableCopy];
    rule[kPrecisionKey] = [self precisionKeyWithIndex:index];
    [self setRule:rule forRow:rowIndex];
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateHasSelection];
}

- (void)reloadData {
    [tableView_ reloadData];
    [self updateHasSelection];
}

- (void)updateHasSelection {
    self.hasSelection = [tableView_ numberOfSelectedRows] > 0;
}

- (IBAction)logDebugInfoChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:logDebugInfo_.state]
                                              forKey:kLogDebugInfoKey];
}

+ (BOOL)logDebugInfo {
    NSNumber *n = [[NSUserDefaults standardUserDefaults] valueForKey:kLogDebugInfoKey];
    if (n) {
        return [n intValue] == NSControlStateValueOn;
    } else {
        return NO;
    }
}

- (IBAction)editActions:(id)sender {
    const NSInteger row = [tableView_ selectedRow];
    if (row < 0 || row >= self.rules.count) {
        return;
    }
    NSDictionary *rule = [self.rules objectAtIndex:row];
    if (!rule) {
        return;
    }
    NSArray *actions = [SmartSelectionController actionsInRule:rule];
    [contextMenuPrefsController_ setActions:actions];
    contextMenuPrefsController_.useInterpolatedStrings = [self useInterpolatedStrings];
    [contextMenuPrefsController_ window];
    [contextMenuPrefsController_ setDelegate:self];
    __weak __typeof(self) weakSelf = self;
    [self.window beginSheet:contextMenuPrefsController_.window completionHandler:^(NSModalResponse returnCode) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf->contextMenuPrefsController_.window close];
        }
    }];
}

- (void)windowWillOpen {
    [logDebugInfo_ setState:[SmartSelectionController logDebugInfo] ? NSControlStateValueOn : NSControlStateValueOff];
}

#pragma mark - Context Menu Actions Delegate

- (void)contextMenuActionsChanged:(NSArray *)newActions useInterpolatedStrings:(BOOL)useInterpolatedStrings {
    int rowIndex = [tableView_ selectedRow];
    NSMutableDictionary *rule = [[self.rules objectAtIndex:rowIndex] mutableCopy];
    [rule setObject:newActions forKey:kActionsKey];
    [self setUseInterpolatedStrings:useInterpolatedStrings];
    // This call flushes user defaults, which setUseInterpolatedStrings: needs.
    [self setRule:rule forRow:rowIndex];
    [contextMenuPrefsController_.window.sheetParent endSheet:contextMenuPrefsController_.window];
}

- (void)setUseInterpolatedStrings:(BOOL)useInterpolatedStrings {
    // Note: this assumes the caller will flush to user defaults.
    Profile *profile = [self bookmark];
    [[self modelForBookmark:profile] setObject:@(useInterpolatedStrings)
                                        forKey:KEY_SMART_SELECTION_ACTIONS_USE_INTERPOLATED_STRINGS
                                    inBookmark:profile];
}

- (BOOL)useInterpolatedStrings {
    return [iTermProfilePreferences boolForKey:KEY_SMART_SELECTION_ACTIONS_USE_INTERPOLATED_STRINGS
                                     inProfile:self.bookmark];
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    NSTextField *textField = obj.object;
    const NSInteger rowIndex = [[textField it_associatedObjectForKey:&iTermSmartSelectionControllerAssociatedObjectRowIndexKey] integerValue];
    NSMutableDictionary *rule = [self.rules[rowIndex] mutableCopy];
    if ([textField.identifier isEqualToString:kNotesKey]) {
        rule[kNotesKey] = textField.stringValue;
    } else if ([textField.identifier isEqualToString:kRegexKey]) {
        rule[kRegexKey] = textField.stringValue;
    }
    [self setRule:rule forRow:rowIndex];
}

@end
