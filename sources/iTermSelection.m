//
//  iTermSelection.m
//  iTerm
//
//  Created by George Nachman on 2/10/14.
//
//

#import "iTermSelection.h"
#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "ScreenChar.h"

static NSString *const kSelectionSubSelectionsKey = @"Sub selections";

static NSString *const kiTermSubSelectionRange = @"Range";
static NSString *const kiTermSubSelectionMode = @"Mode";

@implementation iTermSubSelection

+ (instancetype)subSelectionWithRange:(VT100GridWindowedRange)range
                                 mode:(iTermSelectionMode)mode {
    iTermSubSelection *sub = [[[iTermSubSelection alloc] init] autorelease];
    sub.range = range;
    sub.selectionMode = mode;
    return sub;
}

+ (instancetype)subSelectinWithDictionary:(NSDictionary *)dict {
    return [self subSelectionWithRange:[dict[kiTermSubSelectionRange] gridWindowedRange]
                                  mode:[dict[kiTermSubSelectionMode] intValue]];
}

- (NSDictionary *)dictionaryValueWithYOffset:(int)yOffset {
    VT100GridWindowedRange range = _range;
    range.coordRange.start.y += yOffset;
    range.coordRange.end.y += yOffset;
    return @{ kiTermSubSelectionRange: [NSDictionary dictionaryWithGridWindowedRange:range],
              kiTermSubSelectionMode: @(_selectionMode) };
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p range=%@ mode=%@>",
            [self class], self, VT100GridWindowedRangeDescription(_range),
            [iTermSelection nameForMode:_selectionMode]];
}

- (BOOL)containsCoord:(VT100GridCoord)coord {
    VT100GridCoord start = VT100GridCoordRangeMin(_range.coordRange);
    VT100GridCoord end = VT100GridCoordRangeMax(_range.coordRange);

    BOOL contained = NO;
    if (_selectionMode == kiTermSelectionModeBox) {
        int left = MIN(start.x, end.x);
        int right = MAX(start.x, end.x);
        int top = MIN(start.y, end.y);
        int bottom = MAX(start.y, end.y);
        contained = (coord.x >= left && coord.x < right && coord.y >= top && coord.y <= bottom);
    } else {
        long long w = MAX(MAX(MAX(1, coord.x), start.x), end.x) + 1;
        long long coordPos = (long long)coord.y * w + coord.x;
        long long minPos = (long long)start.y * w + start.x;
        long long maxPos = (long long)end.y * w + end.x;

        contained = coordPos >= minPos && coordPos < maxPos;
    }
    if (_range.columnWindow.length) {
        contained = contained && VT100GridRangeContains(_range.columnWindow, coord.x);
    }
    return contained;
}

- (instancetype)copyWithZone:(NSZone *)zone {
    iTermSubSelection *theCopy = [[iTermSubSelection alloc] init];
    theCopy.range = self.range;
    theCopy.selectionMode = self.selectionMode;

    return theCopy;
}

- (NSArray *)nonwindowedComponents {
    if (self.selectionMode == kiTermSelectionModeBox ||
        self.range.columnWindow.length <= 0) {
        return @[ self ];
    }
    NSMutableArray *result = [NSMutableArray array];
    [[self class] enumerateRangesInWindowedRange:self.range block:^(VT100GridCoordRange theRange) {
        iTermSubSelection *sub =
            [iTermSubSelection subSelectionWithRange:VT100GridWindowedRangeMake(theRange, 0, 0)
                                                mode:_selectionMode];
        sub.connected = YES;
        [result addObject:sub];
    }];
    [[result lastObject] setConnected:NO];
    return result;
}

+ (void)enumerateRangesInWindowedRange:(VT100GridWindowedRange)windowedRange
                                 block:(void (^)(VT100GridCoordRange))block {
    if (windowedRange.columnWindow.length) {
        int right = windowedRange.columnWindow.location + windowedRange.columnWindow.length;
        int startX = VT100GridWindowedRangeStart(windowedRange).x;
        for (int y = windowedRange.coordRange.start.y; y < windowedRange.coordRange.end.y; y++) {
            block(VT100GridCoordRangeMake(startX, y, right, y));
            startX = windowedRange.columnWindow.location;
        }
        block(VT100GridCoordRangeMake(startX,
                                      windowedRange.coordRange.end.y,
                                      VT100GridWindowedRangeEnd(windowedRange).x,
                                      windowedRange.coordRange.end.y));
    } else {
        block(windowedRange.coordRange);
    }
}

@end

@implementation iTermSelection {
    VT100GridWindowedRange _range;
    VT100GridWindowedRange _initialRange;
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

- (instancetype)init {
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
            [self class], self, VT100GridWindowedRangeDescription(_range),
            VT100GridCoordRangeDescription(_initialRange.coordRange), _live, _extend, _resumable,
            [[self class] nameForMode:_selectionMode], _subSelections, _delegate];
}

- (void)flip {
    _range.coordRange = VT100GridCoordRangeMake(_range.coordRange.end.x,
                                                _range.coordRange.end.y,
                                                _range.coordRange.start.x,
                                                _range.coordRange.start.y);
}

- (VT100GridWindowedRange)unflippedLiveRange {
    return [self unflippedRangeForRange:_range mode:_selectionMode];
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

    VT100GridWindowedRange range = [self rangeForCurrentModeAtCoord:coord
                                              includeParentheticals:YES
                                                 needAccurateWindow:NO];
    // TODO support range.
    if (range.coordRange.start.x != -1) {
        if (range.coordRange.start.x == -1) {
            range = [_delegate selectionRangeForWordAt:coord];
        }
        if ([self coord:coord isInRange:_range]) {
            // The click point is inside old live range.
            int width = [self width];
            long long distanceToStart = VT100GridCoordDistance(_range.coordRange.start,
                                                               range.coordRange.start,
                                                               width);
            long long distanceToEnd = VT100GridCoordDistance(_range.coordRange.end,
                                                             range.coordRange.end,
                                                             width);
            if (distanceToEnd < distanceToStart) {
                // Move the end point
                _range.coordRange.end = range.coordRange.end;
                _initialRange = [self rangeForCurrentModeAtCoord:_range.coordRange.start
                                           includeParentheticals:NO
                                              needAccurateWindow:NO];
                ;
            } else {
                // Flip and move what was the start point
                [self flip];
                _range.coordRange.end = range.coordRange.start;
                VT100GridCoord anchor =
                    [_delegate selectionPredecessorOfCoord:_range.coordRange.start];
                _initialRange = [self rangeForCurrentModeAtCoord:anchor
                                           includeParentheticals:NO
                                              needAccurateWindow:NO];
            }
        } else {
            // The click point is outside the live range
            VT100GridCoordRange determinant = _initialRange.coordRange;
            if ([self coord:determinant.start isEqualToCoord:determinant.end]) {
                // The initial range was empty, so use the live selection range to decide whether to
                // move the start or end point of the live range.
                determinant = [self unflippedLiveRange].coordRange;
            }
            if ([self coord:range.coordRange.end isAfterCoord:determinant.end]) {
                _range.coordRange.end = range.coordRange.end;
                _initialRange = [self rangeForCurrentModeAtCoord:_range.coordRange.start
                                           includeParentheticals:NO
                                              needAccurateWindow:NO];
            }
            if ([self coord:range.coordRange.start isBeforeCoord:determinant.start]) {
                [self flip];
                _range.coordRange.end = range.coordRange.start;
                VT100GridCoord lastSelectedCharCoord =
                    [_delegate selectionPredecessorOfCoord:_range.coordRange.start];
                _initialRange = [self rangeForCurrentModeAtCoord:lastSelectedCharCoord
                                           includeParentheticals:NO
                                              needAccurateWindow:NO];

            }
        }
    }
    [self extendPastNulls];
    [_delegate selectionDidChange:[[self retain] autorelease]];
}

// needAccurateWindow means that soft boundaries must be recomputed. If it's
// not set then the existing soft boundary in _range is used.
 - (VT100GridWindowedRange)rangeForCurrentModeAtCoord:(VT100GridCoord)rawCoord
                                includeParentheticals:(BOOL)includeParentheticals
                                   needAccurateWindow:(BOOL)needAccurateWindow {
     VT100GridCoord coord = rawCoord;
     if (_range.columnWindow.length > 0) {
         coord.x = MAX(_range.columnWindow.location,
                       MIN(_range.columnWindow.location + _range.columnWindow.length - 1,
                           coord.x));
     }
     VT100GridWindowedRange windowedRange =
        VT100GridWindowedRangeMake(VT100GridCoordRangeMake(-1, -1, -1, -1), 0, 0);
     switch (_selectionMode) {
         case kiTermSelectionModeWord:
             if (includeParentheticals) {
                 windowedRange = [_delegate selectionRangeForParentheticalAt:coord];
             }
             if (windowedRange.coordRange.start.x == -1) {
                 windowedRange = [_delegate selectionRangeForWordAt:coord];
             }
             break;

         case kiTermSelectionModeWholeLine:
             windowedRange = [_delegate selectionRangeForWrappedLineAt:coord];
             break;

         case kiTermSelectionModeSmart:
             windowedRange = [_delegate selectionRangeForSmartSelectionAt:coord];
             break;

         case kiTermSelectionModeLine:
             windowedRange = [_delegate selectionRangeForLineAt:coord];
             break;

         case kiTermSelectionModeCharacter:
             if (_range.columnWindow.length > 0) {
                 coord.x = MAX(_range.columnWindow.location,
                               MIN(_range.columnWindow.location + _range.columnWindow.length,
                                   rawCoord.x));
             }
         case kiTermSelectionModeBox:
             if (needAccurateWindow) {
                 windowedRange = [_delegate selectionRangeForLineAt:coord];
             } else {
                 windowedRange = _range;
             }
             windowedRange.coordRange = VT100GridCoordRangeMake(coord.x, coord.y, coord.x, coord.y);
             break;
     }
     return windowedRange;
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
    _range = [self rangeForCurrentModeAtCoord:coord
                        includeParentheticals:YES
                           needAccurateWindow:YES];
    _initialRange = _range;

    DLog(@"Begin selection, range=%@", VT100GridWindowedRangeDescription(_range));
    [self extendPastNulls];
    [_delegate selectionDidChange:[[self retain] autorelease]];
}

- (void)endLiveSelection {
    if (!_live) {
        return;
    }
    DLog(@"End live selection");
    if (_selectionMode == kiTermSelectionModeBox) {
        int left = MIN(_range.coordRange.start.x, _range.coordRange.end.x);
        int right = MAX(_range.coordRange.start.x, _range.coordRange.end.x);
        int top = MIN(_range.coordRange.start.y, _range.coordRange.end.y);
        int bottom = MAX(_range.coordRange.start.y, _range.coordRange.end.y);
        _range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(left, top, right, bottom),
                                            0, 0);
        for (int i = top; i <= bottom; i++) {
            VT100GridWindowedRange theRange =
                VT100GridWindowedRangeMake(VT100GridCoordRangeMake(left, i, right, i), 0, 0);
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
    _range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(-1, -1, -1, -1), 0, 0);
    _extend = NO;
    _live = NO;

    [_delegate selectionDidChange:[[self retain] autorelease]];
}

- (BOOL)haveLiveSelection {
    return (_live &&
            _range.coordRange.start.x != -1 &&
            VT100GridCoordRangeLength(_range.coordRange, [self width]) > 0);
}

- (BOOL)extending {
    return _extend;
}

- (void)clearSelection {
    if (self.hasSelection) {
        DLog(@"Clear selection");
        _range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(-1, -1, -1, -1), 0, 0);
        [_subSelections removeAllObjects];
        [_delegate selectionDidChange:[[self retain] autorelease]];
    }
}

- (VT100GridWindowedRange)liveRange {
    return _range;
}

- (BOOL)coord:(VT100GridCoord)coord isInRange:(VT100GridWindowedRange)range {
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
    VT100GridWindowedRange range = [self rangeForCurrentModeAtCoord:coord
                                              includeParentheticals:NO
                                                 needAccurateWindow:NO];

    if (!_live) {
        [self beginSelectionAt:coord mode:self.selectionMode resume:NO append:NO];
    }
    switch (_selectionMode) {
        case kiTermSelectionModeBox:
        case kiTermSelectionModeCharacter:
            _range.coordRange.end = coord;
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
    [_delegate selectionDidChange:[[self retain] autorelease]];
}

- (void)moveSelectionEndpointToRange:(VT100GridWindowedRange)range {
    DLog(@"move selection endpoint to range=%@ selection=%@ initial=%@",
         VT100GridWindowedRangeDescription(range),
         VT100GridWindowedRangeDescription(_range),
         VT100GridWindowedRangeDescription(_initialRange));
    VT100GridWindowedRange newRange = _range;
    if ([self coord:_range.coordRange.start isBeforeCoord:range.coordRange.end]) {
        // The word you clicked on ends after the start of the existing range.
        if ([self liveRangeIsFlipped]) {
            // The range is flipped. This happens when you were selecting backwards and
            // turned around and started going forwards.
            //
            // end<---------selection--------->start
            //                                |...<-----------range----------->
            //                 <-initialRange->
            //            start<----------------newRange--------------------->end
            newRange.coordRange.start = _initialRange.coordRange.start;
            newRange.coordRange.end = range.coordRange.end;
        } else {
            // start<---------selection---------->end
            //      |<<<<<<<<<<<<<<<|
            //       ...<---range--->
            // start<---newRange---->end
            if ([self coord:range.coordRange.start isBeforeCoord:_range.coordRange.start]) {
                // This happens with smart selection, where the new range is not just a subset of
                // the old range.
                newRange.coordRange.start = range.coordRange.start;
            } else {
                newRange.coordRange.end = range.coordRange.end;
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
            newRange.coordRange.start = _initialRange.coordRange.end;
            newRange.coordRange.end = range.coordRange.start;
        } else {
            // end<-------------selection-------------->start
            //                         <---range--->...|
            //                      end<---newRange---->start
            newRange.coordRange.end = range.coordRange.start;
        }
    }
    DLog(@"  newrange=%@", VT100GridWindowedRangeDescription(newRange));
    _range = newRange;
}

- (BOOL)hasSelection {
    return [_subSelections count] > 0 || [self haveLiveSelection];
}

- (void)moveUpByLines:(int)numLines {
    BOOL notifyDelegateOfChange = _subSelections.count > 0 || [self haveLiveSelection];
    if ([self haveLiveSelection]) {
        _range.coordRange.start.y -= numLines;
        _range.coordRange.end.y -= numLines;
        if (_range.coordRange.start.y < 0) {
           _range.coordRange.start.x = 0;
           _range.coordRange.start.y = 0;
        }
       if (_range.coordRange.end.y < 0) {
          [self clearSelection];
        }
    }

    NSMutableArray *subsToRemove = [NSMutableArray array];
    for (iTermSubSelection *sub in _subSelections) {
        VT100GridWindowedRange range = sub.range;
        range.coordRange.start.y -= numLines;
        range.coordRange.end.y -= numLines;
        if (range.coordRange.start.y < 0) {
            range.coordRange.start.x = 0;
            range.coordRange.start.y = 0;
        }
        sub.range = range;
        if (range.coordRange.end.y < 0) {
            [subsToRemove addObject:sub];
        }
    }

    for (iTermSubSelection *sub in subsToRemove) {
        [_subSelections removeObject:sub];
    }

    if (notifyDelegateOfChange) {
        [_delegate selectionDidChange:self];
    }
}

- (BOOL)rangeIsFlipped:(VT100GridWindowedRange)range {
    return VT100GridCoordOrder(range.coordRange.start, range.coordRange.end) == NSOrderedDescending;
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
    return [_delegate selectionViewportWidth];
}

- (long long)length {
    __block int length = 0;
    const int width = [self width];
    [self enumerateSelectedRanges:^(VT100GridWindowedRange range, BOOL *stop, BOOL eol) {
        length += VT100GridWindowedRangeLength(range, width);
    }];
    return length;
}

- (void)setSelectedRange:(VT100GridWindowedRange)selectedRange {
    _range = selectedRange;
    [_delegate selectionDidChange:[[self retain] autorelease]];
}

- (id)copyWithZone:(NSZone *)zone {
    iTermSelection *theCopy = [[iTermSelection alloc] init];
    theCopy->_range = _range;
    theCopy->_initialRange = _initialRange;
    theCopy->_live = _live;
    theCopy->_extend = _extend;
    for (iTermSubSelection *sub in _subSelections) {
        [theCopy->_subSelections addObject:[[sub copy] autorelease]];
    }
    theCopy->_resumable = _resumable;

    theCopy.delegate = _delegate;
    theCopy.selectionMode = _selectionMode;

    return theCopy;
}

- (VT100GridWindowedRange)unflippedRangeForRange:(VT100GridWindowedRange)range
                                            mode:(iTermSelectionMode)mode {
    if (mode == kiTermSelectionModeBox) {
        // For box selection, we always want the start to be the top left and
        // end to be the bottom right.
        range.coordRange = VT100GridCoordRangeMake(MIN(range.coordRange.start.x,
                                                       range.coordRange.end.x),
                                                   MIN(range.coordRange.start.y,
                                                       range.coordRange.end.y),
                                                   MAX(range.coordRange.start.x,
                                                       range.coordRange.end.x),
                                                   MAX(range.coordRange.start.y,
                                                       range.coordRange.end.y));
    } else if ([self coord:range.coordRange.end isBeforeCoord:range.coordRange.start]) {
        // For all other kinds of selection, the coorinate pair for each of
        // start and end must remain together, but start should precede end in
        // reading order.
        range.coordRange = VT100GridCoordRangeMake(range.coordRange.end.x,
                                                   range.coordRange.end.y,
                                                   range.coordRange.start.x,
                                                   range.coordRange.start.y);
    }
    return range;
}

- (VT100GridWindowedRange)rangeByExtendingRangePastNulls:(VT100GridWindowedRange)range {
    VT100GridWindowedRange unflippedRange = [self unflippedRangeForRange:range mode:_selectionMode];
    VT100GridRange nulls =
        [_delegate selectionRangeOfTerminalNullsOnLine:unflippedRange.coordRange.start.y];

    // Fix the beginning of the range (start if unflipped, end if flipped)
    if (unflippedRange.coordRange.start.x > nulls.location) {
        if ([self rangeIsFlipped:range]) {
            range.coordRange.end.x = nulls.location;
        } else {
            range.coordRange.start.x = nulls.location;
        }
    }

    // Fix the terminus of the range (end if unflipped, start if flipped)
    nulls = [_delegate selectionRangeOfTerminalNullsOnLine:unflippedRange.coordRange.end.y];
    if (unflippedRange.coordRange.end.x > nulls.location) {
        if ([self rangeIsFlipped:range]) {
            range.coordRange.start.x = nulls.location + nulls.length;
        } else {
            range.coordRange.end.x = nulls.location + nulls.length;
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
        VT100GridCoordRange range = sub.range.coordRange;
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

- (VT100GridWindowedRange)lastRange {
    VT100GridWindowedRange best =
        VT100GridWindowedRangeMake(VT100GridCoordRangeMake(-1, -1, -1, -1), 0, 0);
    for (iTermSubSelection *sub in [self allSubSelections]) {
        VT100GridWindowedRange range = sub.range;
        if (best.coordRange.start.x < 0 ||
            [self coord:range.coordRange.end isAfterCoord:best.coordRange.end]) {
            best = range;
        }
    }
    return best;
}

- (VT100GridWindowedRange)firstRange {
    VT100GridWindowedRange best =
        VT100GridWindowedRangeMake(VT100GridCoordRangeMake(-1, -1, -1, -1), 0, 0);
    for (iTermSubSelection *sub in [self allSubSelections]) {
        VT100GridWindowedRange range = sub.range;
        if (best.coordRange.start.x < 0 ||
            [self coord:range.coordRange.start isAfterCoord:best.coordRange.start]) {
            best = range;
        }
    }
    return best;
}

- (void)setFirstRange:(VT100GridWindowedRange)firstRange mode:(iTermSelectionMode)mode {
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
    [_delegate selectionDidChange:[[self retain] autorelease]];
}

- (void)setLastRange:(VT100GridWindowedRange)lastRange mode:(iTermSelectionMode)mode {
    lastRange = [self rangeByExtendingRangePastNulls:lastRange];
    if (_live) {
        _range = lastRange;
        _selectionMode = mode;
    } else if ([_subSelections count]) {
        [_subSelections removeLastObject];
        [_subSelections addObject:[iTermSubSelection subSelectionWithRange:lastRange
                                                                      mode:mode]];
    }
    [_delegate selectionDidChange:[[self retain] autorelease]];
}

- (void)addSubSelection:(iTermSubSelection *)sub {
    [self addSubSelections:@[ sub ]];
}

- (void)addSubSelections:(NSArray<iTermSubSelection *> *)subSelectionArray {
    if (subSelectionArray.count == 0) {
        return;
    }
    for (iTermSubSelection *sub in subSelectionArray) {
        if (sub.selectionMode != kiTermSelectionModeBox) {
            sub.range = [self rangeByExtendingRangePastNulls:sub.range];
        }
        [_subSelections addObject:sub];
    }
    [_delegate selectionDidChange:[[self retain] autorelease]];
}

- (void)removeWindowsWithWidth:(int)width {
    _initialRange = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 0, 0), 0, 0);
    if (_live) {
        [self endLiveSelection];
    }
    NSMutableArray *newSubs = [NSMutableArray array];
    for (iTermSubSelection *sub in _subSelections) {
        if (sub.range.columnWindow.location == 0 &&
            sub.range.columnWindow.length == width) {
            [newSubs addObject:sub];
        } else {
            // There is a nontrivial window
            for (iTermSubSelection *subsub in [sub nonwindowedComponents]) {
                [newSubs addObject:subsub];
            }
        }
    }
    [_subSelections autorelease];
    _subSelections = [newSubs retain];
}

- (NSRange)rangeOfIndexesInRange:(VT100GridWindowedRange)range
                          onLine:(int)line
                            mode:(iTermSelectionMode)mode {
    if (mode == kiTermSelectionModeBox) {
        if (range.coordRange.start.y <= line && range.coordRange.end.y >= line) {
            return NSMakeRange(range.coordRange.start.x,
                               range.coordRange.end.x - range.coordRange.start.x);
        } else {
            return NSMakeRange(0, 0);
        }
    }
    if (range.coordRange.start.y < line && range.coordRange.end.y > line) {
        if (range.columnWindow.length) {
            return NSMakeRange(range.columnWindow.location,
                               range.columnWindow.length);
        } else {
            return NSMakeRange(0, [self width]);
        }
    }
    if (range.coordRange.start.y == line) {
        if (range.coordRange.end.y == line) {
            if (range.columnWindow.length) {
                int limit = VT100GridRangeMax(range.columnWindow) + 1;
                NSRange result;
                result.location = MAX(range.columnWindow.location, range.coordRange.start.x);
                result.length = MIN(limit, range.coordRange.end.x) - result.location;
                return result;
            } else {
                return NSMakeRange(range.coordRange.start.x,
                                   range.coordRange.end.x - range.coordRange.start.x);
            }
        } else {
            if (range.columnWindow.length) {
                int limit = VT100GridRangeMax(range.columnWindow) + 1;
                NSRange result;
                result.location = MAX(range.columnWindow.location, range.coordRange.start.x);
                result.length = MIN(limit, [self width]) - result.location;
                return result;
            } else {
                return NSMakeRange(range.coordRange.start.x,
                                   [self width] - range.coordRange.start.x);
            }
        }
    }
    if (range.coordRange.end.y == line) {
        if (range.columnWindow.length) {
            int limit = VT100GridRangeMax(range.columnWindow) + 1;
            return NSMakeRange(range.columnWindow.location,
                               MIN(limit, range.coordRange.end.x) - range.columnWindow.location);
        } else {
            return NSMakeRange(0, range.coordRange.end.x);
        }
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
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (iTermSubSelection *sub in [self allSubSelections]) {
        VT100GridWindowedRange range = sub.range;
        NSRange theRange = [self rangeOfIndexesInRange:range
                                                onLine:line
                                                  mode:sub.selectionMode];

        // Any values in theRange that intersect indexes should be removed from indexes.
        // And values in theSet that don't intersect indexes should be added to indexes.
        NSMutableIndexSet *indexesToAdd = [NSMutableIndexSet indexSetWithIndexesInRange:theRange];
        NSMutableIndexSet *indexesToRemove = [NSMutableIndexSet indexSet];

        [indexes enumerateRangesInRange:theRange options:0 usingBlock:^(NSRange innerRange, BOOL *stop) {
            // innerRange exists in both indexes and theRange
            [indexesToRemove addIndexesInRange:innerRange];
            [indexesToAdd removeIndexesInRange:innerRange];
        }];
        [indexes removeIndexes:indexesToRemove];
        [indexes addIndexes:indexesToAdd];
    }

    return indexes;
}

// orphaned tab fillers are selected iff they are in the selection.
// unorphaned tab fillers are selected iff their tab is selected.
- (NSIndexSet *)selectedIndexesIncludingTabFillersInLine:(int)y {
    NSIndexSet *basicIndexes = [self selectedIndexesOnLine:y];
    if (!basicIndexes.count) {
        return basicIndexes;
    }

    // Add in tab fillers preceding already-selected tabs.
    NSMutableIndexSet *indexes = [[basicIndexes mutableCopy] autorelease];

    NSRange range;
    if (_range.columnWindow.length > 0) {
        range = NSMakeRange(_range.columnWindow.location, _range.columnWindow.length);
    } else {
        range = NSMakeRange(0, [_delegate selectionViewportWidth]);
    }
    NSIndexSet *tabs = [_delegate selectionIndexesOnLine:y
                                     containingCharacter:'\t'
                                                 inRange:range];
    NSIndexSet *tabFillers =
        [_delegate selectionIndexesOnLine:y
                      containingCharacter:TAB_FILLER
                                  inRange:range];

    [tabs enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        BOOL select = [basicIndexes containsIndex:idx];
        // Found a tab. If selected, add all preceding consecutive TAB_FILLERS
        // to |indexes|. If not selected, remove all preceding consecutive
        // TAB_FILLERs.
        int theIndex = idx;
        for (int i = theIndex - 1; i >= range.location; i--) {
            if ([tabFillers containsIndex:i]) {
                if (select) {
                    [indexes addIndex:i];
                } else {
                    [indexes removeIndex:i];
                }
            } else {
                break;
            }
        }
    }];

    return indexes;
}

- (void)enumerateSelectedRanges:(void (^)(VT100GridWindowedRange, BOOL *, BOOL))block {
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
        block(sub.range, &stop, NO);
        return;
    }

    // NOTE: This assumes a 64-bit platform, otherwise the NSUInteger type used by index set would
    // overflow too quickly.
    assert(sizeof(NSUInteger) >= 8);
    // Ranges ending at connectors don't get a newline following.
    NSMutableIndexSet *connectors = [NSMutableIndexSet indexSet];
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    int width = [self width];
    for (iTermSubSelection *outer in [self allSubSelections]) {
        if (outer.connected) {
            int thePosition = outer.range.coordRange.end.x + outer.range.coordRange.end.y * width;
            [connectors addIndex:thePosition];
        }
        __block NSRange theRange = NSMakeRange(0, 0);
        [iTermSubSelection enumerateRangesInWindowedRange:outer.range
                                                    block:^(VT100GridCoordRange outerRange) {
            theRange = NSMakeRange(outerRange.start.x + outerRange.start.y * width,
                                   VT100GridCoordRangeLength(outerRange, width));

            NSMutableIndexSet *indexesToAdd = [NSMutableIndexSet indexSetWithIndexesInRange:theRange];
            NSMutableIndexSet *indexesToRemove = [NSMutableIndexSet indexSet];
            [indexes enumerateRangesInRange:theRange options:0 usingBlock:^(NSRange range, BOOL *stop) {
                // range exists in both indexes and theRange
                [indexesToRemove addIndexesInRange:range];
                [indexesToAdd removeIndexesInRange:range];
            }];
            [indexes removeIndexes:indexesToRemove];
            [indexes addIndexes:indexesToAdd];

            // In multipart windowed ranges, add connectors for the endpoint of all but the last
            // range. Each enumerated range is on its own line.
            if (outer.range.columnWindow.length &&
                !VT100GridCoordEquals(outerRange.end, outer.range.coordRange.end) &&
                theRange.length > 0) {
                [connectors addIndex:NSMaxRange(theRange)];
            }
        }];
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
        VT100GridCoordRange theRange = [value gridCoordRangeValue];
        NSUInteger endIndex = (theRange.start.x + theRange.start.y * width +
                               VT100GridCoordRangeLength(theRange, width));
        block(VT100GridWindowedRangeMake(theRange, 0, 0),
              &stop,
              ![connectors containsIndex:endIndex] && value != [sortedRanges lastObject]);
        if (stop) {
            break;
        }
    }
}

#pragma mark - Serialization

- (NSDictionary *)dictionaryValueWithYOffset:(int)yOffset {
    NSArray *subs = self.allSubSelections;
    subs = [subs mapWithBlock:^id(id anObject) {
        iTermSubSelection *sub = anObject;
        return [sub dictionaryValueWithYOffset:yOffset];
    }];
    return @{ kSelectionSubSelectionsKey: subs };
}

- (void)setFromDictionaryValue:(NSDictionary *)dict {
    [self clearSelection];
    NSArray<NSDictionary *> *subs = dict[kSelectionSubSelectionsKey];
    NSMutableArray<iTermSubSelection *> *subSelectionsToAdd = [NSMutableArray array];
    for (NSDictionary *subDict in subs) {
        iTermSubSelection *sub = [iTermSubSelection subSelectinWithDictionary:subDict];
        if (sub) {
            [subSelectionsToAdd addObject:sub];
        }
    }
    [self addSubSelections:subSelectionsToAdd];
}

@end


