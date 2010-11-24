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

#import <Cocoa/Cocoa.h>
#import "BookmarkModel.h"

@class BookmarkRow;
// This is an intermediate model that wraps BookmarkModel and allows
// each BookmarkListView to have a different ordering of bookmarks.
// It represents bookmarks are BookmarkRow objects which have a
// key-value coding and can be sorted by the columns relevant to
// BookmarkListView.
@interface BookmarkModelWrapper : NSObject
{
    BookmarkModel* underlyingModel;
    NSMutableArray* bookmarks;
    NSMutableString* filter;
    NSArray* sortDescriptors;
}

- (id)initWithModel:(BookmarkModel*)model;
- (void)dealloc;
- (void)setSortDescriptors:(NSArray*)newSortDescriptors;
- (NSArray*)sortDescriptors;

// Cause the underlying model to have the visible bookmarks in the same order as
// they appear here. Only bookmarks matching the filter are pushed.
- (void)pushOrderToUnderlyingModel;

// Sort the local representation according to sort descriptors set with setSortDescriptors.
- (void)sort;

// These functions take the filter (set with setFilter) into account with respect to indices.
- (int)numberOfBookmarks;
- (BookmarkRow*)bookmarkRowAtIndex:(int)index;
- (Bookmark*)bookmarkAtIndex:(int)index;
- (int)indexOfBookmarkWithGuid:(NSString*)guid;
- (void)moveBookmarkWithGuid:(NSString*)guid toIndex:(int)index;

- (BookmarkModel*)underlyingModel;

// Copy bookmarks matchin the filter from the underlying model.
- (void)sync;

// Show only bookmarks matching a search query 'filter'.
- (void)setFilter:(NSString*)newFilter;

@end

@interface BookmarkSearchField : NSSearchField
{
    id arrowHandler_;
}

- (BOOL)performKeyEquivalent:(NSEvent *)theEvent;
- (void)setArrowHandler:(id)handler;

@end

@interface BookmarkTableView : NSTableView
{
    id parent_;
}

- (void)setParent:(id)parent;
@end

@protocol BookmarkTableDelegate
- (void)bookmarkTableSelectionDidChange:(id)bookmarkTable;
- (void)bookmarkTableSelectionWillChange:(id)bookmarkTable;
- (void)bookmarkTableRowSelected:(id)bookmarkTable;
- (NSMenu*)bookmarkTable:(id)bookmarkTable menuForEvent:(NSEvent*)theEvent;
@end

@interface BookmarkListView : NSView {
    int rowHeight_;
    NSScrollView* scrollView_;
    BookmarkSearchField* searchField_;
    BookmarkTableView* tableView_;
    NSTableColumn* tableColumn_;
    NSTableColumn* commandColumn_;
    NSTableColumn* shortcutColumn_;
    NSTableColumn* starColumn_;
    NSTableColumn* tagsColumn_;
    id<BookmarkTableDelegate> delegate_;
    BOOL showGraphic_;
    NSSet* selectedGuids_;
    BOOL debug;
    BookmarkModelWrapper* dataSource_;
}

- (void)awakeFromNib;
- (id)initWithFrame:(NSRect)frameRect;
- (id)initWithFrame:(NSRect)frameRect model:(BookmarkModel*)dataSource;
- (void)setDelegate:(id<BookmarkTableDelegate>)delegate;
- (void)dealloc;
- (BookmarkModelWrapper*)dataSource;
- (void)setUnderlyingDatasource:(BookmarkModel*)dataSource;

// Drag drop
- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard;
- (NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id <NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)op;
- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id <NSDraggingInfo>)info
              row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation;


// DataSource methods
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView;
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)rowIndex;
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex;
- (BOOL)selectionShouldChangeInTableView:(NSTableView *)aTableView;
- (NSDragOperation)tableView:(NSTableView *)aTableView validateDrop:(id < NSDraggingInfo >)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation;

// Delegate methods
- (BOOL)selectionShouldChangeInTableView:(NSTableView *)aTableView;
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification;

// Don't use this if you've called allowMultipleSelections.
- (int)selectedRow;
- (void)reloadData;
- (void)selectRowIndex:(int)theIndex;
- (void)selectRowByGuid:(NSString*)guid;
- (int)numberOfRows;
- (void)hideSearch;
- (void)setShowGraphic:(BOOL)showGraphic;
- (void)allowEmptySelection;
- (void)allowMultipleSelections;
- (void)deselectAll;
- (void)multiColumns;

// Dont' use this if you've called allowMultipleSelections
- (NSString*)selectedGuid;
- (NSSet*)selectedGuids;
- (void)dataChangeNotification:(id)sender;
- (void)onDoubleClick:(id)sender;
- (void)eraseQuery;
- (void)resizeSubviewsWithOldSize:(NSSize)oldBoundsSize;
- (id)retain;
- (oneway void)release;
- (void)turnOnDebug;
- (NSTableView*)tableView;
- (id)delegate;

@end
