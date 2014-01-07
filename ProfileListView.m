/*
 **  ProfileListView.m
 **  iTerm
 **
 **  Created by George Nachman on 8/26/10.
 **  Project: iTerm
 **
 **  Description: Custom view that shows a search field and table of profiles
 **    and integrates them.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 */

#import "ProfileListView.h"
#import "ITAddressBookMgr.h"
#import "PTYSession.h"
#import "ProfileModel.h"
#import "ProfileModelWrapper.h"
#import "ProfileTableRow.h"
#import "ProfileTableView.h"
#import "ProfileTagsView.h"
#import "iTermSearchField.h"
#import "NSView+RecursiveDescription.h"

#define kProfileTableViewDataType @"iTerm2ProfileGuid"

const int kSearchWidgetHeight = 22;
const int kInterWidgetMargin = 10;
const CGFloat kTagsViewWidth = 0;  // TODO: remember this for each superview
const CGFloat kDefaultTagsWidth = 80;

@interface ProfileListView () <ProfileTagsViewDelegate>
- (NSDictionary *)rowOrder;
- (void)syncTableViewsWithSelectedGuids:(NSArray *)guids;
@end

@implementation ProfileListView {
    BOOL tagsViewIsCollapsed_;
}

- (id)initWithFrame:(NSRect)frameRect
{
    return [self initWithFrame:frameRect model:[ProfileModel sharedInstance]];
}

// This is the designated initializer.
- (id)initWithFrame:(NSRect)frameRect model:(ProfileModel*)dataSource
{
    self = [super initWithFrame:frameRect];
    if (self) {
        margin_ = kInterWidgetMargin;
        [self setUnderlyingDatasource:dataSource];
        debug = NO;
        
        NSRect frame = [self frame];
        NSRect searchFieldFrame;
        searchFieldFrame.origin.x = 0;
        searchFieldFrame.origin.y = frame.size.height - kSearchWidgetHeight;
        searchFieldFrame.size.height = kSearchWidgetHeight;
        searchFieldFrame.size.width = frame.size.width;
        searchField_ = [[iTermSearchField alloc] initWithFrame:searchFieldFrame];
        [self _addTags:[[dataSource_ underlyingModel] allTags] toSearchField:searchField_];
        [searchField_ setDelegate:self];
        [self addSubview:searchField_];
        delegate_ = nil;
        
        // Split view ------------------------------------------------------------------------------
        NSRect splitViewFrame = NSMakeRect(0,
                                           0,
                                           frame.size.width,
                                           frame.size.height - kSearchWidgetHeight - margin_);
        splitView_ = [[[NSSplitView alloc] initWithFrame:splitViewFrame] autorelease];
        splitView_.vertical = YES;
        splitView_.autoresizesSubviews = NO;
        splitView_.delegate = self;
        [self addSubview:splitView_];
        
        // Scroll view -----------------------------------------------------------------------------
        NSRect scrollViewFrame;
        scrollViewFrame.origin.x = kTagsViewWidth + kInterWidgetMargin;
        scrollViewFrame.origin.y = 0;
        scrollViewFrame.size.width = frame.size.width - scrollViewFrame.origin.x;
        scrollViewFrame.size.height = splitViewFrame.size.height;
        scrollView_ = [[NSScrollView alloc] initWithFrame:scrollViewFrame];
        [scrollView_ setHasVerticalScroller:YES];
        
        // Table view ------------------------------------------------------------------------------
        NSRect tableViewFrame;
        tableViewFrame.origin.x = 0;
        tableViewFrame.origin.y = 0;
        tableViewFrame.size =
            [NSScrollView contentSizeForFrameSize:scrollViewFrame.size
                            hasHorizontalScroller:NO
                              hasVerticalScroller:YES
                                       borderType:[scrollView_ borderType]];
        
        tableView_ = [[ProfileTableView alloc] initWithFrame:tableViewFrame];
        [tableView_ setMenuHandler:self];
        [tableView_ registerForDraggedTypes:[NSArray arrayWithObject:kProfileTableViewDataType]];
        normalRowHeight_ = 21;
        rowHeightWithTags_ = 29;
        [tableView_ setRowHeight:rowHeightWithTags_];
        [tableView_
         setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
        [tableView_ setAllowsColumnResizing:YES];
        [tableView_ setAllowsColumnReordering:YES];
        [tableView_ setAllowsColumnSelection:NO];
        [tableView_ setAllowsEmptySelection:YES];
        [tableView_ setAllowsMultipleSelection:NO];
        [tableView_ setAllowsTypeSelect:NO];
        [tableView_ setBackgroundColor:[NSColor whiteColor]];
        
        tableColumn_ =
            [[NSTableColumn alloc] initWithIdentifier:@"name"];
        [tableColumn_ setEditable:NO];
        [tableView_ addTableColumn:tableColumn_];
        
        [scrollView_ setDocumentView:tableView_];
        
        [tableView_ setDelegate:self];
        [tableView_ setDataSource:self];
        selectedGuids_ = [[NSMutableSet alloc] init];
        
        [tableView_ setDoubleAction:@selector(onDoubleClick:)];
        
        NSTableHeaderView* header = [[[NSTableHeaderView alloc] init] autorelease];
        [tableView_ setHeaderView:header];
        [[tableColumn_ headerCell] setStringValue:@"Profile Name"];
        
        [tableView_ sizeLastColumnToFit];
        
        [searchField_ setArrowHandler:tableView_];
        
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(dataChangeNotification:)
                                                     name: @"iTermReloadAddressBook"
                                                   object: nil];
        
        // Tags view -------------------------------------------------------------------------------
        NSRect tagsViewFrame = NSMakeRect(0, 0, kTagsViewWidth, splitViewFrame.size.height);
        lastTagsWidth_ = kDefaultTagsWidth;
        tagsViewIsCollapsed_ = (tagsView_.frame.size.width == 0);
        tagsView_ = [[[ProfileTagsView alloc] initWithFrame:tagsViewFrame] autorelease];
        tagsView_.delegate = self;
        [splitView_ addSubview:tagsView_];
        [splitView_ addSubview:scrollView_];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [dataSource_ release];
    [selectedGuids_ release];
    [super dealloc];
}

- (void)focusSearchField
{
    [[self window] makeFirstResponder:searchField_];
}

- (BOOL)searchFieldHasText
{
    return [[searchField_ stringValue] length] > 0;
}

// Drag drop -------------------------------
- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
    // Copy guid to pboard
    NSInteger rowIndex = [rowIndexes firstIndex];
    NSMutableSet* guids = [[[NSMutableSet alloc] init] autorelease];
    while (rowIndex != NSNotFound) {
        Profile* profile = [dataSource_ profileAtIndex:rowIndex];
        NSString* guid = [profile objectForKey:KEY_GUID];
        [guids addObject:guid];
        rowIndex = [rowIndexes indexGreaterThanIndex:rowIndex];
    }

    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:guids];
    [pboard declareTypes:[NSArray arrayWithObject:kProfileTableViewDataType] owner:self];
    [pboard setData:data forType:kProfileTableViewDataType];
    return YES;
}

- (NSDragOperation)tableView:(NSTableView *)aTableView validateDrop:(id < NSDraggingInfo >)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
    if ([info draggingSource] != aTableView) {
        return NSDragOperationNone;
    }

    // Add code here to validate the drop
    switch (operation) {
        case NSTableViewDropOn:
            return NSDragOperationNone;

        case NSTableViewDropAbove:
            return NSDragOperationMove;

        default:
            return NSDragOperationNone;
    }
}

- (BOOL)tableView:(NSTableView *)aTableView
       acceptDrop:(id <NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation
{
    [[self undoManager] registerUndoWithTarget:self
                                      selector:@selector(setRowOrder:)
                                        object:[self rowOrder]];
    NSPasteboard* pboard = [info draggingPasteboard];
    NSData* rowData = [pboard dataForType:kProfileTableViewDataType];
    NSSet* guids = [NSKeyedUnarchiver unarchiveObjectWithData:rowData];
    NSMutableDictionary* map = [[[NSMutableDictionary alloc] init] autorelease];

    for (NSString* guid in guids) {
        [map setObject:guid forKey:[NSNumber numberWithInt:[dataSource_ indexOfProfileWithGuid:guid]]];
    }
    NSArray* sortedIndexes = [map allKeys];
    sortedIndexes = [sortedIndexes sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber* mapIndex in sortedIndexes) {
        NSString* guid = [map objectForKey:mapIndex];

        [dataSource_ moveBookmarkWithGuid:guid toIndex:row];
        row = [dataSource_ indexOfProfileWithGuid:guid] + 1;
    }

    // Save the (perhaps partial) order of the current view in the underlying
    // model.
    [dataSource_ pushOrderToUnderlyingModel];

    // Remove the sorting order so that our change is not lost when data is
    // reloaded. This will cause a sync so it must be done after pushing the
    // local ordering to the underlying model.
    if ([[tableView_ sortDescriptors] count] > 0) {
        [tableView_ setSortDescriptors:[NSArray arrayWithObjects:nil]];
    }

    // The underlying model doesn't post a change notification for each bookmark
    // move because it would be overwhelming so we must do it ourselves. This
    // makes all other table views sync with the new order. First, add commands
    // to rebuild the menus.
    [self syncTableViewsWithSelectedGuids:[guids allObjects]];
    return YES;
}

- (void)syncTableViewsWithSelectedGuids:(NSArray *)guids
{
    [[dataSource_ underlyingModel] rebuildMenus];
    [[dataSource_ underlyingModel] postChangeNotification];

    NSMutableIndexSet* newIndexes = [[[NSMutableIndexSet alloc] init] autorelease];
    for (NSString* guid in guids) {
        int row = [dataSource_ indexOfProfileWithGuid:guid];
        [newIndexes addIndex:row];
    }
    [tableView_ selectRowIndexes:newIndexes byExtendingSelection:NO];

    [self reloadData];
}

// End Drag drop -------------------------------

- (void)_addTag:(id)sender
{
    int itemTag = [sender tag];
    NSArray* allTags = [[[dataSource_ underlyingModel] allTags] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSString* tag = [allTags objectAtIndex:itemTag];

    [searchField_ setStringValue:[[NSString stringWithFormat:@"%@ %@",
                                   [[searchField_ stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]],
                                   tag] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    [self controlTextDidChange:nil];
}

- (void)_addTags:(NSArray*)tags toSearchField:(NSSearchField*)searchField
{
    NSMenu *cellMenu = [[[NSMenu alloc] initWithTitle:@"Search Menu"]
                        autorelease];
    NSMenuItem *item;

    item = [[[NSMenuItem alloc] initWithTitle:@"Tags"
                                       action:nil
                                keyEquivalent:@""] autorelease];
    [item setTarget:self];
    [item setTag:-1];
    [cellMenu insertItem:item atIndex:0];

    NSArray* sortedTags = [tags sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (int i = 0; i < [sortedTags count]; ++i) {
        item = [[[NSMenuItem alloc] initWithTitle:[sortedTags objectAtIndex:i]
                                           action:@selector(_addTag:)
                                    keyEquivalent:@""] autorelease];
        [item setTarget:self];
        [item setTag:i];
        [cellMenu insertItem:item atIndex:i+1];
    }

    id searchCell = [searchField cell];
    [searchCell setSearchMenuTemplate:cellMenu];
}

- (void)setUnderlyingDatasource:(ProfileModel*)dataSource
{
    [dataSource_ autorelease];
    dataSource_ = [[ProfileModelWrapper alloc] initWithModel:dataSource];
}



- (ProfileModelWrapper*)dataSource
{
    return dataSource_;
}

- (void)setDelegate:(NSObject<ProfileListViewDelegate> *)delegate
{
    delegate_ = delegate;
}

#pragma mark BookmarkTableView menu handler

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
    if ([delegate_ respondsToSelector:@selector(profileTable:menuForEvent:)]) {
        return [delegate_ profileTable:self menuForEvent:theEvent];
    }
    return nil;
}

#pragma mark Undo

- (NSArray *)orderedGuids
{
    NSMutableArray* result = [[[NSMutableArray alloc] init] autorelease];
    for (int i = 0; i < [tableView_ numberOfRows]; i++) {
        Profile* profile = [dataSource_ profileAtIndex:i];
        if (profile) {
            [result addObject:[profile objectForKey:KEY_GUID]];
        }
    }
    return result;
}

- (NSDictionary *)rowOrderWithSortDescriptors:(NSArray *)descriptors
{
    NSMutableDictionary *rowOrder = [NSMutableDictionary dictionary];
    if (descriptors) {
        [rowOrder setObject:descriptors forKey:@"descriptors"];
    }
    [rowOrder setObject:[self orderedGuids] forKey:@"guids"];
    return rowOrder;
}

- (NSDictionary *)rowOrder
{
    return [self rowOrderWithSortDescriptors:[tableView_ sortDescriptors]];
}

- (void)setRowOrder:(NSDictionary *)rowOrder
{
    [[self undoManager] registerUndoWithTarget:self
                                      selector:@selector(setRowOrder:)
                                        object:[self rowOrder]];
    NSArray *selectedGuids = [[self selectedGuids] allObjects];
    NSArray *descriptors = [rowOrder objectForKey:@"descriptors"];
    if (descriptors) {
        [tableView_ setSortDescriptors:descriptors];
    }
    NSArray *guids = [rowOrder objectForKey:@"guids"];
    for (int i = 0; i < [guids count]; i++) {
        [[dataSource_ underlyingModel] moveGuid:[guids objectAtIndex:i] toRow:i];
    }
    [self syncTableViewsWithSelectedGuids:selectedGuids];
}

#pragma mark NSTableView data source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [dataSource_ numberOfBookmarks];
}

- (void)tableView:(NSTableView *)aTableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
    [[self undoManager] registerUndoWithTarget:self
                                      selector:@selector(setRowOrder:)
                                        object:[self rowOrderWithSortDescriptors:oldDescriptors]];

    [dataSource_ setSortDescriptors:[aTableView sortDescriptors]];
    [dataSource_ sort];
    [dataSource_ pushOrderToUnderlyingModel];
    [[dataSource_ underlyingModel] postChangeNotification];

    // Update the sort indicator image for all columns.
    NSArray* sortDescriptors = [dataSource_ sortDescriptors];
    for (NSTableColumn* col in [aTableView tableColumns]) {
        [aTableView setIndicatorImage:nil inTableColumn:col];
    }
    if ([sortDescriptors count] > 0) {
        NSSortDescriptor* primarySortDesc = [sortDescriptors objectAtIndex:0];
        [aTableView setIndicatorImage:([primarySortDesc ascending] ? 
                                       [NSImage imageNamed:@"NSAscendingSortIndicator"] :
                                       [NSImage imageNamed:@"NSDescendingSortIndicator"])
                        inTableColumn:[aTableView tableColumnWithIdentifier:[primarySortDesc key]]];
    }

    [self reloadData];
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)rowIndex
{
    Profile* bookmark = [dataSource_ profileAtIndex:rowIndex];
    NSArray* tags = [bookmark objectForKey:KEY_TAGS];
    if ([tags count] == 0) {
        return normalRowHeight_;
    } else {
        return rowHeightWithTags_;
    }
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    Profile* bookmark = [dataSource_ profileAtIndex:rowIndex];

    if (aTableColumn == tableColumn_) {
        NSColor* textColor;
        if ([[tableView_ selectedRowIndexes] containsIndex:rowIndex]) {
            textColor = [NSColor whiteColor];
        } else {
            textColor = [NSColor blackColor];
        }
        NSDictionary* plainAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                         textColor, NSForegroundColorAttributeName,
                                         [[aTableColumn dataCell] font], NSFontAttributeName,
                                         nil];
        NSDictionary* smallAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                         textColor, NSForegroundColorAttributeName,
                                         [NSFont systemFontOfSize:10], NSFontAttributeName,
                                         nil];

        NSString *defaultCheckmark;
        if ([[bookmark objectForKey:KEY_GUID] isEqualToString:[[[ProfileModel sharedInstance] defaultBookmark] objectForKey:KEY_GUID]]) {
            defaultCheckmark = @"★ ";
        } else {
            defaultCheckmark = @"";
        }
        NSString *name = [NSString stringWithFormat:@"%@%@\n", defaultCheckmark, [bookmark objectForKey:KEY_NAME]];
        NSString* tags = [[bookmark objectForKey:KEY_TAGS] componentsJoinedByString:@", "];

        NSMutableAttributedString *theAttributedString = [[[NSMutableAttributedString alloc] initWithString:name
                                                                                                 attributes:plainAttributes] autorelease];

        [theAttributedString appendAttributedString:[[[NSAttributedString alloc] initWithString:tags
                                                                                     attributes:smallAttributes] autorelease]];
        return theAttributedString;
    } else if (aTableColumn == commandColumn_) {
        if (![[bookmark objectForKey:KEY_CUSTOM_COMMAND] isEqualToString:@"Yes"]) {
            return @"Login shell";
        } else {
            return [bookmark objectForKey:KEY_COMMAND];
        }
    } else if (aTableColumn == shortcutColumn_) {
        NSString* key = [bookmark objectForKey:KEY_SHORTCUT];
        if ([key length]) {
            return [NSString stringWithFormat:@"^⌘%@", [bookmark objectForKey:KEY_SHORTCUT]];
        } else {
            return @"";
        }
    } else {
        return nil;
    }

    return @"";
}

// Delegate methods
- (void)tableView:(NSTableView *)aTableView didClickTableColumn:(NSTableColumn *)aTableColumn 
{
    NSMutableArray* newSortDescriptors = [NSMutableArray arrayWithArray:[tableView_ sortDescriptors]];
    BOOL done = NO;
    BOOL ascending = YES;
    // Find the existing sort descriptor for the clicked-on column and move it
    // to the front.
    for (int i = 0; i < [newSortDescriptors count]; ++i) {
        NSSortDescriptor* desc = [newSortDescriptors objectAtIndex:i];
        if ([[desc key] isEqualToString:[aTableColumn identifier]]) {
            ascending = ![desc ascending];
            [newSortDescriptors removeObjectAtIndex:i];
            [newSortDescriptors insertObject:[[[NSSortDescriptor alloc] initWithKey:[aTableColumn identifier]
                                                                          ascending:ascending] autorelease]
                                     atIndex:0];
            done = YES;
            break;
        }
    }

    if (!done) {
        // This column was not previously sorted. Add it to the head of the array.
        [newSortDescriptors insertObject:[[[NSSortDescriptor alloc] initWithKey:[aTableColumn identifier]
                                                                      ascending:YES] autorelease] 
                                 atIndex:0];
    }
    [tableView_ setSortDescriptors:newSortDescriptors];

    [aTableView reloadData];
}

- (BOOL)selectionShouldChangeInTableView:(NSTableView *)aTableView
{
    if (delegate_ && [delegate_ respondsToSelector:@selector(profileTableSelectionWillChange:)]) {
        [delegate_ profileTableSelectionWillChange:self];
    }
    return YES;
}

- (void)tableViewSelectionIsChanging:(NSNotification *)aNotification
{
    // Mouse is being dragged across rows
    if (delegate_ && [delegate_ respondsToSelector:@selector(profileTableSelectionDidChange:)]) {
        [delegate_ profileTableSelectionDidChange:self];
    }
    [selectedGuids_ release];
    selectedGuids_ = [self selectedGuids];
    [selectedGuids_ retain];
}

- (void)setHasSelection:(BOOL)value
{
    // Placeholder for key-value observation
}

- (BOOL)hasSelection
{
    return [tableView_ numberOfSelectedRows] > 0;
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    // There was a click on a row
    if (delegate_ && [delegate_ respondsToSelector:@selector(profileTableSelectionDidChange:)]) {
        [delegate_ profileTableSelectionDidChange:self];
    }
    [selectedGuids_ release];
    selectedGuids_ = [self selectedGuids];
    [selectedGuids_ retain];
    // tweak key value observation
    [self setHasSelection:[selectedGuids_ count] > 0];
}

- (int)selectedRow
{
    return [tableView_ selectedRow];
}

- (void)reloadData
{
    [self _addTags:[[dataSource_ underlyingModel] allTags] toSearchField:searchField_];
    [dataSource_ sync];
    [tableView_ reloadData];
    if (delegate_ && ![selectedGuids_ isEqualToSet:[self selectedGuids]]) {
        [selectedGuids_ release];
        selectedGuids_ = [self selectedGuids];
        [selectedGuids_ retain];
        if ([delegate_ respondsToSelector:@selector(profileTableSelectionDidChange:)]) {
            [delegate_ profileTableSelectionDidChange:self];
        }
    }
}

- (void)selectRowIndex:(int)theRow
{
    NSIndexSet* indexes = [NSIndexSet indexSetWithIndex:theRow];
    [tableView_ selectRowIndexes:indexes byExtendingSelection:NO];
    [tableView_ scrollRowToVisible:theRow];
}

- (void)selectRowByGuid:(NSString*)guid
{
    int theRow = [dataSource_ indexOfProfileWithGuid:guid];
    if (theRow == -1) {
        [self deselectAll];
        return;
    }
    [self selectRowIndex:theRow];
}

- (int)numberOfRows
{
    return [dataSource_ numberOfBookmarks];
}

- (void)hideSearch
{
    [searchField_ setStringValue:@""];
    [searchField_ setHidden:YES];

    NSRect frame = [self frame];
    NSRect scrollViewFrame;
    scrollViewFrame.origin.x = 0;
    scrollViewFrame.origin.y = 0;
    scrollViewFrame.size = frame.size;
    [scrollView_ setFrame:scrollViewFrame];

    NSRect tableViewFrame;
    tableViewFrame.origin.x = 0;
    tableViewFrame.origin.y = 0;;
    tableViewFrame.size =
        [NSScrollView contentSizeForFrameSize:scrollViewFrame.size
                        hasHorizontalScroller:NO
                          hasVerticalScroller:YES
                                   borderType:[scrollView_ borderType]];
    [tableView_ setFrame:tableViewFrame];
    [tableView_ sizeLastColumnToFit];
}

- (void)allowEmptySelection
{
    [tableView_ setAllowsEmptySelection:YES];
}

- (void)allowMultipleSelections
{
    [tableView_ setAllowsMultipleSelection:YES];
}

- (void)deselectAll
{
    [tableView_ deselectAll:self];
}

- (NSString*)selectedGuid
{
    int row = [self selectedRow];
    if (row < 0) {
        return nil;
    }
    Profile* bookmark = [dataSource_ profileAtIndex:row];
    if (!bookmark) {
        return nil;
    }
    return [bookmark objectForKey:KEY_GUID];
}

- (NSArray *)orderedSelectedGuids
{
    NSMutableArray* result = [[[NSMutableArray alloc] init] autorelease];
    NSIndexSet* indexes = [tableView_ selectedRowIndexes];
    NSUInteger theIndex = [indexes firstIndex];
    while (theIndex != NSNotFound) {
        Profile* bookmark = [dataSource_ profileAtIndex:theIndex];
        if (bookmark) {
            [result addObject:[bookmark objectForKey:KEY_GUID]];
        }

        theIndex = [indexes indexGreaterThanIndex:theIndex];
    }
    return result;
}

- (NSSet*)selectedGuids
{
    return [NSSet setWithArray:[self orderedSelectedGuids]];
}

- (void)controlTextDidChange:(NSNotification *)aNotification
{
    [self updateResultsForSearch];
}

- (void)updateResultsForSearch
{
    // search field changed
    [dataSource_ setFilter:[searchField_ stringValue]];
    [self reloadData];
    if ([self selectedRow] < 0 && [self numberOfRows] > 0) {
        [self selectRowIndex:0];
        [tableView_ scrollRowToVisible:0];
    }
    if ([delegate_ respondsToSelector:@selector(profileTableFilterDidChange:)]) {
        [delegate_ profileTableFilterDidChange:self];
    }
}

- (void)multiColumns
{
    shortcutColumn_ = [[NSTableColumn alloc] initWithIdentifier:@"shortcut"];
    [shortcutColumn_ setEditable:NO];
    [shortcutColumn_ setWidth:50];
    [tableView_ addTableColumn:shortcutColumn_];

    commandColumn_ = [[NSTableColumn alloc] initWithIdentifier:@"command"];
    [commandColumn_ setEditable:NO];
    [tableView_ addTableColumn:commandColumn_];

    [tableColumn_ setWidth:250];

    [[shortcutColumn_ headerCell] setStringValue:@"Shortcut"];
    [[commandColumn_ headerCell] setStringValue:@"Command"];
    [tableView_ sizeLastColumnToFit];
}

- (void)dataChangeNotification:(id)sender
{
    // Use a delayed perform so the underlying model has a chance to parse its journal.
    [self performSelector:@selector(reloadData)
               withObject:nil
               afterDelay:0];
}

- (void)onDoubleClick:(id)sender
{
    if (delegate_ && [delegate_ respondsToSelector:@selector(profileTableRowSelected:)]) {
        [delegate_ profileTableRowSelected:self];
    }
}

- (void)eraseQuery
{
    [searchField_ setStringValue:@""];
    [self controlTextDidChange:nil];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldBoundsSize
{
    NSRect frame = [self frame];

    NSRect searchFieldFrame;
    searchFieldFrame.origin.x = 0;
    searchFieldFrame.origin.y = frame.size.height - kSearchWidgetHeight;
    searchFieldFrame.size.height = kSearchWidgetHeight;
    searchFieldFrame.size.width = frame.size.width;
    [searchField_ setFrame:searchFieldFrame];

    NSRect splitViewFrame = NSMakeRect(0,
                                       0,
                                       frame.size.width,
                                       frame.size.height - kSearchWidgetHeight - margin_);
    splitView_.frame = splitViewFrame;
}

- (void)turnOnDebug
{
    NSLog(@"Debugging object at %p. Current count is %d", (void*)self, (int)[self retainCount]);
    debug=YES;
}

- (NSTableView*)tableView
{
    return tableView_;
}

- (id)delegate
{
    return delegate_;
}

- (void)setFont:(NSFont *)theFont
{
    for (NSTableColumn *col in [tableView_ tableColumns]) {
        [[col dataCell] setFont:theFont];
    }
    NSLayoutManager* layoutManager = [[NSLayoutManager alloc] init];
    [layoutManager autorelease];
    normalRowHeight_ = [layoutManager defaultLineHeightForFont:theFont];
    rowHeightWithTags_ =  normalRowHeight_ + [layoutManager defaultLineHeightForFont:[NSFont systemFontOfSize:10]];
    [tableView_ setRowHeight:normalRowHeight_];

    if ([theFont pointSize] < 13) {
        [[searchField_ cell] setFont:theFont];
        [[searchField_ cell] setControlSize:NSSmallControlSize];
        [searchField_ sizeToFit];

        margin_ = 5;
        [self resizeSubviewsWithOldSize:self.frame.size];
    }
}

- (void)disableArrowHandler
{
    [searchField_ setArrowHandler:nil];
}

- (void)toggleTags
{
    NSRect newTableFrame = tableView_.frame;
    NSRect newTagsFrame = tagsView_.frame;
    CGFloat newTagsWidth;
    if ([self tagsVisible]) {
        lastTagsWidth_ = tagsView_.frame.size.width;
        newTagsWidth = 0;
    } else {
        newTagsWidth = lastTagsWidth_;
    }
    newTableFrame.size.width =  self.frame.size.width - newTagsWidth;
    newTagsFrame.size.width = newTagsWidth;
    
    tagsView_.animator.frame = newTagsFrame;
    tableView_.animator.frame = newTableFrame;
}

- (BOOL)tagsVisible {
    return tagsView_.frame.size.width > 0;
}

#pragma mark - ProfileTagsViewDelegate

- (void)profileTagsViewSelectionDidChange:(ProfileTagsView *)profileTagsView {
    searchField_.stringValue = [profileTagsView.selectedTags componentsJoinedByString:@" "];
    [self updateResultsForSearch];
}

#pragma mark - NSSplitViewDelegate

- (void)splitViewDidResizeSubviews:(NSNotification *)notification {
    if ((tagsView_.frame.size.width == 0) != tagsViewIsCollapsed_ &&
        [delegate_ respondsToSelector:@selector(profileTableTagsVisibilityDidChange:)]) {
        [delegate_ profileTableTagsVisibilityDidChange:self];
    }
    tagsViewIsCollapsed_ = (tagsView_.frame.size.width == 0);
}
@end
