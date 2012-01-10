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
#import "BookmarkTableView.h"

@class BookmarkModelWrapper;
@class iTermSearchField;
@class BookmarkRow;
@class BookmarkTableView;

@protocol BookmarkTableDelegate
@optional
- (void)bookmarkTableSelectionDidChange:(id)bookmarkTable;

@optional
- (void)bookmarkTableSelectionWillChange:(id)bookmarkTable;

@optional
- (void)bookmarkTableRowSelected:(id)bookmarkTable;

@optional
- (NSMenu*)bookmarkTable:(id)bookmarkTable menuForEvent:(NSEvent*)theEvent;
@end

@interface BookmarkListView : NSView <
      NSTextFieldDelegate,
	  NSTableViewDataSource,
	  NSTableViewDelegate,
	  BookmarkTableMenuHandler> {
    int normalRowHeight_;
    int rowHeightWithTags_;
    NSScrollView* scrollView_;
    iTermSearchField* searchField_;
    BookmarkTableView* tableView_;
    NSTableColumn* tableColumn_;
    NSTableColumn* commandColumn_;
    NSTableColumn* shortcutColumn_;
    NSTableColumn* starColumn_;
    NSTableColumn* tagsColumn_;
    NSObject<BookmarkTableDelegate> *delegate_;
    NSSet* selectedGuids_;
    BOOL debug;
    BookmarkModelWrapper* dataSource_;
    int margin_;
}

- (void)awakeFromNib;
- (id)initWithFrame:(NSRect)frameRect;
- (id)initWithFrame:(NSRect)frameRect model:(BookmarkModel*)dataSource;
- (void)setDelegate:(NSObject<BookmarkTableDelegate> *)delegate;
- (void)dealloc;
- (BookmarkModelWrapper*)dataSource;
- (void)setUnderlyingDatasource:(BookmarkModel*)dataSource;
- (void)focusSearchField;

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
- (void)allowEmptySelection;
- (void)allowMultipleSelections;
- (void)deselectAll;
- (void)multiColumns;

// Dont' use this if you've called allowMultipleSelections
- (NSString*)selectedGuid;
- (NSSet*)selectedGuids;
- (BOOL)hasSelection;
- (NSArray *)orderedSelectedGuids;
- (void)dataChangeNotification:(id)sender;
- (void)onDoubleClick:(id)sender;
- (void)eraseQuery;
- (void)resizeSubviewsWithOldSize:(NSSize)oldBoundsSize;
- (void)turnOnDebug;
- (NSTableView*)tableView;
- (id)delegate;

- (void)setFont:(NSFont *)theFont;
- (void)disableArrowHandler;

@end
