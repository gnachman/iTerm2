//
//  iTermFindOnPageHelper.m
//  iTerm2
//
//  Created by George Nachman on 11/24/14.
//
//

#import "iTermFindOnPageHelper.h"
#import "iTerm2SharedARC-Swift.h"
#import "DebugLogging.h"
#import "FindContext.h"
#import "iTermSelection.h"
#import "SearchResult.h"

@interface FindCursor()
@property (nonatomic, readwrite) FindCursorType type;
@property (nonatomic, readwrite) VT100GridAbsCoord coord;
@property (nonatomic, strong, readwrite) iTermExternalSearchResult *external;
@end

@implementation FindCursor
@end

@interface iTermFindOnPageHelper()
@property (nonatomic, strong) SearchResult *selectedResult;
@end

typedef struct {
    // Should this struct be believed?
    BOOL valid;

    // Any search results with absEndY less than this should be ignored. Saves
    // when it was last updated. Consider invalid if the overflowAdjustment has
    // changed.
    long long overflowAdjustment;

    // Number of valid search results.
    NSInteger count;

    // 1-based index of the currently highlighted result, or 0 if none.
    NSInteger index;
} iTermFindOnPageCachedCounts;

@implementation iTermFindOnPageHelper {
    // Find context just after initialization.
    FindContext *_copiedContext;

    // Is a find currently executing?
    BOOL _findInProgress;

    // The string last searched for.
    NSString *_lastStringSearchedFor;

    // The set of SearchResult objects for which matches have been found.
    // Sorted by reverse position (last in the buffer is first in the array).
    NSMutableOrderedSet<SearchResult *> *_searchResults;

    // The next offset into _searchResults where values from _searchResults should
    // be added to the map.
    int _numberOfProcessedSearchResults;

    // True if a result has been highlighted & scrolled to.
    BOOL _haveRevealedSearchResult;

    // Maps an absolute line number (NSNumber longlong) to an NSData bit array
    // with one bit per cell indicating whether that cell is a match.
    NSMutableDictionary *_highlightMap;

    // True if the last search was forward, false if backward.
    BOOL _searchingForward;

    // Offset value for last search.
    int _findOffset;

    // True if trying to find a result before/after current selection to
    // highlight.
    BOOL _searchingForNextResult;

    // Mode for the last search.
    iTermFindMode _mode;

    iTermFindOnPageCachedCounts _cachedCounts;

    NSMutableIndexSet *_locations NS_AVAILABLE_MAC(10_14);

    BOOL _locationsHaveChanged NS_AVAILABLE_MAC(10_14);
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _highlightMap = [[NSMutableDictionary alloc] init];
        _copiedContext = [[FindContext alloc] init];
        _locations = [[NSMutableIndexSet alloc] init];
        _findCursor = [[FindCursor alloc] init];
    }
    return self;
}

- (void)locationsDidChange NS_AVAILABLE_MAC(10_14) {
    if (_locationsHaveChanged) {
        return;
    }
    _locationsHaveChanged = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_locationsHaveChanged = NO;
        [self.delegate findOnPageLocationsDidChange];
    });
}

- (BOOL)findInProgress {
    return _findInProgress || _searchingForNextResult;
}

- (void)setAbsLineRange:(NSRange)absLineRange {
    if (NSEqualRanges(absLineRange, _absLineRange)) {
        return;
    }
    _absLineRange = absLineRange;
    // Remove search results outside this range.
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    [_searchResults enumerateObjectsUsingBlock:^(SearchResult * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.isExternal) {
            if (!NSLocationInRange(obj.externalAbsY, absLineRange)) {
                [indexes addIndex:idx];
                [_locations removeIndex:obj.externalAbsY];
                [_highlightMap removeObjectForKey:@(obj.externalAbsY)];
                [_delegate findOnPageHelperRemoveExternalHighlightsFrom:obj.externalResult];
            }
        } else {
            if (!NSLocationInRange(obj.internalAbsStartY, absLineRange) &&
                !NSLocationInRange(obj.internalAbsEndY, absLineRange)) {
                [indexes addIndex:idx];
                [_locations removeIndex:obj.internalAbsStartY];
                [_highlightMap removeObjectForKey:@(obj.internalAbsStartY)];
            }
        }
    }];
    if (indexes.count) {
        [_searchResults removeObjectsAtIndexes:indexes];

        [self locationsDidChange];
        _cachedCounts.valid = NO;

        if (_numberOfProcessedSearchResults > _searchResults.count) {
            _numberOfProcessedSearchResults = _searchResults.count;
        }
    }
}

- (void)findString:(NSString *)aString
  forwardDirection:(BOOL)direction
              mode:(iTermFindMode)mode
        withOffset:(int)offset
           context:(FindContext *)findContext
     numberOfLines:(int)numberOfLines
    totalScrollbackOverflow:(long long)totalScrollbackOverflow
scrollToFirstResult:(BOOL)scrollToFirstResult 
             force:(BOOL)force {
    DLog(@"Initialize search for %@ dir=%@ offset=%@", aString, direction > 0 ? @"forwards" : @"backwards", @(offset));
    _searchingForward = direction;
    _findOffset = offset;
    if ([_lastStringSearchedFor isEqualToString:aString] &&
        _mode == mode &&
        !force) {
        DLog(@"query and mode are unchanged.");
        _haveRevealedSearchResult = NO;  // select the next item before/after the current selection.
        _searchingForNextResult = scrollToFirstResult;
        // I would like to call selectNextResultForward:withOffset: here, but
        // it results in drawing errors (drawing is clipped to the findbar for
        // some reason). So we return YES and continueFind is run from a timer
        // and everything works fine. The 100ms delay introduced is not
        // noticeable.
    } else {
        DLog(@"Begin a brand new search");
        // Begin a brand new search.
        self.selectedResult = nil;
        if (_findInProgress) {
            [findContext reset];
        }

        // Search backwards from the end. This is slower than searching
        // forwards, but most searches are reverse searches begun at the end,
        // so it will get a result sooner.
        VT100GridCoord startCoord = VT100GridCoordMake(0, numberOfLines + 1 + totalScrollbackOverflow);
        if (_findCursor) {
            switch (_findCursor.type) {
                case FindCursorTypeCoord: {
                    BOOL ok;
                    startCoord = VT100GridCoordFromAbsCoord(_findCursor.coord,
                                                            totalScrollbackOverflow,
                                                            &ok);
                    if (!ok) {
                        DLog(@"Failed to convert find cursor coord so using end");
                    }
                    break;
                }

                case FindCursorTypeExternal:
                    // TODO
                    break;

                case FindCursorTypeInvalid:
                    break;
            }
        }
        DLog(@"Start search at %@", VT100GridCoordDescription(startCoord));
        [_delegate findOnPageSetFindString:aString
                          forwardDirection:NO
                                      mode:mode
                               startingAtX:startCoord.x
                               startingAtY:startCoord.y
                                withOffset:0
                                 inContext:findContext
                           multipleResults:YES
                              absLineRange:self.absLineRange];

        [_copiedContext copyFromFindContext:findContext];
        _copiedContext.results = nil;
        [_delegate findOnPageSaveFindContextAbsPos];
        _findInProgress = YES;

        // Reset every bit of state.
        [self clearHighlights];

        // Initialize state with new values.
        _mode = mode;
        _searchResults = [[NSMutableOrderedSet alloc] init];
        _searchingForNextResult = scrollToFirstResult;
        _lastStringSearchedFor = [aString copy];

        [_delegate findOnPageHelperRequestRedraw];
        [_delegate findOnPageHelperSearchExternallyFor:aString mode:mode];
    }
}

- (void)clearHighlights {
    _lastStringSearchedFor = nil;

    [_locations removeAllIndexes];
    [self locationsDidChange];

    _searchResults = [[NSMutableOrderedSet alloc] init];
    _cachedCounts.valid = NO;

    _numberOfProcessedSearchResults = 0;
    _haveRevealedSearchResult = NO;
    [_highlightMap removeAllObjects];
    _searchingForNextResult = NO;
    [_delegate findOnPageHelperRemoveExternalHighlights];

    [_delegate findOnPageHelperRequestRedraw];
}

- (void)resetCopiedFindContext {
    _copiedContext.substring = nil;
}

- (void)resetFindCursor {
    _findCursor.type = FindCursorTypeInvalid;
}

// continueFind is called by a timer in the client until it returns NO. It does
// two things:
// 1. If _findInProgress is true, search for more results in the _dataSource and
//   call _addResultFromX:absY:toX:toAbsY: for each.
// 2. If _searchingForNextResult is true, highlight the next result before/after
//   the current selection and flip _searchingForNextResult to false.
- (BOOL)continueFind:(double *)progress
            rangeOut:(NSRange *)rangePtr
             context:(FindContext *)context
               width:(int)width
       numberOfLines:(int)numberOfLines
  overflowAdjustment:(long long)overflowAdjustment {
    BOOL more = NO;
    BOOL redraw = NO;

    assert([self findInProgress]);
    NSMutableArray<SearchResult *> *newSearchResults = [NSMutableArray array];
    if (_findInProgress) {
        // Collect more results.
        more = [_delegate continueFindAllResults:newSearchResults
                                        rangeOut:rangePtr
                                       inContext:context
                                    absLineRange:self.absLineRange
                                   rangeSearched:NULL];
        *progress = [context progress];
    } else {
        *progress = 1;
    }
    if (!more) {
        _findInProgress = NO;
    }
    // Add new results to map.
    for (SearchResult *r in newSearchResults.reverseObjectEnumerator) {
        [self addSearchResult:r width:width];
        redraw = YES;
    }
    _numberOfProcessedSearchResults = [_searchResults count];

    // Highlight next result if needed.
    if (_searchingForNextResult) {
        if ([self selectNextResultForward:_searchingForward
                               withOffset:_findOffset
                                    width:width
                            numberOfLines:numberOfLines
                       overflowAdjustment:overflowAdjustment]) {
            _searchingForNextResult = NO;
        }
    }

    if (redraw) {
        [_delegate findOnPageHelperRequestRedraw];
    }
    return more;
}

- (void)addExternalResults:(NSArray<iTermExternalSearchResult *> *)externalResults
                     width:(int)width {
    [externalResults enumerateObjectsUsingBlock:^(iTermExternalSearchResult *externalResult,
                                                  NSUInteger i,
                                                  BOOL * _Nonnull stop) {
        SearchResult *searchResult = [SearchResult searchResultFromExternal:externalResult
                                                                      index:i];
        [self addSearchResult:searchResult width:width];
    }];
}

- (void)addSearchResult:(SearchResult *)searchResult width:(int)width {
    if ([_searchResults containsObject:searchResult]) {
        // Tail find produces duplicates sometimes. This can break monotonicity.
        return;
    }

    NSInteger insertionIndex = [_searchResults indexOfObject:searchResult
                                               inSortedRange:NSMakeRange(0, _searchResults.count)
                                                     options:NSBinarySearchingInsertionIndex
                                             usingComparator:^NSComparisonResult(SearchResult  * _Nonnull obj1, SearchResult  * _Nonnull obj2) {
                                                 NSComparisonResult result = [obj1 compare:obj2];
                                                 switch (result) {
                                                     case NSOrderedAscending:
                                                         return NSOrderedDescending;
                                                     case NSOrderedDescending:
                                                         return NSOrderedAscending;
                                                     default:
                                                         return result;
                                                 }
                                             }];
    [_searchResults insertObject:searchResult atIndex:insertionIndex];
    if (searchResult.isExternal) {
        [_locations addIndex:searchResult.externalAbsY];
    } else {
        [_locations addIndex:searchResult.internalAbsStartY];
    }
    [self locationsDidChange];
    _cachedCounts.valid = NO;

    // Update highlights.
    if (!searchResult.isExternal) {
        for (long long y = searchResult.internalAbsStartY; y <= searchResult.internalAbsEndY; y++) {
            NSNumber* key = @(y);
            NSMutableData *data = _highlightMap[key];
            BOOL set = NO;
            if (!data) {
                data = [NSMutableData dataWithLength:(width / 8 + 1)];
                char* b = [data mutableBytes];
                memset(b, 0, (width / 8) + 1);
                set = YES;
            }
            char* b = [data mutableBytes];
            int lineEndX = MIN(searchResult.internalEndX + 1, width);
            int lineStartX = searchResult.internalStartX;
            if (searchResult.internalAbsEndY > y) {
                lineEndX = width;
            }
            if (y > searchResult.internalAbsStartY) {
                lineStartX = 0;
            }
            for (int i = lineStartX; i < lineEndX; i++) {
                const int byteIndex = i/8;
                const int bit = 1 << (i & 7);
                if (byteIndex < [data length]) {
                    b[byteIndex] |= bit;
                }
            }
            if (set) {
                _highlightMap[key] = data;
            }
        }
    }
}

- (void)setSelectedResult:(SearchResult *)selectedResult {
    _cachedCounts.valid = NO;
    if (selectedResult == _selectedResult) {
        return;
    }
    _selectedResult = selectedResult;
    [self.delegate findOnPageSelectedResultDidChange];
}

// Select the next highlighted result by searching findResults_ for a match just before/after the
// current selection.
- (BOOL)selectNextResultForward:(BOOL)forward
                     withOffset:(int)offset
                          width:(int)width
                  numberOfLines:(int)numberOfLines
             overflowAdjustment:(long long)overflowAdjustment {
    // Range of positions before backwards find cursor or after forwards find cursor. Stays empty if no cursor.
    NSRange range = NSMakeRange(NSNotFound, 0);
    int start;
    int stride;
    const NSInteger bottomLimitPos = (1 + numberOfLines + overflowAdjustment) * width;
    const NSInteger topLimitPos = overflowAdjustment * width;
    if (forward) {
        start = [_searchResults count] - 1;
        stride = -1;
        if (_findCursor.type == FindCursorTypeCoord) {
            const NSInteger afterCurrentSelectionPos = _findCursor.coord.x + _findCursor.coord.y * width + offset;
            range = NSMakeRange(afterCurrentSelectionPos, MAX(0, bottomLimitPos - afterCurrentSelectionPos));
        }
    } else {
        start = 0;
        stride = 1;
        if (_findCursor.type == FindCursorTypeCoord) {
            const NSInteger beforeCurrentSelectionPos = _findCursor.coord.x + _findCursor.coord.y * width - offset;
            range = NSMakeRange(topLimitPos, MAX(0, beforeCurrentSelectionPos - topLimitPos));
        } else {
            range = NSMakeRange(topLimitPos, MAX(0, bottomLimitPos - topLimitPos));
        }
    }
    BOOL found = NO;
    VT100GridCoordRange selectedRange = VT100GridCoordRangeMake(0, 0, 0, 0);
    iTermExternalSearchResult *external = nil;

    // The position and result of the first/last (if going backward/forward) result to wrap around
    // to if nothing is found. Reset to -1/nil when wrapping is not needed, so its nilness entirely
    // determines whether wrapping should occur.
    long long wrapAroundResultPosition = -1;
    SearchResult *wrapAroundResult = nil;
    BOOL haveFoundExternalCursor = NO;
    for (int j = 0, i = start; !found && j < [_searchResults count]; j++) {
        SearchResult* r = _searchResults[i];
        i += stride;
        if (i < 0) {
            i += _searchResults.count;
        } else if (i >= _searchResults.count) {
            i -= _searchResults.count;
        }
        if (found) {
            continue;
        }
        if (_findCursor.type == FindCursorTypeExternal &&
            !haveFoundExternalCursor &&
            r.externalResult == _findCursor.external) {
            haveFoundExternalCursor = YES;
        }
        NSInteger pos;
        if (r.isExternal) {
            if (r.externalAbsY < overflowAdjustment) {
                continue;
            }
            pos = r.externalAbsY * width;
        } else {
            if (r.internalAbsEndY < overflowAdjustment) {
                continue;
            }
            pos = r.internalStartX + (long long)r.internalAbsStartY * width;
        }
        assert(!found);
        if (_findCursor.type == FindCursorTypeExternal) {
            // Flip found to true if the previous result was the find cursor.
            found = haveFoundExternalCursor && r.externalResult != _findCursor.external && r.externalResult.isVisible;
        } else {
            found = NSLocationInRange(pos, range);
        }
        if (found) {
            DLog(@"Result %@ is in the desired range", r);
            found = YES;
            wrapAroundResult = nil;
            wrapAroundResultPosition = -1;
            self.selectedResult = r;
            if (r.isExternal) {
                selectedRange = [_delegate findOnPageSelectExternalResult:r.externalResult];
                external = r.externalResult;
            } else {
                selectedRange =
                    VT100GridCoordRangeMake(r.internalStartX,
                                            MAX(0, r.internalAbsStartY - overflowAdjustment),
                                            r.internalEndX + 1,  // half-open
                                            MAX(0, r.internalAbsEndY - overflowAdjustment));
                external = nil;
                [_delegate findOnPageSelectRange:selectedRange wrapped:NO];
            }
        } else if (!_haveRevealedSearchResult) {
            if (!r.isExternal || r.externalResult.isVisible) {  // Don't wrap around to invisible result
                if (forward) {
                    if (wrapAroundResultPosition == -1 || pos < wrapAroundResultPosition) {
                        self.selectedResult = r;
                        wrapAroundResult = r;
                        wrapAroundResultPosition = pos;
                    }
                } else {
                    if (wrapAroundResultPosition == -1 || pos > wrapAroundResultPosition) {
                        self.selectedResult = r;
                        wrapAroundResult = r;
                        wrapAroundResultPosition = pos;
                    }
                }
            }
        }
    }

    if (wrapAroundResult != nil) {
        // Wrap around
        found = YES;
        if (wrapAroundResult.isExternal) {
            selectedRange = [_delegate findOnPageSelectExternalResult:wrapAroundResult.externalResult];
            external = wrapAroundResult.externalResult;
        } else {
            DLog(@"Because no results were found in the desired range use %@ as wraparound result", wrapAroundResult);
            selectedRange =
                VT100GridCoordRangeMake(wrapAroundResult.internalStartX,
                                        MAX(0, wrapAroundResult.internalAbsStartY - overflowAdjustment),
                                        wrapAroundResult.internalEndX + 1,  // half-open
                                        MAX(0, wrapAroundResult.internalAbsEndY - overflowAdjustment));
            external = nil;
            [_delegate findOnPageSelectRange:selectedRange wrapped:YES];
        }
        [_delegate findOnPageDidWrapForwards:forward];
    }

    if (found) {
        if (!external) {  // selectedRange is approximate and scrolling happens w/ selection
            [_delegate findOnPageRevealRange:selectedRange];
            _findCursor.type = FindCursorTypeCoord;
            _findCursor.coord = VT100GridAbsCoordMake(selectedRange.start.x,
                                                      (long long)selectedRange.start.y + overflowAdjustment);
        } else {
            _findCursor.type = FindCursorTypeExternal;
            _findCursor.external = external;
        }
        _haveRevealedSearchResult = YES;
    }

    if (!_findInProgress && !_haveRevealedSearchResult) {
        // Clear the selection.
        [_delegate findOnPageFailed];
    }

    return found;
}

- (void)removeHighlightsInRange:(NSRange)range {
    for (NSUInteger o = 0; o < range.length; o++) {
        [_highlightMap removeObjectForKey:@(range.location + o)];
    }
}

- (NSInteger)smallestIndexOfLastSearchResultWithYLessThan:(NSInteger)query {
    SearchResult *querySearchResult = [[SearchResult alloc] init];
    querySearchResult.internalAbsStartY = query;
    NSInteger index = [_searchResults indexOfObject:querySearchResult
                                      inSortedRange:NSMakeRange(0, _searchResults.count)
                                            options:(NSBinarySearchingInsertionIndex | NSBinarySearchingFirstEqual)
                                    usingComparator:^NSComparisonResult(SearchResult * _Nonnull obj1, SearchResult * _Nonnull obj2) {
                                        return [@(obj2.safeAbsStartY) compare:@(obj1.safeAbsStartY)];
                                    }];
    if (index == _searchResults.count) {
        index--;
    }
    while (_searchResults[index].safeAbsStartY >= query) {
        if (index + 1 == _searchResults.count) {
            return NSNotFound;
        }
        index++;
    }
    return index;
}

- (NSInteger)largestIndexOfSearchResultWithYGreaterThanOrEqualTo:(NSInteger)query {
    SearchResult *querySearchResult = [[SearchResult alloc] init];
    querySearchResult.internalAbsStartY = query;
    NSInteger index = [_searchResults indexOfObject:querySearchResult
                                      inSortedRange:NSMakeRange(0, _searchResults.count)
                                            options:(NSBinarySearchingInsertionIndex | NSBinarySearchingLastEqual)
                                    usingComparator:^NSComparisonResult(SearchResult * _Nonnull obj1, SearchResult * _Nonnull obj2) {
                                        return [@(obj2.safeAbsStartY) compare:@(obj1.safeAbsStartY)];
                                    }];
    if (index == _searchResults.count) {
        index--;
    }
    while (_searchResults[index].safeAbsStartY < query) {
        if (index == 0) {
            return NSNotFound;
        }
        index--;
    }
    return index;
}

- (NSRange)rangeOfSearchResultsInRangeOfLines:(NSRange)range {
    if (_searchResults.count == 0) {
        return NSMakeRange(NSNotFound, 0);
    }
    NSInteger tailIndex = [self largestIndexOfSearchResultWithYGreaterThanOrEqualTo:range.location];
    if (tailIndex == NSNotFound) {
        return NSMakeRange(NSNotFound, 0);
    }
    NSInteger headIndex = [self smallestIndexOfLastSearchResultWithYLessThan:NSMaxRange(range)];
    if (tailIndex < headIndex) {
        return NSMakeRange(NSNotFound, 0);
    } else {
        return NSMakeRange(headIndex, tailIndex - headIndex + 1);
    }
}

- (void)enumerateSearchResultsInRangeOfLines:(NSRange)range
                                       block:(void (^ NS_NOESCAPE)(SearchResult *result))block {
    if (_searchResults.count == 0) {
        return;
    }
    const NSInteger headIndex = [self smallestIndexOfLastSearchResultWithYLessThan:NSMaxRange(range)];
    for (NSInteger i = headIndex; i < _searchResults.count; i++) {
        SearchResult *result = _searchResults[i];
        if (result.internalAbsStartY < range.location) {
            continue;
        }
        if (result.isExternal) {
            // External search results aren't supported yet.
            continue;
        }
        block(result);
    }
}

- (void)removeAllSearchResults {
    [_searchResults removeAllObjects];
    [_locations removeAllIndexes];
    [self locationsDidChange];
    _cachedCounts.valid = NO;
}

- (void)removeSearchResultsInRange:(NSRange)range {
    NSRange objectRange = [self rangeOfSearchResultsInRangeOfLines:range];
    if (objectRange.location != NSNotFound && objectRange.length > 0) {
        [_searchResults removeObjectsInRange:objectRange];
        [_locations removeIndexesInRange:range];
        [self locationsDidChange];
        _cachedCounts.valid = NO;
    }
}

- (void)setStartPoint:(VT100GridAbsCoord)startPoint {
    _findCursor.coord = startPoint;
    _findCursor.type = FindCursorTypeCoord;
}

- (NSInteger)currentIndex {
    [self updateCachedCountsIfNeeded];
    return _cachedCounts.index;
}

- (NSInteger)numberOfSearchResults {
    [self updateCachedCountsIfNeeded];
    return _cachedCounts.count;
}

- (void)overflowAdjustmentDidChange {
    if (self.selectedResult == nil) {
        return;
    }
    [self updateCachedCountsIfNeeded];
}

- (void)updateCachedCountsIfNeeded {
    const long long overflowAdjustment = [self.delegate findOnPageOverflowAdjustment];
    if (self.selectedResult.safeAbsEndY < overflowAdjustment) {
        self.selectedResult = nil;
    }
    if (self.selectedResult == nil) {
        _cachedCounts.valid = YES;
        _cachedCounts.index = 0;
        _cachedCounts.count = 0;
        _cachedCounts.overflowAdjustment = 0;
        return;
    }
    DLog(@"selected result ok vs %@: %@", @(overflowAdjustment), self.selectedResult);
    if (_cachedCounts.valid && _cachedCounts.overflowAdjustment == overflowAdjustment) {
        return;
    }

    [self updateCachedCounts];
}

- (void)updateCachedCounts {
    _cachedCounts.overflowAdjustment = [self.delegate findOnPageOverflowAdjustment];
    SearchResult *temp = [SearchResult searchResultFromX:0 y:_cachedCounts.overflowAdjustment toX:0 y:_cachedCounts.overflowAdjustment];

    _cachedCounts.valid = YES;
    if (!_searchResults.count) {
        _cachedCounts.count = 0;
        _cachedCounts.index = 0;
        return;
    }

    if (_searchResults.lastObject.safeAbsEndY >= _cachedCounts.overflowAdjustment) {
        // All search results are valid.
        _cachedCounts.count = _searchResults.count;
    } else {
        // Some search results at the end of the list have been lost to scrollback. Find where the
        // valid ones end. Because search results are sorted descending, a prefix of _searchResults
        // will contain the valid ones.
        const NSInteger index = [_searchResults indexOfObject:temp inSortedRange:NSMakeRange(0, _searchResults.count) options:NSBinarySearchingInsertionIndex usingComparator:^NSComparisonResult(SearchResult *_Nonnull obj1, SearchResult *_Nonnull obj2) {
            return [@(-obj1.safeAbsEndY) compare:@(-obj2.safeAbsEndY)];
        }];
        if (index == NSNotFound) {
            _cachedCounts.count = 0;
            _cachedCounts.index = 0;
            return;
        }
        _cachedCounts.count = index + 1;
    }
    
    if (self.selectedResult == nil) {
        _cachedCounts.index = 0;
        return;
    }

    // Do a binary search to find the current result.
    _cachedCounts.index = [_searchResults indexOfObject:self.selectedResult inSortedRange:NSMakeRange(0, _searchResults.count) options:NSBinarySearchingFirstEqual usingComparator:^NSComparisonResult(SearchResult *_Nonnull obj1, SearchResult *_Nonnull obj2) {
        const NSComparisonResult result = [obj1 compare:obj2];
        // Swap ascending and descending because the values or ordered descending.
        switch (result) {
        case NSOrderedSame:
            return result;
        case NSOrderedAscending:
            return NSOrderedDescending;
        case NSOrderedDescending:
            return NSOrderedAscending;
        }
    }];

    // Rewrite the index to be 1-based for valid results and 0 if none is selected.
    if (_cachedCounts.index == NSNotFound) {
        _cachedCounts.index = 0;
    } else {
        _cachedCounts.index += 1;
    }
}

#pragma mark - iTermSearchResultsMinimapViewDelegate

- (NSIndexSet *)searchResultsMinimapViewLocations:(iTermSearchResultsMinimapView *)view NS_AVAILABLE_MAC(10_14) {
    return _locations;
}

- (NSRange)searchResultsMinimapViewRangeOfVisibleLines:(iTermSearchResultsMinimapView *)view NS_AVAILABLE_MAC(10_14) {
    return [_delegate findOnPageRangeOfVisibleLines];
}

@end
