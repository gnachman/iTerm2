/*
 **  BookmarkTableController.m
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

#define BookmarkTableViewDataType @"iTerm2BookmarkGuid"

const int kSearchWidgetHeight = 22;
const int kInterWidgetMargin = 10;

@implementation BookmarkSearchField

- (void)setArrowHandler:(id)handler
{
    arrowHandler_ = handler;
}

- (BOOL)performKeyEquivalent:(NSEvent *)theEvent
{
    unsigned int modflag;
    unsigned short keycode;
    modflag = [theEvent modifierFlags];
    keycode = [theEvent keyCode];
    NSLog(@"Keycode %d", keycode);
    
    const int mask = NSShiftKeyMask | NSControlKeyMask | NSAlternateKeyMask | NSCommandKeyMask;
    // TODO(georgen): Not getting normal keycodes here, but 125 and 126 are up and down arrows.
    // This is a pretty ugly hack. Also, calling keyDown from here is probably not cool.
    BOOL handled = NO;
    if (!(mask & modflag) && (keycode == 125 || keycode == 126)) {
        [arrowHandler_ keyDown:theEvent];
        handled = YES;
        
    } else {
        handled = [super performKeyEquivalent:theEvent];
    }
    return handled;
}

@end

@interface ComparableImage : NSImage {
    NSString* key_;
}

- (ComparableImage*)init;
- (void)dealloc;
- (void)setKey:(NSString*)key;
- (NSComparisonResult)compare:(ComparableImage*)aString;
- (NSString*) key;

@end

@implementation ComparableImage

- (ComparableImage*)init
{
    self = [super init];
    key_ = nil;
    return self;
}

- (void)dealloc
{
    [key_ release];
    [super dealloc];
}

- (void)setKey:(NSString*)key
{
    [key_ release];
    key_ = key;
    [key_ retain];
}

- (NSComparisonResult)compare:(ComparableImage*)other
{
    return [key_ localizedCaseInsensitiveCompare:[other key]];
}

- (NSString*) key
{
    return key_;
}

@end


@implementation BookmarkListView


- (void)awakeFromNib
{
}

// Drag drop -------------------------------
- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
    // Copy guid to pboard
    NSInteger rowIndex = [rowIndexes firstIndex];
    NSMutableSet* guids = [[[NSMutableSet alloc] init] autorelease];
    while (rowIndex != NSNotFound) {
        Bookmark* bookmark = [dataSource_ bookmarkAtIndex:rowIndex
                                               withFilter:[searchField_ stringValue]];
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

        int absRow;
        if (row < [dataSource_ numberOfBookmarks]) {
            absRow = [dataSource_ convertFilteredIndex:row withFilter:[searchField_ stringValue]];
        } else {
            // convertFilteredIndex can't handle this case. Would only happen w/o a filter.
            absRow = row;
        }
        [dataSource_ moveGuid:guid toRow:absRow];
        row = [dataSource_ indexOfBookmarkWithGuid:guid withFilter:[searchField_ stringValue]] + 1;
    }
    NSMutableIndexSet* newIndexes = [[[NSMutableIndexSet alloc] init] autorelease];
    for (NSString* guid in guids) {
        row = [dataSource_ indexOfBookmarkWithGuid:guid withFilter:[searchField_ stringValue]];
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
    NSArray* allTags = [dataSource_ allTags];
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
        
    for (int i = 0; i < [tags count]; ++i) {
        item = [[[NSMenuItem alloc] initWithTitle:[tags objectAtIndex:i]
                                           action:@selector(_addTag:)
                                    keyEquivalent:@""] autorelease];
        [item setTarget:self];
        [item setTag:i];
        [cellMenu insertItem:item atIndex:i+1];
    }
    
    id searchCell = [searchField cell];
    [searchCell setSearchMenuTemplate:cellMenu];
}


- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    dataSource_ = [BookmarkModel sharedInstance];
    debug=NO;
    
    NSRect frame = [self frame];
    NSRect searchFieldFrame;
    searchFieldFrame.origin.x = 0;
    searchFieldFrame.origin.y = frame.size.height - kSearchWidgetHeight;
    searchFieldFrame.size.height = kSearchWidgetHeight;
    searchFieldFrame.size.width = frame.size.width;
    searchField_ = [[BookmarkSearchField alloc] initWithFrame:searchFieldFrame];
    [self _addTags:[dataSource_ allTags] toSearchField:searchField_];
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
    
    tableView_ = [[NSTableView alloc] initWithFrame:tableViewFrame];
    [tableView_ registerForDraggedTypes:[NSArray arrayWithObject:BookmarkTableViewDataType]];
    rowHeight_ = 21;
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
    
    tagsColumn_ = [[NSTableColumn alloc] initWithIdentifier:@"tags"];
    [tagsColumn_ setEditable:NO];
    [tableView_ addTableColumn:tagsColumn_];
    
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
    [[tagsColumn_ headerCell] setStringValue:@"Tags"];

    [tableView_ sizeLastColumnToFit];
    
    [searchField_ setArrowHandler:tableView_];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(dataChangeNotification:)
                                                 name: @"iTermReloadAddressBook"
                                               object: nil];
    return self;
}

- (void)setDataSource:(BookmarkModel*)dataSource
{
    dataSource_ = dataSource;
    [self reloadData];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [selectedGuids_ release];
    [super dealloc];
}

- (void)setDelegate:(id<BookmarkTableDelegate>)delegate
{
    delegate_ = delegate;
}

// DataSource methods
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [dataSource_ numberOfBookmarksWithFilter:[searchField_ stringValue]];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    Bookmark* bookmark = 
        [dataSource_ bookmarkAtIndex:rowIndex 
                          withFilter:[searchField_ stringValue]];

    if (aTableColumn == tableColumn_) {
        return [bookmark objectForKey:KEY_NAME];
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
    } else if (aTableColumn == tagsColumn_) {
        NSArray* tags = [bookmark objectForKey:KEY_TAGS];
        return [NSString stringWithString:[tags componentsJoinedByString:@", "]];
    } else if (aTableColumn == starColumn_) {
        static NSImage* starImage;
        if (!starImage) {
            NSString* starFile = [[NSBundle bundleForClass:[self class]] 
                                  pathForResource:@"star-gold24" 
                                  ofType:@"png"];   
            starImage = [[NSImage alloc] initWithContentsOfFile:starFile];
            [starImage retain];
        }
        NSImage *image = [[NSImage alloc] init];
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
    [self _addTags:[dataSource_ allTags] toSearchField:searchField_];
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
    int theRow = [dataSource_ indexOfBookmarkWithGuid:guid 
                                           withFilter:[searchField_ stringValue]];
    if (theRow == -1) {
        [self deselectAll];
        return;
    }
    [self selectRowIndex:theRow];
}

- (int)numberOfRows
{
    return [dataSource_ numberOfBookmarksWithFilter:[searchField_ stringValue]];
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
        [tableColumn_ setDataCell:[[NSTextFieldCell alloc] initTextCell:@""]];
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
    Bookmark* bookmark = [dataSource_ bookmarkAtIndex:row 
                                           withFilter:[searchField_ stringValue]];
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
        Bookmark* bookmark = [dataSource_ bookmarkAtIndex:theIndex 
                                               withFilter:[searchField_ stringValue]];
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

    [tableColumn_ setWidth:150];
    [tagsColumn_ setWidth:150];

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

- (void)allowMultipleSelection
{
    [tableView_ setAllowsMultipleSelection:YES];
}

@end
