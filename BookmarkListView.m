/*
 **  BookmarkListView.m
 **  iTerm
 **
 **  Created by George Nachman on 8/26/10.
 **  Project: iTerm
 **
 **  Description: Custom view that shows a search field and table of bookmarks
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

#import "BookmarkListView.h"
#import "BookmarkModel.h"
#import "ITAddressBookMgr.h"
#import "PTYSession.h"
#import "iTermSearchField.h"
#import "BookmarkRow.h"
#import "BookmarkModelWrapper.h"
#import "BookmarkTableView.h"

#define BookmarkTableViewDataType @"iTerm2BookmarkGuid"

const int kSearchWidgetHeight = 22;
const int kInterWidgetMargin = 10;

@implementation BookmarkListView


- (void)awakeFromNib
{
}

- (void)focusSearchField
{
    [[self window] makeFirstResponder:searchField_];
}

// Drag drop -------------------------------
- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
    // Copy guid to pboard
    NSInteger rowIndex = [rowIndexes firstIndex];
    NSMutableSet* guids = [[[NSMutableSet alloc] init] autorelease];
    while (rowIndex != NSNotFound) {
        Bookmark* bookmark = [dataSource_ bookmarkAtIndex:rowIndex];
        NSString* guid = [bookmark objectForKey:KEY_GUID];
        [guids addObject:guid];
        rowIndex = [rowIndexes indexGreaterThanIndex:rowIndex];
    }

    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:guids];
    [pboard declareTypes:[NSArray arrayWithObject:BookmarkTableViewDataType] owner:self];
    [pboard setData:data forType:BookmarkTableViewDataType];
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

- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id <NSDraggingInfo>)info
              row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
    NSPasteboard* pboard = [info draggingPasteboard];
    NSData* rowData = [pboard dataForType:BookmarkTableViewDataType];
    NSSet* guids = [NSKeyedUnarchiver unarchiveObjectWithData:rowData];
    NSMutableDictionary* map = [[[NSMutableDictionary alloc] init] autorelease];

    for (NSString* guid in guids) {
        [map setObject:guid forKey:[NSNumber numberWithInt:[dataSource_ indexOfBookmarkWithGuid:guid]]];
    }
    NSArray* sortedIndexes = [map allKeys];
    sortedIndexes = [sortedIndexes sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber* mapIndex in sortedIndexes) {
        NSString* guid = [map objectForKey:mapIndex];

        [dataSource_ moveBookmarkWithGuid:guid toIndex:row];
        row = [dataSource_ indexOfBookmarkWithGuid:guid] + 1;
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
    [[dataSource_ underlyingModel] rebuildMenus];
    [[dataSource_ underlyingModel] postChangeNotification];

    NSMutableIndexSet* newIndexes = [[[NSMutableIndexSet alloc] init] autorelease];
    for (NSString* guid in guids) {
        row = [dataSource_ indexOfBookmarkWithGuid:guid];
        [newIndexes addIndex:row];
    }
    [tableView_ selectRowIndexes:newIndexes byExtendingSelection:NO];

    [self reloadData];
    return YES;
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

- (void)setUnderlyingDatasource:(BookmarkModel*)dataSource
{
    [dataSource_ autorelease];
    dataSource_ = [[BookmarkModelWrapper alloc] initWithModel:dataSource];
}

- (id)initWithFrame:(NSRect)frameRect
{
    return [self initWithFrame:frameRect model:[BookmarkModel sharedInstance]];
}

- (id)initWithFrame:(NSRect)frameRect model:(BookmarkModel*)dataSource
{
    self = [super initWithFrame:frameRect];

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

    NSRect scrollViewFrame;
    scrollViewFrame.origin.x = 0;
    scrollViewFrame.origin.y = 0;
    scrollViewFrame.size.width = frame.size.width;
    scrollViewFrame.size.height =
        frame.size.height - kSearchWidgetHeight - margin_;
    scrollView_ = [[NSScrollView alloc] initWithFrame:scrollViewFrame];
    [scrollView_ setHasVerticalScroller:YES];
    [self addSubview:scrollView_];

    NSRect tableViewFrame;
    tableViewFrame.origin.x = 0;
    tableViewFrame.origin.y = 0;
    tableViewFrame.size =
        [NSScrollView contentSizeForFrameSize:scrollViewFrame.size
                        hasHorizontalScroller:NO
                          hasVerticalScroller:YES
                                   borderType:[scrollView_ borderType]];

    tableView_ = [[BookmarkTableView alloc] initWithFrame:tableViewFrame];
    [tableView_ setMenuHandler:self];
    [tableView_ registerForDraggedTypes:[NSArray arrayWithObject:BookmarkTableViewDataType]];
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

    starColumn_ = [[NSTableColumn alloc] initWithIdentifier:@"default"];
    [starColumn_ setEditable:NO];
    [starColumn_ setDataCell:[[NSImageCell alloc] initImageCell:nil]];
    [starColumn_ setWidth:34];
    [tableView_ addTableColumn:starColumn_];

    tableColumn_ =
        [[NSTableColumn alloc] initWithIdentifier:@"name"];
    [tableColumn_ setEditable:NO];
    [tableView_ addTableColumn:tableColumn_];

    [scrollView_ setDocumentView:tableView_];

    [tableView_ setDelegate:self];
    [tableView_ setDataSource:self];
    selectedGuids_ = [[NSMutableSet alloc] init];

    [tableView_ setDoubleAction:@selector(onDoubleClick:)];

    NSTableHeaderView* header = [[NSTableHeaderView alloc] init];
    [tableView_ setHeaderView:header];
    [[tableColumn_ headerCell] setStringValue:@"Name"];
    [[starColumn_ headerCell] setStringValue:@"Default"];
    [starColumn_ setWidth:[[starColumn_ headerCell] cellSize].width];

    [tableView_ sizeLastColumnToFit];

    [searchField_ setArrowHandler:tableView_];

    [scrollView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [searchField_ setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(dataChangeNotification:)
                                                 name: @"iTermReloadAddressBook"
                                               object: nil];
    return self;
}

- (BookmarkModelWrapper*)dataSource
{
    return dataSource_;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [dataSource_ release];
    [selectedGuids_ release];
    [super dealloc];
}

- (void)setDelegate:(NSObject<BookmarkTableDelegate> *)delegate
{
    delegate_ = delegate;
}

#pragma mark BookmarkTableView menu handler

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
    return [delegate_ bookmarkTable:self menuForEvent:theEvent];
}

#pragma mark NSTableView data source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [dataSource_ numberOfBookmarks];
}

- (void)tableView:(NSTableView *)aTableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
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
    Bookmark* bookmark = [dataSource_ bookmarkAtIndex:rowIndex];
    NSArray* tags = [bookmark objectForKey:KEY_TAGS];
    if ([tags count] == 0) {
        return normalRowHeight_;
    } else {
        return rowHeightWithTags_;
    }
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    Bookmark* bookmark = [dataSource_ bookmarkAtIndex:rowIndex];

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

        NSString *name = [NSString stringWithFormat:@"%@\n", [bookmark objectForKey:KEY_NAME]];
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
    } else if (aTableColumn == starColumn_) {
        // FIXME: use imageNamed and clean up drawing code
        static NSImage* starImage;
        if (!starImage) {
            NSString* starFile = [[NSBundle bundleForClass:[self class]]
                                  pathForResource:@"star-gold24"
                                  ofType:@"png"];
            starImage = [[NSImage alloc] initWithContentsOfFile:starFile];
        }
        NSImage *image = [[[NSImage alloc] init] autorelease];
        NSSize size;
        size.width = [aTableColumn width];
        size.height = rowHeightWithTags_;
        [image setSize:size];

        NSRect rect;
        rect.origin.x = 0;
        rect.origin.y = 0;
        rect.size = size;
        [image lockFocus];
        if ([[bookmark objectForKey:KEY_GUID] isEqualToString:[[[BookmarkModel sharedInstance] defaultBookmark] objectForKey:KEY_GUID]]) {
            NSPoint destPoint;
            destPoint.x = (size.width - [starImage size].width) / 2;
            destPoint.y = (rowHeightWithTags_ - [starImage size].height) / 2;
            [starImage drawAtPoint:destPoint fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
        }
        [image unlockFocus];
        return image;
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
    if (delegate_ && [delegate_ respondsToSelector:@selector(bookmarkTableSelectionWillChange:)]) {
        [delegate_ bookmarkTableSelectionWillChange:self];
    }
    return YES;
}

- (void)tableViewSelectionIsChanging:(NSNotification *)aNotification
{
    // Mouse is being dragged across rows
    if (delegate_ && [delegate_ respondsToSelector:@selector(bookmarkTableSelectionDidChange:)]) {
        [delegate_ bookmarkTableSelectionDidChange:self];
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
    if (delegate_ && [delegate_ respondsToSelector:@selector(bookmarkTableSelectionDidChange:)]) {
        [delegate_ bookmarkTableSelectionDidChange:self];
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
        if ([delegate_ respondsToSelector:@selector(bookmarkTableSelectionDidChange:)]) {
            [delegate_ bookmarkTableSelectionDidChange:self];
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
    int theRow = [dataSource_ indexOfBookmarkWithGuid:guid];
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
    Bookmark* bookmark = [dataSource_ bookmarkAtIndex:row];
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
        Bookmark* bookmark = [dataSource_ bookmarkAtIndex:theIndex];
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
    // search field changed
    [dataSource_ setFilter:[searchField_ stringValue]];
    [self reloadData];
    if ([self selectedRow] < 0 && [self numberOfRows] > 0) {
        [self selectRowIndex:0];
        [tableView_ scrollRowToVisible:0];
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
    [self reloadData];
}

- (void)onDoubleClick:(id)sender
{
    if (delegate_ && [delegate_ respondsToSelector:@selector(bookmarkTableRowSelected:)]) {
        [delegate_ bookmarkTableRowSelected:self];
    }
}

- (void)eraseQuery
{
    [searchField_ setStringValue:@""];
    [self reloadData];
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

    NSRect scrollViewFrame;
    scrollViewFrame.origin.x = 0;
    scrollViewFrame.origin.y = 0;
    scrollViewFrame.size.width = frame.size.width;
    scrollViewFrame.size.height =
        frame.size.height - kSearchWidgetHeight - margin_;
    [scrollView_ setFrame:scrollViewFrame];

    NSRect tableViewFrame = [tableView_ frame];
    tableViewFrame.origin.x = 0;
    tableViewFrame.origin.y = 0;;
    NSSize temp =
        [NSScrollView contentSizeForFrameSize:scrollViewFrame.size
                        hasHorizontalScroller:NO
                          hasVerticalScroller:YES
                                   borderType:[scrollView_ borderType]];
    tableViewFrame.size.width = temp.width;
    [tableView_ setFrame:tableViewFrame];
}

- (void)turnOnDebug
{
    NSLog(@"Debugging object at %x. Current count is %d", (void*)self, [self retainCount]);
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

@end
