//
//  TmuxWindowsTable.m
//  iTerm
//
//  Created by George Nachman on 12/25/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import "TmuxWindowsTable.h"
#import "FutureMethods.h"

NSString *kWindowPasteboardType = @"kWindowPasteboardType";

@implementation TmuxWindowsTable {
    NSMutableArray *model_;
    NSMutableArray *filteredModel_;
    
    IBOutlet NSTableView *tableView_;
    IBOutlet NSButton *addWindowButton_;
    IBOutlet NSButton *removeWindowButton_;
    IBOutlet NSButton *openInTabsButton_;
    IBOutlet NSButton *openInWindowsButton_;
    IBOutlet NSButton *hideWindowButton_;
    IBOutlet NSSearchField *searchField_;
}

@synthesize delegate = delegate_;

- (instancetype)init {
    self = [super init];
    if (self) {
        model_ = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)awakeFromNib {
    [tableView_ setDraggingSourceOperationMask:NSDragOperationLink forLocal:NO];
    [tableView_ setTarget:self];
    [tableView_ setDoubleAction:@selector(didDoubleClickTableView:)];
}

- (void)dealloc
{
    [model_ release];
    [filteredModel_ release];
    [super dealloc];
}

- (void)setDelegate:(id<TmuxWindowsTableProtocol>)delegate {
    delegate_ = delegate;
    [delegate_ reloadWindows];
    [self updateEnabledStateOfButtons];
}

- (void)setWindows:(NSArray *)windows
{
    [model_ removeAllObjects];
    [model_ addObjectsFromArray:windows];
    [self resetFilteredModel];
    [tableView_ reloadData];
    [self updateEnabledStateOfButtons];
}

- (void)setNameOfWindowWithId:(int)wid to:(NSString *)newName
{
    for (int i = 0; i < model_.count; i++) {
        if ([[[model_ objectAtIndex:i] objectAtIndex:1] intValue] == wid) {
            NSMutableArray *tuple = [model_ objectAtIndex:i];
            [tuple replaceObjectAtIndex:0 withObject:newName];
            break;
        }
    }
    [self resetFilteredModel];
    [tableView_ reloadData];
}

- (NSArray<NSString *> *)names {
    NSMutableArray *names = [NSMutableArray array];
    for (NSArray *tuple in model_) {
        [names addObject:[tuple objectAtIndex:0]];
    }
    return names;
}

- (void)updateEnabledStateOfButtons
{
    [addWindowButton_ setEnabled:[delegate_ haveSelectedSession] && [self filteredModel].count > 0];
    [removeWindowButton_ setEnabled:[delegate_ haveSelectedSession] && [tableView_ numberOfSelectedRows] > 0];
    [openInTabsButton_ setEnabled:[delegate_ currentSessionSelected] && [tableView_ numberOfSelectedRows] > 1 && ![self anySelectedWindowIsOpen]];
    [openInWindowsButton_ setEnabled:[delegate_ currentSessionSelected] && [tableView_ numberOfSelectedRows] > 0 && ![self anySelectedWindowIsOpen]];
    if ([openInWindowsButton_ isEnabled] && [tableView_ numberOfSelectedRows] == 1) {
        [openInWindowsButton_ setTitle:@"Open in Window"];
    } else {
        [openInWindowsButton_ setTitle:@"Open in Windows"];
    }
    [hideWindowButton_ setEnabled:[tableView_ numberOfSelectedRows] > 0 && [self allSelectedWindowsAreOpen]];
}

- (void)reloadData
{
        [tableView_ reloadData];
}

#pragma mark Interface Builder actions

- (IBAction)addWindow:(id)sender
{
    [delegate_ addWindow];
}

- (IBAction)removeWindow:(id)sender
{
    for (NSNumber *wid in [self selectedWindowIds]) {
        [delegate_ unlinkWindowWithId:[wid intValue]];
    }

}

- (IBAction)showInWindows:(id)sender
{
    [delegate_ showWindowsWithIds:[self selectedWindowIdsAsStrings] inTabs:NO];
    [tableView_ reloadData];
}

- (IBAction)showInTabs:(id)sender
{
    [delegate_ showWindowsWithIds:[self selectedWindowIdsAsStrings] inTabs:YES];
    [tableView_ reloadData];
}

- (IBAction)hideWindow:(id)sender
{
    for (NSNumber *n in [self selectedWindowIds]) {
        [delegate_ hideWindowWithId:[n intValue]];
    }
    [tableView_ reloadData];
}

#pragma mark NSTableViewDelegate

- (void)tableView:(NSTableView *)tableView
  willDisplayCell:(id)cell
   forTableColumn:(NSTableColumn *)tableColumn
              row:(NSInteger)row
{
    if ([delegate_ haveOpenWindowWithId:[[[[self filteredModel] objectAtIndex:row] objectAtIndex:1] intValue]]) {
        [cell setTextColor:[[cell textColor] colorWithAlphaComponent:1]];
    } else {
        [cell setTextColor:[[cell textColor] colorWithAlphaComponent:0.5]];
    }
}

#pragma mark NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [self filteredModel].count;
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(NSInteger)rowIndex
{
    NSString *name = [[[self filteredModel] objectAtIndex:rowIndex] objectAtIndex:0];
    if (rowIndex < [self filteredModel].count) {
        return name;
    } else {
        return nil;
    }
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex
{
    [delegate_ renameWindowWithId:[[[[self filteredModel] objectAtIndex:rowIndex] objectAtIndex:1] intValue]
                           toName:anObject];
}

- (BOOL)tableView:(NSTableView *)aTableView
    shouldEditTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex {
    return YES;
}

- (void)didDoubleClickTableView:(id)sender {
    NSInteger rowIndex = tableView_.clickedRow;
    if (rowIndex >= 0) {
        [delegate_ tmuxWindowsTableDidSelectWindowWithId:[[[[self filteredModel] objectAtIndex:rowIndex] objectAtIndex:1] intValue]];
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
    [self updateEnabledStateOfButtons];
}

- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard {
    NSArray* selectedItems = [[self filteredModel] objectsAtIndexes:rowIndexes];
    [pboard declareTypes:[NSArray arrayWithObject:kWindowPasteboardType] owner:self];
    [pboard setPropertyList:[NSArray arrayWithObjects:
                             [delegate_ selectedSessionName],
                             selectedItems,
                             nil]
                    forType:kWindowPasteboardType];
    return YES;
}

#pragma mark NSSearchField delegate

- (void)controlTextDidChange:(NSNotification *)aNotification
{
    if ([aNotification object] == searchField_) {
        [self resetFilteredModel];
        [tableView_ reloadData];
    }
}

#pragma mark - Private

- (NSArray *)selectedWindowIdsAsStrings
{
        NSArray *ids = [self selectedWindowIds];
    NSMutableArray *result = [NSMutableArray array];
        for (NSString *n in ids) {
                [result addObject:n];
        }
        return result;
}

- (NSArray *)selectedWindowIds
{
    NSMutableArray *result = [NSMutableArray array];
    NSIndexSet *anIndexSet = [tableView_ selectedRowIndexes];
    NSUInteger i = [anIndexSet firstIndex];

    while (i != NSNotFound) {
        [result addObject:[[[self filteredModel] objectAtIndex:i] objectAtIndex:1]];
        i = [anIndexSet indexGreaterThanIndex:i];
    }

    return result;
}

- (NSArray *)selectedWindowNames
{
    NSMutableArray *result = [NSMutableArray array];
    NSIndexSet *anIndexSet = [tableView_ selectedRowIndexes];
    NSUInteger i = [anIndexSet firstIndex];
    
    while (i != NSNotFound) {
        [result addObject:[[[self filteredModel] objectAtIndex:i] objectAtIndex:0]];
        i = [anIndexSet indexGreaterThanIndex:i];
    }
    
    return result;
}

- (BOOL)allSelectedWindowsAreOpen
{
    for (NSNumber *n in [self selectedWindowIds]) {
        if (![delegate_ haveOpenWindowWithId:[n intValue]]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)anySelectedWindowIsOpen
{
    for (NSNumber *n in [self selectedWindowIds]) {
        if ([delegate_ haveOpenWindowWithId:[n intValue]]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)nameMatchesFilter:(NSString *)name
{
    NSString *needle = [searchField_ stringValue];
    
    return (!needle.length ||
            [name rangeOfString:needle
                        options:(NSCaseInsensitiveSearch |
                                 NSDiacriticInsensitiveSearch |
                                 NSWidthInsensitiveSearch)].location != NSNotFound);
}

- (NSArray *)filteredModel
{
    if (!filteredModel_) {
        filteredModel_ = [[NSMutableArray alloc] init];
        for (NSArray *tuple in model_) {
            if ([self nameMatchesFilter:[tuple objectAtIndex:0]]) {
                [filteredModel_ addObject:tuple];
            }
        }
    }
    return filteredModel_;
}

- (void)resetFilteredModel
{
    [filteredModel_ release];
    filteredModel_ = nil;
}

@end
