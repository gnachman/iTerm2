//
//  VT100Screen+Search.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/16/22.
//

#import "VT100Screen+Search.h"
#import "VT100Screen+Private.h"

#import "DebugLogging.h"
#import "SearchResult.h"
#include <sys/time.h>

@implementation VT100Screen (Search)

- (LineBuffer *)searchBuffer {
    _wantsSearchBuffer = YES;
    if (!_searchBuffer) {
        _searchBuffer = [_state.linebuffer copy];
    }
    return _searchBuffer;
}

- (void)setFindStringImpl:(NSString*)aString
         forwardDirection:(BOOL)direction
                     mode:(iTermFindMode)mode
              startingAtX:(int)x
              startingAtY:(int)y
               withOffset:(int)offset
                inContext:(FindContext *)context
          multipleResults:(BOOL)multipleResults {
    DLog(@"begin self=%@ aString=%@", self, aString);
    @autoreleasepool {
        LineBuffer *tempLineBuffer = [self searchBuffer];
        [tempLineBuffer performBlockWithTemporaryChanges:^{
            // Append the screen contents to the scrollback buffer so they are included in the search.
            [_state.currentGrid appendLines:[_state.currentGrid numberOfLinesUsed]
                               toLineBuffer:tempLineBuffer];

            // Get the start position of (x,y)
            LineBufferPosition *startPos;
            startPos = [tempLineBuffer positionForCoordinate:VT100GridCoordMake(x, y)
                                                       width:_state.currentGrid.size.width
                                                      offset:offset * (direction ? 1 : -1)];
            if (!startPos) {
                // x,y wasn't a real position in the line buffer, probably a null after the end.
                if (direction) {
                    DLog(@"Search from first position");
                    startPos = [tempLineBuffer firstPosition];
                } else {
                    DLog(@"Search from last position");
                    startPos = [[tempLineBuffer lastPosition] predecessor];
                }
            } else {
                DLog(@"Search from %@", startPos);
                // Make sure startPos is not at or after the last cell in the line buffer.
                BOOL ok;
                VT100GridCoord startPosCoord = [tempLineBuffer coordinateForPosition:startPos
                                                                               width:_state.currentGrid.size.width
                                                                        extendsRight:YES
                                                                                  ok:&ok];
                LineBufferPosition *lastValidPosition = [tempLineBuffer penultimatePosition];

                if (!ok) {
                    startPos = lastValidPosition;
                } else {
                    VT100GridCoord lastPositionCoord = [tempLineBuffer coordinateForPosition:lastValidPosition
                                                                                       width:_state.currentGrid.size.width
                                                                                extendsRight:YES
                                                                                          ok:&ok];
                    assert(ok);
                    long long s = startPosCoord.y;
                    s *= _state.currentGrid.size.width;
                    s += startPosCoord.x;

                    long long l = lastPositionCoord.y;
                    l *= _state.currentGrid.size.width;
                    l += lastPositionCoord.x;

                    if (s >= l) {
                        startPos = lastValidPosition;
                    }
                }
            }

            // Set up the options bitmask and call findSubstring.
            FindOptions opts = 0;
            if (!direction) {
                opts |= FindOptBackwards;
            }
            if (multipleResults) {
                opts |= FindMultipleResults;
            }
            [tempLineBuffer prepareToSearchFor:aString startingAt:startPos options:opts mode:mode withContext:context];
            context.hasWrapped = NO;
        }];
    }
}

- (BOOL)continueFindAllResultsImpl:(NSMutableArray<SearchResult *> *)results
                         inContext:(FindContext *)context
                     rangeSearched:(VT100GridAbsCoordRange *)rangeSearched {
    context.hasWrapped = YES;
    NSDate* start = [NSDate date];
    BOOL keepSearching;
    do {
        keepSearching = [self continueFindResultsInContext:context
                                                      toArray:results
                                             rangeSearched:rangeSearched];
    } while (keepSearching &&
             [[NSDate date] timeIntervalSinceDate:start] < context.maxTime);
    if (results.count > 0) {
        [self.delegate screenRefreshFindOnPageView];
    }
    return keepSearching;
}

#pragma mark - Tail Find

- (void)saveFindContextAbsPosImpl {
    LineBuffer *temp = [_state.linebuffer copy];
    [_state.currentGrid appendLines:[self.currentGrid numberOfLinesUsed]
                       toLineBuffer:temp];
    self.savedFindContextAbsPos = [temp absPositionOfFindContext:self.findContext];
}

- (void)restoreSavedPositionToFindContextImpl:(FindContext *)context {
    @autoreleasepool {
        LineBuffer *temp = [self searchBuffer];
        [temp performBlockWithTemporaryChanges:^{
            [_state.currentGrid appendLines:[_state.currentGrid numberOfLinesUsed]
                               toLineBuffer:temp];
            [temp storeLocationOfAbsPos:self.savedFindContextAbsPos
                              inContext:context];
        }];
    }
}

- (void)storeLastPositionInLineBufferAsFindContextSavedPositionImpl {
    self.savedFindContextAbsPos = [[_state.linebuffer lastPosition] absolutePosition];
}

#pragma mark - Private

- (VT100GridAbsCoord)absCoordOfFindContext:(FindContext *)context lineBuffer:(LineBuffer *)temporaryLineBuffer {
    LineBufferPosition *startPosition = [temporaryLineBuffer positionOfFindContext:context
                                                                             width:self.width];
    BOOL ok = NO;
    const VT100GridCoord coord = [temporaryLineBuffer coordinateForPosition:startPosition
                                                                      width:self.width
                                                               extendsRight:NO
                                                                         ok:&ok];
    if (!ok) {
        return VT100GridAbsCoordMake(-1, -1);
    }
    return VT100GridAbsCoordFromCoord(coord, self.totalScrollbackOverflow);
}

- (BOOL)continueFindResultsInContext:(FindContext *)context
                             toArray:(NSMutableArray *)results
                       rangeSearched:(VT100GridAbsCoordRange *)rangeSearched {
    // Append the screen contents to the scrollback buffer so they are included in the search.
    __block BOOL keepSearching = NO;
    @autoreleasepool {
        LineBuffer *temporaryLineBuffer = [self searchBuffer];
        [temporaryLineBuffer performBlockWithTemporaryChanges:^{
            [_state.currentGrid appendLines:[_state.currentGrid numberOfLinesUsed]
                               toLineBuffer:temporaryLineBuffer];

            // Search one block.
            LineBufferPosition *stopAt;
            if (context.dir > 0) {
                stopAt = [temporaryLineBuffer lastPosition];
            } else {
                stopAt = [temporaryLineBuffer firstPosition];
            }

            if (rangeSearched) {
                rangeSearched->start = [self absCoordOfFindContext:context lineBuffer:temporaryLineBuffer];
            }
            struct timeval begintime;
            gettimeofday(&begintime, NULL);
            int iterations = 0;
            int ms_diff = 0;
            do {
                if (context.status == Searching) {
                    [temporaryLineBuffer findSubstring:context stopAt:stopAt];
                }

                // Handle the current state
                switch (context.status) {
                    case Matched: {
                        // NSLog(@"matched");
                        // Found a match in the text.
                        NSArray *allPositions = [temporaryLineBuffer convertPositions:context.results
                                                                            withWidth:_state.currentGrid.size.width];
                        for (XYRange *xyrange in allPositions) {
                            SearchResult *result = [SearchResult withCoordRange:xyrange.coordRange
                                                                       overflow:_state.cumulativeScrollbackOverflow];

                            [results addObject:result];

                            if (!(context.options & FindMultipleResults)) {
                                assert([context.results count] == 1);
                                [context reset];
                                keepSearching = NO;
                            } else {
                                keepSearching = YES;
                            }
                        }
                        [context.results removeAllObjects];
                        break;
                    }

                    case Searching:
                        // NSLog(@"searching");
                        // No result yet but keep looking
                        keepSearching = YES;
                        break;

                    case NotFound:
                        // NSLog(@"not found");
                        // Reached stopAt point with no match.
                        if (context.hasWrapped) {
                            [context reset];
                            keepSearching = NO;
                        } else {
                            // NSLog(@"...wrapping");
                            // wrap around and resume search.
                            FindContext *tempFindContext = [[FindContext alloc] init];
                            [temporaryLineBuffer prepareToSearchFor:self.findContext.substring
                                                         startingAt:(self.findContext.dir > 0 ? [temporaryLineBuffer firstPosition] : [[temporaryLineBuffer lastPosition] predecessor])
                                                            options:self.findContext.options
                                                               mode:self.findContext.mode
                                                        withContext:tempFindContext];
                            [self.findContext reset];
                            // TODO test this!
                            [context copyFromFindContext:tempFindContext];
                            context.hasWrapped = YES;
                            keepSearching = YES;
                        }
                        break;

                    default:
                        assert(false);  // Bogus status
                }

                struct timeval endtime;
                if (keepSearching) {
                    gettimeofday(&endtime, NULL);
                    ms_diff = (endtime.tv_sec - begintime.tv_sec) * 1000 +
                    (endtime.tv_usec - begintime.tv_usec) / 1000;
                    context.status = Searching;
                }
                ++iterations;
            } while (keepSearching && ms_diff < context.maxTime * 1000);

            switch (context.status) {
                case Searching: {
                    int numDropped = [temporaryLineBuffer numberOfDroppedBlocks];
                    double current = context.absBlockNum - numDropped;
                    double max = [temporaryLineBuffer largestAbsoluteBlockNumber] - numDropped;
                    double p = MAX(0, current / max);
                    if (context.dir > 0) {
                        context.progress = p;
                    } else {
                        context.progress = 1.0 - p;
                    }
                    break;
                }
                case Matched:
                case NotFound:
                    context.progress = 1;
                    break;
            }
            // NSLog(@"Did %d iterations in %dms. Average time per block was %dms", iterations, ms_diff, ms_diff/iterations);

            if (rangeSearched) {
                rangeSearched->end = [self absCoordOfFindContext:context lineBuffer:temporaryLineBuffer];
            }
        }];
        return keepSearching;
    }
}


@end
