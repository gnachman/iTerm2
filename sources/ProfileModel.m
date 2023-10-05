/*
 **  ProfileModel.m
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

#import "ProfileModel.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermProfileModelJournal.h"
#import "iTermProfileSearchToken.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSStringITerm.h"
#import "NSThread+iTerm.h"
#import "PreferencePanel.h"

NSString *const kReloadAddressBookNotification = @"iTermReloadAddressBook";
NSString *const kReloadAllProfiles = @"kReloadAllProfiles";
NSString *const iTermProfileModelNewWindowMenuItemIdentifierPrefix = @"NewWindow:";
NSString *const iTermProfileModelNewTabMenuItemIdentifierPrefix = @"NewTab:";

// Set to true if a bookmark was changed automatically due to migration to a new
// standard.
int gMigrated;
static NSMutableArray<NSString *> *_combinedLog;

@interface ProfileModel()<iTermProfileModelJournalModel>
@end

@implementation ProfileModel {
    NSString *_modelName;
    NSMutableArray<NSNotification *> *_delayedNotifications;
//    NSMutableSet<NSString *> *_debugGuids;
//    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *_debugHistory;
    NSMutableArray* bookmarks_;
    NSString* defaultBookmarkGuid_;

    // The journal is an array of actions since the last change notification was
    // posted.
    NSMutableArray* journal_;
    NSUserDefaults* prefs_;
    BOOL postChanges_;              // should change notifications be posted?
}

+ (BOOL)migrated {
    return gMigrated;
}

+ (void)updateSharedProfileWithGUID:(NSString *)sharedProfileGUID
                          newValues:(NSDictionary *)newValues {
    if (!sharedProfileGUID) {
        return;
    }
    MutableProfile *sharedProfile = [[[[ProfileModel sharedInstance] profileWithGuid:sharedProfileGUID] mutableCopy] autorelease];
    if (!sharedProfile) {
        return;
    }
    [sharedProfile it_mergeFrom:newValues];
    [[ProfileModel sharedInstance] setBookmark:sharedProfile withGuid:sharedProfileGUID];

    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles
                                                        object:nil
                                                      userInfo:nil];

    // Update user defaults
    [[NSUserDefaults standardUserDefaults] setObject:[[ProfileModel sharedInstance] rawData]
                                              forKey:@"New Bookmarks"];
}

- (NSMutableArray<NSString *> *)debugHistoryForGuid:(NSString *)guid {
    return _combinedLog;
//    if ([_debugGuids containsObject:guid]) {
//        if (!_debugHistory) {
//            _debugHistory = [[NSMutableDictionary alloc] init];
//        }
//        NSMutableArray *entries = _debugHistory[guid];
//        if (!entries) {
//            entries = [[[NSMutableArray alloc] init] autorelease];
//            _debugHistory[guid] = entries;
//        }
//        return entries;
//    } else {
//        return nil;
//    }
}

- (ProfileModel *)initWithName:(NSString *)modelName {
    self = [super init];
    if (self) {
        _modelName = [modelName copy];
        bookmarks_ = [[NSMutableArray alloc] init];
        defaultBookmarkGuid_ = @"";
        journal_ = [[NSMutableArray alloc] init];
//        _debugGuids = [[NSMutableSet alloc] init];
        if (!_combinedLog) {
            _combinedLog = [[NSMutableArray alloc] init];
        }
    }
    return self;
}

+ (ProfileModel *)sharedInstance {
    static ProfileModel* shared = nil;

    if (!shared) {
        shared = [[ProfileModel alloc] initWithName:@"Shared"];
        shared->prefs_ = [NSUserDefaults standardUserDefaults];
        shared->postChanges_ = YES;
    }

    return shared;
}

+ (ProfileModel*)sessionsInstance
{
    static ProfileModel* shared = nil;

    if (!shared) {
        shared = [[ProfileModel alloc] initWithName:@"Sessions"];
        shared->prefs_ = nil;
        shared->postChanges_ = NO;
    }

    return shared;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<ProfileModel %@: %p>", _modelName, self];
}

- (void)dealloc
{
    [journal_ release];
    [_modelName release];
    [_delayedNotifications release];
//    [_debugGuids release];
//    [_debugHistory release];
    [_menuController release];
    NSLog(@"Deallocating bookmark model!");
    [super dealloc];
}

// Use only when tmuxUsesDedicatedProfile is off
- (Profile *)tmuxProfile {
    Profile *profile = [self bookmarkWithName:@"tmux"];
    if (!profile) {
        Profile *defaultBookmark = [self defaultBookmark];
        NSMutableDictionary *tmuxProfile = [[defaultBookmark mutableCopy] autorelease];
        tmuxProfile[KEY_HAS_HOTKEY] = @NO;
        
        [tmuxProfile setObject:@"tmux" forKey:KEY_NAME];
        [tmuxProfile setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
        [tmuxProfile setObject:[NSNumber numberWithInt:1000]
                         forKey:KEY_SCROLLBACK_LINES];
        [self addBookmark:tmuxProfile];
        [self postChangeNotification];
        profile = tmuxProfile;
    }
    return profile;
}


- (int)numberOfBookmarks
{
    return [bookmarks_ count];
}

+ (NSAttributedString *)attributedStringForName:(NSString *)name
                   highlightingMatchesForFilter:(NSString *)filter
                              defaultAttributes:(NSDictionary *)defaultAttributes
                          highlightedAttributes:(NSDictionary *)highlightedAttributes {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    NSArray<iTermProfileSearchToken *> *tokens = [self parseFilter:filter];
    [self doesProfileWithName:name tags:@[] matchFilter:tokens nameIndexSet:indexes tagIndexSets:nil];
    NSMutableAttributedString *result =
        [[[NSMutableAttributedString alloc] initWithString:name
                                                attributes:defaultAttributes] autorelease];
    [indexes enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        [result setAttributes:highlightedAttributes range:range];
    }];
    return result;
}

+ (NSArray *)attributedTagsForTags:(NSArray *)tags
                 highlightingMatchesForFilter:(NSString *)filter
                            defaultAttributes:(NSDictionary *)defaultAttributes
                        highlightedAttributes:(NSDictionary *)highlightedAttributes {
    NSMutableArray *indexSets = [NSMutableArray array];
    for (int i = 0; i < tags.count; i++) {
        [indexSets addObject:[NSMutableIndexSet indexSet]];
    }
    NSArray* tokens = [self parseFilter:filter];
    [self doesProfileWithName:nil
                         tags:tags
                  matchFilter:tokens
                 nameIndexSet:nil
                 tagIndexSets:indexSets];
    NSMutableArray *result = [NSMutableArray array];
    for (int i = 0; i < tags.count; i++) {
        NSMutableAttributedString *attributedString =
            [[[NSMutableAttributedString alloc] initWithString:tags[i]
                                                    attributes:defaultAttributes] autorelease];
        NSIndexSet *indexSet = indexSets[i];
        [indexSet enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
            [attributedString setAttributes:highlightedAttributes range:range];
        }];
        [result addObject:attributedString];
    }
    return result;
}

+ (BOOL)doesProfile:(Profile *)profile matchFilter:(NSArray *)tokens {
    return [self.class doesProfileWithName:profile[KEY_NAME]
                                      tags:profile[KEY_TAGS]
                               matchFilter:tokens
                              nameIndexSet:nil
                              tagIndexSets:nil];
}

+ (BOOL)doesProfileWithName:(NSString *)name
                       tags:(NSArray *)tags
                matchFilter:(NSArray<iTermProfileSearchToken *> *)tokens
               nameIndexSet:(NSMutableIndexSet *)nameIndexSet
               tagIndexSets:(NSArray *)tagIndexSets {
    NSArray* nameWords = [name componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    for (iTermProfileSearchToken *token in tokens) {
        // Search each word in tag until one has this token as a prefix.
        // First see if this token occurs in the title
        BOOL found = [token matchesAnyWordInNameWords:nameWords];

        if (found) {
            if (token.negated) {
                return NO;
            }
            [nameIndexSet addIndexesInRange:token.range];
        }
        // If not try each tag.
        for (int j = 0; !found && j < [tags count]; ++j) {
            // Expand the jth tag into an array of the words in the tag
            NSArray* tagWords = [[tags objectAtIndex:j] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            found = [token matchesAnyWordInTagWords:tagWords];
            if (found) {
                if (token.negated) {
                    return NO;
                }
                NSMutableIndexSet *indexSet = tagIndexSets[j];
                [indexSet addIndexesInRange:token.range];
            }
        }
        if (!token.negated && !found && name != nil) {
            // Failed to match a non-negated token. If name is nil then we don't really care about the
            // answer and we just want index sets.
            return NO;
        }
    }
    return YES;
}

+ (NSArray<iTermProfileSearchToken *> *)parseFilter:(NSString*)filter {
    NSArray *phrases = [filter componentsBySplittingProfileListQuery];
    NSMutableArray<iTermProfileSearchToken *> *tokens = [NSMutableArray array];
    for (NSString *phrase in phrases) {
        iTermProfileSearchToken *token = [[[iTermProfileSearchToken alloc] initWithPhrase:phrase] autorelease];
        [tokens addObject:token];
    }
    return tokens;
}

- (NSArray*)bookmarkIndicesMatchingFilter:(NSString*)filter orGuid:(NSString *)lockedGuid {
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:[bookmarks_ count]];
    NSArray* tokens = [self.class parseFilter:filter];
    int count = [bookmarks_ count];
    for (int i = 0; i < count; ++i) {
        if ([self.class doesProfile:[self profileAtIndex:i] matchFilter:tokens] ||
            [bookmarks_[i][KEY_GUID] isEqualToString:lockedGuid]) {
            [result addObject:@(i)];
        }
    }
    return result;
}

- (NSArray*)bookmarkIndicesMatchingFilter:(NSString*)filter {
    return[ self bookmarkIndicesMatchingFilter:filter orGuid:nil];
}

- (int)numberOfBookmarksWithFilter:(NSString*)filter
{
    NSArray* tokens = [self.class parseFilter:filter];
    int count = [bookmarks_ count];
    int n = 0;
    for (int i = 0; i < count; ++i) {
        if ([self.class doesProfile:[self profileAtIndex:i] matchFilter:tokens]) {
            ++n;
        }
    }
    return n;
}

- (Profile*)profileAtIndex:(int)i
{
    if (i < 0 || i >= [bookmarks_ count]) {
        return nil;
    }
    return [bookmarks_ objectAtIndex:i];
}

- (Profile*)profileAtIndex:(int)theIndex withFilter:(NSString*)filter
{
    NSArray* tokens = [self.class parseFilter:filter];
    int count = [bookmarks_ count];
    int n = 0;
    for (int i = 0; i < count; ++i) {
        if ([self.class doesProfile:[self profileAtIndex:i] matchFilter:tokens]) {
            if (n == theIndex) {
                return [self profileAtIndex:i];
            }
            ++n;
        }
    }
    return nil;
}

- (void)addBookmark:(Profile*)bookmark
{
    [self addBookmark:bookmark inSortedOrder:NO];
}

+ (void)migrateDeprecatedKeysInMutableBookmark:(NSMutableDictionary *)dict {
    // Migrate KEY_DISABLE_BOLD to KEY_USE_BOLD_FONT
    if (dict[KEY_DISABLE_BOLD] && !dict[KEY_USE_BOLD_FONT]) {
        dict[KEY_USE_BOLD_FONT] = @(![dict[KEY_DISABLE_BOLD] boolValue]);
    }
}

+ (void)migratePromptOnCloseInMutableBookmark:(NSMutableDictionary *)dict
{
    // Migrate global "prompt on close" to per-profile prompt enum
    if ([dict objectForKey:KEY_PROMPT_CLOSE_DEPRECATED]) {
        // The 8/28 build incorrectly ignored the OnlyWhenMoreTabs setting
        // when migrating PromptOnClose to KEY_PRMOPT_CLOSE. Its preference
        // key has been changed to KEY_PROMPT_CLOSE_DEPRECATED and a new
        // pref key with the same intended usage has been added on 9/4 but
        // with a different name. If the setting is PROMPT_ALWAYS, then it may
        // have been migrated incorrectly. There are three ways to get here:
        // 1. PromptOnClose && OnlyWhenMoreTabs was migrated wrong.
        // 2. PromptOnClose && !OnlyWhenMoreTabs was migrated right.
        // 3. Post migration, the user set it to PROMPT_ALWAYS
        //
        // For case 1, redoing the migration produces the correct result.
        // For case 2, redoing the migration has no effect.
        // For case 3, the user's pref is overwritten. This should be rare.
        int value = [[dict objectForKey:KEY_PROMPT_CLOSE_DEPRECATED] intValue];
        if (value != PROMPT_ALWAYS) {
            [dict setObject:[NSNumber numberWithInt:value]
                     forKey:KEY_PROMPT_CLOSE];
        }
    }
    if (![dict objectForKey:KEY_PROMPT_CLOSE]) {
        BOOL promptOnClose = [[[NSUserDefaults standardUserDefaults] objectForKey:@"PromptOnClose"] boolValue];
        NSNumber *onlyWhenNumber = [[NSUserDefaults standardUserDefaults] objectForKey:@"OnlyWhenMoreTabs"];
        if (!onlyWhenNumber || [onlyWhenNumber boolValue]) {
            promptOnClose = NO;
        }

        NSNumber *newValue = [NSNumber numberWithBool:promptOnClose ? PROMPT_ALWAYS : PROMPT_NEVER];
        [dict setObject:newValue forKey:KEY_PROMPT_CLOSE];
        gMigrated = YES;
    }

    // This is a required field to avoid setting nil values in the bookmark
    // dict later on.
    if (![dict objectForKey:KEY_JOBS]) {
        [dict setObject:[NSArray arrayWithObjects:@"rlogin", @"ssh", @"slogin", @"telnet", nil]
                 forKey:KEY_JOBS];
        gMigrated = YES;
    }
}

- (void)addBookmark:(Profile*)bookmark inSortedOrder:(BOOL)sort {
    NSMutableDictionary *newBookmark = [[bookmark mutableCopy] autorelease];

    // Ensure required fields are present
    if (![newBookmark objectForKey:KEY_NAME]) {
        [newBookmark setObject:@"Bookmark" forKey:KEY_NAME];
    }
    if (![newBookmark objectForKey:KEY_TAGS]) {
        [newBookmark setObject:@[] forKey:KEY_TAGS];
    }
    if (![newBookmark objectForKey:KEY_CUSTOM_COMMAND]) {
        [newBookmark setObject:kProfilePreferenceCommandTypeLoginShellValue forKey:KEY_CUSTOM_COMMAND];
    }
    if (![newBookmark objectForKey:KEY_COMMAND_LINE]) {
        [newBookmark setObject:@"/bin/bash --login" forKey:KEY_COMMAND_LINE];
    }
    if (![newBookmark objectForKey:KEY_GUID]) {
        [newBookmark setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
    }
    if (![newBookmark objectForKey:KEY_DEFAULT_BOOKMARK]) {
        [newBookmark setObject:@"No" forKey:KEY_DEFAULT_BOOKMARK];
    }
    [ProfileModel migratePromptOnCloseInMutableBookmark:newBookmark];
    [ProfileModel migrateDeprecatedKeysInMutableBookmark:newBookmark];
    bookmark = [[newBookmark copy] autorelease];

    int theIndex;
    if (sort) {
        // Insert alphabetically. Sort so that objects with the "bonjour" tag come after objects without.
        int insertionPoint = -1;
        NSString* newName = [bookmark objectForKey:KEY_NAME];
        BOOL hasBonjour = [self bookmark:bookmark hasTag:@"bonjour"];
        for (int i = 0; i < [bookmarks_ count]; ++i) {
            Profile* bookmarkAtI = [bookmarks_ objectAtIndex:i];
            NSComparisonResult order = NSOrderedSame;
            BOOL currentHasBonjour = [self bookmark:bookmarkAtI hasTag:@"bonjour"];
            if (hasBonjour != currentHasBonjour) {
                if (hasBonjour) {
                    order = NSOrderedAscending;
                } else {
                    order = NSOrderedDescending;
                }
            }
            if (order == NSOrderedSame) {
                order = [[[bookmarks_ objectAtIndex:i] objectForKey:KEY_NAME] caseInsensitiveCompare:newName];
            }
            if (order == NSOrderedDescending) {
                insertionPoint = i;
                break;
            }
        }
        if (insertionPoint == -1) {
            theIndex = [bookmarks_ count];
            [bookmarks_ addObject:[NSDictionary dictionaryWithDictionary:bookmark]];
        } else {
            theIndex = insertionPoint;
            [bookmarks_ insertObject:[NSDictionary dictionaryWithDictionary:bookmark] atIndex:insertionPoint];
        }
    } else {
        theIndex = [bookmarks_ count];
        [bookmarks_ addObject:[NSDictionary dictionaryWithDictionary:bookmark]];
    }
    NSString* isDeprecatedDefaultBookmark = [bookmark objectForKey:KEY_DEFAULT_BOOKMARK];

    // The call to setDefaultByGuid may add a journal entry so make sure this one comes first.
    BookmarkJournalEntry *e = [BookmarkJournalEntry journalWithAction:JOURNAL_ADD
                                                             bookmark:bookmark
                                                                model:self
                                                                index:theIndex
                                                           identifier:nil];
    [journal_ addObject:e];

    if (![self defaultBookmark] || (isDeprecatedDefaultBookmark && [isDeprecatedDefaultBookmark isEqualToString:@"Yes"])) {
        [self setDefaultByGuid:[bookmark objectForKey:KEY_GUID]];
    }
    [self postChangeNotification];
    [[self debugHistoryForGuid:bookmark[KEY_GUID]] addObject:[NSString stringWithFormat:@"%@: Add bookmark with guid %@",
                                                              self,
                                                              bookmark[KEY_GUID]]];
}

- (void)addGuidToDebug:(NSString *)guid {
//    [_debugGuids addObject:guid];
}

- (BOOL)bookmark:(Profile*)bookmark hasTag:(NSString*)tag
{
    NSArray* tags = [bookmark objectForKey:KEY_TAGS];
    return [tags containsObject:tag];
}

- (int)convertFilteredIndex:(int)theIndex withFilter:(NSString*)filter
{
    NSArray* tokens = [self.class parseFilter:filter];
    int count = [bookmarks_ count];
    int n = 0;
    for (int i = 0; i < count; ++i) {
        if ([self.class doesProfile:[self profileAtIndex:i] matchFilter:tokens]) {
            if (n == theIndex) {
                return i;
            }
            ++n;
        }
    }
    return -1;
}

- (void)removeBookmarksAtIndices:(NSArray*)indices
{
    NSArray* sorted = [indices sortedArrayUsingSelector:@selector(compare:)];
    for (int j = [sorted count] - 1; j >= 0; j--) {
        int i = [[sorted objectAtIndex:j] intValue];
        assert(i >= 0);

        [journal_ addObject:[BookmarkJournalEntry journalWithAction:JOURNAL_REMOVE bookmark:[bookmarks_ objectAtIndex:i] model:self identifier:nil]];
        [[self debugHistoryForGuid:bookmarks_[i][KEY_GUID]] addObject:[NSString stringWithFormat:@"%@: Remove bookmark with guid %@",
                                                                       self,
                                                                       bookmarks_[i][KEY_GUID]]];
        [bookmarks_ removeObjectAtIndex:i];
        if (![self defaultBookmark] && [bookmarks_ count]) {
            [self setDefaultByGuid:[[bookmarks_ objectAtIndex:0] objectForKey:KEY_GUID]];
        }
    }
    [self postChangeNotification];
}

- (void)removeBookmarkAtIndex:(int)i {
    DLog(@"Remove profile at index %d", i);
    assert(i >= 0);
    [journal_ addObject:[BookmarkJournalEntry journalWithAction:JOURNAL_REMOVE bookmark:[bookmarks_ objectAtIndex:i] model:self identifier:nil]];
    [[self debugHistoryForGuid:bookmarks_[i][KEY_GUID]] addObject:[NSString stringWithFormat:@"%@: Remove bookmark with guid %@",
                                                                   self,
                                                                   bookmarks_[i][KEY_GUID]]];
    [bookmarks_ removeObjectAtIndex:i];
    DLog(@"Number of profiles is now %d", (int)bookmarks_.count);
    if (![self defaultBookmark] && [bookmarks_ count]) {
        [self setDefaultByGuid:[[bookmarks_ objectAtIndex:0] objectForKey:KEY_GUID]];
    }
    [self postChangeNotification];
}

- (void)removeBookmarkAtIndex:(int)i withFilter:(NSString*)filter
{
    [self removeBookmarkAtIndex:[self convertFilteredIndex:i withFilter:filter]];
}

- (void)removeProfileWithGuid:(NSString*)guid {
    DLog(@"Remove profile with guid %@", guid);
    int i = [self indexOfProfileWithGuid:guid];
    DLog(@"Index is %d", i);
    if (i >= 0) {
        [self removeBookmarkAtIndex:i];
    }
}

// A change in bookmarks is journal-worthy only if the name, shortcut, tags, or guid changes.
- (BOOL)bookmark:(Profile*)a differsJournalablyFrom:(Profile*)b
{
    // Any field that is shown in a view (profiles window, menus, bookmark list views, etc.) must
    // be a criteria for journalability for it to be updated immediately.
    if (![[a objectForKey:KEY_NAME] isEqualToString:[b objectForKey:KEY_NAME]] ||
        ![[a objectForKey:KEY_SHORTCUT] isEqualToString:[b objectForKey:KEY_SHORTCUT]] ||
        ![[a objectForKey:KEY_TAGS] isEqualToArray:[b objectForKey:KEY_TAGS]] ||
        ![[a objectForKey:KEY_GUID] isEqualToString:[b objectForKey:KEY_GUID]] ||
        ![[a objectForKey:KEY_COMMAND_LINE] isEqualToString:[b objectForKey:KEY_COMMAND_LINE]] ||
        ![[a objectForKey:KEY_CUSTOM_COMMAND] isEqualToString:[b objectForKey:KEY_CUSTOM_COMMAND]]) {
        return YES;
    } else {
        return NO;
    }
}

- (void)setBookmark:(Profile*)bookmark atIndex:(int)i
{
    Profile* orig = [bookmarks_ objectAtIndex:i];
    BOOL isDefault = NO;
    if ([[orig objectForKey:KEY_GUID] isEqualToString:defaultBookmarkGuid_]) {
        isDefault = YES;
    }

    Profile* before = [bookmarks_ objectAtIndex:i];
    BOOL needJournal = [self bookmark:bookmark differsJournalablyFrom:before];
    if (needJournal) {
        [journal_ addObject:[BookmarkJournalEntry journalWithAction:JOURNAL_REMOVE bookmark:[bookmarks_ objectAtIndex:i] model:self identifier:nil]];
    }
    [[self debugHistoryForGuid:bookmark[KEY_GUID]] addObject:[NSString stringWithFormat:@"%@: Replace bookmark at index %@ (%@) with %@",
                                                              self,
                                                              @(i),
                                                              bookmarks_[i][KEY_GUID],
                                                              bookmark[KEY_GUID]]];
    [bookmarks_ replaceObjectAtIndex:i withObject:bookmark];
    if (needJournal) {
        BookmarkJournalEntry* e = [BookmarkJournalEntry journalWithAction:JOURNAL_ADD
                                                                 bookmark:bookmark
                                                                    model:self
                                                                    index:i
                                                               identifier:nil];
        [journal_ addObject:e];
    }
    if (isDefault) {
        [self setDefaultByGuid:[bookmark objectForKey:KEY_GUID]];
    }
    if (needJournal) {
        [self postChangeNotification];
    }
}

- (void)setBookmark:(Profile*)bookmark withGuid:(NSString*)guid
{
    int i = [self indexOfProfileWithGuid:guid];
    if (i >= 0) {
        [self setBookmark:bookmark atIndex:i];
    }
}

- (void)removeAllBookmarks
{
    [[self debugHistoryForGuid:@"na"] addObject:[NSString stringWithFormat:@"%@: Remove all bookmarks",
                                                 self]];
    [bookmarks_ removeAllObjects];
    defaultBookmarkGuid_ = @"";
    [journal_ addObject:[BookmarkJournalEntry journalWithAction:JOURNAL_REMOVE_ALL bookmark:nil model:self identifier:nil]];
    [self postChangeNotification];
}

- (NSArray*)rawData
{
    return bookmarks_;
}

- (void)load:(NSArray *)prefs {
    [bookmarks_ removeAllObjects];
    for (Profile *profile in prefs) {
        NSArray *tags = profile[KEY_TAGS];
        if (![tags containsObject:@"bonjour"]) {
            [self addBookmark:profile];
        }
    }
    [[self debugHistoryForGuid:@"na"] addObject:[NSString stringWithFormat:@"%@: Load bookmarks. Now have %@.",
                                                 self,
                                                 [self guids]]];
}

+ (NSString*)freshGuid {
    return [NSString uuid];
}

- (int)indexOfProfileWithGuid:(NSString*)guid
{
    return [self indexOfProfileWithGuid:guid withFilter:@""];
}

- (int)indexOfProfileWithGuid:(NSString*)guid withFilter:(NSString*)filter
{
    NSArray* tokens = [self.class parseFilter:filter];
    int count = [bookmarks_ count];
    int n = 0;
    for (int i = 0; i < count; ++i) {
        if (![self.class doesProfile:[self profileAtIndex:i] matchFilter:tokens]) {
            continue;
        }
        if ([[[bookmarks_ objectAtIndex:i] objectForKey:KEY_GUID] isEqualToString:guid]) {
            return n;
        }
        ++n;
    }
    return -1;
}

- (Profile *)defaultProfile {
    return [self defaultBookmark];
}

- (Profile*)defaultBookmark
{
    return [self bookmarkWithGuid:defaultBookmarkGuid_];
}

- (Profile*)bookmarkWithName:(NSString*)name
{
    int count = [bookmarks_ count];
    for (int i = 0; i < count; ++i) {
        if ([[[bookmarks_ objectAtIndex:i] objectForKey:KEY_NAME] isEqualToString:name]) {
            return [bookmarks_ objectAtIndex:i];
        }
    }
    return nil;
}

- (Profile*)bookmarkWithGuid:(NSString*)guid
{
    int count = [bookmarks_ count];
    for (int i = 0; i < count; ++i) {
        if ([[[bookmarks_ objectAtIndex:i] objectForKey:KEY_GUID] isEqualToString:guid]) {
            return [bookmarks_ objectAtIndex:i];
        }
    }
    return nil;
}

- (int)indexOfBookmarkWithName:(NSString*)name
{
    int count = [bookmarks_ count];
    for (int i = 0; i < count; ++i) {
        if ([[[bookmarks_ objectAtIndex:i] objectForKey:KEY_NAME] isEqualToString:name]) {
            return i;
        }
    }
    return -1;
}

- (NSArray*)allTags
{
    NSMutableSet *tags = [NSMutableSet set];
    for (Profile *profile in bookmarks_) {
        for (NSString *tag in [profile objectForKey:KEY_TAGS]) {
            [tags addObject:tag];
        }
    }
    return [tags allObjects];
}

- (Profile *)setObjectsFromDictionary:(NSDictionary *)dictionary inProfile:(Profile *)profile {
    NSMutableDictionary *newDict = [[profile mutableCopy] autorelease];
    [dictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        [newDict setObject:obj forKey:key];
    }];
    NSString *guid = [profile objectForKey:KEY_GUID];
    Profile *newProfile = [NSDictionary dictionaryWithDictionary:newDict];
    [self setBookmark:newProfile withGuid:guid];
    return newProfile;
}

- (Profile*)setObject:(id)object forKey:(NSString*)key inBookmark:(Profile*)bookmark {
    NSMutableDictionary* newDict = [NSMutableDictionary dictionaryWithDictionary:bookmark];
    if (object == nil) {
        [newDict removeObjectForKey:key];
    } else {
        [newDict setObject:object forKey:key];
    }
    NSString* guid = [bookmark objectForKey:KEY_GUID];
    Profile* newBookmark = [NSDictionary dictionaryWithDictionary:newDict];
    [self setBookmark:newBookmark
             withGuid:guid];
    return newBookmark;
}

- (void)setDefaultByGuid:(NSString*)guid
{
    [guid retain];
    [defaultBookmarkGuid_ release];
    defaultBookmarkGuid_ = guid;
    if (prefs_) {
        [prefs_ setObject:defaultBookmarkGuid_ forKey:KEY_DEFAULT_GUID];
    }
    [journal_ addObject:[BookmarkJournalEntry journalWithAction:JOURNAL_SET_DEFAULT
                                                       bookmark:[self defaultBookmark]
                                                          model:self
                                                     identifier:nil]];
    [self postChangeNotification];
}

- (NSArray *)names
{
    NSMutableArray *array = [NSMutableArray array];
    for (Profile *profile in bookmarks_) {
        [array addObject:[profile objectForKey:KEY_NAME]];
    }
    return array;
}

- (void)setProfilePreservingGuidWithGuid:(NSString *)origGuid
                             fromProfile:(Profile *)bookmark
                               overrides:(NSDictionary<NSString *, id> *)overrides {
    Profile *origProfile = [self bookmarkWithGuid:origGuid];
    NSString *preDivorceGuid = origProfile[KEY_ORIGINAL_GUID];
    Profile *preDivorceProfile = [[ProfileModel sharedInstance] bookmarkWithGuid:preDivorceGuid];

    // Only preserve the name if it has changed since the divorce.
    BOOL preserveName = NO;
    if (preDivorceProfile &&
        ![preDivorceProfile[KEY_NAME] isEqualToString:origProfile[KEY_NAME]]) {
        preserveName = YES;
    }

    NSMutableDictionary *dict = [[bookmark mutableCopy] autorelease];
    if (preserveName) {
        dict[KEY_NAME] = [[origProfile[KEY_NAME] copy] autorelease];
    }
    dict[KEY_GUID] = [[origGuid copy] autorelease];

    // Change the dict in the sessions bookmarks so that if you copy it back, it gets copied to
    // the new profile.
    dict[KEY_ORIGINAL_GUID] = [[bookmark[KEY_GUID] copy] autorelease];
    [dict it_mergeFrom:overrides];
    [[ProfileModel sessionsInstance] setBookmark:dict withGuid:origGuid];
    [self postNotificationName:kReloadAllProfiles object:nil userInfo:nil];
}

- (void)recordSortOrder {
    if (!prefs_) {
        return;
    }
    [prefs_ setObject:self.guids forKey:@"NoSyncSortedGUIDs"];
}

- (void)moveProfileWithGuidIfNeededToRespectSortOrder:(NSString *)guid {
    NSArray<NSString *> *order = [prefs_ objectForKey:@"NoSyncSortedGUIDs"];
    if (!order) {
        return;
    }

    const NSInteger j = [self desiredIndexFor:guid using:order];
    if (j == NSNotFound) {
        return;
    }
    [self moveGuid:guid toRow:j];
}

- (NSInteger)desiredIndexFor:(NSString *)guid using:(NSArray<NSString *> *)order {
    // Find where this guid is in `order`.
    const NSInteger savedIndex = [order indexOfObject:guid];
    if (savedIndex == NSNotFound) {
        return NSNotFound;
    }

    // Create an inverted index of the current order, mapping guid -> index
    NSMutableDictionary<NSString *, NSNumber *> *existing = [NSMutableDictionary dictionary];
    [bookmarks_ enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        existing[obj[KEY_GUID]] = @(idx);
    }];

    // Search backwards from savedIndex for a predecessor we have.
    for (NSInteger i = savedIndex - 1; i >= 0; i--) {
        NSString *orderGuid = order[i];
        NSNumber *n = existing[orderGuid];
        if (!n) {
            continue;
        }
        const NSInteger existingIndex = n.integerValue;
        return existingIndex + 1;
    }

    // Search forwards from savedIndex for a successor we have.
    for (NSInteger i = savedIndex + 1; i < order.count; i++) {
        NSString *orderGuid = order[i];
        NSNumber *n = existing[orderGuid];
        if (!n) {
            continue;
        }
        const NSInteger existingIndex = n.integerValue;
        return existingIndex;
    }

    return NSNotFound;
}

- (void)moveGuid:(NSString*)guid toRow:(int)destinationRow
{
    int sourceRow = [self indexOfProfileWithGuid:guid];
    if (sourceRow < 0) {
        return;
    }
    if (sourceRow == destinationRow) {
        return;
    }
    Profile* bookmark = [bookmarks_ objectAtIndex:sourceRow];
    [bookmark retain];
    [[self debugHistoryForGuid:bookmark[KEY_GUID]] addObject:[NSString stringWithFormat:@"%@: Moving guid %@ to row %@. First, remove it from row %@",
                                                              self,
                                                              guid,
                                                              @(destinationRow),
                                                              @(sourceRow)]];
    [bookmarks_ removeObjectAtIndex:sourceRow];
    if (sourceRow < destinationRow) {
        destinationRow--;
    }
    [[self debugHistoryForGuid:bookmark[KEY_GUID]] addObject:[NSString stringWithFormat:@"%@: Now insert it %@ at row %@",
                                                              self,
                                                              guid,
                                                              @(destinationRow)]];
    [bookmarks_ insertObject:bookmark atIndex:destinationRow];
    [bookmark release];
}

- (void)rebuildMenus
{
    [journal_ addObject:[BookmarkJournalEntry journalWithAction:JOURNAL_REMOVE_ALL bookmark:nil model:self identifier:nil]];
    int i = 0;
    for (Profile *b in bookmarks_) {
        BookmarkJournalEntry* e = [BookmarkJournalEntry journalWithAction:JOURNAL_ADD bookmark:b model:self index:i identifier:nil];
        i += 1;
        [journal_ addObject:e];
    }
    [self postChangeNotification];
}

- (void)performBlockWithCoalescedNotifications:(void (^)(void))block {
    if (!_delayedNotifications) {
        _delayedNotifications = [[NSMutableArray alloc] init];

        block();

        for (NSNotification *notification in _delayedNotifications) {
            [[NSNotificationCenter defaultCenter] postNotification:notification];
        }
        [_delayedNotifications release];
        _delayedNotifications = nil;
        [self flush];
    } else {
        block();
    }
}

- (void)postNotificationName:(NSString *)name object:(id)object userInfo:(id)userInfo {
    NSNotification *notification = [NSNotification notificationWithName:name object:object userInfo:userInfo];
    [self postNotification:notification];
}

- (void)postNotification:(NSNotification *)notification {
    if (_delayedNotifications) {
        NSNotification *last = [_delayedNotifications lastObject];
        if ([notification.name isEqualToString:kReloadAddressBookNotification] &&
            [last.name isEqualToString:notification.name]) {
            // Special hack to combine journals to avoid sending a million notifications each with a
            // small journal.
            NSArray *lastArray = last.userInfo[@"array"] ?: @[];
            NSArray *thisArray = notification.userInfo[@"array"] ?: @[];
            NSArray *combinedArray = [lastArray arrayByAddingObjectsFromArray:thisArray];
            NSNotification *combined = [NSNotification notificationWithName:notification.name object:nil userInfo:@{ @"array": combinedArray }];
            [_delayedNotifications removeLastObject];
            [_delayedNotifications addObject:combined];
        } else {
            [_delayedNotifications addObject:notification];
        }
    } else {
        [[NSNotificationCenter defaultCenter] postNotification:notification];
    }
}

- (void)postChangeNotification {
    DLog(@"Post bookmark changed notification");
    if (postChanges_) {
        DLog(@"Posting notification");
        // NOTE: if userInfo is ever changed update -postNotification:, which
        // has code that coalesces userinfos for this notification.
        [self postNotificationName:kReloadAddressBookNotification object:nil userInfo:@{ @"array": journal_ }];
    }
    [journal_ release];
    journal_ = [[NSMutableArray alloc] init];
}

- (void)dump
{
    for (int i = 0; i < [self numberOfBookmarks]; ++i) {
        Profile* bookmark = [self profileAtIndex:i];
        NSLog(@"%d: %@ %@", i, [bookmark objectForKey:KEY_NAME], [bookmark objectForKey:KEY_GUID]);
    }
}

- (NSArray<Profile *> *)bookmarks {
    return bookmarks_;
}

- (NSArray*)guids
{
    NSMutableArray* guids = [NSMutableArray arrayWithCapacity:[bookmarks_ count]];
    for (Profile* bookmark in bookmarks_) {
        [guids addObject:[bookmark objectForKey:KEY_GUID]];
    }
    return guids;
}

- (void)flush {
    if (_delayedNotifications) {
        return;
    }
    // If KEY_NEW_BOOKMARKS is a string then it was overridden at the command line to point at a
    // file and we shouldn't save it to user defaults. If it wasn't overridden it'll be an array.
    if (![[prefs_ objectForKey:KEY_NEW_BOOKMARKS] isKindOfClass:[NSString class]]) {
        [prefs_ setObject:[self rawData] forKey:KEY_NEW_BOOKMARKS];
    }
}

- (nonnull id<iTermProfileModelMenuController>)menuController {
    return _menuController;
}

- (nonnull NSDictionary *)profileWithGuid:(nonnull NSString *)guid {
    return [self bookmarkWithGuid:guid];
}

@end

