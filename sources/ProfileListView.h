/*
 **  ProfileListView.h
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

#import <Cocoa/Cocoa.h>
#import "ProfileModel.h"
#import "ProfileTableView.h"
#import "FutureMethods.h"

@class ProfileListView;
@class ProfileModelWrapper;
@class ProfileTableRow;
@class ProfileTableView;
@class ProfileTagsView;
@class iTermSearchField;

@protocol ProfileListViewDelegate <NSObject>
@optional
- (void)profileTableSelectionDidChange:(id)profileTable;

- (void)profileTableSelectionWillChange:(id)profileTable;

- (void)profileTableRowSelected:(id)profileTable;

- (NSMenu*)profileTable:(id)profileTable menuForEvent:(NSEvent*)theEvent;

- (void)profileTableFilterDidChange:(ProfileListView *)profileListView;

- (void)profileTableTagsVisibilityDidChange:(ProfileListView *)profileListView;

@end

@interface ProfileListView : NSView <
  NSSplitViewDelegate,
  NSTextFieldDelegate,
  NSTableViewDataSource,
  NSTableViewDelegate,
  ProfileTableMenuHandler>

@property(nonatomic, readonly) BOOL tagsVisible;
@property(nonatomic, assign) IBOutlet id<ProfileListViewDelegate> delegate;

- (id)initWithFrame:(NSRect)frameRect;
- (id)initWithFrame:(NSRect)frameRect model:(ProfileModel*)dataSource;
- (void)dealloc;
- (ProfileModelWrapper*)dataSource;
- (void)setUnderlyingDatasource:(ProfileModel*)dataSource;
- (void)focusSearchField;
- (BOOL)searchFieldHasText;

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

// Delegate methods
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification;

// Don't use this if you've called allowMultipleSelections.
- (int)selectedRow;
- (void)reloadData;
- (void)selectRowIndex:(int)theIndex;
- (void)selectRowByGuid:(NSString*)guid;
- (int)numberOfRows;
- (void)clearSearchField;
- (void)allowEmptySelection;
- (void)allowMultipleSelections;
- (void)deselectAll;
- (void)multiColumns;

// Don't use this if you've called allowMultipleSelections
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

- (void)setFont:(NSFont *)theFont;
- (void)disableArrowHandler;

- (void)toggleTags;
- (void)setTagsOpen:(BOOL)open animated:(BOOL)animated;

// Keep the currently selected profile in the list and selected even if it no longer matches the
// filter.
- (void)lockSelection;
- (void)unlockSelection;

@end
