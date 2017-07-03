//
//  iTermFindOnPageHelper.m
//  iTerm2
//
//  Created by George Nachman on 11/24/14.
//
//

#import "iTermFindOnPageHelper.h"
#import "FindContext.h"
#import "iTermSelection.h"
#import "SearchResult.h"

@implementation iTermFindOnPageHelper {
    // Find context just after initialization.
    FindContext *_copiedContext;

    // Find cursor. -1,-1 if no cursor. This is used to select which search result should be
    // highlighted. If searching forward, it'll be after the find cursor; if searching backward it
    // will be before the find cursor.
    VT100GridAbsCoord _findCursor;

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

    // True if the last search was forward, flase if backward.
    BOOL _searchingForward;

    // Offset value for last search.
    int _findOffset;

    // True if trying to find a result before/after current selection to
    // highlight.
    BOOL _searchingForNextResult;

    // Mode for the last search.
    iTermFindMode _mode;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _highlightMap = [[NSMutableDictionary alloc] init];
        _copiedContext = [[FindContext alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_highlightMap release];
    [_copiedContext release];
    [super dealloc];
}

- (BOOL)findInProgress {
    return _findInProgress || _searchingForNextResult;
}

- (void)findString:(NSString *)aString
  forwardDirection:(BOOL)direction
              mode:(iTermFindMode)mode
        withOffset:(int)offset
           context:(FindContext *)findContext
     numberOfLines:(int)numberOfLines
    totalScrollbackOverflow:(long long)totalScrollbackOverflow {
    _searchingForward = direction;
    _findOffset = offset;
    if ([_lastStringSearchedFor isEqualToString:aString] &&
        _mode == mode) {
        _haveRevealedSearchResult = NO;  // select the next item before/after the current selection.
        _searchingForNextResult = YES;
        // I would like to call selectNextResultForward:withOffset: here, but
        // it results in drawing errors (drawing is clipped to the findbar for
        // some reason). So we return YES and continueFind is run from a timer
        // and everything works fine. The 100ms delay introduced is not
        // noticeable.
    } else {
        // Begin a brand new search.
        if (_findInProgress) {
            [findContext reset];
        }

        // Search backwards from the end. This is slower than searching
        // forwards, but most searches are reverse searches begun at the end,
        // so it will get a result sooner.
        [_delegate findOnPageSetFindString:aString
                          forwardDirection:NO
                                      mode:mode
                               startingAtX:0
                               startingAtY:numberOfLines + 1 + totalScrollbackOverflow
                                withOffset:0
                                 inContext:findContext
                           multipleResults:YES];

        [_copiedContext copyFromFindContext:findContext];
        _copiedContext.results = nil;
        [_delegate findOnPageSaveFindContextAbsPos];
        _findInProgress = YES;

        // Reset every bit of state.
        [self clearHighlights];

        // Initialize state with new values.
        _mode = mode;
        _searchResults = [[NSMutableOrderedSet alloc] init];
        _searchingForNextResult = YES;
        _lastStringSearchedFor = [aString copy];

        [_delegate setNeedsDisplay:YES];
    }
}

- (void)clearHighlights {
    [_lastStringSearchedFor release];
    _lastStringSearchedFor = nil;

    [_searchResults release];
    _searchResults = nil;

    _numberOfProcessedSearchResults = 0;
    _haveRevealedSearchResult = NO;
    [_highlightMap removeAllObjects];
    _searchingForNextResult = NO;

    [_delegate setNeedsDisplay:YES];
}

- (void)resetCopiedFindContext {
    _copiedContext.substring = nil;
}

- (void)resetFindCursor {
    _findCursor = VT100GridAbsCoordMake(-1, -1);
}

// continueFind is called by a timer in the client until it returns NO. It does
// two things:
// 1. If _findInProgress is true, search for more results in the _dataSource and
//   call _addResultFromX:absY:toX:toAbsY: for each.
// 2. If _searchingForNextResult is true, highlight the next result before/after
//   the current selection and flip _searchingForNextResult to false.
- (BOOL)continueFind:(double *)progress
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
                                       inContext:context];
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
        [_delegate setNeedsDisplay:YES];
    }
    return more;
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

    // Update highlights.
    for (long long y = searchResult.absStartY; y <= searchResult.absEndY; y++) {
        NSNumber* key = [NSNumber numberWithLongLong:y];
        NSMutableData* data = _highlightMap[key];
        BOOL set = NO;
        if (!data) {
            data = [NSMutableData dataWithLength:(width / 8 + 1)];
            char* b = [data mutableBytes];
            memset(b, 0, (width / 8) + 1);
            set = YES;
        }
        char* b = [data mutableBytes];
        int lineEndX = MIN(searchResult.endX + 1, width);
        int lineStartX = searchResult.startX;
        if (searchResult.absEndY > y) {
            lineEndX = width;
        }
        if (y > searchResult.absStartY) {
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

// Select the next highlighted result by searching findResults_ for a match just before/after the
// current selection.
- (BOOL)selectNextResultForward:(BOOL)forward
                     withOffset:(int)offset
                          width:(int)width
                  numberOfLines:(int)numberOfLines
             overflowAdjustment:(long long)overflowAdjustment {
    NSRange range = NSMakeRange(NSNotFound, 0);
    int start;
    int stride;
    const NSInteger bottomLimitPos = (1 + numberOfLines + overflowAdjustment) * width;
    const NSInteger topLimitPos = overflowAdjustment * width;
    if (forward) {
        start = [_searchResults count] - 1;
        stride = -1;
        if ([self haveFindCursor]) {
            const NSInteger afterCurrentSelectionPos = _findCursor.x + _findCursor.y * width + offset;
            range = NSMakeRange(afterCurrentSelectionPos, MAX(0, bottomLimitPos - afterCurrentSelectionPos));
        }
    } else {
        start = 0;
        stride = 1;
        if ([self haveFindCursor]) {
            const NSInteger beforeCurrentSelectionPos = _findCursor.x + _findCursor.y * width - offset;
            range = NSMakeRange(topLimitPos, MAX(0, beforeCurrentSelectionPos - topLimitPos));
        } else {
            range = NSMakeRange(topLimitPos, MAX(0, bottomLimitPos - topLimitPos));
        }
    }
    BOOL found = NO;
    VT100GridCoordRange selectedRange = VT100GridCoordRangeMake(0, 0, 0, 0);

    // The position and result of the first/last (if going backward/forward) result to wrap around
    // to if nothing is found. Reset to -1/nil when wrapping is not needed, so its nilness entirely
    // determines whether wrapping should occur.
    long long wrapAroundResultPosition = -1;
    SearchResult *wrapAroundResult = nil;
    int i = start;
    for (int j = 0; !found && j < [_searchResults count]; j++) {
        SearchResult* r = _searchResults[i];
        NSInteger pos = r.startX + (long long)r.absStartY * width;
        if (!found) {
            if (NSLocationInRange(pos, range)) {
                found = YES;
                wrapAroundResult = nil;
                wrapAroundResultPosition = -1;
                selectedRange =
                    VT100GridCoordRangeMake(r.startX,
                                            r.absStartY - overflowAdjustment,
                                            r.endX + 1,  // half-open
                                            r.absEndY - overflowAdjustment);
                [_delegate findOnPageSelectRange:selectedRange wrapped:NO];
            } else if (!_haveRevealedSearchResult) {
                if (forward) {
                    if (wrapAroundResultPosition == -1 || pos < wrapAroundResultPosition) {
                        wrapAroundResult = r;
                        wrapAroundResultPosition = pos;
                    }
                } else {
                    if (wrapAroundResultPosition == -1 || pos > wrapAroundResultPosition) {
                        wrapAroundResult = r;
                        wrapAroundResultPosition = pos;
                    }
                }
            }
        }
        i += stride;
    }

    if (wrapAroundResult != nil) {
        // Wrap around
        found = YES;
        selectedRange =
            VT100GridCoordRangeMake(wrapAroundResult.startX,
                                    wrapAroundResult.absStartY - overflowAdjustment,
                                    wrapAroundResult.endX + 1,  // half-open
                                    wrapAroundResult.absEndY - overflowAdjustment);
        [_delegate findOnPageSelectRange:selectedRange wrapped:YES];
        [_delegate findOnPageDidWrapForwards:forward];
    }

    if (found) {
        [_delegate findOnPageRevealRange:selectedRange];
        _findCursor = VT100GridAbsCoordMake(selectedRange.start.x,
                                            (long long)selectedRange.start.y + overflowAdjustment);
        _haveRevealedSearchResult = YES;
    }

    if (!_findInProgress && !_haveRevealedSearchResult) {
        // Clear the selection.
        [_delegate findOnPageFailed];
        [self resetFindCursor];
    }

    return found;
}

- (void)removeHighlightsInRange:(NSRange)range {
    for (NSUInteger o = 0; o < range.length; o++) {
        [_highlightMap removeObjectForKey:@(range.location + o)];
    }
}

- (NSInteger)smallestIndexOfLastSearchResultWithYLessThan:(NSInteger)query {
    SearchResult *querySearchResult = [[[SearchResult alloc] init] autorelease];
    querySearchResult.absStartY = query;
    NSInteger index = [_searchResults indexOfObject:querySearchResult
                                      inSortedRange:NSMakeRange(0, _searchResults.count)
                                            options:(NSBinarySearchingInsertionIndex | NSBinarySearchingFirstEqual)
                                    usingComparator:^NSComparisonResult(SearchResult * _Nonnull obj1, SearchResult * _Nonnull obj2) {
                                        return [@(obj2.absStartY) compare:@(obj1.absStartY)];
                                    }];
    if (index == _searchResults.count) {
        index--;
    }
    while (_searchResults[index].absStartY >= query) {
        if (index + 1 == _searchResults.count) {
            return NSNotFound;
        }
        index++;
    }
    return index;
}

- (NSInteger)largestIndexOfSearchResultWithYGreaterThanOrEqualTo:(NSInteger)query {
    SearchResult *querySearchResult = [[[SearchResult alloc] init] autorelease];
    querySearchResult.absStartY = query;
    NSInteger index = [_searchResults indexOfObject:querySearchResult
                                      inSortedRange:NSMakeRange(0, _searchResults.count)
                                            options:(NSBinarySearchingInsertionIndex | NSBinarySearchingLastEqual)
                                    usingComparator:^NSComparisonResult(SearchResult * _Nonnull obj1, SearchResult * _Nonnull obj2) {
                                        return [@(obj2.absStartY) compare:@(obj1.absStartY)];
                                    }];
    if (index == _searchResults.count) {
        index--;
    }
    while (_searchResults[index].absStartY < query) {
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

- (void)removeAllSearchResults {
    [_searchResults removeAllObjects];
}

- (void)removeSearchResultsInRange:(NSRange)range {
    NSRange objectRange = [self rangeOfSearchResultsInRangeOfLines:range];
    if (objectRange.location != NSNotFound && objectRange.length > 0) {
        [_searchResults removeObjectsInRange:objectRange];
    }
}

- (void)setStartPoint:(VT100GridAbsCoord)startPoint {
    _findCursor = startPoint;
}

- (BOOL)haveFindCursor {
    return _findCursor.y != -1;
}

- (VT100GridAbsCoord)findCursorAbsCoord {
    return _findCursor;
}

@end
