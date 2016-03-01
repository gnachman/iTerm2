//
//  SmartSelection.m
//  iTerm
//
//  Created by George Nachman on 9/25/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "SmartSelectionController.h"
#import "ProfileModel.h"
#import "ITAddressBookMgr.h"
#import "FutureMethods.h"

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
    [guid_ release];
    [super dealloc];
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
        rulesArray = [[rulesDict objectForKey:@"Rules"] retain];
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
    NSMutableArray *rules = [[self.rules mutableCopy] autorelease];
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
    [tableView_ reloadData];
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
    [self setRule:nil forRow:[tableView_ selectedRow]];
}

- (IBAction)loadDefaults:(id)sender {
    Profile *bookmark = [self bookmark];
    [[self modelForBookmark:bookmark] setObject:[SmartSelectionController defaultRules]
                                         forKey:KEY_SMART_SELECTION_RULES
                                     inBookmark:bookmark];
    [tableView_ reloadData];
    [delegate_ smartSelectionChanged:nil];
}

- (void)setGuid:(NSString *)guid {
    [guid_ autorelease];
    guid_ = [guid copy];
    [tableView_ reloadData];
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
    return self.rules.count;
}

- (id)tableView:(NSTableView *)aTableView
        objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(NSInteger)rowIndex {
    NSDictionary *rule = self.rules[rowIndex];
    if (aTableColumn == regexColumn_) {
        return rule[kRegexKey];
    } else if (aTableColumn == notesColumn_) {
        return rule[kNotesKey];
    } else {
        NSString *precision = rule[kPrecisionKey];
        return @([self indexForPrecision:precision]);
    }
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn
                   *)aTableColumn
              row:(NSInteger)rowIndex {
    NSMutableDictionary *rule = [[self.rules[rowIndex] mutableCopy] autorelease];

    if (aTableColumn == regexColumn_) {
        rule[kRegexKey] = anObject;
    } else if (aTableColumn == notesColumn_) {
        rule[kNotesKey] = anObject;
    } else {
        rule[kPrecisionKey] = [self precisionKeyWithIndex:[anObject intValue]];
    }
    [self setRule:rule forRow:rowIndex];
}

#pragma mark - NSTableViewDelegate

- (BOOL)tableView:(NSTableView *)aTableView
      shouldEditTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex {
    if (aTableColumn == regexColumn_ ||
        aTableColumn == notesColumn_) {
        return YES;
    }
    return NO;
}

- (NSCell *)tableView:(NSTableView *)tableView
    dataCellForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    if (tableColumn == precisionColumn_) {
        NSPopUpButtonCell *cell =
            [[[NSPopUpButtonCell alloc] initTextCell:[self displayNameForPrecision:kVeryLowPrecision] pullsDown:NO] autorelease];
        for (NSString *precisionKey in [SmartSelectionController precisionKeys]) {
            [cell addItemWithTitle:[self displayNameForPrecision:precisionKey]];
        }

        [cell setBordered:NO];

        return cell;
    } else if (tableColumn == regexColumn_) {
        NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:@"regex"] autorelease];
        [cell setPlaceholderString:@"Enter Regular Expression"];
        [cell setEditable:YES];
        [cell setTruncatesLastVisibleLine:YES];
        [cell setLineBreakMode:NSLineBreakByTruncatingTail];

        return cell;
    } else if (tableColumn == notesColumn_) {
        NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:@"notes"] autorelease];
        [cell setPlaceholderString:@"Enter Description"];
        [cell setTruncatesLastVisibleLine:YES];
        [cell setLineBreakMode:NSLineBreakByTruncatingTail];
        [cell setEditable:YES];
        return cell;
    }
    return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    self.hasSelection = [tableView_ numberOfSelectedRows] > 0;
}

- (IBAction)logDebugInfoChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:logDebugInfo_.state]
                                              forKey:kLogDebugInfoKey];
}

+ (BOOL)logDebugInfo {
    NSNumber *n = [[NSUserDefaults standardUserDefaults] valueForKey:kLogDebugInfoKey];
    if (n) {
        return [n intValue] == NSOnState;
    } else {
        return NO;
    }
}

- (IBAction)editActions:(id)sender {
    NSDictionary *rule = [self.rules objectAtIndex:[tableView_ selectedRow]];
    NSArray *actions = [SmartSelectionController actionsInRule:rule];
    [contextMenuPrefsController_ setActions:actions];
    [contextMenuPrefsController_ window];
    [contextMenuPrefsController_ setDelegate:self];
    [NSApp beginSheet:[contextMenuPrefsController_ window]
        modalForWindow:[self window]
        modalDelegate:self
        didEndSelector:@selector(closeSheet:returnCode:contextInfo:)
        contextInfo:nil];
}

- (void)closeSheet:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
    [sheet close];
}

- (void)windowWillOpen {
    [logDebugInfo_ setState:[SmartSelectionController logDebugInfo] ? NSOnState : NSOffState];
}

#pragma mark - Context Menu Actions Delegate

- (void)contextMenuActionsChanged:(NSArray *)newActions {
    int rowIndex = [tableView_ selectedRow];
    NSMutableDictionary *rule = [[[self.rules objectAtIndex:rowIndex] mutableCopy] autorelease];
    [rule setObject:newActions forKey:kActionsKey];
    [self setRule:rule forRow:rowIndex];
    [NSApp endSheet:[contextMenuPrefsController_ window]];
}

@end
