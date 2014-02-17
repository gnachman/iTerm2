//
//  iTermSelection.m
//  iTerm
//
//  Created by George Nachman on 2/10/14.
//
//

#import "iTermSelection.h"
#import "DebugLogging.h"

@implementation iTermSubSelection

+ (instancetype)subSelectionWithRange:(VT100GridCoordRange)range
                                 mode:(iTermSelectionMode)mode {
    iTermSubSelection *sub = [[[iTermSubSelection alloc] init] autorelease];
    sub.range = range;
    sub.selectionMode = mode;
    return sub;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p range=%@ mode=%@>",
            [self class], self, VT100GridCoordRangeDescription(_range),
            [iTermSelection nameForMode:_selectionMode]];
}

- (BOOL)containsCoord:(VT100GridCoord)coord {
    VT100GridCoord start = VT100GridCoordRangeMin(_range);
    VT100GridCoord end = VT100GridCoordRangeMax(_range);
    
    if (_selectionMode == kiTermSelectionModeBox) {
        int left = MIN(start.x, end.x);
        int right = MAX(start.x, end.x);
        int top = MIN(start.y, end.y);
        int bottom = MAX(start.y, end.y);
        return (coord.x >= left && coord.x < right && coord.y >= top && coord.y <= bottom);
    } else {
        long long w = MAX(MAX(MAX(1, coord.x), start.x), end.x) + 1;
        long long coordPos = (long long)coord.y * w + coord.x;
        long long minPos = (long long)start.y * w + start.x;
        long long maxPos = (long long)end.y * w + end.x;
        
        return coordPos >= minPos && coordPos < maxPos;
    }
}

- (instancetype)copyWithZone:(NSZone *)zone {
    iTermSubSelection *theCopy = [[iTermSubSelection alloc] init];
    theCopy.range = self.range;
    theCopy.selectionMode = self.selectionMode;

    return theCopy;
}

@end

@interface iTermSelection ()
@property(nonatomic, assign) BOOL appending;
@end

@implementation iTermSelection {
    VT100GridCoordRange _range;
    VT100GridCoordRange _initialRange;
    BOOL _live;
    BOOL _extend;
    NSMutableArray *_subSelections;  // iTermSubSelection array
}

+ (NSString *)nameForMode:(iTermSelectionMode)mode {
    switch (mode) {
        case kiTermSelectionModeCharacter:
            return @"character";
        case kiTermSelectionModeBox:
            return @"box";
        case kiTermSelectionModeLine:
            return @"line";
        case kiTermSelectionModeSmart:
            return @"smart";
        case kiTermSelectionModeWholeLine:
            return @"wholeLine";
        case kiTermSelectionModeWord:
            return @"word";
        default:
            return [NSString stringWithFormat:@"undefined-%d", (int)mode];
    }
}

- (id)init {
    self = [super init];
    if (self) {
        _subSelections = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_subSelections release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p liveRange=%@ initialRange=%@ live=%d extend=%d "
            @"resumable=%d mode=%@ subselections=%@ delegate=%@>",
            [self class], self, VT100GridCoordRangeDescription(_range),
            VT100GridCoordRangeDescription(_initialRange), _live, _extend, _resumable,
            [[self class] nameForMode:_selectionMode], _subSelections, _delegate];
}

- (void)flip {
    _range = VT100GridCoordRangeMake(_range.end.x,
                                     _range.end.y,
                                     _range.start.x,
                                     _range.start.y);
}

- (VT100GridCoordRange)unflippedLiveRange {
    return [self unflippedRangeForRange:_range];
}

- (void)beginExtendingSelectionAt:(VT100GridCoord)coord {
    if (_live) {
        return;
    }
    if ([_subSelections count] == 0) {
        [self beginSelectionAt:coord mode:_selectionMode resume:NO append:NO];
        return;
    } else {
        iTermSubSelection *sub = [_subSelections lastObject];
        _range = sub.range;
        _selectionMode = sub.selectionMode;
        [_subSelections removeLastObject];
    }
    DLog(@"Begin extending selection.");
    _live = YES;
    _appending = NO;
    _extend = YES;
    
    if ([self liveRangeIsFlipped]) {
        // Make sure range is not flipped.
        [self flip];
    }
    
    VT100GridCoordRange range = [self rangeForCurrentModeAtCoord:coord
                                           includeParentheticals:YES];
    
    if (range.start.x != -1) {
        if (range.start.x == -1) {
            range = [_delegate selectionRangeForWordAt:coord];
        }
        if ([self coord:coord isInRange:_range]) {
            // The click point is inside old live range.
            int width = [self width];
            long long distanceToStart = VT100GridCoordDistance(_range.start,
                                                               range.start,
                                                               width);
            long long distanceToEnd = VT100GridCoordDistance(_range.end, range.end, width);
            if (distanceToEnd < distanceToStart) {
                // Move the end point
                _range.end = range.end;
                _initialRange = [self rangeForCurrentModeAtCoord:_range.start
                                           includeParentheticals:NO];
                ;
            } else {
                // Flip and move what was the start point
                [self flip];
                _range.end = range.start;
                VT100GridCoord anchor = [_delegate selectionPredecessorOfCoord:_range.start];
                _initialRange = [self rangeForCurrentModeAtCoord:anchor
                                           includeParentheticals:NO];
            }
        } else {
            // The click point is outside the live range
            VT100GridCoordRange determinant = _initialRange;
            if ([self coord:determinant.start isEqualToCoord:determinant.end]) {
                // The initial range was empty, so use the live selection range to decide whether to
                // move the start or end point of the live range.
                determinant = [self unflippedLiveRange];
            }
            if ([self coord:range.end isAfterCoord:determinant.end]) {
                _range.end = range.end;
                _initialRange = [self rangeForCurrentModeAtCoord:_range.start
                                           includeParentheticals:NO];
            }
            if ([self coord:range.start isBeforeCoord:determinant.start]) {
                [self flip];
                _range.end = range.start;
                VT100GridCoord lastSelectedCharCoord =
                    [_delegate selectionPredecessorOfCoord:_range.start];
                _initialRange = [self rangeForCurrentModeAtCoord:lastSelectedCharCoord
                                           includeParentheticals:NO];

            }
        }
    }
    [self extendPastNulls];
    [_delegate selectionDidChange:self];
}

 - (VT100GridCoordRange)rangeForCurrentModeAtCoord:(VT100GridCoord)coord
                             includeParentheticals:(BOOL)includeParentheticals {
     VT100GridCoordRange range = VT100GridCoordRangeMake(-1, -1, -1, -1);
     switch (_selectionMode) {
         case kiTermSelectionModeWord:
             if (includeParentheticals) {
                 range = [_delegate selectionRangeForParentheticalAt:coord];
             }
             if (range.start.x == -1) {
                 range = [_delegate selectionRangeForWordAt:coord];
             }
             break;
             
         case kiTermSelectionModeWholeLine:
             range = [_delegate selectionRangeForWrappedLineAt:coord];
             break;
             
         case kiTermSelectionModeSmart:
             range = [_delegate selectionRangeForSmartSelectionAt:coord];
             break;
             
         case kiTermSelectionModeLine:
             range = [_delegate selectionRangeForLineAt:coord];
             break;
             
         case kiTermSelectionModeCharacter:
         case kiTermSelectionModeBox:
             range = VT100GridCoordRangeMake(coord.x, coord.y, coord.x, coord.y);
             break;
     }
     return range;
 }
                             
- (void)beginSelectionAt:(VT100GridCoord)coord
                    mode:(iTermSelectionMode)mode
                  resume:(BOOL)resume
                  append:(BOOL)append {
    if (_live) {
        return;
    }
    if (_resumable && resume && [_subSelections count]) {
        _range = [self lastRange];
        [_subSelections removeLastObject];
        // Preserve existing value of appending flag.
    } else {
        _appending = append;
    }
    
    if (!_appending) {
        [_subSelections removeAllObjects];
    }
    DLog(@"Begin new selection. coord=%@, extend=%d", VT100GridCoordDescription(coord), extend);
    _live = YES;
    _extend = NO;
    _selectionMode = mode;
    _range = [self rangeForCurrentModeAtCoord:coord includeParentheticals:YES];
    _initialRange = _range;

    DLog(@"Begin selection, range=%@", VT100GridCoordRangeDescription(_range));
    [self extendPastNulls];
    [_delegate selectionDidChange:self];
}

- (void)endLiveSelection {
    if (!_live) {
        return;
    }
    DLog(@"End live selection");
    if (_selectionMode == kiTermSelectionModeBox) {
        int left = MIN(_range.start.x, _range.end.x);
        int right = MAX(_range.start.x, _range.end.x);
        int top = MIN(_range.start.y, _range.end.y);
        int bottom = MAX(_range.start.y, _range.end.y);
        _range = VT100GridCoordRangeMake(left, top, right, bottom);
        for (int i = top; i <= bottom; i++) {
            VT100GridCoordRange theRange = VT100GridCoordRangeMake(left, i, right, i);
            theRange = [self rangeByExtendingRangePastNulls:theRange];
            iTermSubSelection *sub =
                [iTermSubSelection subSelectionWithRange:theRange
                                                    mode:kiTermSelectionModeCharacter];
            [_subSelections addObject:sub];
        }
        _resumable = NO;
    } else {
        if (self.liveRangeIsFlipped) {
            DLog(@"Unflip selection");
            [self flip];
        }
        if (_selectionMode == kiTermSelectionModeSmart) {
            // This allows extension to work more sanely.
            _initialRange = _range;
        }
        if ([self haveLiveSelection]) {
            iTermSubSelection *sub = [[[iTermSubSelection alloc] init] autorelease];
            sub.range = _range;
            sub.selectionMode = _selectionMode;
            [_subSelections addObject:sub];
            _resumable = YES;
        } else {
            _resumable = NO;
        }
    }
    _range = VT100GridCoordRangeMake(-1, -1, -1, -1);
    _extend = NO;
    _live = NO;
    
    [_delegate selectionDidChange:self];
}

- (BOOL)haveLiveSelection {
    return _live && _range.start.x != -1 && VT100GridCoordRangeLength(_range, [self width]) > 0;
}
    
- (BOOL)extending {
    return _extend;
}

- (void)clearSelection {
    DLog(@"Clear selection");
    _range = VT100GridCoordRangeMake(-1, -1, -1, -1);
    [_subSelections removeAllObjects];
    [_delegate selectionDidChange:self];
}

- (VT100GridCoordRange)liveRange {
    return _range;
}

- (BOOL)coord:(VT100GridCoord)coord isInRange:(VT100GridCoordRange)range {
    iTermSubSelection *temp = [iTermSubSelection subSelectionWithRange:range
                                                                  mode:_selectionMode];
    return [temp containsCoord:coord];
}

- (BOOL)coord:(VT100GridCoord)a isBeforeCoord:(VT100GridCoord)b {
    return VT100GridCoordOrder(a, b) == NSOrderedAscending;
}

- (BOOL)coord:(VT100GridCoord)a isAfterCoord:(VT100GridCoord)b {
    return VT100GridCoordOrder(a, b) == NSOrderedDescending;
}

- (BOOL)coord:(VT100GridCoord)a isEqualToCoord:(VT100GridCoord)b {
    return VT100GridCoordOrder(a, b) == NSOrderedSame;
}

- (void)moveSelectionEndpointTo:(VT100GridCoord)coord {
    DLog(@"Move selection to %@", VT100GridCoordDescription(coord));
    if (coord.y < 0) {
        coord.x = coord.y = 0;
    }
    VT100GridCoordRange range = [self rangeForCurrentModeAtCoord:coord includeParentheticals:NO];
    
    if (!_live) {
        [self beginSelectionAt:coord mode:self.selectionMode resume:NO append:NO];
    }
    switch (_selectionMode) {
        case kiTermSelectionModeBox:
        case kiTermSelectionModeCharacter:
            _range.end = coord;
            break;
            
        case kiTermSelectionModeLine:
        case kiTermSelectionModeSmart:
        case kiTermSelectionModeWholeLine:
        case kiTermSelectionModeWord:
            [self moveSelectionEndpointToRange:range];
            break;
    }

    _extend = YES;
    [self extendPastNulls];
    [_delegate selectionDidChange:self];
}

- (void)moveSelectionEndpointToRange:(VT100GridCoordRange)range {
    DLog(@"move selection endpoint to range=%@ selection=%@ initial=%@",
         VT100GridCoordRangeDescription(range),
         VT100GridCoordRangeDescription(_range),
         VT100GridCoordRangeDescription(_initialRange));
    VT100GridCoordRange newRange = _range;
    if ([self coord:_range.start isBeforeCoord:range.end]) {
        // The word you clicked on ends after the start of the existing range.
        if ([self liveRangeIsFlipped]) {
            // The range is flipped. This happens when you were selecting backwards and
            // turned around and started going forwards.
            //
            // end<---------selection--------->start
            //                                |...<-----------range----------->
            //                 <-initialRange->
            //            start<----------------newRange--------------------->end
            newRange.start = _initialRange.start;
            newRange.end = range.end;
        } else {
            // start<---------selection---------->end
            //      |<<<<<<<<<<<<<<<|
            //       ...<---range--->
            // start<---newRange---->end
            if ([self coord:range.start isBeforeCoord:_range.start]) {
                // This happens with smart selection, where the new range is not just a subset of
                // the old range.
                newRange.start = range.start;
            } else {
                newRange.end = range.end;
            }
        }
    } else {
        if (![self liveRangeIsFlipped]) {
            // This happens when you were selecting forwards and turned around and started
            // going backwards.
            //                 start<-------------selection------------->end
            //    <----range---->...|
            //                      <-initialRange->
            // end<-----------newRange------------->start
            newRange.start = _initialRange.end;
            newRange.end = range.start;
        } else {
            // end<-------------selection-------------->start
            //                         <---range--->...|
            //                      end<---newRange---->start
            newRange.end = range.start;
        }
    }
    DLog(@"  newrange=%@", VT100GridCoordRangeDescription(newRange));
    _range = newRange;
}

- (BOOL)hasSelection {
    return [_subSelections count] > 0 || [self haveLiveSelection];
}

- (void)moveUpByLines:(int)numLines {
    _range.start.y -= numLines;
    _range.end.y -= numLines;
    
    if (_range.start.y < 0 || _range.end.y < 0) {
        [self clearSelection];
    }
}

- (BOOL)rangeIsFlipped:(VT100GridCoordRange)range {
    return VT100GridCoordOrder(range.start, range.end) == NSOrderedDescending;
}

- (BOOL)liveRangeIsFlipped {
    return [self rangeIsFlipped:_range];
}

- (BOOL)containsCoord:(VT100GridCoord)coord {
    if (![self hasSelection]) {
        return NO;
    }
    BOOL contained = NO;
    for (iTermSubSelection *sub in [self allSubSelections]) {
        if ([sub containsCoord:coord]) {
            contained = !contained;
        }
    }
    
    return contained;
}

- (int)width {
    return [_delegate selectionRangeForLineAt:VT100GridCoordMake(0, 0)].end.x;
}

- (long long)length {
    return VT100GridCoordRangeLength(_range, [self width]);
}

- (void)setSelectedRange:(VT100GridCoordRange)selectedRange {
    _range = selectedRange;
    [_delegate selectionDidChange:self];
}

- (id)copyWithZone:(NSZone *)zone {
    iTermSelection *theCopy = [[iTermSelection alloc] init];
    theCopy->_range = _range;
    theCopy->_initialRange = _initialRange;
    theCopy->_live = _live;
    theCopy->_extend = _extend;
    theCopy->_subSelections = [_subSelections mutableCopy];
    theCopy->_resumable = _resumable;
    
    theCopy.delegate = _delegate;
    theCopy.selectionMode = _selectionMode;
    
    return theCopy;
}

- (VT100GridCoordRange)unflippedRangeForRange:(VT100GridCoordRange)range {
    if ([self coord:range.end isBeforeCoord:range.start]) {
        return VT100GridCoordRangeMake(range.end.x, range.end.y, range.start.x, range.start.y);
    } else {
        return range;
    }
}

- (VT100GridCoordRange)rangeByExtendingRangePastNulls:(VT100GridCoordRange)range {
    VT100GridCoordRange unflippedRange = [self unflippedRangeForRange:range];
    VT100GridRange nulls =
        [_delegate selectionRangeOfTerminalNullsOnLine:unflippedRange.start.y];
    
    // Fix the beginning of the range (start if unflipped, end if flipped)
    if (unflippedRange.start.x > nulls.location) {
        if ([self rangeIsFlipped:range]) {
            range.end.x = nulls.location;
        } else {
            range.start.x = nulls.location;
        }
    }
    
    // Fix the terminus of the range (end if unflipped, start if flipped)
    nulls = [_delegate selectionRangeOfTerminalNullsOnLine:unflippedRange.end.y];
    if (unflippedRange.end.x > nulls.location) {
        if ([self rangeIsFlipped:range]) {
            range.start.x = nulls.location + nulls.length;
        } else {
            range.end.x = nulls.location + nulls.length;
        }
    }
    return range;
}

- (void)extendPastNulls {
    if (_selectionMode == kiTermSelectionModeBox) {
        return;
    }
    if ([self hasSelection] && _live) {
        _range = [self rangeByExtendingRangePastNulls:_range];
    }
}

- (NSArray *)allSubSelections {
    if ([self haveLiveSelection]) {
        NSMutableArray *subs = [NSMutableArray array];
        [subs addObjectsFromArray:_subSelections];
        iTermSubSelection *temp = [iTermSubSelection subSelectionWithRange:[self unflippedLiveRange]
                                                                      mode:_selectionMode];
        [subs addObject:temp];
        return subs;
    } else {
        return _subSelections;
    }
}

- (VT100GridCoordRange)spanningRange {
    VT100GridCoordRange span = VT100GridCoordRangeMake(-1, -1, -1, -1);
    for (iTermSubSelection *sub in [self allSubSelections]) {
        VT100GridCoordRange range = sub.range;
        if (span.start.x == -1) {
            span.start = range.start;
            span.end = range.end;
        } else {
            if ([self coord:range.start isBeforeCoord:span.start]) {
                span.start = range.start;
            }
            if ([self coord:range.end isAfterCoord:span.end]) {
                span.end = range.end;
            }
        }
    }
    return span;
}

- (VT100GridCoordRange)lastRange {
    VT100GridCoordRange best = VT100GridCoordRangeMake(-1, -1, -1, -1);
    for (iTermSubSelection *sub in [self allSubSelections]) {
        VT100GridCoordRange range = sub.range;
        if (best.start.x < 0 || [self coord:range.end isAfterCoord:best.end]) {
            best = range;
        }
    }
    return best;
}

- (VT100GridCoordRange)firstRange {
    VT100GridCoordRange best = VT100GridCoordRangeMake(-1, -1, -1, -1);
    for (iTermSubSelection *sub in [self allSubSelections]) {
        VT100GridCoordRange range = sub.range;
        if (best.start.x < 0 || [self coord:range.start isAfterCoord:best.start]) {
            best = range;
        }
    }
    return best;
}

- (void)setFirstRange:(VT100GridCoordRange)firstRange mode:(iTermSelectionMode)mode {
    firstRange = [self rangeByExtendingRangePastNulls:firstRange];
    if ([_subSelections count] == 0) {
        if (_live) {
            _range = firstRange;
            _selectionMode = mode;
        }
    } else {
        [_subSelections replaceObjectAtIndex:0
                                  withObject:[iTermSubSelection subSelectionWithRange:firstRange
                                                                                 mode:mode]];
    }
    [_delegate selectionDidChange:self];
}

- (void)setLastRange:(VT100GridCoordRange)lastRange mode:(iTermSelectionMode)mode {
    lastRange = [self rangeByExtendingRangePastNulls:lastRange];
    if (_live) {
        _range = lastRange;
        _selectionMode = mode;
    } else if ([_subSelections count]) {
        [_subSelections removeLastObject];
        [_subSelections addObject:[iTermSubSelection subSelectionWithRange:lastRange
                                                                      mode:mode]];
    }
    [_delegate selectionDidChange:self];
}

- (void)addSubSelection:(iTermSubSelection *)sub {
    if (sub.selectionMode != kiTermSelectionModeBox) {
        sub.range = [self rangeByExtendingRangePastNulls:sub.range];
    }
    [_subSelections addObject:sub];
    [_delegate selectionDidChange:self];
}

- (NSRange)rangeOfIndexesInRange:(VT100GridCoordRange)range
                          onLine:(int)line
                            mode:(iTermSelectionMode)mode {
    if (mode == kiTermSelectionModeBox) {
        if (range.start.y <= line && range.end.y >= line) {
            return NSMakeRange(range.start.x, range.end.x - range.start.x);
        } else {
            return NSMakeRange(0, 0);
        }
    }
    if (range.start.y < line && range.end.y > line) {
        return NSMakeRange(0, [self width]);
    }
    if (range.start.y == line) {
        if (range.end.y == line) {
            return NSMakeRange(range.start.x, range.end.x - range.start.x);
        } else {
            return NSMakeRange(range.start.x, [self width] - range.start.x);
        }
    }
    if (range.end.y == line) {
        return NSMakeRange(0, range.end.x);
    }
    return NSMakeRange(0, 0);
}

- (NSIndexSet *)selectedIndexesOnLine:(int)line {
    if (!_live && _subSelections.count == 1) {
        // Fast path
        iTermSubSelection *sub = _subSelections[0];
        NSRange theRange = [self rangeOfIndexesInRange:sub.range
                                                onLine:line
                                                  mode:sub.selectionMode];
        return [NSIndexSet indexSetWithIndexesInRange:theRange];
    }
    if (_live && _subSelections.count == 0) {
        // Fast path
        NSRange theRange = [self rangeOfIndexesInRange:[self unflippedLiveRange]
                                                onLine:line
                                                  mode:_selectionMode];
        return [NSIndexSet indexSetWithIndexesInRange:theRange];
    }

    // Slow path.
    NSArray *subs = [self allSubSelections];
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (iTermSubSelection *sub in [self allSubSelections]) {
        VT100GridCoordRange range = sub.range;
        NSRange theRange = [self rangeOfIndexesInRange:range
                                                onLine:line
                                                  mode:sub.selectionMode];

        // Any values in theRange that intersect indexes should be removed from indexes.
        // And values in theSet that don't intersect indexes should be added to indexes.
        NSMutableIndexSet *indexesToAdd = [NSMutableIndexSet indexSetWithIndexesInRange:theRange];
        NSMutableIndexSet *indexesToRemove = [NSMutableIndexSet indexSet];
        
        [indexes enumerateRangesInRange:theRange options:0 usingBlock:^(NSRange range, BOOL *stop) {
            // range exists in both indexes and theRange
            [indexesToRemove addIndexesInRange:range];
            [indexesToAdd removeIndexesInRange:range];
        }];
        [indexes removeIndexes:indexesToRemove];
        [indexes addIndexes:indexesToAdd];
    }

    return indexes;
}

- (void)enumerateSelectedRanges:(void (^)(VT100GridCoordRange range, BOOL *stop))block {
    if (_live) {
        // Live ranges can have box subs, which is just a pain to deal with, so make a copy,
        // end live selection in the copy (which converts boxes to individual selections), and
        // then try again on the copy.
        iTermSelection *temp = [[self copy] autorelease];
        [temp endLiveSelection];
        [temp enumerateSelectedRanges:block];
        return;
    }

    NSArray *allSubs = [self allSubSelections];
    if ([allSubs count] == 0) {
        return;
    }
    if ([allSubs count] == 1) {
        // fast path
        iTermSubSelection *sub = allSubs[0];
        BOOL stop = NO;
        block(sub.range, &stop);
        return;
    }
    
    // NOTE: This assumes a 64-bit platform, otherwise the NSUInteger type used by index set would
    // overflow too quickly.
    assert(sizeof(NSUInteger) >= 8);
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    int width = [self width];
    for (iTermSubSelection *outer in [self allSubSelections]) {
        NSRange theRange = NSMakeRange(outer.range.start.x + outer.range.start.y * width,
                                       VT100GridCoordRangeLength(outer.range, width));
        
        NSMutableIndexSet *indexesToAdd = [NSMutableIndexSet indexSetWithIndexesInRange:theRange];
        NSMutableIndexSet *indexesToRemove = [NSMutableIndexSet indexSet];
        [indexes enumerateRangesInRange:theRange options:0 usingBlock:^(NSRange range, BOOL *stop) {
            // range exists in both indexes and theRange
            [indexesToRemove addIndexesInRange:range];
            [indexesToAdd removeIndexesInRange:range];
        }];
        [indexes removeIndexes:indexesToRemove];
        [indexes addIndexes:indexesToAdd];
    }
    
    // enumerateRangesUsingBlock doesn't guarantee the ranges come in order, so put them in an array
    // and then sort it.
    NSMutableArray *allRanges = [NSMutableArray array];
    [indexes enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        VT100GridCoordRange coordRange =
            VT100GridCoordRangeMake(range.location % width,
                                    range.location / width,
                                    (range.location + range.length) % width,
                                    (range.location + range.length) / width);
        [allRanges addObject:[NSValue valueWithGridCoordRange:coordRange]];
    }];

    NSArray *sortedRanges =
        [allRanges sortedArrayUsingSelector:@selector(compareGridCoordRangeStart:)];
    for (NSValue *value in sortedRanges) {
        BOOL stop = NO;
        block([value gridCoordRangeValue], &stop);
        if (stop) {
            break;
        }
    }
}

@end
