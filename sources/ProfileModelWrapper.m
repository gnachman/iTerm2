//
//  ProfileModelWrapper.m
//  iTerm
//
//  Created by George Nachman on 1/9/12.
//

#import "ProfileModelWrapper.h"
#import "DebugLogging.h"

@implementation ProfileModelWrapper {
    ProfileModel* underlyingModel;
    NSMutableArray* bookmarks;
    NSMutableString* filter;
    NSArray* sortDescriptors;
}

- (instancetype)initWithModel:(ProfileModel*)model {
    self = [super init];
    if (self) {
        underlyingModel = model;
        bookmarks = [[NSMutableArray alloc] init];
        filter = [[NSMutableString alloc] init];
        [self sync];
    }
    return self;
}

- (void)dealloc
{
    [bookmarks release];
    [filter release];
    [_lockedGuid release];
    [super dealloc];
}

- (void)setSortDescriptors:(NSArray*)newSortDescriptors
{
    [sortDescriptors autorelease];
    sortDescriptors = [newSortDescriptors retain];
}

- (void)dump
{
    for (int i = 0; i < [self numberOfBookmarks]; ++i) {
        NSLog(@"Dump of %p: At %d: %@", self, i, [[self profileTableRowAtIndex:i] name]);
    }
}

- (void)sort
{
    if ([sortDescriptors count] > 0) {
        [bookmarks sortUsingDescriptors:sortDescriptors];
    }
}

- (int)numberOfBookmarks
{
    return [bookmarks count];
}

- (ProfileTableRow *)profileTableRowAtIndex:(int)i
{
    return [bookmarks objectAtIndex:i];
}

- (Profile*)profileAtIndex:(int)i
{
    return [[bookmarks objectAtIndex:i] bookmark];
}

- (int)indexOfProfileWithGuid:(NSString*)guid
{
    for (int i = 0; i < [bookmarks count]; ++i) {
        if ([[[bookmarks objectAtIndex:i] guid] isEqualToString:guid]) {
            return i;
        }
    }
    return -1;
}

- (ProfileModel*)underlyingModel
{
    return underlyingModel;
}

- (void)sync {
    DLog(@"Synchronize profile model wrapper with underlying bookmarks");
    [bookmarks removeAllObjects];
    NSArray *filteredBookmarks = [underlyingModel bookmarkIndicesMatchingFilter:filter
                                                                         orGuid:self.lockedGuid];
    for (NSNumber *n in filteredBookmarks) {
        int i = [n intValue];
        [bookmarks addObject:[[[ProfileTableRow alloc] initWithBookmark:[underlyingModel profileAtIndex:i]
                                                        underlyingModel:underlyingModel] autorelease]];
    }
    [self sort];
    DLog(@"There are now %d bookmarks", (int)bookmarks.count);
}

- (void)moveBookmarkWithGuid:(NSString*)guid toIndex:(int)row
{
    // Make the change locally.
    int origRow = [self indexOfProfileWithGuid:guid];
    if (origRow < row) {
        [bookmarks insertObject:[bookmarks objectAtIndex:origRow] atIndex:row];
        [bookmarks removeObjectAtIndex:origRow];
    } else if (origRow > row) {
        ProfileTableRow* temp = [[bookmarks objectAtIndex:origRow] retain];
        [bookmarks removeObjectAtIndex:origRow];
        [bookmarks insertObject:temp atIndex:row];
        [temp release];
    }
}

- (void)pushOrderToUnderlyingModel
{
    // Since we may have a filter, let's ensure that the visible bookmarks occur
    // in the same order in the underlying model without regard to how invisible
    // bookmarks fit into the order. This also prevents instability when the
    // reload happens.
    int i = 0;
    for (ProfileTableRow* theRow in bookmarks) {
        [underlyingModel moveGuid:[theRow guid] toRow:i++];
    }
    [underlyingModel rebuildMenus];
    [underlyingModel flush];
}

- (NSArray *)names
{
    NSMutableArray *array = [NSMutableArray array];
    for (ProfileTableRow* theRow in bookmarks) {
        [array addObject:[theRow name]];
    }
    return array;
}

- (NSArray*)sortDescriptors
{
    return sortDescriptors;
}

- (void)setFilter:(NSString*)newFilter
{
    self.lockedGuid = nil;
    [filter release];
    filter = [[NSMutableString stringWithString:newFilter] retain];
}

@end
