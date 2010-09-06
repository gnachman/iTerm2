/*
 **  BookmarkModel.m
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

#import <iTerm/ITAddressBookMgr.h>
#import <iTerm/BookmarkModel.h>


@implementation BookmarkModel

- (BookmarkModel*)init
{
    bookmarks_ = [[NSMutableArray alloc] init];
    defaultBookmarkGuid_ = @"";
    return self;
}

+ (BookmarkModel*)sharedInstance
{
    static BookmarkModel* shared = nil;
    
    if (!shared) {
        shared = [[BookmarkModel alloc] init];
        shared->prefs_ = [NSUserDefaults standardUserDefaults];
    }
    
    return shared;
}

+ (BookmarkModel*)sessionsInstance
{
    static BookmarkModel* shared = nil;
    
    if (!shared) {
        shared = [[BookmarkModel alloc] init];
        shared->prefs_ = nil;
    }
    
    return shared;
}


- (int)numberOfBookmarks
{
    return [bookmarks_ count];
}

- (BOOL)_document:(NSArray *)nameWords containsToken:(NSString *)token
{
    for (int k = 0; k < [nameWords count]; ++k) {
        NSString* tagPart = [nameWords objectAtIndex:k];
        NSRange range = [tagPart rangeOfString:token options:(NSCaseInsensitiveSearch | NSAnchoredSearch)];
        if (range.location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}
- (BOOL)doesBookmarkAtIndex:(int)theIndex matchFilter:(NSArray*)tokens
{
    Bookmark* bookmark = [self bookmarkAtIndex:theIndex];
    NSArray* tags = [bookmark objectForKey:KEY_TAGS];
    NSArray* nameWords = [[bookmark objectForKey:KEY_NAME] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    for (int i = 0; i < [tokens count]; ++i) {
        NSString* token = [tokens objectAtIndex:i];
        if (![token length]) {
            continue;
        }
        // Search each word in tag until one has this token as a prefix.
        bool found;
        
        // First see if this token occurs in the title
        found = [self _document:nameWords containsToken:token];
        
        // If not try each tag.
        for (int j = 0; !found && j < [tags count]; ++j) {
            // Expand the jth tag into an array of the words in the tag
            NSArray* tagWords = [[tags objectAtIndex:j] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            found = [self _document:tagWords containsToken:token];
        }
        if (!found) {
            // No tag had token i as a prefix.
            return NO;
        }
    }
    return YES;
}

- (NSArray*)parseFilter:(NSString*)filter
{
    return [filter componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

- (int)numberOfBookmarksWithFilter:(NSString*)filter
{
    NSArray* tokens = [self parseFilter:filter];
    int count = [bookmarks_ count];
    int n = 0;
    for (int i = 0; i < count; ++i) {
        if ([self doesBookmarkAtIndex:i matchFilter:tokens]) {
            ++n;
        }
    }
    return n;
}

- (Bookmark*)bookmarkAtIndex:(int)i
{
    if (i < 0 || i >= [bookmarks_ count]) {
        return nil;
    }
    return [bookmarks_ objectAtIndex:i];
}

- (Bookmark*)bookmarkAtIndex:(int)theIndex withFilter:(NSString*)filter
{
    NSArray* tokens = [self parseFilter:filter];
    int count = [bookmarks_ count];
    int n = 0;
    for (int i = 0; i < count; ++i) {
        if ([self doesBookmarkAtIndex:i matchFilter:tokens]) {
            if (n == theIndex) {
                return [self bookmarkAtIndex:i];
            }
            ++n;
        }
    }
    return nil;
}

- (void)addBookmark:(Bookmark*)bookmark
{
    [self addBookmark:bookmark inSortedOrder:NO];
}

- (void)addBookmark:(Bookmark*)bookmark inSortedOrder:(BOOL)sort
{
    // Ensure required fields are present
    if (![bookmark objectForKey:KEY_NAME]) {
        NSMutableDictionary* aDict = [[NSMutableDictionary alloc] initWithDictionary:bookmark];
        [aDict setObject:@"Bookmark" forKey:KEY_NAME];
        bookmark = aDict;
    }
    if (![bookmark objectForKey:KEY_TAGS]) {
        NSMutableDictionary* aDict = [[NSMutableDictionary alloc] initWithDictionary:bookmark];
        [aDict setObject:[NSArray arrayWithObjects:nil] forKey:KEY_TAGS];
        bookmark = aDict;
    }
    if (![bookmark objectForKey:KEY_CUSTOM_COMMAND]) {
        NSMutableDictionary* aDict = [[NSMutableDictionary alloc] initWithDictionary:bookmark];
        [aDict setObject:@"No" forKey:KEY_CUSTOM_COMMAND];
        bookmark = aDict;
    }
    if (![bookmark objectForKey:KEY_COMMAND]) {
        NSMutableDictionary* aDict = [[NSMutableDictionary alloc] initWithDictionary:bookmark];
        [aDict setObject:@"/bin/bash --login" forKey:KEY_COMMAND];
        bookmark = aDict;
    }
    if (![bookmark objectForKey:KEY_GUID]) {
        NSMutableDictionary* aDict = [[NSMutableDictionary alloc] initWithDictionary:bookmark];
        [aDict setObject:[BookmarkModel newGuid] forKey:KEY_GUID];
        bookmark = aDict;
    }
    if (![bookmark objectForKey:KEY_DEFAULT_BOOKMARK]) {
        NSMutableDictionary* aDict = [[NSMutableDictionary alloc] initWithDictionary:bookmark];
        [aDict setObject:@"No" forKey:KEY_DEFAULT_BOOKMARK];
        bookmark = aDict;
    }
    
    if (sort) {
        // Insert alphabetically. Sort so that objects with the "bonjour" tag come after objects without.
        int insertionPoint = -1;
        NSString* newName = [bookmark objectForKey:KEY_NAME];
        BOOL hasBonjour = [self bookmark:bookmark hasTag:@"bonjour"];
        for (int i = 0; i < [bookmarks_ count]; ++i) {
            Bookmark* bookmarkAtI = [bookmarks_ objectAtIndex:i];
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
            [bookmarks_ addObject:[NSDictionary dictionaryWithDictionary:bookmark]];
        } else {
            [bookmarks_ insertObject:[NSDictionary dictionaryWithDictionary:bookmark] atIndex:insertionPoint];
        }
    } else {
        [bookmarks_ addObject:[NSDictionary dictionaryWithDictionary:bookmark]];
    }
    NSString* isDeprecatedDefaultBookmark = [bookmark objectForKey:KEY_DEFAULT_BOOKMARK];
    if (![self defaultBookmark] || (isDeprecatedDefaultBookmark && [isDeprecatedDefaultBookmark isEqualToString:@"Yes"])) {
        [self setDefaultByGuid:[bookmark objectForKey:KEY_GUID]];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermReloadAddressBook" object: nil userInfo: nil];    		    
}

- (BOOL)bookmark:(Bookmark*)bookmark hasTag:(NSString*)tag
{
    NSArray* tags = [bookmark objectForKey:KEY_TAGS];
    return [tags containsObject:tag];
}

- (int)convertFilteredIndex:(int)theIndex withFilter:(NSString*)filter
{
    NSArray* tokens = [self parseFilter:filter];
    int count = [bookmarks_ count];
    int n = 0;
    for (int i = 0; i < count; ++i) {
        if ([self doesBookmarkAtIndex:i matchFilter:tokens]) {
            if (n == theIndex) {
                return i;
            }
            ++n;
        }
    }
    return -1;
}

- (void)removeBookmarkAtIndex:(int)i
{
    NSAssert(i >= 0, @"Bounds");
    [bookmarks_ removeObjectAtIndex:i];
    if (![self defaultBookmark] && [bookmarks_ count]) {
        [self setDefaultByGuid:[[bookmarks_ objectAtIndex:0] objectForKey:KEY_GUID]];
    }
	[[NSNotificationCenter defaultCenter] postNotificationName: @"iTermReloadAddressBook" object: nil userInfo: nil];    		
}

- (void)removeBookmarkAtIndex:(int)i withFilter:(NSString*)filter
{
    [self removeBookmarkAtIndex:[self convertFilteredIndex:i withFilter:filter]];
}

- (void)removeBookmarkWithGuid:(NSString*)guid
{
    int i = [self indexOfBookmarkWithGuid:guid];
    if (i >= 0) {
        [self removeBookmarkAtIndex:i];
    }
}

- (void)setBookmark:(Bookmark*)bookmark atIndex:(int)i
{
    Bookmark* orig = [bookmarks_ objectAtIndex:i];
    BOOL isDefault = NO;
    if ([[orig objectForKey:KEY_GUID] isEqualToString:defaultBookmarkGuid_]) {
        isDefault = YES;
    }
    [bookmarks_ replaceObjectAtIndex:i withObject:bookmark];
    if (isDefault) {
        [self setDefaultByGuid:[bookmark objectForKey:KEY_GUID]];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermReloadAddressBook" object: nil userInfo: nil];    		
}

- (void)setBookmark:(Bookmark*)bookmark withGuid:(NSString*)guid
{
    int i = [self indexOfBookmarkWithGuid:guid];
    if (i >= 0) {
        [self setBookmark:bookmark atIndex:i];
    }
}

- (void)removeAllBookmarks
{
    [bookmarks_ removeAllObjects];
    defaultBookmarkGuid_ = @"";
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermReloadAddressBook" object: nil userInfo: nil];    		
}

- (NSArray*)rawData
{
    return bookmarks_;
}

- (void)load:(NSArray*)prefs
{
    [bookmarks_ removeAllObjects];
    for (int i = 0; i < [prefs count]; ++i) {
        Bookmark* bookmark = [prefs objectAtIndex:i];
        NSArray* tags = [bookmark objectForKey:KEY_TAGS];
        if (![tags containsObject:@"bonjour"]) {
            [self addBookmark:bookmark];
        }
    }
    [bookmarks_ retain];
}

+ (NSString*)newGuid
{
    CFUUIDRef uuidObj = CFUUIDCreate(nil); //create a new UUID
    //get the string representation of the UUID
    NSString *uuidString = (NSString*)CFUUIDCreateString(nil, uuidObj);
    CFRelease(uuidObj);
    return [uuidString autorelease];
}

- (int)indexOfBookmarkWithGuid:(NSString*)guid
{
    return [self indexOfBookmarkWithGuid:guid withFilter:@""];
}

- (int)indexOfBookmarkWithGuid:(NSString*)guid withFilter:(NSString*)filter
{
    NSArray* tokens = [self parseFilter:filter];
    int count = [bookmarks_ count];
    int n = 0;
    for (int i = 0; i < count; ++i) {
        if (![self doesBookmarkAtIndex:i matchFilter:tokens]) {
            continue;
        }
        if ([[[bookmarks_ objectAtIndex:i] objectForKey:KEY_GUID] isEqualToString:guid]) {
            return n;
        }
        ++n;
    }
    return -1;
}

- (Bookmark*)defaultBookmark
{
    return [self bookmarkWithGuid:defaultBookmarkGuid_];
}

- (Bookmark*)bookmarkWithName:(NSString*)name
{
    int count = [bookmarks_ count];
    for (int i = 0; i < count; ++i) {
        if ([[[bookmarks_ objectAtIndex:i] objectForKey:KEY_NAME] isEqualToString:name]) {
            return [bookmarks_ objectAtIndex:i];
        }
    }
    return nil;
}

- (Bookmark*)bookmarkWithGuid:(NSString*)guid
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
    NSMutableDictionary* temp = [[[NSMutableDictionary alloc] init] autorelease];
    for (int i = 0; i < [self numberOfBookmarks]; ++i) {
        Bookmark* bookmark = [self bookmarkAtIndex:i];
        NSArray* tags = [bookmark objectForKey:KEY_TAGS];
        for (int j = 0; j < [tags count]; ++j) {
            NSString* tag = [tags objectAtIndex:j];
            [temp setObject:@"" forKey:tag];
        }
    }
    return [temp allKeys];
}

- (void)setObject:(id)object forKey:(NSString*)key inBookmark:(Bookmark*)bookmark
{
    NSMutableDictionary* newDict = [NSMutableDictionary dictionaryWithDictionary:bookmark];
    [newDict setObject:object forKey:key];
    NSString* guid = [bookmark objectForKey:KEY_GUID];
    [self setBookmark:[NSDictionary dictionaryWithDictionary:newDict] 
             withGuid:guid];
}

- (void)setDefaultByGuid:(NSString*)guid
{    
    [guid retain];
    [defaultBookmarkGuid_ release];
    defaultBookmarkGuid_ = guid;
    if (prefs_) {
        [prefs_ setObject:defaultBookmarkGuid_ forKey:KEY_DEFAULT_GUID];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermReloadAddressBook" object: nil userInfo: nil];    		    
}

- (void)moveGuid:(NSString*)guid toRow:(int)destinationRow
{
    int sourceRow = [self indexOfBookmarkWithGuid:guid];
    if (sourceRow < 0) {
        return;
    }
    Bookmark* bookmark = [bookmarks_ objectAtIndex:sourceRow];
    [bookmark retain];
    [bookmarks_ removeObjectAtIndex:sourceRow];
    if (sourceRow < destinationRow) {
        destinationRow--;
    }
    [bookmarks_ insertObject:bookmark atIndex:destinationRow];
    [bookmark release];
}

- (void)dump
{
    for (int i = 0; i < [self numberOfBookmarks]; ++i) {
        Bookmark* bookmark = [self bookmarkAtIndex:i];
        NSLog(@"%d: %@ %@", i, [bookmark objectForKey:KEY_NAME], [bookmark objectForKey:KEY_GUID]);
    }
}

@end
