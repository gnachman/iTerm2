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
#import "iTermProfileSearchToken.h"
#import "NSStringITerm.h"
#import "PreferencePanel.h"

NSString *const kReloadAddressBookNotification = @"iTermReloadAddressBook";
NSString *const kReloadAllProfiles = @"kReloadAllProfiles";

id gAltOpenAllRepresentedObject;
// Set to true if a bookmark was changed automatically due to migration to a new
// standard.
int gMigrated;

@implementation ProfileModel

+ (void)initialize
{
    gAltOpenAllRepresentedObject = [[NSObject alloc] init];
}

+ (BOOL)migrated
{
    return gMigrated;
}

- (ProfileModel*)init
{
    self = [super init];
    if (self) {
        bookmarks_ = [[NSMutableArray alloc] init];
        defaultBookmarkGuid_ = @"";
        journal_ = [[NSMutableArray alloc] init];
    }
    return self;
}

+ (ProfileModel*)sharedInstance
{
    static ProfileModel* shared = nil;

    if (!shared) {
        shared = [[ProfileModel alloc] init];
        shared->prefs_ = [NSUserDefaults standardUserDefaults];
        shared->postChanges_ = YES;
    }

    return shared;
}

+ (ProfileModel*)sessionsInstance
{
    static ProfileModel* shared = nil;

    if (!shared) {
        shared = [[ProfileModel alloc] init];
        shared->prefs_ = nil;
        shared->postChanges_ = NO;
    }

    return shared;
}

- (void)dealloc
{
    [super dealloc];
    [journal_ release];
    NSLog(@"Deallocating bookmark model!");
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
    NSArray* tokens = [self parseFilter:filter];
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
                matchFilter:(NSArray *)tokens
               nameIndexSet:(NSMutableIndexSet *)nameIndexSet
               tagIndexSets:(NSArray *)tagIndexSets {
    NSArray* nameWords = [name componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    for (int i = 0; i < [tokens count]; ++i) {
        iTermProfileSearchToken *token = [tokens objectAtIndex:i];
        // Search each word in tag until one has this token as a prefix.
        // First see if this token occurs in the title
        BOOL found = [token matchesAnyWordInNameWords:nameWords];

        if (found) {
            [nameIndexSet addIndexesInRange:token.range];
        }
        // If not try each tag.
        for (int j = 0; !found && j < [tags count]; ++j) {
            // Expand the jth tag into an array of the words in the tag
            NSArray* tagWords = [[tags objectAtIndex:j] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            found = [token matchesAnyWordInTagWords:tagWords];
            if (found) {
                NSMutableIndexSet *indexSet = tagIndexSets[j];
                [indexSet addIndexesInRange:token.range];
            }
        }
        if (!found && name != nil) {
            // No tag had token i as a prefix. If name is nil then we don't really care about the
            // answer and we just want index sets.
            return NO;
        }
    }
    return YES;
}

+ (NSArray *)parseFilter:(NSString*)filter {
    NSArray *phrases = [filter componentsBySplittingProfileListQuery];
    NSMutableArray *tokens = [NSMutableArray array];
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

- (void)addBookmark:(Profile*)bookmark inSortedOrder:(BOOL)sort
{

    NSMutableDictionary *newBookmark = [[bookmark mutableCopy] autorelease];

    // Ensure required fields are present
    if (![newBookmark objectForKey:KEY_NAME]) {
        [newBookmark setObject:@"Bookmark" forKey:KEY_NAME];
    }
    if (![newBookmark objectForKey:KEY_TAGS]) {
        [newBookmark setObject:@[] forKey:KEY_TAGS];
    }
    if (![newBookmark objectForKey:KEY_CUSTOM_COMMAND]) {
        [newBookmark setObject:@"No" forKey:KEY_CUSTOM_COMMAND];
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
    BookmarkJournalEntry* e = [BookmarkJournalEntry journalWithAction:JOURNAL_ADD bookmark:bookmark model:self];
    e->index = theIndex;
    [journal_ addObject:e];

    if (![self defaultBookmark] || (isDeprecatedDefaultBookmark && [isDeprecatedDefaultBookmark isEqualToString:@"Yes"])) {
        [self setDefaultByGuid:[bookmark objectForKey:KEY_GUID]];
    }
    [self postChangeNotification];
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

        [journal_ addObject:[BookmarkJournalEntry journalWithAction:JOURNAL_REMOVE bookmark:[bookmarks_ objectAtIndex:i] model:self]];
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
    [journal_ addObject:[BookmarkJournalEntry journalWithAction:JOURNAL_REMOVE bookmark:[bookmarks_ objectAtIndex:i] model:self]];
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
        [journal_ addObject:[BookmarkJournalEntry journalWithAction:JOURNAL_REMOVE bookmark:[bookmarks_ objectAtIndex:i] model:self]];
    }
    [bookmarks_ replaceObjectAtIndex:i withObject:bookmark];
    if (needJournal) {
        BookmarkJournalEntry* e = [BookmarkJournalEntry journalWithAction:JOURNAL_ADD bookmark:bookmark model:self];
        e->index = i;
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
    [bookmarks_ removeAllObjects];
    defaultBookmarkGuid_ = @"";
    [journal_ addObject:[BookmarkJournalEntry journalWithAction:JOURNAL_REMOVE_ALL bookmark:nil model:self]];
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

- (Profile*)setObject:(id)object forKey:(NSString*)key inBookmark:(Profile*)bookmark
{
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
                                                          model:self]];
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
                             fromProfile:(Profile *)bookmark {
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
    [[ProfileModel sessionsInstance] setBookmark:dict withGuid:origGuid];
    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles
                                                        object:nil
                                                      userInfo:nil];
}

- (void)moveGuid:(NSString*)guid toRow:(int)destinationRow
{
    int sourceRow = [self indexOfProfileWithGuid:guid];
    if (sourceRow < 0) {
        return;
    }
    Profile* bookmark = [bookmarks_ objectAtIndex:sourceRow];
    [bookmark retain];
    [bookmarks_ removeObjectAtIndex:sourceRow];
    if (sourceRow < destinationRow) {
        destinationRow--;
    }
    [bookmarks_ insertObject:bookmark atIndex:destinationRow];
    [bookmark release];
}

- (void)rebuildMenus
{
    [journal_ addObject:[BookmarkJournalEntry journalWithAction:JOURNAL_REMOVE_ALL bookmark:nil model:self]];
    int i = 0;
    for (Profile* b in bookmarks_) {
        BookmarkJournalEntry* e = [BookmarkJournalEntry journalWithAction:JOURNAL_ADD bookmark:b model:self];
        e->index = i++;
        [journal_ addObject:e];
    }
    [self postChangeNotification];
}

- (void)postChangeNotification {
    DLog(@"Post bookmark changed notification");
    if (postChanges_) {
        DLog(@"Posting notification");
        [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAddressBookNotification
                                                            object:nil
                                                          userInfo:[NSDictionary dictionaryWithObject:journal_ forKey:@"array"]];
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
    // If KEY_NEW_BOOKMARKS is a string then it was overridden at the command line to point at a
    // file and we shouldn't save it to user defaults. If it wasn't overridden it'll be an array.
    if (![[prefs_ objectForKey:KEY_NEW_BOOKMARKS] isKindOfClass:[NSString class]]) {
        [prefs_ setObject:[self rawData] forKey:KEY_NEW_BOOKMARKS];
    }
}

+ (BOOL)menuHasMultipleItemsExcludingAlternates:(NSMenu *)menu fromIndex:(int)first
{
    int n = 0;
    NSArray *array = [menu itemArray];
    for (int i = first; i < array.count; i++) {
        NSMenuItem *item = array[i];
        if (!item.isAlternate) {
            n++;
            if (n == 2) {
                return YES;
            }
        }
    }
    return NO;
}

+ (NSMenu*)findOrCreateTagSubmenuInMenu:(NSMenu*)menu
                         startingAtItem:(int)skip
                               withName:(NSString*)multipartName
                                 params:(JournalParams*)params
{
    NSArray *parts = [multipartName componentsSeparatedByString:@"/"];
    if (parts.count == 0) {
        return nil;
    }
    NSString *name = parts[0];
    NSArray* items = [menu itemArray];
    int pos = [menu numberOfItems];
    int N = pos;
    NSMenu *submenu = nil;
    for (int i = skip; i < N; i++) {
        NSMenuItem* cur = [items objectAtIndex:i];
        if (![cur submenu] || [cur isSeparatorItem]) {
            pos = i;
            break;
        }
        int comp = [[cur title] caseInsensitiveCompare:name];
        if (comp == 0) {
            submenu = [cur submenu];
            break;
        } else if (comp > 0) {
            pos = i;
            break;
        }
    }

    if (!submenu) {
        // Add menu item with submenu
        NSMenuItem* newItem = [[[NSMenuItem alloc] initWithTitle:name
                                                          action:nil
                                                   keyEquivalent:@""] autorelease];
        [newItem setSubmenu:[[[NSMenu alloc] init] autorelease]];
        [menu insertItem:newItem atIndex:pos];
        submenu = [newItem submenu];
    }
    
    if (parts.count > 1) {
        NSArray *tail = [parts subarrayWithRange:NSMakeRange(1, parts.count - 1)];
        NSString *suffix = [tail componentsJoinedByString:@"/"];
        NSMenu *menuToAddOpenAll = submenu;
        submenu = [self findOrCreateTagSubmenuInMenu:submenu
                                      startingAtItem:0
                                            withName:suffix
                                              params:params];
        if (menuToAddOpenAll &&
            [self menuHasMultipleItemsExcludingAlternates:menuToAddOpenAll fromIndex:0] &&
            ![self menuHasOpenAll:menuToAddOpenAll]) {
            [self addOpenAllToMenu:menuToAddOpenAll params:params];
        }
    }
    return submenu;
}

+ (void)addOpenAllToMenu:(NSMenu*)menu params:(JournalParams*)params
{
    // Add separator + open all menu items
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* openAll = [menu addItemWithTitle:@"Open All" action:params->openAllSelector keyEquivalent:@""];
    [openAll setTarget:params->target];

    // Add alternate open all menu
    NSMenuItem* altOpenAll = [[NSMenuItem alloc] initWithTitle:@"Open All in New Window"
                                                        action:params->alternateOpenAllSelector
                                                 keyEquivalent:@""];
    [altOpenAll setTarget:params->target];
    [altOpenAll setKeyEquivalentModifierMask:NSAlternateKeyMask];
    [altOpenAll setAlternate:YES];
    [altOpenAll setRepresentedObject:gAltOpenAllRepresentedObject];
    [menu addItem:altOpenAll];
    [altOpenAll release];
}

+ (BOOL)menuHasOpenAll:(NSMenu*)menu
{
    NSArray* items = [menu itemArray];
    if ([items count] < 3) {
        return NO;
    }
    int n = [items count];
    return ([[items objectAtIndex:n-1] representedObject] == gAltOpenAllRepresentedObject);
}

- (int)positionOfBookmark:(Profile*)b startingAtItem:(int)skip inMenu:(NSMenu*)menu
{
    // Find position of bookmark in menu
    NSString* name = [b objectForKey:KEY_NAME];
    int N = [menu numberOfItems];
    if ([ProfileModel menuHasOpenAll:menu]) {
        N -= 3;
    }
    NSArray* items = [menu itemArray];
    int pos = N;
    for (int i = skip; i < N; i++) {
        NSMenuItem* cur = [items objectAtIndex:i];
        if ([cur isSeparatorItem]) {
            break;
        }
        if ([cur isHidden] || [cur submenu]) {
            continue;
        }
        if ([[cur title] caseInsensitiveCompare:name] > 0) {
            pos = i;
            break;
        }
    }

    return pos;
}

- (int)positionOfBookmarkWithIndex:(int)theIndex startingAtItem:(int)skip inMenu:(NSMenu*)menu
{
    // Find position of bookmark in menu
    int N = [menu numberOfItems];
    if ([ProfileModel menuHasOpenAll:menu]) {
        N -= 3;
    }
    NSArray* items = [menu itemArray];
    int pos = N;
    for (int i = skip; i < N; i++) {
        NSMenuItem* cur = [items objectAtIndex:i];
        if ([cur isSeparatorItem]) {
            break;
        }
        if ([cur isHidden] || [cur submenu]) {
            continue;
        }
        if ([cur tag] > theIndex) {
            pos = i;
            break;
        }
    }

    return pos;
}

- (void)addBookmark:(Profile*)b
             toMenu:(NSMenu*)menu
         atPosition:(int)pos
         withParams:(JournalParams*)params
        isAlternate:(BOOL)isAlternate
            withTag:(int)tag
{
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:[b objectForKey:KEY_NAME]
                                                  action:isAlternate ? params->alternateSelector : params->selector
                                           keyEquivalent:@""];
    NSString* shortcut = [b objectForKey:KEY_SHORTCUT];
    if ([shortcut length]) {
        [item setKeyEquivalent:[shortcut lowercaseString]];
        [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSControlKeyMask | (isAlternate ? NSAlternateKeyMask : 0)];
    } else if (isAlternate) {
        [item setKeyEquivalentModifierMask:NSAlternateKeyMask];
    }
    [item setAlternate:isAlternate];
    [item setTarget:params->target];
    [item setRepresentedObject:[[[b objectForKey:KEY_GUID] copy] autorelease]];
    [item setTag:tag];
    [menu insertItem:item atIndex:pos];
    [item release];
}

- (void)addBookmark:(Profile*)b
             toMenu:(NSMenu*)menu
     startingAtItem:(int)skip
           withTags:(NSArray*)tags
             params:(JournalParams*)params
              atPos:(int)theIndex
{
    int pos;
    if (theIndex == -1) {
        // Add in sorted order
        pos = [self positionOfBookmark:b startingAtItem:skip inMenu:menu];
    } else {
        pos = [self positionOfBookmarkWithIndex:theIndex startingAtItem:skip inMenu:menu];
    }

    if (![tags count]) {
        // Add item & alternate if no tags
        [self addBookmark:b toMenu:menu atPosition:pos withParams:params isAlternate:NO withTag:theIndex];
        [self addBookmark:b toMenu:menu atPosition:pos+1 withParams:params isAlternate:YES withTag:theIndex];
    }

    // Add to tag submenus
    for (NSString* tag in [NSSet setWithArray:tags]) {
        NSMenu* tagSubMenu = [ProfileModel findOrCreateTagSubmenuInMenu:menu
                                                          startingAtItem:skip
                                                                withName:tag
                                                                  params:params];
        [self addBookmark:b toMenu:tagSubMenu startingAtItem:0 withTags:nil params:params atPos:theIndex];
    }

    if ([[self class] menuHasMultipleItemsExcludingAlternates:menu fromIndex:skip] &&
        ![ProfileModel menuHasOpenAll:menu]) {
        [ProfileModel addOpenAllToMenu:menu params:params];
    }
}

+ (void)applyAddJournalEntry:(BookmarkJournalEntry*)e toMenu:(NSMenu*)menu startingAtItem:(int)skip params:(JournalParams*)params
{
    ProfileModel* model = e->model;
    Profile* b = [model bookmarkWithGuid:e->guid];
    if (!b) {
        return;
    }
    [model addBookmark:b toMenu:menu startingAtItem:skip withTags:[b objectForKey:KEY_TAGS] params:params atPos:e->index];
}

+ (NSArray *)menuItemsForTag:(NSString *)multipartName inMenu:(NSMenu *)menu
{
    NSMutableArray *result = [NSMutableArray array];
    NSArray *parts = [multipartName componentsSeparatedByString:@"/"];
    NSMenuItem *item = nil;
    for (NSString *name in parts) {
        item = [menu itemWithTitle:name];
        if (!item) {
            break;
        }
        [result addObject:item];
        menu = [item submenu];
    }
    return result;
}

+ (void)applyRemoveJournalEntry:(BookmarkJournalEntry*)e toMenu:(NSMenu*)menu startingAtItem:(int)skip params:(JournalParams*)params
{
    int pos = [menu indexOfItemWithRepresentedObject:e->guid];
    if (pos != -1) {
        [menu removeItemAtIndex:pos];
        [menu removeItemAtIndex:pos];
    }

    // Remove bookmark from each tag it belongs to
    for (NSString* tag in e->tags) {
        NSArray *items = [self menuItemsForTag:tag inMenu:menu];
        for (int i = items.count - 1; i >= 0; i--) {
            NSMenuItem *item = items[i];
            NSMenu *submenu = [item submenu];
            if (submenu) {
                if (i == items.count - 1) {
                    [self applyRemoveJournalEntry:e toMenu:submenu startingAtItem:0 params:params];
                }
                if ([submenu numberOfItems] == 0) {
                    [[[item parentItem] submenu] removeItem:item];
                    
                    // Remove "open all" (not at first level)
                    if ([ProfileModel menuHasOpenAll:submenu] && submenu.numberOfItems <= 5) {
                        [menu removeItemAtIndex:[menu numberOfItems] - 1];
                        [menu removeItemAtIndex:[menu numberOfItems] - 1];
                        [menu removeItemAtIndex:[menu numberOfItems] - 1];
                    }
                } else {
                    break;
                }
            }
        }
    }

    // Remove "open all" section if it's no longer needed.
    // [0, ..., skip-1, bm1, bm1alt, separator, open all, open all alternate]
    if (([ProfileModel menuHasOpenAll:menu] && [menu numberOfItems] <= skip + 5)) {
        [menu removeItemAtIndex:[menu numberOfItems] - 1];
        [menu removeItemAtIndex:[menu numberOfItems] - 1];
        [menu removeItemAtIndex:[menu numberOfItems] - 1];
    }
}

+ (void)applyRemoveAllJournalEntry:(BookmarkJournalEntry*)e toMenu:(NSMenu*)menu startingAtItem:(int)skip params:(JournalParams*)params
{
    while ([menu numberOfItems] > skip) {
        [menu removeItemAtIndex:[menu numberOfItems] - 1];
    }
}

+ (void)applySetDefaultJournalEntry:(BookmarkJournalEntry*)e toMenu:(NSMenu*)menu startingAtItem:(int)skip params:(JournalParams*)params
{
}

+ (void)applyJournal:(NSDictionary*)journalDict toMenu:(NSMenu*)menu startingAtItem:(int)skip params:(JournalParams*)params
{
    NSArray* journal = [journalDict objectForKey:@"array"];
    for (BookmarkJournalEntry* e in journal) {
        switch (e->action) {
            case JOURNAL_ADD:
                [ProfileModel applyAddJournalEntry:e toMenu:menu startingAtItem:skip params:params];
                break;

            case JOURNAL_REMOVE:
                [ProfileModel applyRemoveJournalEntry:e toMenu:menu startingAtItem:skip params:params];
                break;

            case JOURNAL_REMOVE_ALL:
                [ProfileModel applyRemoveAllJournalEntry:e toMenu:menu startingAtItem:skip params:params];
                break;

            case JOURNAL_SET_DEFAULT:
                [ProfileModel applySetDefaultJournalEntry:e toMenu:menu startingAtItem:skip params:params];
                break;

            default:
                assert(false);
        }
    }
}

+ (void)applyJournal:(NSDictionary*)journal toMenu:(NSMenu*)menu params:(JournalParams*)params
{
    [ProfileModel applyJournal:journal toMenu:menu startingAtItem:0 params:params];
}


@end

@implementation BookmarkJournalEntry


+ (BookmarkJournalEntry*)journalWithAction:(JournalAction)action
                                  bookmark:(Profile*)bookmark
                                     model:(ProfileModel*)model
{
    BookmarkJournalEntry* entry = [[[BookmarkJournalEntry alloc] init] autorelease];
    entry->action = action;
    entry->guid = [[bookmark objectForKey:KEY_GUID] copy];
    entry->model = model;
    entry->tags = [[NSArray alloc] initWithArray:[bookmark objectForKey:KEY_TAGS]];
    return entry;
}

- (void)dealloc
{
    [guid release];
    [tags release];
    [super dealloc];
}

@end
