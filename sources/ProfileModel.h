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

typedef NS_OPTIONS(NSUInteger, ProfileType) {
    ProfileTypeTerminal = 1,
    ProfileTypeBrowser = 1 << 1,

    ProfileTypeAll = (ProfileTypeTerminal | ProfileTypeBrowser)
};

@protocol iTermProfileModelMenuController;

// Notification posted when a stored profile changes.
extern NSString *const kReloadAddressBookNotification;

// All profiles should be reloaded.
extern NSString *const kReloadAllProfiles;

// Menu item identifier prefixes for NSMenuItems that open a window/tab
extern NSString *const iTermProfileModelNewWindowMenuItemIdentifierPrefix;
extern NSString *const iTermProfileModelNewTabMenuItemIdentifierPrefix;
extern NSString *const iTermProfileDidChange;

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
// Returns a profile suitable for creating a new session based on the given profile.
// If the source profile is divorced (its guid exists in the sessions instance),
// returns a copy with a fresh guid to avoid two sessions sharing the same divorced guid.
// Otherwise, returns the original profile unchanged.
+ (Profile *)profileForCreatingNewSessionBasedOn:(Profile *)profile;
+ (void)migratePromptOnCloseInMutableBookmark:(NSMutableDictionary *)dict;
+ (BOOL)migrated;
+ (NSAttributedString *)attributedStringForCommand:(NSString *)command
                      highlightingMatchesForFilter:(NSString *)filter
                                 defaultAttributes:(NSDictionary *)defaultAttributes
                             highlightedAttributes:(NSDictionary *)highlightedAttributes;
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
- (NSArray<Profile *> *)profileIndicesMatchingFilter:(NSString *)filter
                                              orGuid:(NSString *)lockedGuid
                                              ofType:(ProfileType)profileTypes;
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
- (Profile *)defaultBrowserProfileCreatingIfNeeded;
- (Profile *)defaultBrowserProfile;
- (Profile*)bookmarkWithName:(NSString*)name;
- (Profile*)bookmarkWithGuid:(NSString*)guid;
- (int)indexOfBookmarkWithName:(NSString*)name;
- (NSArray*)allTags;
- (BOOL)bookmark:(Profile*)bookmark hasTag:(NSString*)tag;
- (Profile*)setObject:(id)object forKey:(NSString*)key inBookmark:(Profile*)bookmark;
- (Profile*)setObject:(id)object forKey:(NSString*)key inBookmark:(Profile*)bookmark sideEffects:(BOOL)sideEffects;
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

+ (void)log:(NSString *)message;

@end

@interface NSDictionary(ProfileModel)
@property(nonatomic, readonly) ProfileType profileType;
+ (ProfileType)profileTypeForCustomCommand:(id)customCommand;  // pass the value of KEY_CUSTOM_COMMAND
@end

