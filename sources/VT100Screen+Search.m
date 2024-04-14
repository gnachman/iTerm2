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
        //assert([_searchBuffer isEqual:_state.linebuffer]);
        DLog(@"Make fresh copy");
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
          multipleResults:(BOOL)multipleResults
             absLineRange:(NSRange)absLineRange {
    DLog(@"begin self=%@ aString=%@", self, aString);

    // It's too hard to reason about merging the search buffer with the real
    // buffer when the real buffer is a moving target! When state is shared
    // then _state.linebuffer is the mutation line buffer. But _searchBuffer is
    // kept in sync with the non-mutation linebuffer by merging it
    // periodically. We can't mix and match who we merge with because merging
    // uses progenitor pointers and expects a consistent pair of LineBuffers
    // for the merge.
    assert(!self.stateIsShared);

    if (absLineRange.length > 0) {
        // Constrain y to absLineRange
        const long long overflow = self.totalScrollbackOverflow;
        long long absY = y + overflow;
        if (absY < absLineRange.location) {
            absY = absLineRange.location;
        } else if (absY >= NSMaxRange(absLineRange)) {
            absY = NSMaxRange(absLineRange);
        }
        if (absY < overflow) {
            y = 0;
        } else {
            y = absY - overflow;
        }
    }
    context.initialStart = VT100GridAbsCoordMake(x, self.totalScrollbackOverflow + y);

    @autoreleasepool {
        LineBuffer *tempLineBuffer = [self searchBuffer];

        //assert([tempLineBuffer isEqual:_state.linebuffer]);
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
                    VT100GridCoord lastPositionCoord;
                    if (absLineRange.length > 0) {
                        const long long lastY = MAX(0, NSMaxRange(absLineRange) - 1 - self.totalScrollbackOverflow);
                        lastPositionCoord = VT100GridCoordMake(_state.currentGrid.size.width - 1, lastY);
                        ok = YES;
                    } else {
                        lastPositionCoord = [tempLineBuffer coordinateForPosition:lastValidPosition
                                                                            width:_state.currentGrid.size.width
                                                                     extendsRight:YES
                                                                               ok:&ok];
                    }
                    assert(ok);
                    long long s = startPosCoord.y;
                    s *= _state.currentGrid.size.width;
                    s += startPosCoord.x;

                    long long l = lastPositionCoord.y;
                    l *= _state.currentGrid.size.width;
                    l += lastPositionCoord.x;

                    if (s >= l) {
                        startPos = lastValidPosition;
                    } else {
                        VT100GridCoord lastValidCoord = [tempLineBuffer coordinateForPosition:lastValidPosition width:_state.currentGrid.size.width extendsRight:YES ok:&ok];
                        if (ok && (startPosCoord.y > lastValidCoord.y ||
                                   (startPosCoord.y == lastValidCoord.y && startPosCoord.x > lastValidCoord.x))) {
                            startPos = lastValidPosition;
                        }
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
        //assert([tempLineBuffer isEqual:_state.linebuffer]);
    }
}

- (BOOL)continueFindAllResultsImpl:(NSMutableArray<SearchResult *> *)results
                          rangeOut:(NSRange *)rangePtr
                         inContext:(FindContext *)context
                      absLineRange:(NSRange)absLineRange
                     rangeSearched:(VT100GridAbsCoordRange *)rangeSearched {
    NSDate* start = [NSDate date];
    BOOL keepSearching;
    do {
        keepSearching = [self continueFindResultsInContext:context
                                                  rangeOut:rangePtr
                                                   toArray:results
                                              absLineRange:(NSRange)absLineRange
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

- (void)updateRange:(NSRange *)rangePtr
        fromContext:(FindContext *)context
         lineBuffer:(LineBuffer *)linebuffer {
    const long long line = [linebuffer numberOfWrappedLinesWithWidth:_state.width
                                             upToAbsoluteBlockNumber:context.absBlockNum] + _state.totalScrollbackOverflow;
    if (context.dir > 0) {
        // Searching forwards
        *rangePtr = NSMakeRange(0, line);
    } else {
        const long long numberOfLines = [linebuffer numberOfWrappedLinesWithWidth:_state.width] + _state.totalScrollbackOverflow;
        *rangePtr = NSMakeRange(line, numberOfLines - line);
    }
}

- (BOOL)continueFindResultsInContext:(FindContext *)context
                            rangeOut:(NSRange *)rangePtr
                             toArray:(NSMutableArray *)results
                        absLineRange:(NSRange)absLineRange
                       rangeSearched:(VT100GridAbsCoordRange *)rangeSearched {
    DLog(@"continue find…");
    // Append the screen contents to the scrollback buffer so they are included in the search.
    __block BOOL keepSearching = NO;
    assert(context.substring != nil);
    @autoreleasepool {
        LineBuffer *temporaryLineBuffer = [self searchBuffer];
        [temporaryLineBuffer performBlockWithTemporaryChanges:^{
            [_state.currentGrid appendLines:[_state.currentGrid numberOfLinesUsed]
                               toLineBuffer:temporaryLineBuffer];

            // Search one block.
            BOOL ok;
            const VT100GridCoord initialStartRel = VT100GridCoordFromAbsCoord(context.initialStart,
                                                                              self.totalScrollbackOverflow,
                                                                              &ok);

            LineBufferPosition *initialStartPosition = nil;
            if (ok) {
                initialStartPosition = [temporaryLineBuffer positionForCoordinate:initialStartRel
                                                                            width:_state.currentGrid.size.width
                                                                           offset:0];
            }
            LineBufferPosition *stopAt = nil;
            if (context.hasWrapped) {
                DLog(@"Set stopAt to initial start position %@", initialStartPosition);
                stopAt = initialStartPosition;
            }
            if (absLineRange.length > 0) {
                if (!stopAt) {
                    int y = 0;
                    if (context.dir > 0) {
                        DLog(@"Continue searching until the end of the selected command");
                        y = NSMaxRange(absLineRange) - _state.totalScrollbackOverflow;
                    } else {
                        DLog(@"Continue searching until the start of the selected command");
                        y = absLineRange.location - _state.totalScrollbackOverflow;
                    }
                    stopAt = [temporaryLineBuffer positionForCoordinate:VT100GridCoordMake(0, y)
                                                                  width:_state.currentGrid.size.width
                                                                 offset:0];
                    if (!stopAt) {
                        if (context.dir > 0) {
                            DLog(@"Continue searching until the end");
                            stopAt = temporaryLineBuffer.penultimatePosition;
                        } else {
                            DLog(@"Continue searching until the start");
                            stopAt = temporaryLineBuffer.firstPosition;
                        }
                    }
                }
                const VT100GridAbsCoord originalStartCoord = [self absCoordOfFindContext:context lineBuffer:temporaryLineBuffer];
                VT100GridAbsCoord startCoord = originalStartCoord;
                BOOL moveStart = NO;
                if (startCoord.y < (NSInteger)absLineRange.location) {
                    startCoord.y = absLineRange.location;
                    startCoord.x = 0;
                    moveStart = YES;
                } else if (startCoord.y >= (NSInteger)NSMaxRange(absLineRange)) {
                    startCoord.y = NSMaxRange(absLineRange) - 1;
                    startCoord.x = _state.currentGrid.size.width - 1;
                    moveStart = YES;
                }
                if (moveStart) {
                    BOOL ok;
                    VT100GridCoord rel = VT100GridCoordFromAbsCoord(startCoord, self.totalScrollbackOverflow, &ok);
                    if (!ok) {
                        DLog(@"Unable to convert %@, assume 0,0", VT100GridAbsCoordDescription(startCoord));
                        rel = VT100GridCoordMake(0, 0);
                    }
                    DLog(@"Tweak start coord of search with line range %@ from %@ to %@",
                         NSStringFromRange(absLineRange), VT100GridAbsCoordDescription(originalStartCoord),
                         VT100GridAbsCoordDescription(startCoord));
                    ok = [temporaryLineBuffer setStartCoord:rel
                                              ofFindContext:context
                                                      width:_state.currentGrid.size.width];
                    if (!ok) {
                        DLog(@"Failed to set search coord");
                    }
                }
            } else {
                if (!stopAt) {
                    if (context.dir > 0) {
                        DLog(@"Continue searching until the end");
                        stopAt = [temporaryLineBuffer lastPosition];
                    } else {
                        DLog(@"Continue searching until the start");
                        stopAt = [temporaryLineBuffer firstPosition];
                    }
                }
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
                    const int width = _state.currentGrid.size.width;
                    const VT100GridCoord startCoord =
                    [temporaryLineBuffer coordinateForPosition:[temporaryLineBuffer positionOfFindContext:context
                                                                                                    width:width]
                                                         width:width
                                                  extendsRight:NO
                                                            ok:nil];

                    const VT100GridCoord stopCoord =
                    [temporaryLineBuffer coordinateForPosition:stopAt
                                                         width:width
                                                  extendsRight:NO
                                                            ok:nil];
                    [temporaryLineBuffer findSubstring:context stopAt:stopAt];
                    const VT100GridCoord currentCoord =
                    [temporaryLineBuffer coordinateForPosition:[temporaryLineBuffer positionOfFindContext:context
                                                                                                    width:width]
                                                         width:width
                                                  extendsRight:NO
                                                            ok:nil];
                    DLog(@"Search from %@ to %@ went up to %@",
                         VT100GridCoordDescription(startCoord),
                         VT100GridCoordDescription(stopCoord),
                         VT100GridCoordDescription(currentCoord));
                }

                // Handle the current state
                switch (context.status) {
                    case Matched: {
                        // NSLog(@"matched");
                        // Found a match in the text.
                        NSArray *allPositions = [temporaryLineBuffer convertPositions:context.results
                                                                            withWidth:_state.currentGrid.size.width];
                        for (XYRange *xyrange in allPositions) {
                            DLog(@"  Add result at %@", xyrange);
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
                            // wrap around and resume search.
                            DLog(@"...wrapping");
                            FindContext *tempFindContext = [[FindContext alloc] init];
                            LineBufferPosition *startPos;
                            if (absLineRange.length > 0) {
                                const int width = _state.currentGrid.size.width;
                                long long absY;
                                int x;
                                int offset;
                                if (context.dir > 0) {
                                    // First position in range
                                    x = 0;
                                    absY = absLineRange.location;
                                    offset = 0;
                                } else {
                                    // Last position in range
                                    absY = NSMaxRange(absLineRange);
                                    x = 0;
                                    offset = -1;
                                }
                                const int y = absY - self.totalScrollbackOverflow;
                                startPos = [temporaryLineBuffer positionForCoordinate:VT100GridCoordMake(x, y)
                                                                                width:width
                                                                               offset:offset];
                                DLog(@"New start position is %@,%@", @(x), @(y));
                            } else {
                                if (context.dir > 0) {
                                    startPos = temporaryLineBuffer.firstPosition;
                                    DLog(@"New start position is first position");
                                } else {
                                    startPos = temporaryLineBuffer.lastPosition.predecessor;
                                    DLog(@"New start position is penultimate position");
                                }
                            }
                            [temporaryLineBuffer prepareToSearchFor:context.substring
                                                         startingAt:startPos
                                                            options:context.options
                                                               mode:context.mode
                                                        withContext:tempFindContext];
                            [context copyFromFindContext:tempFindContext];
                            context.hasWrapped = YES;
                            keepSearching = YES;
                        }
                        break;

                    default:
                        assert(false);  // Bogus status
                }

                if (keepSearching) {
                    [self updateRange:rangePtr
                          fromContext:context
                           lineBuffer:temporaryLineBuffer];
                } else {
                    *rangePtr = NSMakeRange(0, [_state numberOfLines] + [_state totalScrollbackOverflow]);
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
            DLog(@"Did %d iterations in %dms. Average time per block was %dms", iterations, ms_diff, ms_diff/iterations);

            if (rangeSearched) {
                rangeSearched->end = [self absCoordOfFindContext:context lineBuffer:temporaryLineBuffer];
            }
        }];
        return keepSearching;
    }
}


@end
