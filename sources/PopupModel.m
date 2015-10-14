//
//  PopupModel.m
//  iTerm
//
//  Created by George Nachman on 12/27/13.
//
//

#import "PopupModel.h"
#import "DebugLogging.h"
#import "PopupEntry.h"

#define PopLog DLog

@implementation PopupModel {
    NSMutableArray* values_;
    int maxEntries_;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        maxEntries_ = -1;
        values_ = [[NSMutableArray alloc] init];
    }
    return self;
}

- (instancetype)initWithMaxEntries:(int)maxEntries {
    self = [super init];
    if (self) {
        maxEntries_ = maxEntries;
        values_ = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [values_ release];
    [super dealloc];
}

- (NSUInteger)count
{
    return [values_ count];
}

- (void)removeAllObjects
{
    [values_ removeAllObjects];
}

- (void)addObject:(id)object
{
    [values_ addObject:object];
}

- (PopupEntry*)entryEqualTo:(PopupEntry*)entry
{
    for (PopupEntry* candidate in values_) {
        if ([candidate isEqual:entry]) {
            return candidate;
        }
    }
    return nil;
}

- (void)removeLowestScoringEntry
{
    PopupEntry *entryWithMinScore = nil;
    for (PopupEntry *entry in values_) {
        if (!entryWithMinScore || entry.score < entryWithMinScore.score) {
            entryWithMinScore = entry;
        }
    }
    if (entryWithMinScore) {
        [values_ removeObject:entryWithMinScore];
    }
}

- (void)addHit:(PopupEntry*)object
{
    PopupEntry* entry = [self entryEqualTo:object];
    if (entry) {
        [entry setScore:[entry score] + [object score] * [entry advanceHitMult]];
        PopLog(@"Add additional hit for %@ bringing score to %lf", [entry mainValue], [entry score]);
    } else if (maxEntries_ < 0 || [self count] < maxEntries_) {
        [self addObject:object];
        PopLog(@"Add entry for %@ with score %lf", [object mainValue], [object score]);
    } else {
        [self removeLowestScoringEntry];
        [self addObject:object];
        PopLog(@"Not adding entry because max of %u hit", maxEntries_);
    }
}

- (id)objectAtIndex:(NSUInteger)i
{
    return [values_ objectAtIndex:i];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)stackbuf count:(NSUInteger)len
{
    return [values_ countByEnumeratingWithState:state objects:stackbuf count:len];
}

- (NSUInteger)indexOfObject:(id)o
{
    return [values_ indexOfObject:o];
}

- (void)sortByScore
{
    NSSortDescriptor *sortDescriptor;
    sortDescriptor = [[[NSSortDescriptor alloc] initWithKey:@"score"
                                                  ascending:NO] autorelease];
    NSArray *sortDescriptors = [NSArray arrayWithObject:sortDescriptor];
    NSArray *sortedArray;
    sortedArray = [values_ sortedArrayUsingDescriptors:sortDescriptors];
    [values_ release];
    values_ = [[NSMutableArray arrayWithArray:sortedArray] retain];
}

- (int)indexOfObjectWithMainValue:(NSString*)value
{
    for (int i = 0; i < [values_ count]; ++i) {
        PopupEntry* entry = [values_ objectAtIndex:i];
        if ([[entry mainValue] isEqualToString:value]) {
            return i;
        }
    }
    return -1;
}

@end
