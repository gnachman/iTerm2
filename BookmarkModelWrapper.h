//
//  BookmarkModelWrapper.h
//  iTerm
//
//  Created by George Nachman on 1/9/12.
//

#import <Foundation/Foundation.h>
#import "BookmarkModel.h"
#import "BookmarkRow.h"

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
