/*
 **  ProfileModel.h
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

// Notification posted when a stored profile changes.
extern NSString *const kReloadAddressBookNotification;

// All profiles should be reloaded.
extern NSString *const kReloadAllProfiles;

#define BMKEY_BOOKMARKS_ARRAY @"Bookmarks Array"

#define Profile NSDictionary

typedef struct {
    SEL selector;                  // normal action
    SEL alternateSelector;         // opt+click
    SEL openAllSelector;           // open all bookmarks
    SEL alternateOpenAllSelector;  // opt+open all bookmarks
    id target;                     // receiver of selector
} JournalParams;

@interface ProfileModel : NSObject {
    NSMutableArray* bookmarks_;
    NSString* defaultBookmarkGuid_;

    // The journal is an array of actions since the last change notification was
    // posted.
    NSMutableArray* journal_;
    NSUserDefaults* prefs_;
    BOOL postChanges_;              // should change notifications be posted?
}

+ (ProfileModel*)sharedInstance;
+ (ProfileModel*)sessionsInstance;
+ (NSString*)freshGuid;
+ (void)migratePromptOnCloseInMutableBookmark:(NSMutableDictionary *)dict;
+ (BOOL)migrated;
+ (NSAttributedString *)attributedStringForName:(NSString *)name
                   highlightingMatchesForFilter:(NSString *)filter
                              defaultAttributes:(NSDictionary *)defaultAttributes
                          highlightedAttributes:(NSDictionary *)highlightedAttributes;
+ (NSArray *)attributedTagsForTags:(NSArray *)tags
      highlightingMatchesForFilter:(NSString *)filter
                 defaultAttributes:(NSDictionary *)defaultAttributes
             highlightedAttributes:(NSDictionary *)highlightedAttributes;
- (int)numberOfBookmarks;
- (int)numberOfBookmarksWithFilter:(NSString*)filter;
- (NSArray*)bookmarkIndicesMatchingFilter:(NSString*)filter;
- (NSArray*)bookmarkIndicesMatchingFilter:(NSString*)filter orGuid:(NSString *)lockedGuid;
- (int)indexOfProfileWithGuid:(NSString*)guid;
- (int)indexOfProfileWithGuid:(NSString*)guid withFilter:(NSString*)filter;
- (Profile*)profileAtIndex:(int)index;
- (Profile*)profileAtIndex:(int)index withFilter:(NSString*)filter;
- (void)addBookmark:(Profile*)bookmark;
- (void)addBookmark:(Profile*)bookmark inSortedOrder:(BOOL)sort;
- (void)removeProfileWithGuid:(NSString*)guid;
- (void)removeBookmarksAtIndices:(NSArray*)indices;
- (void)removeBookmarkAtIndex:(int)index;
- (void)removeBookmarkAtIndex:(int)index withFilter:(NSString*)filter;
- (void)setBookmark:(Profile*)bookmark atIndex:(int)index;
- (void)setBookmark:(Profile*)bookmark withGuid:(NSString*)guid;
- (void)removeAllBookmarks;
- (NSArray*)rawData;
- (void)load:(NSArray*)prefs;
- (Profile*)defaultBookmark;
- (Profile*)bookmarkWithName:(NSString*)name;
- (Profile*)bookmarkWithGuid:(NSString*)guid;
- (int)indexOfBookmarkWithName:(NSString*)name;
- (NSArray*)allTags;
- (BOOL)bookmark:(Profile*)bookmark hasTag:(NSString*)tag;
- (Profile*)setObject:(id)object forKey:(NSString*)key inBookmark:(Profile*)bookmark;
- (void)setDefaultByGuid:(NSString*)guid;
- (void)moveGuid:(NSString*)guid toRow:(int)row;
- (void)rebuildMenus;
// Return the absolute index of a bookmark given its index with the filter applied.
- (int)convertFilteredIndex:(int)theIndex withFilter:(NSString*)filter;
- (void)dump;
- (NSArray<Profile *> *)bookmarks;
- (NSArray*)guids;
- (void)addBookmark:(Profile*)b toMenu:(NSMenu*)menu startingAtItem:(int)skip withTags:(NSArray*)tags params:(JournalParams*)params atPos:(int)pos;
- (NSArray *)names;

// Updates the profile with guid 'origGuid' by replacing all elements except
// guid in 'bookmark'. The name is preserved if it is different than the
// original profile's name.
- (void)setProfilePreservingGuidWithGuid:(NSString *)origGuid fromProfile:(Profile *)bookmark;

// Write to user defaults
- (void)flush;

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
    ProfileModel* model;
    // Tags before the action was applied.
    NSArray* tags;
    int index;  // Index of bookmark
}

+ (instancetype)journalWithAction:(JournalAction)action
                         bookmark:(Profile*)bookmark
                            model:(ProfileModel*)model;

@end
