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
    int _firstRow;
    int _previousRow;
    int _numberOfRowsVisited;
    int _numberOfCharactersAppended;
    NSTimeInterval _lastUpdateTime;
    NSTimer *_timer;
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
        // Check if a fullscreen update has just finished.
        [self cursorMovedUp];
        _firstRow = row;
    } else {
        // Just update stats.
        ++_numberOfRowsVisited;
    }
    _previousRow = row;
}

- (void)willAppendCharacters:(int)count {
    _numberOfCharactersAppended += count;
}

- (void)reset {
    self.savedGrid = nil;
    [self resetStatistics];
}

#pragma mark - Private

- (void)cursorMovedUp {
    static const NSTimeInterval kTimeToKeepSavedGrid = 0.1;
    if ([self hasFullScreenUpdateOccurred]) {
        NSLog(@"**UPDATE DETECTED**  %d rows visited in range [%d, %d], with %d chars appended",
              _numberOfRowsVisited, _firstRow, _previousRow, _numberOfCharactersAppended);
        self.savedGrid = [[_delegate fullScreenUpdateDidComplete] retain];
        [_timer invalidate];
        _timer = [NSTimer scheduledTimerWithTimeInterval:kTimeToKeepSavedGrid
                                                  target:self
                                                selector:@selector(savedGridExpirationTimer:)
                                                userInfo:nil
                                                 repeats:NO];
    } else {
        NSLog(@"[no update]  %d rows visited in range [%d, %d], with %d chars appended",
              _numberOfRowsVisited, _firstRow, _previousRow, _numberOfCharactersAppended);
    }
    [self reset];
}

- (BOOL)hasFullScreenUpdateOccurred {
    VT100GridSize size = [_delegate fullScreenSize];
    static const int kSkippableRowsOnTop = 3;
    static const int kSkippableRowsOnBottom = 4;
    static const int kSkippableVisitedRows = 3;
    int span = _previousRow - _firstRow + 1;
    return (_firstRow < kSkippableRowsOnTop &&
            _previousRow > size.height - kSkippableRowsOnBottom &&
            _numberOfRowsVisited > span - kSkippableVisitedRows &&
            _numberOfCharactersAppended >= _numberOfRowsVisited);
}

- (void)savedGridExpirationTimer:(NSTimer *)timer {
    NSLog(@"Expire saved grid");
    self.savedGrid = nil;
    _timer = nil;
}

- (void)resetStatistics {
    _previousRow = -1;
    _numberOfRowsVisited = 0;
    _numberOfCharactersAppended = 0;
}

- (void)checkForTimeout {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval elapsed = now - _lastUpdateTime;
    static const NSTimeInterval kIdleTime = 10;//0.05;
    if (elapsed > kIdleTime) {
        NSLog(@"Detector timeout");
        [self resetStatistics];
    }
    _lastUpdateTime = now;
}

@end
