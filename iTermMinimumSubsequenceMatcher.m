//
//  iTermMinimumSubsequenceMatcher.m
//  iTerm2
//
//  Created by George Nachman on 4/19/15.
//
//

#import "iTermMinimumSubsequenceMatcher.h"

@implementation iTermMinimumSubsequenceMatcher {
    NSString *_query;  // The original query
    NSArray *_queryChars;  // NSNumbers, one for each character in the query.
    NSDictionary *_postingLists;  // Maps a character to an array of sorted document offsets.
    NSMutableArray *_indexes;  // 1:1 with _queryChars, gives indexes into matching posting list.
}

- (instancetype)initWithQuery:(NSString *)query {
    self = [super init];
    if (self) {
        _query = [query copy];
        NSMutableArray *temp = [NSMutableArray array];
        for (int i = 0; i < query.length; i++) {
            [temp addObject:@([query characterAtIndex:i])];
        }
        _queryChars = [temp retain];
    }
    return self;
}

- (void)dealloc {
    [_query release];
    [_postingLists release];
    [_indexes release];
    [_queryChars release];
    [super dealloc];
}

// Dictionary mapping letter->array(indexes into document where letter occurs)
// Returns nil if no matches are possible.
- (NSDictionary *)postingListsForDocument:(NSString *)document {
    NSMutableDictionary *postingLists = [NSMutableDictionary dictionary];
    // Create an empty posting list for each character in the query.
    const NSInteger queryLength = _queryChars.count;
    for (int i = 0; i < queryLength; i++) {
        if (!postingLists[_queryChars[i]]) {
            postingLists[_queryChars[i]] = [NSMutableArray array];
        }
    }

    // Add indexes to posting lists.
    NSInteger documentLength = document.length;
    for (NSInteger i = 0; i < documentLength; i++) {
        unichar c = [document characterAtIndex:i];
        NSMutableArray *indexArray = postingLists[@(c)];
        if (indexArray) {
            [indexArray addObject:@(i)];
        }
    }

    // Check for empty posting lists for an early abort.
    for (int i = 0; i < queryLength; i++) {
        if (![postingLists[_queryChars[i]] count]) {
            // The letter query[i] did not occur in document.
            return nil;
        }
    }

    return postingLists;
}

// Advance the first index and any subsequent indexes that need to be advanced.
// Returns YES if it was possible to advance, NO if all done.
- (BOOL)advanceIndexes {
    // Advance first index and as many subsequent indices as needed
    NSInteger previousDocOffset = -1;
    const NSInteger queryLength = _queryChars.count;
    for (NSInteger i = 0; i < queryLength; i++) {
        NSMutableArray *postingList = _postingLists[_queryChars[i]];
        NSInteger currentIndex = [_indexes[i] integerValue];
        NSInteger docOffset = [postingList[currentIndex] integerValue];
        if (previousDocOffset == -1) {
            // Force the first letter's index to advance.
            previousDocOffset = docOffset;
        }

        // Search linearly for next index in posting list that gives an offset after
        // previousDocOffset. An open-ended binary search would be faster but probably not worth the
        // extra complexity in this application.
        const NSInteger originalIndex = currentIndex;
        const NSInteger postingListCount = postingList.count;
        while (docOffset <= previousDocOffset) {
            ++currentIndex;
            if (currentIndex == postingListCount) {
                return NO;
            }
            docOffset = [postingList[currentIndex] integerValue];
        }

        if (currentIndex == originalIndex) {
            // No change made, so we can stop.
            break;
        }
        _indexes[i] = @(currentIndex);
        previousDocOffset = docOffset;
    }
    return YES;
}

- (NSRange)range {
    NSInteger firstIndex = [_indexes.firstObject integerValue];
    NSInteger start = [_postingLists[_queryChars[0]][firstIndex] integerValue];

    NSInteger lastIndex = [_indexes.lastObject integerValue];
    NSInteger end = [_postingLists[_queryChars.lastObject][lastIndex] integerValue];

    return NSMakeRange(start, end - start);
}

- (NSMutableArray *)initialIndexes {
    NSInteger largestDocIndexSoFar = -1;
    NSMutableArray *indexes = [NSMutableArray array];
    const NSInteger queryLength = _queryChars.count;
    for (int i = 0; i < queryLength; i++) {
        NSNumber *c = _queryChars[i];
        NSInteger index = 0;
        while ([_postingLists[c][index] integerValue] <= largestDocIndexSoFar) {
            index++;
            if (index >= [_postingLists[c] count]) {
                // Not enough occurrences of query[i] in document for a match.
                return nil;
            }
        }
        largestDocIndexSoFar = [_postingLists[c][index] integerValue];
        [indexes addObject:@(index)];
    }

    return indexes;
}

- (NSIndexSet *)indexSetForIndexes:(NSArray *)indexes {
    if (!indexes) {
        return nil;
    }

    NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
    const NSInteger queryLength = _queryChars.count;
    for (int i = 0; i < queryLength; i++) {
        NSArray *postingList = _postingLists[_queryChars[i]];
        NSInteger index = [indexes[i] integerValue];
        NSInteger offset = [postingList[index] integerValue];
        [indexSet addIndex:offset];
    }

    return indexSet;
}

- (NSArray *)bestIndexes {
    NSRange bestRange = NSMakeRange(NSNotFound, 0);
    NSMutableArray *bestIndexes = [NSMutableArray array];
    const NSInteger queryLength = _queryChars.count;
    while (1) {
        NSRange currentRange = [self range];
        if (bestRange.location == NSNotFound || bestRange.length > currentRange.length) {
            bestRange = currentRange;
            [bestIndexes removeAllObjects];
            [bestIndexes addObjectsFromArray:_indexes];
        }

        if (currentRange.length == queryLength) {
            // No need to keep looking.
            break;
        }

        // Move to the next match.
        if (![self advanceIndexes]) {
            break;
        }
    }
    return bestIndexes;
}

- (NSIndexSet *)indexSetForDocument:(NSString *)document {
    [_postingLists release];
    _postingLists = [[self postingListsForDocument:document] retain];
    if (!_postingLists.count) {
        return nil;
    }

    [_indexes release];
    _indexes = [[self initialIndexes] retain];
    if (!_indexes) {
        return nil;
    }
    
    return [self indexSetForIndexes:[self bestIndexes]];
}

@end
