//
//  iTermSelection.m
//  iTerm
//
//  Created by George Nachman on 2/10/14.
//
//

#import "iTermSelection.h"
#import "DebugLogging.h"

@implementation iTermSelection {
    VT100GridCoordRange _range;
    VT100GridCoordRange _initialRange;
    BOOL _live;
    BOOL _extend;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p range=%@ live=%d extend=%d>",
            [self class], self, VT100GridCoordRangeDescription(_range), _live, _extend];
}

- (void)flip {
    _range = VT100GridCoordRangeMake(_range.end.x,
                                     _range.end.y,
                                     _range.start.x,
                                     _range.start.y);
}

- (VT100GridCoordRange)unflippedRange {
    if ([self isFlipped]) {
        return VT100GridCoordRangeMake(_range.end.x, _range.end.y, _range.start.x, _range.start.y);
    } else {
        return _range;
    }
}

- (void)beginExtendingSelectionAt:(VT100GridCoord)coord {
    // enter an intermediate state where the next update doesn't look like we just reversed course
    DLog(@"Begin extending selection.");
    _live = YES;
    _extend = YES;
    
    if ([self isFlipped]) {
        // Make sure range is not flipped.
        [self flip];
    }
    
    VT100GridCoordRange range = [self rangeForCurrentModeAtCoord:coord
                                           includeParentheticals:YES];
    
    if (range.start.x != -1) {
        if (range.start.x == -1) {
            range = [_delegate selectionRangeForWordAt:coord];
        }
        if ([self containsCoord:coord]) {
            // New range is inside old range.
            int width = [self width];
            long long distanceToStart = VT100GridCoordDistance(_range.start,
                                                               range.start,
                                                               width);
            long long distanceToEnd = VT100GridCoordDistance(_range.end, range.end, width);
            if (distanceToEnd < distanceToStart) {
                _range.end = range.end;
                _initialRange = [self rangeForCurrentModeAtCoord:_range.start
                                           includeParentheticals:NO];
                ;
            } else {
                [self flip];
                _range.end = range.start;
                VT100GridCoord anchor = [_delegate selectionPredecessorOfCoord:_range.start];
                _initialRange = [self rangeForCurrentModeAtCoord:anchor
                                           includeParentheticals:NO];
            }
        } else {
            VT100GridCoordRange determinant = _initialRange;
            if ([self coord:determinant.start isEqualToCoord:determinant.end]) {
                determinant = [self unflippedRange];
            }
            if ([self coord:range.end isAfterCoord:determinant.end]) {
                _range.end = range.end;
                _initialRange = [self rangeForCurrentModeAtCoord:_range.start
                                           includeParentheticals:NO];
            }
            if ([self coord:range.start isBeforeCoord:determinant.start]) {
                [self flip];
                _range.end = range.start;
                _initialRange = [self rangeForCurrentModeAtCoord:_range.start
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
                    mode:(iTermSelectionMode)mode {
    DLog(@"Begin new selection. coord=%@, extend=%d", VT100GridCoordDescription(coord), extend);
    _live = YES;
    _extend = NO;
    _selectionMode = mode;
    _range = [self rangeForCurrentModeAtCoord:coord includeParentheticals:YES];
    _initialRange = _range;

    [self extendPastNulls];
    [_delegate selectionDidChange:self];
}

- (void)endLiveSelection {
    DLog(@"End live selection");
    if (_selectionMode == kiTermSelectionModeBox) {
        int left = MIN(_range.start.x, _range.end.x);
        int right = MAX(_range.start.x, _range.end.x);
        int top = MIN(_range.start.y, _range.end.y);
        int bottom = MAX(_range.start.y, _range.end.y);
        _range = VT100GridCoordRangeMake(left, top, right, bottom);
    } else if (self.isFlipped) {
        DLog(@"Unflip selection");
        [self flip];
    }
    if (_selectionMode == kiTermSelectionModeSmart) {
        // This allows extension to work more sanely.
        _initialRange = _range;
    }
    _extend = NO;
    _live = NO;
}

- (BOOL)extending {
    return _extend;
}

- (void)clearSelection {
    DLog(@"Clear selection");
    _range = VT100GridCoordRangeMake(-1, -1, -1, -1);
    [_delegate selectionDidChange:self];
}

- (VT100GridCoordRange)selectedRange {
    return _range;
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
    if (coord.y < 0) {
        coord.x = coord.y = 0;
    }
    VT100GridCoordRange range = [self rangeForCurrentModeAtCoord:coord includeParentheticals:NO];
    
    if (!_live) {
        [self beginSelectionAt:coord mode:self.selectionMode];
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
    NSLog(@"move selection endpoint to range=%@ selection=%@",
          VT100GridCoordRangeDescription(range), VT100GridCoordRangeDescription(_range));
    VT100GridCoordRange newRange = self.selectedRange;
    if ([self coord:_range.start isBeforeCoord:range.end]) {
        // The word you clicked on ends after the start of the existing range.
        if ([self isFlipped]) {
            // The range is flipped. This happens when you were selecting backwards and
            // turned around and started going forwards.
            //
            // end<---------selection--------->start
            //                                |...<-----------range----------->
            //                 <-initialRange->
            //            start<----------------newRange--------------------->end
            NSLog(@"1");
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
                NSLog(@"5");
                newRange.start = range.start;
            } else {
                NSLog(@"2");
                newRange.end = range.end;
            }
        }
    } else {
        if (![self isFlipped]) {
            // This happens when you were selecting forwards and turned around and started
            // going backwards.
            //                 start<-------------selection------------->end
            //    <----range---->...|
            //                      <-initialRange->
            // end<-----------newRange------------->start
            NSLog(@"3");
            newRange.start = _initialRange.end;
            newRange.end = range.start;
        } else {
            // end<-------------selection-------------->start
            //                         <---range--->...|
            //                      end<---newRange---->start
            NSLog(@"4");
            newRange.end = range.start;
        }
    }
    NSLog(@"  newrange=%@", VT100GridCoordRangeDescription(newRange));
    _range = newRange;
}

- (BOOL)hasSelection {
    return _range.start.x >= 0 && !VT100GridCoordEquals(_range.start, _range.end);
}

- (void)moveUpByLines:(int)numLines {
    _range.start.y -= numLines;
    _range.end.y -= numLines;
    
    if (_range.start.y < 0 || _range.end.y < 0) {
        [self clearSelection];
    }
}

- (BOOL)isFlipped {
    return VT100GridCoordOrder(_range.start, _range.end) == NSOrderedDescending;
}

- (BOOL)containsCoord:(VT100GridCoord)coord {
    if (![self hasSelection]) {
        return NO;
    }
    
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
    theCopy->_live = _live;
    theCopy->_extend = _extend;
    
    theCopy.delegate = _delegate;
    theCopy.selectionMode = _selectionMode;
    
    return theCopy;
}

- (void)extendPastNulls {
    if (_selectionMode == kiTermSelectionModeBox) {
        return;
    }
    if ([self hasSelection] && _live) {
        VT100GridCoordRange unflippedRange = [self unflippedRange];
        VT100GridRange nulls =
            [_delegate selectionRangeOfTerminalNullsOnLine:unflippedRange.start.y];
        
        // Fix the beginning of the range (start if unflipped, end if flipped)
        if (unflippedRange.start.x > nulls.location) {
            if ([self isFlipped]) {
                _range.end.x = nulls.location;
            } else {
                _range.start.x = nulls.location;
            }
        }
        
        // Fix the terminus of the range (end if unflipped, start if flipped)
        nulls = [_delegate selectionRangeOfTerminalNullsOnLine:unflippedRange.end.y];
        if (unflippedRange.end.x > nulls.location) {
            if ([self isFlipped]) {
                _range.start.x = nulls.location + nulls.length;
            } else {
                _range.end.x = nulls.location + nulls.length;
            }
        }
    }
}

@end
