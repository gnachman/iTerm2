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

#import "iTermProfile.h"

@protocol iTermProfileModelMenuController;

// Notification posted when a stored profile changes.
extern NSString *const kReloadAddressBookNotification;

// All profiles should be reloaded.
extern NSString *const kReloadAllProfiles;

// Menu item identifier prefixes for NSMenuItems that open a window/tab
extern NSString *const iTermProfileModelNewWindowMenuItemIdentifierPrefix;
extern NSString *const iTermProfileModelNewTabMenuItemIdentifierPrefix;

#define BMKEY_BOOKMARKS_ARRAY @"Bookmarks Array"

@interface ProfileModel : NSObject

@property(nonatomic, readonly) NSString *modelName;
@property(nonatomic, strong) id<iTermProfileModelMenuController> menuController;

- (instancetype)init NS_UNAVAILABLE;

+ (ProfileModel *)sharedInstance;
+ (ProfileModel *)sessionsInstance;

+ (void)updateSharedProfileWithGUID:(NSString *)sharedProfileGUID
                          newValues:(NSDictionary *)newValues;


- (NSMutableArray<NSString *> *)debugHistoryForGuid:(NSString *)guid;
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
- (Profile*)defaultBookmark;  // prefer defaultProfile
- (Profile *)defaultProfile;
- (Profile*)bookmarkWithName:(NSString*)name;
- (Profile*)bookmarkWithGuid:(NSString*)guid;
- (int)indexOfBookmarkWithName:(NSString*)name;
- (NSArray*)allTags;
- (BOOL)bookmark:(Profile*)bookmark hasTag:(NSString*)tag;
- (Profile*)setObject:(id)object forKey:(NSString*)key inBookmark:(Profile*)bookmark;
- (Profile *)setObjectsFromDictionary:(NSDictionary *)dictionary inProfile:(Profile *)bookmark;
- (void)setDefaultByGuid:(NSString*)guid;
- (void)moveGuid:(NSString*)guid toRow:(int)row;
- (void)rebuildMenus;
// Return the absolute index of a bookmark given its index with the filter applied.
- (int)convertFilteredIndex:(int)theIndex withFilter:(NSString*)filter;
- (void)dump;
- (NSArray<Profile *> *)bookmarks;
- (NSArray *)guids;
- (NSArray *)names;
- (void)addGuidToDebug:(NSString *)guid;

// Updates the profile with guid 'origGuid' by replacing all elements except
// guid in 'bookmark'. The name is preserved if it is different than the
// original profile's name.
- (void)setProfilePreservingGuidWithGuid:(NSString *)origGuid
                             fromProfile:(Profile *)bookmark
                               overrides:(NSDictionary<NSString *, id> *)overrides;

// Write to user defaults
- (void)flush;

// Returns the profile to be used for tmux sessions.
- (Profile *)tmuxProfile;

// Tell all listeners that the model has changed.
- (void)postChangeNotification;

- (void)performBlockWithCoalescedNotifications:(void (^)(void))block;
- (void)recordSortOrder;
- (void)moveProfileWithGuidIfNeededToRespectSortOrder:(NSString *)guid;

@end

