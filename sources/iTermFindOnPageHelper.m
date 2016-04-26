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
    NSMutableArray *_searchResults;

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

    // True if the last search was case insensitive.
    BOOL _findIgnoreCase;

    // True if the last search was for a regex.
    BOOL _findRegex;
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
      ignoringCase:(BOOL)ignoreCase
             regex:(BOOL)regex
        withOffset:(int)offset
           context:(FindContext *)findContext
     numberOfLines:(int)numberOfLines
    totalScrollbackOverflow:(long long)totalScrollbackOverflow {
    _searchingForward = direction;
    _findOffset = offset;
    if ([_lastStringSearchedFor isEqualToString:aString] &&
        _findRegex == regex &&
        _findIgnoreCase == ignoreCase) {
        _haveRevealedSearchResult = NO;  // select the next item before/after the current selection.
        _searchingForNextResult = YES;
        // I would like to call selectNextResultForward:withOffset: here, but
        // it results in drawing errors (drawing is clipped to the findbar for
        // some reason). So we return YES and continueFind is run from a timer
        // and everything works fine. The 100ms delay introduced is not
        // noticable.
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
                              ignoringCase:ignoreCase
                                     regex:regex
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
        _findRegex = regex;
        _findIgnoreCase = ignoreCase;
        _searchResults = [[NSMutableArray alloc] init];
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
    if (_findInProgress) {
        // Collect more results.
        more = [_delegate continueFindAllResults:_searchResults
                                       inContext:context];
        *progress = [context progress];
    } else {
        *progress = 1;
    }
    if (!more) {
        _findInProgress = NO;
    }
    // Add new results to map.
    for (int i = _numberOfProcessedSearchResults; i < [_searchResults count]; i++) {
        SearchResult* r = [_searchResults objectAtIndex:i];
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
    long long maxPos = -1;
    long long minPos = -1;
    int start;
    int stride;
    if (forward) {
        start = [_searchResults count] - 1;
        stride = -1;
        if ([self haveFindCursor]) {
            minPos = _findCursor.x + _findCursor.y * width + offset;
        } else {
            minPos = -1;
        }
    } else {
        start = 0;
        stride = 1;
        if ([self haveFindCursor]) {
            maxPos = _findCursor.x + _findCursor.y * width - offset;
        } else {
            maxPos = (1 + numberOfLines + overflowAdjustment) * width;
        }
    }
    BOOL found = NO;
    VT100GridCoordRange selectedRange = VT100GridCoordRangeMake(0, 0, 0, 0);
    int i = start;
    for (int j = 0; !found && j < [_searchResults count]; j++) {
        SearchResult* r = [_searchResults objectAtIndex:i];
        long long pos = r.startX + (long long)r.absStartY * width;
        if (!found &&
            ((maxPos >= 0 && pos <= maxPos) ||
             (minPos >= 0 && pos >= minPos))) {
                found = YES;
                selectedRange =
                    VT100GridCoordRangeMake(r.startX,
                                            r.absStartY - overflowAdjustment,
                                            r.endX + 1,  // half-open
                                            r.absEndY - overflowAdjustment);
                [_delegate findOnPageSelectRange:selectedRange wrapped:NO];
            }
        i += stride;
    }

    if (!found && !_haveRevealedSearchResult && [_searchResults count] > 0) {
        // Wrap around
        SearchResult* r = [_searchResults objectAtIndex:start];
        found = YES;
        selectedRange =
            VT100GridCoordRangeMake(r.startX,
                                    r.absStartY - overflowAdjustment,
                                    r.endX + 1,  // half-open
                                    r.absEndY - overflowAdjustment);
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
