//
//  iTermUpdateCadenceController.m
//  iTerm2
//
//  Created by George Nachman on 8/1/17.
//
//

#import "iTermUpdateCadenceController.h"

#import "DebugLogging.h"
#import "NSTimer+iTerm.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermHistogram.h"
#import "iTermThroughputEstimator.h"
#import "iTermWarning.h"

// Timer period for background sessions. This changes the tab item's color
// so it must run often enough for that to be useful.
// TODO(georgen): There's room for improvement here.
static const NSTimeInterval kBackgroundUpdateCadence = 1;


@implementation iTermUpdateCadenceController {
    BOOL _useGCDUpdateTimer;
    // This timer fires periodically to redraw textview, update the scroll position, tab appearance,
    // etc.
    NSTimer *_updateTimer;

    // This is the experimental GCD version of the update timer that seems to have more regular refreshes.
    dispatch_source_t _gcdUpdateTimer;
    NSTimeInterval _cadence;

    BOOL _deferredCadenceChange;

    iTermThroughputEstimator *_throughputEstimator;
    NSTimeInterval _lastUpdate;

    // Timer period between updates when active (not idle, tab is visible or title bar is changing,
    // etc.)
    NSTimeInterval _activeUpdateCadence;

    CFTimeInterval _lastKeystrokeTime;
}

- (instancetype)initWithThroughputEstimator:(iTermThroughputEstimator *)throughputEstimator {
    self = [super init];
    if (self) {
        _useGCDUpdateTimer = [iTermAdvancedSettingsModel useGCDUpdateTimer];
        _throughputEstimator = throughputEstimator;
        _histogram = [[iTermHistogram alloc] init];
        _activeUpdateCadence = 1.0 / MAX(1, [iTermAdvancedSettingsModel activeUpdateCadence]);
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_gcdUpdateTimer != nil) {
        dispatch_source_cancel(_gcdUpdateTimer);
    }
    [_updateTimer invalidate];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p delegate=%@ active=%@ cadence=%@>",
            NSStringFromClass([self class]),
            self,
            self.delegate,
            @(self.isActive),
            @(_cadence)];
}

- (void)changeCadenceIfNeeded {
    [self changeCadenceIfNeeded:NO];
}

- (void)didHandleInput {
    const NSInteger kThroughputLimit = 1024;
    const NSInteger estimatedThroughput = [_throughputEstimator estimatedThroughput];
    if (estimatedThroughput < kThroughputLimit && [self lastKeystrokeWasRecent]) {
        [self updateDisplay];
    }
}

- (BOOL)lastKeystrokeWasRecent {
    const CFTimeInterval diff = CACurrentMediaTime() - _lastKeystrokeTime;
    return diff < 0.1;
}

- (void)didHandleKeystroke {
    _lastKeystrokeTime = CACurrentMediaTime();
}

- (void)willStartLiveResize {
    if (!_useGCDUpdateTimer && _updateTimer) {
        [[NSRunLoop currentRunLoop] addTimer:_updateTimer forMode:NSRunLoopCommonModes];
    }
}

- (void)liveResizeDidEnd {
    if (_useGCDUpdateTimer) {
        NSTimeInterval cadence = _cadence;
        _cadence = 0;
        [self setUpdateCadence:cadence liveResizing:NO force:NO];
    } else {
        if (_updateTimer) {
            NSTimeInterval cadence = _updateTimer.timeInterval;
            [_updateTimer invalidate];
            _updateTimer = nil;
            [self setUpdateCadence:cadence liveResizing:NO force:NO];
        }
    }
}

#pragma mark - Private

- (void)setIsActive:(BOOL)active {
    if (active != _isActive) {
        _isActive = active;
        [_delegate cadenceControllerActiveStateDidChange:active];
    }
}

- (void)changeCadenceIfNeeded:(BOOL)force {
    iTermUpdateCadenceState state = [_delegate updateCadenceControllerState];
    DLog(@"%@ state: active=%@, idle=%@, visible=%@, useAdaptiveFrameRate=%@, adaptiveFrameRateThroughputThreshold=%@, slowFrameRate=%@, liveResizing=%@",
         self,
         @(state.active),
         @(state.idle),
         @(state.visible),
         @(state.useAdaptiveFrameRate),
         @(state.adaptiveFrameRateThroughputThreshold),
         @(state.slowFrameRate),
         @(state.liveResizing));

    // state.active means that it needs periodic redraws OR the tab label is changing.
    // idle means no input has been received on the PTY in a while (3 seconds by default).
    // assignment to self.isActive is used to update whether Metal is in use, when it's disabled while idle.
    self.isActive = (state.active || !state.idle);

    if (!self.isActive) {
        // Periodic redraws not needed (i.e., nothing is blinking) and the session is idle. It doesn't matter
        // if the app itself is active because there's nothing to do so use the background update cadence.
        DLog(@"select background update cadence because the session is idle");
        [self setUpdateCadence:kBackgroundUpdateCadence liveResizing:state.liveResizing force:force];
        return;
    }

    // visible means the session belongs to the visible tab.
    if (!state.visible) {
        // Although self.isActive is true, the session is not visible so there's no point redrawing it.
        DLog(@"select background update cadence");
        [self setUpdateCadence:[self backgroundInterval]
                  liveResizing:state.liveResizing
                         force:force];
        return;
    }

    if (!state.useAdaptiveFrameRate) {
        // The session is visible and self.active is true (it needs redraws or it's not idle).
        DLog(@"select active update cadence");
        [self setUpdateCadence:[self foregroundNonadaptiveInterval:&state]
                  liveResizing:state.liveResizing
                         force:force];
    }

    // Adaptive framerate path - the session is active and visible
    const NSInteger kThroughputLimit = state.adaptiveFrameRateThroughputThreshold;
    const NSInteger estimatedThroughput = [_throughputEstimator estimatedThroughput];
    if (estimatedThroughput < kThroughputLimit && estimatedThroughput > 0) {
        DLog(@"select fast cadence");
        [self setUpdateCadence:[self fastAdaptiveInterval]
                  liveResizing:state.liveResizing
                         force:force];
    } else {
        DLog(@"select slow frame rate");
        [self setUpdateCadence:[self slowAdaptiveInterval:&state]
                  liveResizing:state.liveResizing
                         force:force];
    }
}

- (double)proMotionAdjustment:(const iTermUpdateCadenceState *)statePtr {
    if (statePtr->proMotion) {
        return 2;
    }
    return 1;
}

// When adaptive framerate is enabled and throughput is low, update with this period.
- (NSTimeInterval)fastAdaptiveInterval {
    // Note I do not do a ProMotion adjustment because this is used outside interactive apps when
    // maximizing throughput. That is where frequent updates limit throughput the most.
    return 1.0 / MAX(1, [iTermAdvancedSettingsModel maximumFrameRate]);
}

// When adaptive framerate is enabled and throughput is high, update with this period.
- (NSTimeInterval)slowAdaptiveInterval:(const iTermUpdateCadenceState *)statePtr {
    // Maximize throughput and drop frame rate to free up CPU.
    return 1.0 / statePtr->slowFrameRate;
}

// When the view is not visible, update with this period.
- (NSTimeInterval)backgroundInterval {
    return kBackgroundUpdateCadence;
}

// When adaptive framerate is disabled and the view is visible, update with this period.
- (NSTimeInterval)foregroundNonadaptiveInterval:(const iTermUpdateCadenceState *)statePtr {
    // This is critical for good performance in interactive apps.
    return _activeUpdateCadence / [self proMotionAdjustment:statePtr];
}

// During live resize, update with this period.
- (NSTimeInterval)liveResizeInterval {
    return _activeUpdateCadence;
}

- (void)setUpdateCadence:(NSTimeInterval)cadence liveResizing:(BOOL)liveResizing force:(BOOL)force {
    if (_useGCDUpdateTimer) {
        [self setGCDUpdateCadence:cadence liveResizing:liveResizing force:force];
    } else {
        [self setTimerUpdateCadence:cadence liveResizing:liveResizing force:force];
    }
}

- (void)setTimerUpdateCadence:(NSTimeInterval)cadence liveResizing:(BOOL)liveResizing force:(BOOL)force {
    if (_updateTimer.timeInterval == cadence) {
        DLog(@"No change to cadence: %@", self);
        return;
    }
    DLog(@"Set cadence of %@ to %f", self, cadence);

    if (liveResizing) {
        // This solves the bug where we don't redraw properly during live resize.
        // I'm worried about the possible side effects it might have since there's no way to
        // know all the tracking event loops.
        [_updateTimer invalidate];
        _updateTimer = [NSTimer weakTimerWithTimeInterval:[self liveResizeInterval]
                                                   target:self
                                                 selector:@selector(updateDisplay)
                                                 userInfo:nil
                                                  repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:_updateTimer forMode:NSRunLoopCommonModes];
    } else {
        if (!force && _updateTimer && cadence > _updateTimer.timeInterval) {
            DLog(@"Defer cadence change");
            _deferredCadenceChange = YES;
        } else {
            [_updateTimer invalidate];
            _updateTimer = [NSTimer scheduledWeakTimerWithTimeInterval:cadence
                                                                target:self
                                                              selector:@selector(updateDisplay)
                                                              userInfo:nil
                                                               repeats:YES];
        }
    }
}
- (void)setGCDUpdateCadence:(NSTimeInterval)cadence liveResizing:(BOOL)liveResizing force:(BOOL)force {
    const NSTimeInterval period = liveResizing ? [self liveResizeInterval] : cadence;
    if (_cadence == period) {
        DLog(@"No change to cadence: %@", self);
        return;
    }
    DLog(@"Set cadence of %@ to %f", self, cadence);

    if (!force && _cadence > 0 && cadence > _cadence) {
        // Don't increase the cadence until after the screen has a chance to
        // draw. This way if you do "cat bigfile.txt" you see the first
        // screenful before the refresh rate drops. This way you know
        // something's happening.
        DLog(@"Defer cadence change");
        _deferredCadenceChange = YES;
        return;
    }

    _cadence = period;

    if (_gcdUpdateTimer != nil) {
        dispatch_source_cancel(_gcdUpdateTimer);
        _gcdUpdateTimer = nil;
    }

    _gcdUpdateTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_gcdUpdateTimer,
                              dispatch_time(DISPATCH_TIME_NOW, period * NSEC_PER_SEC),
                              period * NSEC_PER_SEC,
                              0.0005 * NSEC_PER_SEC);
    __weak __typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_gcdUpdateTimer, ^{
        DLog(@"GCD cadence timer fired for %@", weakSelf);
        [weakSelf maybeUpdateDisplay];
    });
    dispatch_resume(_gcdUpdateTimer);
}

- (BOOL)updateTimerIsValid {
    if (_useGCDUpdateTimer) {
        return _gcdUpdateTimer != nil;
    } else {
        return _updateTimer.isValid;
    }
}

- (void)maybeUpdateDisplay {
    if ([iTermWarning showingWarning] || [NSApp modalWindow] || [self.delegate updateCadenceControllerWindowHasSheet]) {
        return;
    }
    [self updateDisplay];
}

- (void)updateDisplay {
    if (_deferredCadenceChange) {
        [self changeCadenceIfNeeded:YES];
        _deferredCadenceChange = NO;
    }
    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (_lastUpdate) {
        double ms = (now - _lastUpdate) * 1000;
        [_histogram addValue:ms];
    }
    _lastUpdate = now;
    [_delegate updateCadenceControllerUpdateDisplay:self];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    _histogram = [[iTermHistogram alloc] init];
    _lastUpdate = 0;
}

@end
