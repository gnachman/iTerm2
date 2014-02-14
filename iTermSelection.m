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
    BOOL _live;
    BOOL _extend;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p range=%@ live=%d extend=%d>",
            [self class], self, VT100GridCoordRangeDescription(_range), _live, _extend];
}

- (void)beginLiveSelectionAt:(VT100GridCoord)coord
                      extend:(BOOL)extend
                        mode:(iTermSelectionMode)mode {
    DLog(@"Begin new selection. coord=%@, extend=%d", VT100GridCoordDescription(coord), extend);
    _live = YES;
    _extend = extend;
    if ((mode == kiTermSelectionModeBox && mode != _selectionMode) ||
        (_selectionMode == kiTermSelectionModeBox && mode != _selectionMode)) {
        extend = NO;
        _range = VT100GridCoordRangeMake(-1, -1, -1, -1);
    }
    _selectionMode = mode;
    if (!extend) {
        _range.start = coord;
        _range.end = coord;
    } else if (extend &&
               ![self isFlipped] &&
               VT100GridCoordOrder(_range.start, coord) == NSOrderedDescending) {
        _range.start = _range.end;
    }
    [_delegate selectionDidChange:self];
}

- (void)endLiveSelection {
    DLog(@"End live selection");
    if (self.isFlipped) {
        _range = VT100GridCoordRangeMake(_range.end.x,
                                         _range.end.y,
                                         _range.start.x,
                                         _range.start.y);
        DLog(@"Unflip selection");
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

- (void)updateLiveSelectionWithCoord:(VT100GridCoord)coord {
    if (!_live) {
        [self beginLiveSelectionAt:coord extend:NO mode:kiTermSelectionModeCharacter];
    }
    _range.end = coord;

    _extend = YES;
    [_delegate selectionDidChange:self];
}

- (void)updateLiveSelectionWithRange:(VT100GridCoordRange)range {
    assert(_live);
    if (_extend) {
        if (VT100GridCoordOrder(_range.start, range.start) == NSOrderedAscending) {
            // Passed-in range starts after existing selection. Extend end of selection to end of range.
            _range.end = range.end;
        } else {
            // Passed-in selection starts before existing selection's start point.
            _range.start = _range.end;
            _range.end = range.start;
        }
    } else {
        _range.start = range.start;
        _range.end = range.end;
    }
    _extend = YES;
    [_delegate selectionDidChange:self];
}

- (void)updateLiveSelectionToLine:(int)y width:(int)width {
    if (_extend) {
        if (_range.start.y < y) {
            // start of existing selection is before cursor so move end point.
            _range.start.x = 0;
            _range.end.x = width;
            _range.end.y = y;
        } else {
            // end of existing selection is at or after the cursor
            _range.start.x = width;
            _range.end.x = 0;
            _range.end.y = y;
        }
    } else {
        // Not extending
        _range = VT100GridCoordRangeMake(0, y, width, y);
    }
    _extend = YES;
    [_delegate selectionDidChange:self];
}

- (void)updateLiveSelectionToRangeOfLines:(VT100GridRange)lineRange width:(int)width {
    if (_extend) {
        if ([self isFlipped]) {
            _range.start.y = lineRange.location;
            _range.end.y = lineRange.location + lineRange.length;
        } else {
            _range.start.y = lineRange.location;
            _range.end.y = lineRange.location + lineRange.length;
        }
        
        // Ensure startX and endX are correct.
        if (_range.start.y < _range.end.y) {
            _range.start.x = 0;
            _range.end.x = width;
        } else {
            _range.start.x = width;
            _range.end.x = 0;
        }
    } else {
        _range.start = VT100GridCoordMake(0, lineRange.location);
        _range.end = VT100GridCoordMake(width, lineRange.location + lineRange.length);
    }
    _extend = YES;
    [_delegate selectionDidChange:self];
}

- (void)updateLiveSelectionWithRange:(VT100GridCoordRange)range
                         rangeToKeep:(VT100GridCoordRange)rangeToKeep {
    // Now the complicated bit...
    VT100GridCoordRange newRange = self.selectedRange;
    if (VT100GridCoordOrder(self.selectedRange.start, range.end) == NSOrderedAscending) {
        // The word you clicked on ends after the start of the existing range.
        if ([self isFlipped]) {
            // The range is flipped. This happens when you were selecting backwards and
            // turned around and started going forwards.
            //
            //     word word word woooooooooord      woooooooooooooooooooooooooord
            // end<---------selection--------->start
            //                                       <-----------range----------->
            //                  <-rangeToKeep->
            //             start<----------------newRange------------------------>end
            newRange.start = rangeToKeep.start;
        } // else, not flipped. Just select the next word forward.
        newRange.end = range.end;
    } else {
        if (![self isFlipped]) {
            // This happens when you were selecting forwards and turned around and started
            // going backwards.
            // woooooooooooord       woooooooooord word word word wooooord
            //                  start<-------------selection------------->end
            // <----range---->
            //                       <-rangeToKeep->
            // <-------------newRange-------------->
            newRange.start = rangeToKeep.end;
        }  // else, flipped. Just select the next work backward.
        newRange.end = range.start;
    }
    
    _range = newRange;
    [_delegate selectionDidChange:self];
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
        return (coord.x >= start.x &&
                coord.y >= start.y &&
                coord.x < end.x &&
                coord.y <= end.y);
    } else {
        long long w = MAX(MAX(MAX(1, coord.x), start.x), end.x) + 1;
        long long coordPos = (long long)coord.y * w + coord.x;
        long long minPos = (long long)start.y * w + start.x;
        long long maxPos = (long long)end.y * w + end.x;
        
        return coordPos >= minPos && coordPos < maxPos;
    }
}

- (long long)lengthGivenWidth:(int)width {
    long long minPos = (long long)_range.start.y * width + _range.start.x;
    long long maxPos = (long long)_range.end.y * width + _range.end.x;
    
    return llabs(maxPos - minPos);
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

@end
