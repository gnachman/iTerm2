//
//  iTermFullScreenUpdateDetector.m
//  iTerm2
//
//  Created by George Nachman on 4/23/15.
//
//

#import "iTermFullScreenUpdateDetector.h"
#import "VT100Grid.h"

@interface iTermFullScreenUpdateDetector()
@property(nonatomic, retain) VT100Grid *savedGrid;
@end

@implementation iTermFullScreenUpdateDetector {
    int _previousRow;
    NSTimeInterval _lastUpdateTime;
    BOOL _updateInProgress;
    NSTimer *_timer;
    VT100Grid *_savedGrid;
}

- (void)dealloc {
    [_savedGrid release];
    [super dealloc];
}

- (void)cursorMovedToRow:(int)row {
    if (row == _previousRow) {
        return;
    }

    // The cursor must change rows often or we throw out our existing statistics.
    [self checkForTimeout];

    if (row < _previousRow) {
        // Cursor's moving up. Next time it moves down, it's ok to take a snapshot even if there's
        // already a saved grid.
        _updateInProgress = NO;
    } else if (!_updateInProgress) {
        // Cursor is moving down, and no update was in progress.
        [self snapshot];
    }

    _previousRow = row;
}

- (void)willAppendCharacters:(int)count {
}

- (void)reset {
    BOOL hadSavedGrid = _savedGrid != nil;
    _updateInProgress = NO;
    self.savedGrid = nil;
    [_timer invalidate];
    _timer = nil;
    if (hadSavedGrid && _drewSavedGrid) {
        [_delegate fullScreenDidExpire];
    }
}

#pragma mark - Private

- (void)snapshot {
    static const NSTimeInterval kTimeToKeepSavedGrid = 0.1;
    BOOL hadSavedGrid = self.savedGrid != nil;
    self.savedGrid = [[_delegate fullScreenUpdateDidComplete] retain];
    if (hadSavedGrid) {
        [_delegate fullScreenDidExpire];
    }
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:kTimeToKeepSavedGrid
                                              target:self
                                            selector:@selector(savedGridExpirationTimer:)
                                            userInfo:nil
                                             repeats:NO];
    _updateInProgress = YES;
    _drewSavedGrid = NO;
}

- (void)setSavedGrid:(VT100Grid *)savedGrid {
    [_savedGrid autorelease];
    _savedGrid = [savedGrid retain];
}

- (VT100Grid *)savedGrid {
    return _savedGrid;
}

- (void)savedGridExpirationTimer:(NSTimer *)timer {
    _timer = nil;
    [self reset];
}

- (void)checkForTimeout {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval elapsed = now - _lastUpdateTime;
    static const NSTimeInterval kIdleTime = 0.05;
    if (elapsed > kIdleTime) {
        [self reset];
    }
    _lastUpdateTime = now;
}

@end
