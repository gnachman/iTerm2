/*
 **  BookmarkModel.h
 **  iTerm
 **
 **  Created by George Nachman on 8/24/10.
 **  Project: iTerm
 **
 **  Description: Model for an ordered collection of bookmarks. Bookmarks have
 **    numerous attributes, but always have a name, set of tags, and a guid.
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

#define BMKEY_BOOKMARKS_ARRAY @"Bookmarks Array"

typedef NSDictionary Bookmark;
typedef struct {
    SEL selector;                  // normal action
    SEL alternateSelector;         // opt+click
    SEL openAllSelector;           // open all bookmarks
    SEL alternateOpenAllSelector;  // opt+open all bookmarks
    id target;                     // receiver of selector
} JournalParams;

@interface BookmarkModel : NSObject {
    NSMutableArray* bookmarks_;
    NSString* defaultBookmarkGuid_;

    // The journal is an array of actions since the last change notification was
    // posted.
    NSMutableArray* journal_;
    NSUserDefaults* prefs_;
    BOOL postChanges_;              // should change notifications be posted?
}

+ (BookmarkModel*)sharedInstance;
+ (BookmarkModel*)sessionsInstance;
+ (NSString*)freshGuid;
- (int)numberOfBookmarks;
- (int)numberOfBookmarksWithFilter:(NSString*)filter;
- (NSArray*)bookmarkIndicesMatchingFilter:(NSString*)filter;
- (int)indexOfBookmarkWithGuid:(NSString*)guid;
- (int)indexOfBookmarkWithGuid:(NSString*)guid withFilter:(NSString*)filter;
- (Bookmark*)bookmarkAtIndex:(int)index;
- (Bookmark*)bookmarkAtIndex:(int)index withFilter:(NSString*)filter;
- (void)addBookmark:(Bookmark*)bookmark;
- (void)addBookmark:(Bookmark*)bookmark inSortedOrder:(BOOL)sort;
- (void)removeBookmarkWithGuid:(NSString*)guid;
- (void)removeBookmarksAtIndices:(NSArray*)indices;
- (void)removeBookmarkAtIndex:(int)index;
- (void)removeBookmarkAtIndex:(int)index withFilter:(NSString*)filter;
- (void)setBookmark:(Bookmark*)bookmark atIndex:(int)index;
- (void)setBookmark:(Bookmark*)bookmark withGuid:(NSString*)guid;
- (void)removeAllBookmarks;
- (NSArray*)rawData;
- (void)load:(NSArray*)prefs;
- (Bookmark*)defaultBookmark;
- (Bookmark*)bookmarkWithName:(NSString*)name;
- (Bookmark*)bookmarkWithGuid:(NSString*)guid;
- (int)indexOfBookmarkWithName:(NSString*)name;
- (NSArray*)allTags;
- (BOOL)bookmark:(Bookmark*)bookmark hasTag:(NSString*)tag;
- (Bookmark*)setObject:(id)object forKey:(NSString*)key inBookmark:(Bookmark*)bookmark;
- (void)setDefaultByGuid:(NSString*)guid;
- (void)moveGuid:(NSString*)guid toRow:(int)row;
- (void)rebuildMenus;
// Return the absolute index of a bookmark given its index with the filter applied.
- (int)convertFilteredIndex:(int)theIndex withFilter:(NSString*)filter;
- (void)dump;
- (NSArray*)bookmarks;
- (NSArray*)guids;
- (void)addBookmark:(Bookmark*)b toMenu:(NSMenu*)menu startingAtItem:(int)skip withTags:(NSArray*)tags params:(JournalParams*)params atPos:(int)pos;

// Tell all listeners that the model has changed.
- (void)postChangeNotification;

+ (void)applyJournal:(NSDictionary*)journal
              toMenu:(NSMenu*)menu
      startingAtItem:(int)skip
              params:(JournalParams*)params;

+ (void)applyJournal:(NSDictionary*)journal
              toMenu:(NSMenu*)menu
              params:(JournalParams*)params;

@end

typedef enum {
    JOURNAL_ADD,
    JOURNAL_REMOVE,
    JOURNAL_REMOVE_ALL,
    JOURNAL_SET_DEFAULT
} JournalAction;

@interface BookmarkJournalEntry : NSObject {
  @public
    JournalAction action;
    NSString* guid;
    BookmarkModel* model;
    // Tags before the action was applied.
    NSArray* tags;
    int index;  // Index of bookmark
}

+ (BookmarkJournalEntry*)journalWithAction:(JournalAction)action
                                  bookmark:(Bookmark*)bookmark
                                     model:(BookmarkModel*)model;

@end
