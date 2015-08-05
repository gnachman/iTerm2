//
//  iTermFullScreenUpdateDetector.m
//  iTerm2
//
//  Created by George Nachman on 4/23/15.
//
//

#import "iTermTemporaryDoubleBufferedGridController.h"
#import "DebugLogging.h"
#import "VT100Grid.h"

@interface iTermTemporaryDoubleBufferedGridController()
@property(nonatomic, retain) VT100Grid *savedGrid;
@end

@implementation iTermTemporaryDoubleBufferedGridController {
    NSTimer *_timer;
    VT100Grid *_savedGrid;
}

- (void)dealloc {
    [_savedGrid release];
    [super dealloc];
}

- (void)start {
    if (!_savedGrid) {
        [self snapshot];
    }
}

- (void)reset {
    DLog(@"Reset saved grid (delegate=%@)", _delegate);
    BOOL hadSavedGrid = _savedGrid != nil;
    self.savedGrid = nil;
    [_timer invalidate];
    _timer = nil;
    if (hadSavedGrid && _drewSavedGrid) {
        [_delegate temporaryDoubleBufferedGridDidExpire];
    }
}

#pragma mark - Private

- (void)snapshot {
    DLog(@"Take a snapshot of the grid because cursor was hidden (delegate=%@)", _delegate);
    static const NSTimeInterval kTimeToKeepSavedGrid = 0.2;
    self.savedGrid = [_delegate temporaryDoubleBufferedGridCopy];

    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:kTimeToKeepSavedGrid
                                              target:self
                                            selector:@selector(savedGridExpirationTimer:)
                                            userInfo:nil
                                             repeats:NO];
    _drewSavedGrid = NO;
}

- (void)savedGridExpirationTimer:(NSTimer *)timer {
    DLog(@"Saved grid expired. (delegate=%@)", _delegate);
    _timer = nil;
    [self reset];
}

@end
