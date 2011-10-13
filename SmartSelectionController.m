//
//  SmartSelection.m
//  iTerm
//
//  Created by George Nachman on 9/25/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "SmartSelectionController.h"
#import "BookmarkModel.h"
#import "ITAddressBookMgr.h"

static NSString *kRegexKey = @"regex";
static NSString *kNotesKey = @"notes";
static NSString *kPrecisionKey = @"precision";

#define kVeryLowPrecision @"very_low"
#define kLowPrecision @"low"
#define kNormalPrecision @"normal"
#define kHighPrecision @"high"
#define kVeryHighPrecision @"very_high"

#define kLogDebugInfoKey @"Log Smart Selection Debug Info"

static NSString *gPrecisionKeys[] = {
    kVeryLowPrecision,
    kLowPrecision,
    kNormalPrecision,
    kHighPrecision,
    kVeryHighPrecision
};

@implementation SmartSelectionController

@synthesize guid = guid_;
@synthesize hasSelection = hasSelection_;
@synthesize delegate = delegate_;

- (void)dealloc
{
    [guid_ release];
    [super dealloc];
}

+ (NSArray *)defaultRules
{
    static NSArray *rulesArray;
    if (!rulesArray) {
        NSString* plistFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"SmartSelectionRules"
                                                                               ofType:@"plist"];
        NSDictionary* rulesDict = [NSDictionary dictionaryWithContentsOfFile:plistFile];
        rulesArray = [[rulesDict objectForKey:@"Rules"] retain];
    }
    return rulesArray;
}

+ (NSString *)regexInRule:(NSDictionary *)rule
{
    return [rule objectForKey:kRegexKey];
}

+ (double)precisionInRule:(NSDictionary *)rule
{
    static const double precisionValues[] = {
        0.00001,
        0.001,
        1.0,
        1000.0,
        1000000.0
    };
    NSString *precision = [rule objectForKey:kPrecisionKey];
    for (int i = 0; i < sizeof(gPrecisionKeys) / sizeof(NSString *); i++) {
        if ([gPrecisionKeys[i] isEqualToString:precision]) {
            return precisionValues[i];
        }
    }
    return 0;
}

- (Bookmark *)bookmark
{
    Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:self.guid];
    if (!bookmark) {
        bookmark = [[BookmarkModel sessionsInstance] bookmarkWithGuid:self.guid];
    }
    return bookmark;
}

- (BookmarkModel *)modelForBookmark:(Bookmark *)bookmark
{
    if ([[BookmarkModel sharedInstance] bookmarkWithGuid:[bookmark objectForKey:KEY_GUID]]) {
        return [BookmarkModel sharedInstance];
    } else if ([[BookmarkModel sessionsInstance] bookmarkWithGuid:[bookmark objectForKey:KEY_GUID]]) {
        return [BookmarkModel sessionsInstance];
    } else {
        return nil;
    }
}

- (NSArray *)rules
{
    Bookmark* bookmark = [self bookmark];
    NSArray *rules = [bookmark objectForKey:KEY_SMART_SELECTION_RULES];
    return rules ? rules : [SmartSelectionController defaultRules];
}

- (NSDictionary *)defaultRule
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            @"", kRegexKey,
            kVeryLowPrecision, kPrecisionKey,
            nil];
}

- (void)setRule:(NSDictionary *)rule forRow:(NSInteger)rowIndex
{
    NSMutableArray *rules = [[[self rules] mutableCopy] autorelease];
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
    Bookmark* bookmark = [self bookmark];
    [[self modelForBookmark:bookmark] setObject:rules forKey:KEY_SMART_SELECTION_RULES inBookmark:bookmark];
    [tableView_ reloadData];
    [delegate_ smartSelectionChanged:nil];
}

- (IBAction)help:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.iterm2.com/smartselection.html"]];
}

- (IBAction)addRule:(id)sender
{
    [self setRule:[self defaultRule] forRow:-1];
    [tableView_ selectRowIndexes:[NSIndexSet indexSetWithIndex:tableView_.numberOfRows - 1]
            byExtendingSelection:NO];
}

- (IBAction)removeRule:(id)sender
{
    assert(tableView_.selectedRow >= 0);
    [self setRule:nil forRow:[tableView_ selectedRow]];
}

- (IBAction)loadDefaults:(id)sender
{
    Bookmark* bookmark = [self bookmark];
    [[self modelForBookmark:bookmark] setObject:[SmartSelectionController defaultRules]
                                         forKey:KEY_SMART_SELECTION_RULES
                                     inBookmark:bookmark];
    [tableView_ reloadData];
    [delegate_ smartSelectionChanged:nil];
}

- (void)setGuid:(NSString *)guid
{
    [guid_ autorelease];
    guid_ = [guid copy];
    [tableView_ reloadData];
}

- (NSString *)displayNameForPrecision:(NSString *)precision
{
    if ([precision isEqualToString:kVeryLowPrecision]) {
        return @"Very low";
    } else if ([precision isEqualToString:kLowPrecision]) {
        return @"Low";
    } else if ([precision isEqualToString:kNormalPrecision]) {
        return @"Normal";
    } else if ([precision isEqualToString:kHighPrecision]) {
        return @"High";
    } else if ([precision isEqualToString:kVeryHighPrecision]) {
        return @"Very high";
    } else {
        return @"Undefined";
    }
}

- (int)indexForPrecision:(NSString *)precision
{
    for (int i = 0; i < sizeof(gPrecisionKeys) / sizeof(NSString *); i++) {
        if ([gPrecisionKeys[i] isEqualToString:precision]) {
            return i;
        }
    }
    return 0;
}

- (NSString *)precisionKeyWithIndex:(int)i
{
    return gPrecisionKeys[i];
}

#pragma mark NSTableViewDataSource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [[self rules] count];
}

- (id)tableView:(NSTableView *)aTableView
        objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(NSInteger)rowIndex {
    NSDictionary *rule = [[self rules] objectAtIndex:rowIndex];
    if (aTableColumn == regexColumn_) {
        return [rule objectForKey:kRegexKey];
    } else if (aTableColumn == notesColumn_) {
        return [rule objectForKey:kNotesKey];
    } else {
        NSString *precision = [rule objectForKey:kPrecisionKey];
        return [NSNumber numberWithInt:[self indexForPrecision:precision]];
    }
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn
                   *)aTableColumn
              row:(NSInteger)rowIndex
{
    NSMutableDictionary *rule = [[[[self rules] objectAtIndex:rowIndex] mutableCopy] autorelease];

    if (aTableColumn == regexColumn_) {
        [rule setObject:anObject forKey:kRegexKey];
    } else if (aTableColumn == notesColumn_) {
        [rule setObject:anObject forKey:kNotesKey];
    } else {
        [rule setObject:[self precisionKeyWithIndex:[anObject intValue]]
                    forKey:kPrecisionKey];
    }
    [self setRule:rule forRow:rowIndex];
}

#pragma mark NSTableViewDelegate
- (BOOL)tableView:(NSTableView *)aTableView
      shouldEditTableColumn:(NSTableColumn
                       *)aTableColumn
              row:(NSInteger)rowIndex
{
    if (aTableColumn == regexColumn_ ||
        aTableColumn == notesColumn_) {
        return YES;
    }
    return NO;
}

- (NSCell *)tableView:(NSTableView *)tableView
    dataCellForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row
{
    if (tableColumn == precisionColumn_) {
        NSPopUpButtonCell *cell =
            [[[NSPopUpButtonCell alloc] initTextCell:[self displayNameForPrecision:kVeryLowPrecision] pullsDown:NO] autorelease];
        for (int i = 0; i < sizeof(gPrecisionKeys) / sizeof(NSString *); i++) {
            [cell addItemWithTitle:[self displayNameForPrecision:[self precisionKeyWithIndex:i]]];
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

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    self.hasSelection = [tableView_ numberOfSelectedRows] > 0;
}

- (IBAction)logDebugInfoChanged:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:logDebugInfo_.state]
                                              forKey:kLogDebugInfoKey];
}

+ (BOOL)logDebugInfo
{
    NSNumber *n = [[NSUserDefaults standardUserDefaults] valueForKey:kLogDebugInfoKey];
    if (n) {
        return [n intValue] == NSOnState;
    } else {
        return NO;
    }
}

- (void)windowWillOpen
{
    [logDebugInfo_ setState:[SmartSelectionController logDebugInfo] ? NSOnState : NSOffState];
}

@end
