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
#import "NSIndexSet+iTerm.h"
#import "NSObject+iTerm.h"
#import "ScreenChar.h"

static NSString *const kSelectionSubSelectionsKey = @"Sub selections";

static NSString *const kiTermSubSelectionRange = @"Range";
static NSString *const kiTermSubSelectionMode = @"Mode";

@implementation iTermSubSelection

+ (instancetype)subSelectionWithAbsRange:(VT100GridAbsWindowedRange)unsafeRange
                                    mode:(iTermSelectionMode)mode
                                   width:(int)width {
    iTermSubSelection *sub = [[[iTermSubSelection alloc] init] autorelease];
    VT100GridAbsWindowedRange range = VT100GridAbsWindowedRangeClampedToWidth(unsafeRange, width);
    sub.absRange = range;
    sub.selectionMode = mode;
    return sub;
}

+ (instancetype)subSelectionWithDictionary:(NSDictionary *)dict
                                     width:(int)width
                   totalScrollbackOverflow:(long long)totalScrollbackOverflow {
    VT100GridAbsWindowedRange range;
    range = VT100GridAbsWindowedRangeFromWindowedRange([dict[kiTermSubSelectionRange] gridWindowedRange],
                                                       totalScrollbackOverflow);
    return [self subSelectionWithAbsRange:range
                                     mode:[dict[kiTermSubSelectionMode] intValue]
                                    width:width];
}

- (NSDictionary *)dictionaryValueWithYOffset:(int)yOffset
                     totalScrollbackOverflow:(long long)totalScrollbackOverflow {
    VT100GridAbsWindowedRange absrange = _absRange;
    absrange.coordRange.start.y += yOffset;
    absrange.coordRange.end.y += yOffset;

    const VT100GridWindowedRange range = VT100GridWindowedRangeFromAbsWindowedRange(absrange,
                                                                                    totalScrollbackOverflow);
    return @{ kiTermSubSelectionRange: [NSDictionary dictionaryWithGridWindowedRange:range],
              kiTermSubSelectionMode: @(_selectionMode) };
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p range=%@ mode=%@>",
            [self class], self, VT100GridAbsWindowedRangeDescription(_absRange),
            [iTermSelection nameForMode:_selectionMode]];
}

- (BOOL)containsAbsCoord:(VT100GridAbsCoord)coord {
    const VT100GridAbsCoord start = VT100GridAbsCoordRangeMin(_absRange.coordRange);
    const VT100GridAbsCoord end = VT100GridAbsCoordRangeMax(_absRange.coordRange);

    BOOL contained = NO;
    if (_selectionMode == kiTermSelectionModeBox) {
        const int left = MIN(start.x, end.x);
        const int right = MAX(start.x, end.x);
        const long long top = MIN(start.y, end.y);
        const long long bottom = MAX(start.y, end.y);
        contained = (coord.x >= left && coord.x < right && coord.y >= top && coord.y <= bottom);
    } else {
        long long w = MAX(MAX(MAX(1, coord.x), start.x), end.x) + 1;
        long long coordPos = (long long)coord.y * w + coord.x;
        long long minPos = (long long)start.y * w + start.x;
        long long maxPos = (long long)end.y * w + end.x;

        contained = coordPos >= minPos && coordPos < maxPos;
    }
    if (_absRange.columnWindow.length) {
        contained = contained && VT100GridRangeContains(_absRange.columnWindow, coord.x);
    }
    return contained;
}

- (instancetype)copyWithZone:(NSZone *)zone {
    iTermSubSelection *theCopy = [[iTermSubSelection alloc] init];
    theCopy.absRange = self.absRange;
    theCopy.selectionMode = self.selectionMode;
    theCopy.connected = self.connected;

    return theCopy;
}

- (NSArray *)nonwindowedComponentsWithWidth:(int)width {
    if (self.selectionMode == kiTermSelectionModeBox ||
        self.absRange.columnWindow.length <= 0) {
        return @[ self ];
    }
    NSMutableArray *result = [NSMutableArray array];
    [[self class] enumerateAbsoluteRangesInAbsWindowedRange:self.absRange
                                                      block:^(VT100GridAbsCoordRange subrange) {
        iTermSubSelection *sub =
            [iTermSubSelection subSelectionWithAbsRange:VT100GridAbsWindowedRangeMake(subrange, 0, 0)
                                                   mode:_selectionMode
                                                  width:width];
        sub.connected = YES;
        [result addObject:sub];
    }];
    [[result lastObject] setConnected:NO];
    return result;
}

+ (void)enumerateAbsoluteRangesInAbsWindowedRange:(VT100GridAbsWindowedRange)absWindowedRange
                                            block:(void (^)(VT100GridAbsCoordRange))block {
    if (absWindowedRange.columnWindow.length) {
        const int right = absWindowedRange.columnWindow.location + absWindowedRange.columnWindow.length;
        int startX = VT100GridAbsWindowedRangeStart(absWindowedRange).x;
        for (long long y = absWindowedRange.coordRange.start.y; y < absWindowedRange.coordRange.end.y; y++) {
            block(VT100GridAbsCoordRangeMake(startX, y, right, y));
            startX = absWindowedRange.columnWindow.location;
        }
        block(VT100GridAbsCoordRangeMake(startX,
                                         absWindowedRange.coordRange.end.y,
                                         VT100GridAbsWindowedRangeEnd(absWindowedRange).x,
                                         absWindowedRange.coordRange.end.y));
    } else {
        block(absWindowedRange.coordRange);
    }
}

- (BOOL)isEqual:(id)object {
    iTermSubSelection *other = [iTermSubSelection castFrom:object];
    if (!other) {
        return NO;
    }
    return (VT100GridAbsWindowsRangeEqualsAbsWindowedRange(self.absRange, other.absRange) &&
            self.selectionMode == other.selectionMode &&
            self.connected == other.connected);
}

- (int)approximateNumberOfLines {
    return self.absRange.coordRange.end.y - self.absRange.coordRange.start.y + 1;
}

@end

@implementation iTermSelection {
    VT100GridAbsWindowedRange _absRange;
    VT100GridAbsWindowedRange _initialAbsRange;
    BOOL _live;
    BOOL _extend;
    NSMutableArray<iTermSubSelection *> *_subSelections;
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
            [self class], self, VT100GridAbsWindowedRangeDescription(_absRange),
            VT100GridAbsCoordRangeDescription(_initialAbsRange.coordRange), _live, _extend, _resumable,
            [[self class] nameForMode:_selectionMode], _subSelections, _delegate];
}

- (void)flip {
    _absRange.coordRange = VT100GridAbsCoordRangeMake(_absRange.coordRange.end.x,
                                                      _absRange.coordRange.end.y,
                                                      _absRange.coordRange.start.x,
                                                      _absRange.coordRange.start.y);
}

- (VT100GridAbsWindowedRange)unflippedLiveAbsRange {
    return [self unflippedAbsRangeForAbsRange:_absRange mode:_selectionMode];
}

- (void)beginExtendingSelectionAt:(VT100GridAbsCoord)absCoord {
    if (_live) {
        return;
    }
    if ([_subSelections count] == 0) {
        [self beginSelectionAtAbsCoord:absCoord
                                  mode:_selectionMode
                                resume:NO
                                append:NO];
        return;
    } else {
        iTermSubSelection *sub = [_subSelections lastObject];
        _absRange = sub.absRange;
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

    VT100GridAbsWindowedRange absRange = [self absRangeForCurrentModeAtAbsCoord:absCoord
                                                          includeParentheticals:YES
                                                             needAccurateWindow:NO];
    // TODO support range.
    if (absRange.coordRange.start.x != -1) {
        if (absRange.coordRange.start.x == -1) {
            absRange = [_delegate selectionAbsRangeForWordAt:absCoord];
        }
        if ([self absCoord:absCoord isInAbsRange:_absRange]) {
            // The click point is inside old live range.
            int width = [self width];
            long long distanceToStart = VT100GridAbsCoordDistance(_absRange.coordRange.start,
                                                                  absRange.coordRange.start,
                                                                  width);
            long long distanceToEnd = VT100GridAbsCoordDistance(_absRange.coordRange.end,
                                                                absRange.coordRange.end,
                                                                width);
            if (distanceToEnd < distanceToStart) {
                // Move the end point
                _absRange.coordRange.end = absRange.coordRange.end;
                _initialAbsRange = [self absRangeForCurrentModeAtAbsCoord:_absRange.coordRange.start
                                                    includeParentheticals:NO
                                                       needAccurateWindow:NO];
                ;
            } else {
                // Flip and move what was the start point
                [self flip];
                _absRange.coordRange.end = absRange.coordRange.start;
                const VT100GridAbsCoord anchor =
                    [_delegate selectionPredecessorOfAbsCoord:_absRange.coordRange.start];
                _initialAbsRange = [self absRangeForCurrentModeAtAbsCoord:anchor
                                                    includeParentheticals:NO
                                                       needAccurateWindow:NO];
            }
        } else {
            // The click point is outside the live range
            VT100GridAbsCoordRange determinant = _initialAbsRange.coordRange;
            if ([self absCoord:determinant.start isEqualToAbsCoord:determinant.end]) {
                // The initial range was empty, so use the live selection range to decide whether to
                // move the start or end point of the live range.
                determinant = [self unflippedLiveAbsRange].coordRange;
            }
            if ([self absCoord:absRange.coordRange.end isAfterAbsCoord:determinant.end]) {
                _absRange.coordRange.end = absRange.coordRange.end;
                _initialAbsRange = [self absRangeForCurrentModeAtAbsCoord:_absRange.coordRange.start
                                                    includeParentheticals:NO
                                                       needAccurateWindow:NO];
            }
            if ([self absCoord:absRange.coordRange.start isBeforeAbsCoord:determinant.start]) {
                [self flip];
                _absRange.coordRange.end = absRange.coordRange.start;
                VT100GridAbsCoord lastSelectedCharAbsCoord =
                    [_delegate selectionPredecessorOfAbsCoord:_absRange.coordRange.start];
                _initialAbsRange = [self absRangeForCurrentModeAtAbsCoord:lastSelectedCharAbsCoord
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
- (VT100GridAbsWindowedRange)absRangeForCurrentModeAtAbsCoord:(VT100GridAbsCoord)rawAbsCoord
                                        includeParentheticals:(BOOL)includeParentheticals
                                           needAccurateWindow:(BOOL)needAccurateWindow {
     VT100GridAbsCoord absCoord = rawAbsCoord;
     if (_absRange.columnWindow.length > 0) {
         absCoord.x = MAX(_absRange.columnWindow.location,
                          MIN(_absRange.columnWindow.location + _absRange.columnWindow.length - 1,
                              absCoord.x));
     }
     VT100GridAbsWindowedRange absWindowedRange =
        VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0);
     switch (_selectionMode) {
         case kiTermSelectionModeWord:
             if (includeParentheticals) {
                 absWindowedRange = [_delegate selectionAbsRangeForParentheticalAt:absCoord];
             }
             if (absWindowedRange.coordRange.start.x == -1) {
                 absWindowedRange = [_delegate selectionAbsRangeForWordAt:absCoord];
             }
             break;

         case kiTermSelectionModeWholeLine:
             absWindowedRange = [_delegate selectionAbsRangeForWrappedLineAt:absCoord];
             break;

         case kiTermSelectionModeSmart:
             absWindowedRange = [_delegate selectionAbsRangeForSmartSelectionAt:absCoord];
             break;

         case kiTermSelectionModeLine:
             absWindowedRange = [_delegate selectionAbsRangeForLineAt:absCoord];
             break;

         case kiTermSelectionModeCharacter:
             if (_absRange.columnWindow.length > 0) {
                 absCoord.x = MAX(_absRange.columnWindow.location,
                                  MIN(_absRange.columnWindow.location + _absRange.columnWindow.length,
                                      rawAbsCoord.x));
             }
         case kiTermSelectionModeBox:
             if (needAccurateWindow) {
                 absWindowedRange = [_delegate selectionAbsRangeForLineAt:absCoord];
             } else {
                 absWindowedRange = _absRange;
             }
             absWindowedRange.coordRange = VT100GridAbsCoordRangeMake(absCoord.x, absCoord.y, absCoord.x, absCoord.y);
             break;
     }
     return absWindowedRange;
 }

- (void)beginSelectionAtAbsCoord:(VT100GridAbsCoord)absCoord
                            mode:(iTermSelectionMode)mode
                          resume:(BOOL)resume
                          append:(BOOL)append {
    if (_live) {
        return;
    }
    const long long totalScrollbackOverflow = _delegate.selectionTotalScrollbackOverflow;
    if (absCoord.y < totalScrollbackOverflow) {
        absCoord.x = 0;
        absCoord.y = totalScrollbackOverflow;
    }
    if (_resumable && resume && [_subSelections count]) {
        _absRange = [self lastAbsRange];
        [_subSelections removeLastObject];
        // Preserve existing value of appending flag.
    } else {
        _appending = append;
    }

    if (!_appending) {
        [_subSelections removeAllObjects];
    }
    DLog(@"Begin new selection. coord=%@, extend=%d", VT100GridAbsCoordDescription(absCoord), extend);
    _live = YES;
    _extend = NO;
    _haveClearedColumnWindow = NO;
    _selectionMode = mode;
    _absRange = [self absRangeForCurrentModeAtAbsCoord:absCoord
                                 includeParentheticals:YES
                                    needAccurateWindow:YES];
    _initialAbsRange = _absRange;

    DLog(@"Begin selection, range=%@", VT100GridAbsWindowedRangeDescription(_absRange));
    [self extendPastNulls];
    [_delegate selectionDidChange:[[self retain] autorelease]];
}

- (void)endLiveSelection {
    [self endLiveSelectionWithSideEffects:YES];
}

- (void)endLiveSelectionWithSideEffects:(BOOL)sideEffects {
    if (!_live) {
        return;
    }
    DLog(@"End live selection");
    if (_selectionMode == kiTermSelectionModeBox) {
        const int left = MIN(_absRange.coordRange.start.x, _absRange.coordRange.end.x);
        const int right = MAX(_absRange.coordRange.start.x, _absRange.coordRange.end.x);
        const long long top = MIN(_absRange.coordRange.start.y, _absRange.coordRange.end.y);
        const long long bottom = MAX(_absRange.coordRange.start.y, _absRange.coordRange.end.y);
        _absRange = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(left, top, right, bottom),
                                                  0, 0);
        for (long long i = top; i <= bottom; i++) {
            VT100GridAbsWindowedRange theRange =
                VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(left, i, right, i), 0, 0);
            theRange = [self absRangeByExtendingRangePastNulls:theRange];
            iTermSubSelection *sub =
                [iTermSubSelection subSelectionWithAbsRange:theRange
                                                       mode:kiTermSelectionModeCharacter
                                                      width:self.width];
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
            _initialAbsRange = _absRange;
        }
        if ([self haveLiveSelection]) {
            iTermSubSelection *sub = [[[iTermSubSelection alloc] init] autorelease];
            sub.absRange = _absRange;
            sub.selectionMode = _selectionMode;
            [_subSelections addObject:sub];
            _resumable = YES;
        } else {
            _resumable = NO;
        }
    }
    _absRange = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0);
    _extend = NO;
    _live = NO;

    if (sideEffects) {
        [_delegate selectionDidChange:[[self retain] autorelease]];
        [_delegate liveSelectionDidEnd];
    }
}

- (void)clearColumnWindowForLiveSelection {
    if (!self.haveLiveSelection) {
        return;
    }
    const int width = [self width];
    const VT100GridRange newRange = VT100GridRangeMake(0, width);
    if (VT100GridRangeEqualsRange(_initialAbsRange.columnWindow, newRange)) {
        return;
    }
    _haveClearedColumnWindow = YES;
    _initialAbsRange.columnWindow = newRange;
    _absRange.columnWindow = newRange;
    switch (_selectionMode) {
        case kiTermSelectionModeLine:
        case kiTermSelectionModeWholeLine:
            _initialAbsRange.coordRange.start.x = 0;
            _initialAbsRange.coordRange.end.x = width;
            if (_absRange.coordRange.end.y > _absRange.coordRange.start.y) {
                _absRange.coordRange.start.x = 0;
                _absRange.coordRange.end.x = width;
            } else {
                _absRange.coordRange.end.x = 0;
                _absRange.coordRange.start.x = width;
            }
            break;

        case kiTermSelectionModeCharacter:
        case kiTermSelectionModeWord:
        case kiTermSelectionModeSmart:
        case kiTermSelectionModeBox:
            break;
    }
    [_delegate selectionDidChange:[[self retain] autorelease]];
}

- (BOOL)haveLiveSelection {
    return (_live &&
            _absRange.coordRange.start.x != -1 &&
            VT100GridAbsCoordRangeLength(_absRange.coordRange, [self width]) > 0);
}

- (BOOL)extending {
    return _extend;
}

- (void)clearSelection {
    if (self.hasSelection) {
        DLog(@"Clear selection");
        _absRange = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0);
        [_subSelections removeAllObjects];
        [_delegate selectionDidChange:[[self retain] autorelease]];
    }
}

- (VT100GridAbsWindowedRange)liveRange {
    return _absRange;
}

- (BOOL)absCoord:(VT100GridAbsCoord)absCoord isInAbsRange:(VT100GridAbsWindowedRange)absRange {
    iTermSubSelection *temp = [iTermSubSelection subSelectionWithAbsRange:absRange
                                                                     mode:_selectionMode
                                                                    width:self.width];
    return [temp containsAbsCoord:absCoord];
}

- (BOOL)absCoord:(VT100GridAbsCoord)a isBeforeAbsCoord:(VT100GridAbsCoord)b {
    return VT100GridAbsCoordOrder(a, b) == NSOrderedAscending;
}

- (BOOL)absCoord:(VT100GridAbsCoord)a isAfterAbsCoord:(VT100GridAbsCoord)b {
    return VT100GridAbsCoordOrder(a, b) == NSOrderedDescending;
}

- (BOOL)absCoord:(VT100GridAbsCoord)a isEqualToAbsCoord:(VT100GridAbsCoord)b {
    return VT100GridAbsCoordOrder(a, b) == NSOrderedSame;
}

- (BOOL)moveSelectionEndpointTo:(VT100GridAbsCoord)coord {
    DLog(@"Move selection to %@", VT100GridAbsCoordDescription(coord));
    const long long totalScrollbackOverflow = [self.delegate selectionTotalScrollbackOverflow];
    if (coord.y < totalScrollbackOverflow) {
        coord.x = 0; coord.y = totalScrollbackOverflow;
    }
    NSArray<iTermSubSelection *> *subselectionsBefore = [[self.allSubSelections copy] autorelease] ?: @[];
    VT100GridAbsWindowedRange range = [self absRangeForCurrentModeAtAbsCoord:coord
                                                    includeParentheticals:NO
                                                       needAccurateWindow:NO];
    if (range.coordRange.start.x < 0) {
        return NO;
    }
    const BOOL startLiveSelection = !_live;
    if (startLiveSelection) {
        [self beginSelectionAtAbsCoord:coord
                                  mode:self.selectionMode
                                resume:NO
                                append:NO];
    }
    switch (_selectionMode) {
        case kiTermSelectionModeBox:
        case kiTermSelectionModeCharacter:
            _absRange.coordRange.end = coord;
            break;

        case kiTermSelectionModeLine:
        case kiTermSelectionModeSmart:
        case kiTermSelectionModeWholeLine:
        case kiTermSelectionModeWord:
            [self moveSelectionEndpointToAbsRange:range];
            break;
    }

    _extend = YES;
    [self extendPastNulls];
    [_delegate selectionDidChange:[[self retain] autorelease]];
    if (startLiveSelection) {
        return YES;
    }
    return ![subselectionsBefore isEqualToArray:self.allSubSelections];
}

- (void)moveSelectionEndpointToAbsRange:(VT100GridAbsWindowedRange)range {
    DLog(@"move selection endpoint to range=%@ selection=%@ initial=%@",
         VT100GridAbsWindowedRangeDescription(range),
         VT100GridAbsWindowedRangeDescription(_absRange),
         VT100GridAbsWindowedRangeDescription(_initialAbsRange));
    VT100GridAbsWindowedRange newRange = _absRange;
    if ([self absCoord:_absRange.coordRange.start isBeforeAbsCoord:range.coordRange.end]) {
        // The word you clicked on ends after the start of the existing range.
        if ([self liveRangeIsFlipped]) {
            // The range is flipped. This happens when you were selecting backwards and
            // turned around and started going forwards.
            //
            // end<---------selection--------->start
            //                                |...<-----------range----------->
            //                 <-initialRange->
            //            start<----------------newRange--------------------->end
            newRange.coordRange.start = _initialAbsRange.coordRange.start;
            newRange.coordRange.end = range.coordRange.end;
        } else {
            // start<---------selection---------->end
            //      |<<<<<<<<<<<<<<<|
            //       ...<---range--->
            // start<---newRange---->end
            if ([self absCoord:range.coordRange.start isBeforeAbsCoord:_absRange.coordRange.start]) {
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
            newRange.coordRange.start = _initialAbsRange.coordRange.end;
            newRange.coordRange.end = range.coordRange.start;
        } else {
            // end<-------------selection-------------->start
            //                         <---range--->...|
            //                      end<---newRange---->start
            newRange.coordRange.end = range.coordRange.start;
        }
    }
    DLog(@"  newrange=%@", VT100GridAbsWindowedRangeDescription(newRange));
    _absRange = newRange;
}

- (BOOL)hasSelection {
    return [_subSelections count] > 0 || [self haveLiveSelection];
}

- (void)scrollbackOverflowDidChange {
    BOOL notifyDelegateOfChange = _subSelections.count > 0 || [self haveLiveSelection];
    const long long totalScrollbackOverflow = [self.delegate selectionTotalScrollbackOverflow];
    if ([self haveLiveSelection]) {
        if (_absRange.coordRange.start.y < totalScrollbackOverflow) {
           _absRange.coordRange.start.x = 0;
           _absRange.coordRange.start.y = totalScrollbackOverflow;
        }
       if (_absRange.coordRange.end.y < totalScrollbackOverflow) {
          [self clearSelection];
        }
    }

    NSMutableArray<iTermSubSelection *> *subsToRemove = [NSMutableArray array];
    for (iTermSubSelection *sub in _subSelections) {
        VT100GridAbsWindowedRange range = sub.absRange;
        if (range.coordRange.start.y < totalScrollbackOverflow) {
            range.coordRange.start.x = 0;
            range.coordRange.start.y = totalScrollbackOverflow;
        }
        sub.absRange = range;
        if (range.coordRange.end.y < totalScrollbackOverflow) {
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

- (BOOL)absRangeIsFlipped:(VT100GridAbsWindowedRange)range {
    return VT100GridAbsCoordOrder(range.coordRange.start, range.coordRange.end) == NSOrderedDescending;
}

- (BOOL)liveRangeIsFlipped {
    return [self absRangeIsFlipped:_absRange];
}

- (BOOL)containsAbsCoord:(VT100GridAbsCoord)absCoord {
    if (![self hasSelection]) {
        return NO;
    }
    BOOL contained = NO;
    for (iTermSubSelection *sub in [self allSubSelections]) {
        if ([sub containsAbsCoord:absCoord]) {
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
    [self enumerateSelectedAbsoluteRanges:^(VT100GridAbsWindowedRange range, BOOL *stop, BOOL eol) {
        length += VT100GridAbsWindowedRangeLength(range, width);
    }];
    return length;
}

- (void)setSelectedAbsRange:(VT100GridAbsWindowedRange)selectedRange {
    _absRange = selectedRange;
    [_delegate selectionDidChange:[[self retain] autorelease]];
}

- (id)copyWithZone:(NSZone *)zone {
    iTermSelection *theCopy = [[iTermSelection alloc] init];
    theCopy->_absRange = _absRange;
    theCopy->_initialAbsRange = _initialAbsRange;
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

- (VT100GridAbsWindowedRange)unflippedAbsRangeForAbsRange:(VT100GridAbsWindowedRange)absRange
                                                     mode:(iTermSelectionMode)mode {
    if (mode == kiTermSelectionModeBox) {
        // For box selection, we always want the start to be the top left and
        // end to be the bottom right.
        absRange.coordRange = VT100GridAbsCoordRangeMake(MIN(absRange.coordRange.start.x,
                                                             absRange.coordRange.end.x),
                                                         MIN(absRange.coordRange.start.y,
                                                             absRange.coordRange.end.y),
                                                         MAX(absRange.coordRange.start.x,
                                                             absRange.coordRange.end.x),
                                                         MAX(absRange.coordRange.start.y,
                                                             absRange.coordRange.end.y));
    } else if ([self absCoord:absRange.coordRange.end isBeforeAbsCoord:absRange.coordRange.start]) {
        // For all other kinds of selection, the coordinate pair for each of
        // start and end must remain together, but start should precede end in
        // reading order.
        absRange.coordRange = VT100GridAbsCoordRangeMake(absRange.coordRange.end.x,
                                                         absRange.coordRange.end.y,
                                                         absRange.coordRange.start.x,
                                                         absRange.coordRange.start.y);
    }
    return absRange;
}

- (VT100GridAbsWindowedRange)absRangeByExtendingRangePastNulls:(VT100GridAbsWindowedRange)range {
    const long long totalScrollbackOverflow = [self.delegate selectionTotalScrollbackOverflow];
    if (range.coordRange.start.y < totalScrollbackOverflow) {
        range.coordRange.start.y = totalScrollbackOverflow;
    }
    if (range.coordRange.end.y < totalScrollbackOverflow) {
        range.coordRange.end.y = totalScrollbackOverflow;
    }
    VT100GridAbsWindowedRange unflippedRange = [self unflippedAbsRangeForAbsRange:range
                                                                             mode:_selectionMode];
    VT100GridRange nulls =
        [_delegate selectionRangeOfTerminalNullsOnAbsoluteLine:unflippedRange.coordRange.start.y];

    // Fix the beginning of the range (start if unflipped, end if flipped)
    if (unflippedRange.coordRange.start.x > nulls.location) {
        if ([self absRangeIsFlipped:range]) {
            range.coordRange.end.x = nulls.location;
        } else {
            range.coordRange.start.x = nulls.location;
        }
    }

    // Fix the terminus of the range (end if unflipped, start if flipped)
    nulls = [_delegate selectionRangeOfTerminalNullsOnAbsoluteLine:unflippedRange.coordRange.end.y];
    if (unflippedRange.coordRange.end.x > nulls.location) {
        if ([self absRangeIsFlipped:range]) {
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
        _absRange = [self absRangeByExtendingRangePastNulls:_absRange];
    }
}

- (NSArray<iTermSubSelection *> *)allSubSelections {
    if ([self haveLiveSelection]) {
        NSMutableArray *subs = [NSMutableArray array];
        [subs addObjectsFromArray:_subSelections];
        iTermSubSelection *temp = [iTermSubSelection subSelectionWithAbsRange:[self unflippedLiveAbsRange]
                                                                         mode:_selectionMode
                                                                        width:self.width];
        [subs addObject:temp];
        return subs;
    } else {
        return _subSelections;
    }
}

- (VT100GridAbsCoordRange)spanningAbsRange {
    VT100GridAbsCoordRange span = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
    for (iTermSubSelection *sub in [self allSubSelections]) {
        VT100GridAbsCoordRange range = sub.absRange.coordRange;
        if (span.start.x == -1) {
            span.start = range.start;
            span.end = range.end;
        } else {
            if ([self absCoord:range.start isBeforeAbsCoord:span.start]) {
                span.start = range.start;
            }
            if ([self absCoord:range.end isAfterAbsCoord:span.end]) {
                span.end = range.end;
            }
        }
    }
    return span;
}

- (VT100GridAbsWindowedRange)lastAbsRange {
    VT100GridAbsWindowedRange best =
        VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0);
    for (iTermSubSelection *sub in [self allSubSelections]) {
        VT100GridAbsWindowedRange absRange = sub.absRange;
        if (best.coordRange.start.x < 0 ||
            [self absCoord:absRange.coordRange.end isAfterAbsCoord:best.coordRange.end]) {
            best = absRange;
        }
    }
    return best;
}

- (VT100GridAbsWindowedRange)firstAbsRange {
    VT100GridAbsWindowedRange best =
        VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0);
    for (iTermSubSelection *sub in [self allSubSelections]) {
        const VT100GridAbsWindowedRange range = sub.absRange;
        if (best.coordRange.start.x < 0 ||
            [self absCoord:range.coordRange.start isAfterAbsCoord:best.coordRange.start]) {
            best = range;
        }
    }
    return best;
}

- (void)setFirstAbsRange:(VT100GridAbsWindowedRange)firstRange mode:(iTermSelectionMode)mode {
    firstRange = [self absRangeByExtendingRangePastNulls:firstRange];
    if ([_subSelections count] == 0) {
        if (_live) {
            _absRange = firstRange;
            _selectionMode = mode;
        }
    } else {
        [_subSelections replaceObjectAtIndex:0
                                  withObject:[iTermSubSelection subSelectionWithAbsRange:firstRange
                                                                                    mode:mode
                                                                                   width:self.width]];
    }
    [_delegate selectionDidChange:[[self retain] autorelease]];
}

- (void)setLastAbsRange:(VT100GridAbsWindowedRange)lastRange mode:(iTermSelectionMode)mode {
    lastRange = [self absRangeByExtendingRangePastNulls:lastRange];
    if (_live) {
        _absRange = lastRange;
        _selectionMode = mode;
    } else if ([_subSelections count]) {
        [_subSelections removeLastObject];
        [_subSelections addObject:[iTermSubSelection subSelectionWithAbsRange:lastRange
                                                                         mode:mode
                                                                        width:self.width]];
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
            sub.absRange = [self absRangeByExtendingRangePastNulls:sub.absRange];
        }
        [_subSelections addObject:sub];
    }
    [_delegate selectionDidChange:[[self retain] autorelease]];
}

- (void)removeWindowsWithWidth:(int)width {
    _initialAbsRange = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, 0, 0, 0), 0, 0);
    if (_live) {
        [self endLiveSelection];
    }
    NSMutableArray<iTermSubSelection *> *newSubs = [NSMutableArray array];
    for (iTermSubSelection *sub in _subSelections) {
        if (sub.absRange.columnWindow.location == 0 &&
            sub.absRange.columnWindow.length == width) {
            [newSubs addObject:sub];
        } else {
            // There is a nontrivial window
            for (iTermSubSelection *subsub in [sub nonwindowedComponentsWithWidth:self.width]) {
                [newSubs addObject:subsub];
            }
        }
    }
    [_subSelections autorelease];
    _subSelections = [newSubs retain];
}

static NSRange iTermMakeRange(NSInteger location, NSInteger length) {
    if (location < 0) {
        return iTermMakeRange(0, length + location);
    }
    if (location > NSNotFound) {
        return NSMakeRange(NSNotFound, 0);
    }
    return NSMakeRange(location, MAX(0, length));
}

- (NSRange)rangeOfIndexesInAbsRange:(VT100GridAbsWindowedRange)range
                     onAbsoluteLine:(long long)line
                               mode:(iTermSelectionMode)mode {
    if (mode == kiTermSelectionModeBox) {
        if (range.coordRange.start.y <= line && range.coordRange.end.y >= line) {
            return iTermMakeRange(range.coordRange.start.x,
                                  range.coordRange.end.x - range.coordRange.start.x);
        } else {
            return iTermMakeRange(0, 0);
        }
    }
    if (range.coordRange.start.y < line && range.coordRange.end.y > line) {
        if (range.columnWindow.length) {
            return iTermMakeRange(range.columnWindow.location,
                                  range.columnWindow.length);
        } else {
            return iTermMakeRange(0, [self width]);
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
                return iTermMakeRange(range.coordRange.start.x,
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
                return iTermMakeRange(range.coordRange.start.x,
                                      [self width] - range.coordRange.start.x);
            }
        }
    }
    if (range.coordRange.end.y == line) {
        if (range.columnWindow.length) {
            int limit = VT100GridRangeMax(range.columnWindow) + 1;
            return iTermMakeRange(range.columnWindow.location,
                                  MIN(limit, range.coordRange.end.x) - range.columnWindow.location);
        } else {
            return iTermMakeRange(0, range.coordRange.end.x);
        }
    }
    return iTermMakeRange(0, 0);
}

- (NSIndexSet *)selectedIndexesOnAbsoluteLine:(long long)line {
    const NSInteger numberOfSubSelections = _subSelections.count;
    if (!_live && numberOfSubSelections == 0) {
        // Fast path
        return [NSIndexSet indexSet];
    }
    if (!_live && numberOfSubSelections == 1) {
        // Fast path
        iTermSubSelection *sub = _subSelections[0];
        NSRange theRange = [self rangeOfIndexesInAbsRange:sub.absRange
                                           onAbsoluteLine:line
                                                     mode:sub.selectionMode];
        return [NSIndexSet it_indexSetWithIndexesInRange:theRange];
    }
    if (_live && numberOfSubSelections == 0) {
        // Fast path
        NSRange theRange = [self rangeOfIndexesInAbsRange:[self unflippedLiveAbsRange]
                                           onAbsoluteLine:line
                                                     mode:_selectionMode];
        return [NSIndexSet it_indexSetWithIndexesInRange:theRange];
    }

    // Slow path.
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (iTermSubSelection *sub in [self allSubSelections]) {
        VT100GridAbsWindowedRange range = sub.absRange;
        NSRange theRange = [self rangeOfIndexesInAbsRange:range
                                           onAbsoluteLine:line
                                                     mode:sub.selectionMode];

        // Any values in theRange that intersect indexes should be removed from indexes.
        // And values in theSet that don't intersect indexes should be added to indexes.
        NSMutableIndexSet *indexesToAdd = [NSMutableIndexSet it_indexSetWithIndexesInRange:theRange];
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
- (NSIndexSet *)selectedIndexesIncludingTabFillersInAbsoluteLine:(long long)y {
    NSIndexSet *basicIndexes = [self selectedIndexesOnAbsoluteLine:y];
    if (!basicIndexes.count) {
        return basicIndexes;
    }

    // Add in tab fillers preceding already-selected tabs.
    NSMutableIndexSet *indexes = [[basicIndexes mutableCopy] autorelease];

    NSRange range;
    if (_absRange.columnWindow.length > 0) {
        range = NSMakeRange(_absRange.columnWindow.location, _absRange.columnWindow.length);
    } else {
        range = NSMakeRange(0, [_delegate selectionViewportWidth]);
    }
    NSIndexSet *tabs = [_delegate selectionIndexesOnAbsoluteLine:y
                                             containingCharacter:'\t'
                                                         inRange:range];
    NSIndexSet *tabFillers =
        [_delegate selectionIndexesOnAbsoluteLine:y
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

- (void)enumerateSelectedAbsoluteRanges:(void (^ NS_NOESCAPE)(VT100GridAbsWindowedRange, BOOL *, BOOL))block {
    if (_live) {
        // Live ranges can have box subs, which is just a pain to deal with, so make a copy,
        // end live selection in the copy (which converts boxes to individual selections), and
        // then try again on the copy.
        iTermSelection *temp = [[self copy] autorelease];
        // Side effects could cause an infinite recursion to here. The delegate shouldn't know that
        // we're using a copy for this.
        [temp endLiveSelectionWithSideEffects:NO];
        [temp enumerateSelectedAbsoluteRanges:block];
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
        block(sub.absRange, &stop, NO);
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
            const long long thePosition = outer.absRange.coordRange.end.x + outer.absRange.coordRange.end.y * width;
            [connectors addIndex:thePosition];
        }
        __block NSRange theRange = NSMakeRange(0, 0);
        [iTermSubSelection enumerateAbsoluteRangesInAbsWindowedRange:outer.absRange
                                                               block:^(VT100GridAbsCoordRange outerRange) {
            theRange = NSMakeRange(outerRange.start.x + outerRange.start.y * width,
                                   VT100GridAbsCoordRangeLength(outerRange, width));

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
            if (outer.absRange.columnWindow.length &&
                !VT100GridAbsCoordEquals(outerRange.end, outer.absRange.coordRange.end) &&
                theRange.length > 0) {
                [connectors addIndex:NSMaxRange(theRange)];
            }
        }];
    }

    // enumerateRangesUsingBlock doesn't guarantee the ranges come in order, so put them in an array
    // and then sort it.
    NSMutableArray<NSValue *> *allRanges = [NSMutableArray array];
    [indexes enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        VT100GridAbsCoordRange coordRange =
            VT100GridAbsCoordRangeMake(range.location % width,
                                       range.location / width,
                                       (range.location + range.length) % width,
                                       (range.location + range.length) / width);
        [allRanges addObject:[NSValue valueWithGridAbsCoordRange:coordRange]];
    }];

    NSArray<NSValue *> *sortedRanges =
        [allRanges sortedArrayUsingSelector:@selector(compareGridAbsCoordRangeStart:)];
    for (NSValue *value in sortedRanges) {
        BOOL stop = NO;
        const VT100GridAbsCoordRange theRange = [value gridAbsCoordRangeValue];
        NSUInteger endIndex = (theRange.start.x + theRange.start.y * width +
                               VT100GridAbsCoordRangeLength(theRange, width));
        block(VT100GridAbsWindowedRangeMake(theRange, 0, 0),
              &stop,
              ![connectors containsIndex:endIndex] && value != [sortedRanges lastObject]);
        if (stop) {
            break;
        }
    }
}

- (int)approximateNumberOfLines {
    __block int sum = 0;
    [_subSelections enumerateObjectsUsingBlock:^(iTermSubSelection * _Nonnull sub, NSUInteger idx, BOOL * _Nonnull stop) {
        sum += sub.approximateNumberOfLines;
    }];
    return sum;
}

#pragma mark - Serialization

- (NSDictionary *)dictionaryValueWithYOffset:(int)yOffset
                     totalScrollbackOverflow:(long long)totalScrollbackOverflow {
    NSArray *subs = self.allSubSelections;
    subs = [subs mapWithBlock:^id(id anObject) {
        iTermSubSelection *sub = anObject;
        return [sub dictionaryValueWithYOffset:yOffset
                       totalScrollbackOverflow:totalScrollbackOverflow];
    }];
    return @{ kSelectionSubSelectionsKey: subs };
}

- (void)setFromDictionaryValue:(NSDictionary *)dict
                         width:(int)width
       totalScrollbackOverflow:(long long)totalScrollbackOverflow {
    [self clearSelection];
    NSArray<NSDictionary *> *subs = dict[kSelectionSubSelectionsKey];
    NSMutableArray<iTermSubSelection *> *subSelectionsToAdd = [NSMutableArray array];
    for (NSDictionary *subDict in subs) {
        iTermSubSelection *sub = [iTermSubSelection subSelectionWithDictionary:subDict
                                                                         width:width
                                                       totalScrollbackOverflow:totalScrollbackOverflow];
        if (sub) {
            [subSelectionsToAdd addObject:sub];
        }
    }
    [self addSubSelections:subSelectionsToAdd];
}

@end


