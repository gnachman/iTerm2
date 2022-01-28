//
//  iTermFullScreenUpdateDetector.m
//  iTerm2
//
//  Created by George Nachman on 4/23/15.
//
//

#import "iTermTemporaryDoubleBufferedGridController.h"
#import "iTermGCDTimer.h"
#import "DebugLogging.h"
#import "VT100Grid.h"

@interface iTermTemporaryDoubleBufferedGridController()
@property(nonatomic, strong) PTYTextViewSynchronousUpdateState *savedState;
@end

@implementation iTermTemporaryDoubleBufferedGridController {
    iTermGCDTimer *_timer;
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        _queue = queue;
    }
    return self;
}

- (void)start {
    if (_explicit) {
        return;
    }
    if (!_savedState) {
        DLog(@"%@ start. take snapshot", self.delegate);
        [self snapshot];
    }
}

- (void)startExplicitly {
    DLog(@"%@ startExplicitly", self.delegate);
    _explicit = YES;
    self.dirty = YES;
    if (_savedState) {
        [self scheduleTimer];
    } else {
        [self snapshot];
    }
}

- (void)reset {
    if (_explicit) {
        return;
    }
    DLog(@"Reset saved grid (delegate=%@)", _delegate);
    self.dirty = YES;
    BOOL hadSavedGrid = _savedState != nil;
    self.savedState = nil;
    [_timer invalidate];
    _timer = nil;
    if (hadSavedGrid && _drewSavedGrid) {
        [_delegate temporaryDoubleBufferedGridDidExpire];
    }
}

- (void)resetExplicitly {
    self.dirty = YES;
    _explicit = NO;
    [self reset];
}

#pragma mark - Private

- (void)snapshot {
    self.dirty = YES;
    DLog(@"Take a snapshot of the grid because cursor was hidden (delegate=%@)", _delegate);
    self.savedState = [_delegate temporaryDoubleBufferedGridSavedState];

    [self scheduleTimer];
    _drewSavedGrid = NO;
}

- (void)scheduleTimer {
    static const NSTimeInterval kTimeToKeepSavedGrid = 0.2;
    static const NSTimeInterval kExplicitSaveTime = 1.0;
    DLog(@"%@ schedule timer", self.delegate);
    [_timer invalidate];
    _timer = [[iTermGCDTimer alloc] initWithInterval:_explicit ? kExplicitSaveTime : kTimeToKeepSavedGrid
                                               queue:_queue
                                              target:self
                                            selector:@selector(savedGridExpirationTimer:)];
}

- (void)savedGridExpirationTimer:(iTermGCDTimer *)timer {
    DLog(@"Saved grid expired. (delegate=%@)", _delegate);
    _timer = nil;
    [self resetExplicitly];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    iTermTemporaryDoubleBufferedGridController *copy = [[iTermTemporaryDoubleBufferedGridController alloc] initWithQueue:_queue];
    copy->_explicit = _explicit;
    copy.drewSavedGrid = _drewSavedGrid;
    copy.savedState = [self.savedState copy];
    self.dirty = NO;
    return copy;
}

@end
