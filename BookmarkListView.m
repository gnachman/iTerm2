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
#import <iTerm/BookmarkModel.h>
#import <iTerm/ITAddressBookMgr.h>
#import <iTerm/PTYSession.h>
#import "iTermSearchField.h"

#define BookmarkTableViewDataType @"iTerm2BookmarkGuid"

const int kSearchWidgetHeight = 22;
const int kInterWidgetMargin = 10;

// This wraps a single bookmark and adds a KeyValueCoding. To keep things simple
// it will hold only the bookmark's GUID, since bookmark dictionaries themselves
// are evanescent.
//
// It implements a KeyValueCoding so that sort descriptors will work.
@interface BookmarkRow : NSObject
{
    NSString* guid;
    BookmarkModel* underlyingModel;
}

- (id)initWithBookmark:(Bookmark*)bookmark underlyingModel:(BookmarkModel*)underlyingModel;
- (void)dealloc;
- (Bookmark*)bookmark;

@end

@interface BookmarkRow (KeyValueCoding)
// We need ascending order to sort default before not-default so we can't use
// anything senible like BOOL or "Yes"/"No" because they'd sort wrong.
typedef enum { IsDefault = 1, IsNotDefault = 2 } BookmarkRowIsDefault;
- (NSNumber*)default;
- (NSString*)name;
- (NSString*)shortcut;
- (NSString*)command;
- (NSString*)guid;
@end

@implementation BookmarkRow

- (id)initWithBookmark:(Bookmark*)bookmark underlyingModel:(BookmarkModel*)newUnderlyingModel;
{
    self = [super init];
    if (self) {
        guid = [[bookmark objectForKey:KEY_GUID] retain];
        self->underlyingModel = [newUnderlyingModel retain];
    }
    return self;
}

- (void)dealloc
{
    [underlyingModel release];
    [guid release];
    [super dealloc];
}

- (Bookmark*)bookmark
{
    return [underlyingModel bookmarkWithGuid:guid];
}

@end

@implementation BookmarkRow (KeyValueCoding)

- (NSNumber*)default
{
    BOOL isDefault = [[[self bookmark] objectForKey:KEY_GUID] isEqualToString:[[[BookmarkModel sharedInstance] defaultBookmark] objectForKey:KEY_GUID]];
    return [NSNumber numberWithInt:isDefault ? IsDefault : IsNotDefault];
}

- (NSString*)name
{
    return [[self bookmark] objectForKey:KEY_NAME];
}

- (NSString*)shortcut
{
    return [[self bookmark] objectForKey:KEY_SHORTCUT];
}

- (NSString*)command
{
    return [[self bookmark] objectForKey:KEY_COMMAND];
}

- (NSString*)guid
{
    return [[self bookmark] objectForKey:KEY_GUID];
}

@end

@implementation BookmarkModelWrapper

- (id)initWithModel:(BookmarkModel*)model
{
    self = [super init];
    if (self) {
        underlyingModel = model;
        bookmarks = [[NSMutableArray alloc] init];
        filter = [[NSMutableString alloc] init];
        [self sync];
    }
    return self;
}

- (void)dealloc
{
    [bookmarks release];
    [filter release];
    [super dealloc];
}

- (void)setSortDescriptors:(NSArray*)newSortDescriptors
{
    [sortDescriptors autorelease];
    sortDescriptors = [newSortDescriptors retain];
}

- (void)dump
{
    for (int i = 0; i < [self numberOfBookmarks]; ++i) {
        NSLog(@"Dump of %p: At %d: %@", self, i, [[self bookmarkRowAtIndex:i] name]);
    }
}

- (void)sort
{
    if ([sortDescriptors count] > 0) {
        [bookmarks sortUsingDescriptors:sortDescriptors];
    }
}

- (int)numberOfBookmarks
{
    return [bookmarks count];
}

- (BookmarkRow*)bookmarkRowAtIndex:(int)i
{
    return [bookmarks objectAtIndex:i];
}

- (Bookmark*)bookmarkAtIndex:(int)i
{
    return [[bookmarks objectAtIndex:i] bookmark];
}

- (int)indexOfBookmarkWithGuid:(NSString*)guid
{
    for (int i = 0; i < [bookmarks count]; ++i) {
        if ([[[bookmarks objectAtIndex:i] guid] isEqualToString:guid]) {
            return i;
        }
    }
    return -1;
}

- (BookmarkModel*)underlyingModel
{
    return underlyingModel;
}

- (void)sync
{
    [bookmarks removeAllObjects];
    NSArray* filteredBookmarks = [underlyingModel bookmarkIndicesMatchingFilter:filter];
    for (NSNumber* n in filteredBookmarks) {
        int i = [n intValue];
        //NSLog(@"Wrapper at %p add bookmark %@ at index %d", self, [[underlyingModel bookmarkAtIndex:i] objectForKey:KEY_NAME], i);
        [bookmarks addObject:[[[BookmarkRow alloc] initWithBookmark:[underlyingModel bookmarkAtIndex:i] 
                                                    underlyingModel:underlyingModel] autorelease]];
    }
    [self sort];
}

- (void)moveBookmarkWithGuid:(NSString*)guid toIndex:(int)row
{
    // Make the change locally.
    int origRow = [self indexOfBookmarkWithGuid:guid];
    if (origRow < row) {
        [bookmarks insertObject:[bookmarks objectAtIndex:origRow] atIndex:row];
        [bookmarks removeObjectAtIndex:origRow];
    } else if (origRow > row) {
        BookmarkRow* temp = [[bookmarks objectAtIndex:origRow] retain];
        [bookmarks removeObjectAtIndex:origRow];
        [bookmarks insertObject:temp atIndex:row];
        [temp release];
    }
}

- (void)pushOrderToUnderlyingModel
{
    // Since we may have a filter, let's ensure that the visible bookmarks occur
    // in the same order in the underlying model without regard to how invisible
    // bookmarks fit into the order. This also prevents instability when the
    // reload happens.
    int i = 0;
    for (BookmarkRow* theRow in bookmarks) {
        [underlyingModel moveGuid:[theRow guid] toRow:i++];
    }
    [underlyingModel rebuildMenus];
}

- (NSArray*)sortDescriptors
{
    return sortDescriptors;
}

- (void)setFilter:(NSString*)newFilter
{
    [filter release];
    filter = [[NSString stringWithString:newFilter] retain];
}

@end


@implementation BookmarkTableView

- (void)setParent:(id)parent
{
    parent_ = parent;
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
    if ([[parent_ delegate] respondsToSelector:@selector(bookmarkTable:menuForEvent:)]) {
        return [[parent_ delegate] bookmarkTable:parent_ menuForEvent:theEvent];
    }
    return nil;
}

@end

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
        frame.size.height - kSearchWidgetHeight - kInterWidgetMargin;
    scrollView_ = [[NSScrollView alloc] initWithFrame:scrollViewFrame];
    [scrollView_ setHasVerticalScroller:YES];
    [self addSubview:scrollView_];

    NSRect tableViewFrame;
    tableViewFrame.origin.x = 0;
    tableViewFrame.origin.y = 0;;
    tableViewFrame.size =
        [NSScrollView contentSizeForFrameSize:scrollViewFrame.size
                        hasHorizontalScroller:NO
                          hasVerticalScroller:YES
                                   borderType:[scrollView_ borderType]];

    tableView_ = [[BookmarkTableView alloc] initWithFrame:tableViewFrame];
    [tableView_ setParent:self];
    [tableView_ registerForDraggedTypes:[NSArray arrayWithObject:BookmarkTableViewDataType]];
    rowHeight_ = 29;
    showGraphic_ = YES;
    [tableView_ setRowHeight:rowHeight_];
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

- (void)setDelegate:(id<BookmarkTableDelegate>)delegate
{
    delegate_ = delegate;
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
        return 21;
    } else {
        return 29;
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
        size.height = rowHeight_;
        [image setSize:size];

        NSRect rect;
        rect.origin.x = 0;
        rect.origin.y = 0;
        rect.size = size;
        [image lockFocus];
        if ([[bookmark objectForKey:KEY_GUID] isEqualToString:[[[BookmarkModel sharedInstance] defaultBookmark] objectForKey:KEY_GUID]]) {
            NSPoint destPoint;
            destPoint.x = (size.width - [starImage size].width) / 2;
            destPoint.y = (rowHeight_ - [starImage size].height) / 2;
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
    if (delegate_) {
        [delegate_ bookmarkTableSelectionWillChange:self];
    }
    return YES;
}

- (void)tableViewSelectionIsChanging:(NSNotification *)aNotification
{
    // Mouse is being dragged across rows
    if (delegate_) {
        [delegate_ bookmarkTableSelectionDidChange:self];
    }
    [selectedGuids_ release];
    selectedGuids_ = [self selectedGuids];
    [selectedGuids_ retain];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    // There was a click on a row
    if (delegate_) {
        [delegate_ bookmarkTableSelectionDidChange:self];
    }
    [selectedGuids_ release];
    selectedGuids_ = [self selectedGuids];
    [selectedGuids_ retain];
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
        [delegate_ bookmarkTableSelectionDidChange:self];
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

- (void)setShowGraphic:(BOOL)showGraphic
{
    NSFont* font = [NSFont systemFontOfSize:0];
    NSLayoutManager* layoutManager = [[NSLayoutManager alloc] init];
    [layoutManager autorelease];
    int height = ([layoutManager defaultLineHeightForFont:font]);

    rowHeight_ = showGraphic ? 75 : height;
    showGraphic_ = showGraphic;
    [tableView_ setRowHeight:rowHeight_];

    if (!showGraphic) {
        [tableView_ setUsesAlternatingRowBackgroundColors:YES];
        [tableView_
         setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
        [tableView_ removeTableColumn:starColumn_];
        [tableColumn_ setDataCell:[[[NSTextFieldCell alloc] initTextCell:@""] autorelease]];
    } else {
        [tableView_ setUsesAlternatingRowBackgroundColors:NO];
        [tableView_
             setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
        [tableView_ removeTableColumn:tableColumn_];
        tableColumn_ =
            [[NSTableColumn alloc] initWithIdentifier:@"name"];
        [tableColumn_ setEditable:NO];

        [tableView_ addTableColumn:tableColumn_];
    }
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

- (NSSet*)selectedGuids
{
    NSMutableSet* result = [[[NSMutableSet alloc] init] autorelease];
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
    if (delegate_) {
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
        frame.size.height - kSearchWidgetHeight - kInterWidgetMargin;
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

- (id)retain
{
    if (debug)
        NSLog(@"Object at %x retain. Count is now %d", (void*)self, [self retainCount]+1);
    return [super retain];
}
- (oneway void)release
{
    if (debug)
        NSLog(@"Object at %x release. Count is now %d", (void*)self, [self retainCount]-1);
    [super release];
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

@end
