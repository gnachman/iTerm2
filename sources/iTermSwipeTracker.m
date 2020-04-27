//
//  iTermSwipeTracker.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/26/20.
//

#import "iTermSwipeTracker.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTimer+iTerm.h"
#import "iTermScrollWheelStateMachine.h"

#warning DNS
#undef DLog
#define DLog NSLog

const CGFloat gSwipeFriction = 0.1;

typedef struct {
    iTermScrollWheelStateMachineState before;
    iTermScrollWheelStateMachineState after;
} iTermScrollWheelStateMachineStateTransition;

@interface iTermGCDTimer: NSObject
- (instancetype)initWithInterval:(NSTimeInterval)interval
                          target:(id)target
                        selector:(SEL)selector NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)invalidate;
@end

@implementation iTermGCDTimer {
    __weak id _target;
    SEL _selector;
    NSTimeInterval _interval;
    BOOL _valid;
}

- (instancetype)initWithInterval:(NSTimeInterval)interval target:(id)target selector:(SEL)selector {
    self = [super init];
    if (self) {
        _target = target;
        _selector = selector;
        _interval = interval;
        _valid = YES;
        [self schedule];
    }
    return self;
}

- (void)invalidate {
    _valid = NO;
}

- (void)schedule {
    __weak __typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_interval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf didFire];
    });
}

- (void)didFire {
    if (!_valid) {
        return;
    }
    [self schedule];
    __strong id strongTarget = _target;
    if (!strongTarget) {
        return;
    }
    [strongTarget it_performNonObjectReturningSelector:_selector withObject:self];
}

@end
@interface iTermSwipeState()

@property (nonatomic, readonly) BOOL isRetired;
@property (nonatomic, readonly) BOOL wantsEvents;

- (void)handleEvent:(NSEvent *)event
         transition:(iTermScrollWheelStateMachineStateTransition)transition;

- (void)update;

@end

@implementation iTermSwipeTracker {
    iTermScrollWheelStateMachine *_stateMachine;
    NSMutableArray<iTermSwipeState *> *_backgroundStates;
    iTermSwipeState *_liveState;
    iTermGCDTimer *_timer;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _stateMachine = [[iTermScrollWheelStateMachine alloc] init];
        _backgroundStates = [NSMutableArray array];
    }
    return self;
}

- (BOOL)shouldTrack {
    if (_liveState && !_liveState.isRetired) {
        return YES;
    }
    return NO;
}

- (BOOL)handleEvent:(NSEvent *)event {
    if (!event.window) {
        return NO;
    }
    const BOOL shouldTrack = [self internalHandleEvent:event];
    if (!shouldTrack) {
        return NO;
    }

    assert([self shouldTrack]);

    DLog(@"Start tracking loop");
    const NSEventMask eventMask = NSEventMaskScrollWheel;
    event = [NSApp nextEventMatchingMask:eventMask
                               untilDate:[NSDate distantFuture]
                                  inMode:NSEventTrackingRunLoopMode
                                 dequeue:YES];
    DLog(@"Got event %@", iTermShortEventPhasesString(event));
    while (1) {
        @autoreleasepool {
            DLog(@"Continue tracking.");
            if (event) {
                [self internalHandleEvent:event];
            }
            if (![self shouldTrack]) {
                break;
            }
            event = [NSApp nextEventMatchingMask:eventMask
                                       untilDate:[NSDate dateWithTimeIntervalSinceNow:1.0 / 60.0]
                                          inMode:NSEventTrackingRunLoopMode
                                         dequeue:YES];
            DLog(@"Got event %@", event);
        }
    }
    DLog(@"Exit tracking loop");
    return YES;
}

- (BOOL)internalHandleEvent:(NSEvent *)event {
    DLog(@"internalHandleEvent: %@", iTermShortEventPhasesString(event));
    if (![NSEvent isSwipeTrackingFromScrollEventsEnabled]) {
        DLog(@"Swipe tracking not enabled");
        return NO;
    }
    if (_stateMachine.state == iTermScrollWheelStateMachineStateGround &&
        fabs(event.scrollingDeltaX) <= fabs(event.scrollingDeltaY)) {
        DLog(@"Not horizontal");
        return NO; // Not horizontal
    }

    iTermScrollWheelStateMachineStateTransition transition = {
        .before = _stateMachine.state
    };
    [_stateMachine handleEvent:event];
    transition.after = _stateMachine.state;

    if (_liveState && !_liveState.isRetired) {
        [_liveState handleEvent:event transition:transition];
        return YES;
    }
    if ([self createStateForEventIfNeeded:event transition:transition]) {
        return YES;
    }
    DLog(@"Live state didn't want event and I couldn't create a new state for it.");
    return NO;
}

- (CGFloat)deltaXForEvent:(NSEvent *)event {
    return -event.scrollingDeltaX;
}

- (BOOL)createStateForEventIfNeeded:(NSEvent *)event
                         transition:(iTermScrollWheelStateMachineStateTransition)transition {
    if (transition.before == iTermScrollWheelStateMachineStateStartDrag ||
        transition.after != iTermScrollWheelStateMachineStateStartDrag) {
        DLog(@"Can't create state for transition %@ -> %@", @(transition.before),
             @(transition.after));
        return NO;
    }
    if (_liveState) {
        [self backgroundLiveState];
    }
    DLog(@"Create new live state");
    _liveState = [self.delegate swipeTrackerWillBeginNewSwipe:self
                                                        delta:[self deltaXForEvent:event]];
    [_liveState handleEvent:event transition:transition];
    [self updateTimer];
    if (!_liveState) {
        DLog(@"fail: live state is nil");
        return NO;
    }
    DLog(@"Success");
    return YES;
}

- (void)backgroundLiveState {
    assert(_liveState);
    DLog(@"Background live state");
    [_backgroundStates addObject:_liveState];
    _liveState = nil;
}

- (void)updateTimer {
    if (!_liveState && !_backgroundStates.count) {
        DLog(@"Cancel timer");
        [_timer invalidate];
        _timer = nil;
        return;
    }
    if (_timer) {
        DLog(@"Already have timer");
        return;
    }
    DLog(@"Schedule timer");
    _timer = [[iTermGCDTimer alloc] initWithInterval:1.0 / 60
                                              target:self
                                            selector:@selector(update:)];
}

- (void)update:(iTermGCDTimer *)timer {
    DLog(@"Timer fired");
    if (_liveState.isRetired) {
        DLog(@"nil out retired live state");
        _liveState = nil;
    }
    DLog(@"Update live state %@", _liveState);
    [_liveState update];
    for (iTermSwipeState *state in _backgroundStates) {
        DLog(@"Update background state %@", state);
        [state update];
    }
    [_backgroundStates removeObjectsPassingTest:^BOOL(iTermSwipeState *state) {
        if (state.isRetired) {
            DLog(@"Remove retired background state %@", state);
        }
        return state.isRetired;
    }];
    [self updateTimer];
}

@end

typedef enum {
    iTermSwipeStateCancelStageNone,
    // drag->ground. Wait 2 ticks to see if momentum starts.
    iTermSwipeStateCancelStageWait2Ticks,
    // drag->ground happened 1 tick ago. Still waiting to see if momentum starts.
    iTermSwipeStateCancelStageWait1Tick,
    // No possibility of momentum events. Continue toward 1.
    iTermSwipeStateCancelStageCanceledPositive,
    // No possibility of momentum events. Continue toward -1.
    iTermSwipeStateCancelStageCanceledNegative
}  iTermSwipeStateCancelStage;

@implementation iTermSwipeState {
    CGFloat _width;
    CGFloat _offset;
    CGFloat _momentum;
    iTermScrollWheelStateMachineState _state;
    iTermSwipeStateCancelStage _cancelStage;
}

- (instancetype)initWithSwipeHandler:(id<iTermSwipeHandler>)handler {
    assert(handler);
    self = [super init];
    if (self) {
        _width = [handler swipeWidth];
        assert(_width > 0);
        _swipeHandler = handler;
        self.wantsEvents = YES;
        DLog(@"New swipe state %@", self);
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p width=%@ offset=%@ momentum=%@ state=%@ cancelStage=%@>",
            NSStringFromClass(self.class),
            self,
            @(_width),
            @(_offset),
            @(_momentum),
            @(_state),
            @(_cancelStage)];
}

- (iTermSwipeStateCancelStage)cancelType {
    if (_momentum < -1) {
        return iTermSwipeStateCancelStageCanceledNegative;
    }
    if (_momentum > 1) {
        return iTermSwipeStateCancelStageCanceledPositive;
    }
    
    const CGFloat fraction = _offset / _width;
    const CGFloat threshold = 0.25;
    if (fraction < 0) {
        if (fraction < -threshold) {
            return iTermSwipeStateCancelStageCanceledNegative;
        }
        return iTermSwipeStateCancelStageCanceledPositive;
    }
    if (fraction > threshold) {
        return iTermSwipeStateCancelStageCanceledPositive;
    }
    return iTermSwipeStateCancelStageCanceledNegative;
}

- (void)retireWithDirection:(int)direction {
    DLog(@"Retire with direction %d", direction);
    assert(!_isRetired);
    [self.swipeHandler didCompleteSwipe:self.userInfo direction:direction];
    self.cancelStage = iTermSwipeStateCancelStageNone;
    self.wantsEvents = NO;
    _isRetired = YES;
}

- (void)update {
    DLog(@"Update %@", self);
    assert(!_isRetired);
    if (_offset == 0) {
        // Super unlikely. This should only happen if the offset was 0 when the touch up occurred.
        [self retireWithDirection:0];
        return;
    }
    const CGFloat force = -_momentum * gSwipeFriction;
    switch (_cancelStage) {
        case iTermSwipeStateCancelStageNone:
            DLog(@"Nothing to do");
            return;
        case iTermSwipeStateCancelStageWait2Ticks:
            self.cancelStage = iTermSwipeStateCancelStageWait1Tick;
            return;
        case iTermSwipeStateCancelStageWait1Tick:
            self.cancelStage = [self cancelType];
            if ((_offset <= 0 && _cancelStage == iTermSwipeStateCancelStageCanceledPositive) ||
                (_offset >= 0 && _cancelStage == iTermSwipeStateCancelStageCanceledNegative)) {
                DLog(@"didCancel %@", self);
                [self.swipeHandler didCancelSwipe:self.userInfo];
            }
            break;
        case iTermSwipeStateCancelStageCanceledPositive:
        case iTermSwipeStateCancelStageCanceledNegative:
            self.wantsEvents = NO;
            [self applyForce:force];
            break;
    }
}

static CGFloat Clamp(CGFloat value, CGFloat min, CGFloat max) {
    return MAX(MIN(value, max), min);
}

- (void)applyForce:(CGFloat)force {
    DLog(@"Apply force %@ to %@", @(force), self);
    _momentum += force;
    const CGFloat offsetBefore = _offset;
    _offset += _momentum;
    CGFloat clamped = Clamp(_offset / _width, -1, 1);
    DLog(@"After applying force: %@", self);
    if ((offsetBefore > 0 && _offset <= 0) || (offsetBefore < 0 && _offset >= 0)) {
        DLog(@"Zero crossing");
        [self.swipeHandler didUpdateSwipe:self.userInfo amount:0];
        _offset = 0;
        [self retireWithDirection:0];
        self.cancelStage = iTermSwipeStateCancelStageNone;
        return;
    }

    [self.swipeHandler didUpdateSwipe:self.userInfo amount:clamped];
    if (_offset >= _width && force < 0) {
        [self retireWithDirection:-1];
    } else if (_offset <= -_width && force > 0) {
        [self retireWithDirection:1];
    }
}

- (void)dragBy:(CGFloat)delta {
    DLog(@"dragBy:%@ for %@", @(delta), self);
    _offset += delta;
    _offset = Clamp(_offset, -_width, _width);
    _momentum = delta;
    DLog(@"After drag: %@", self);
    [self.swipeHandler didUpdateSwipe:self.userInfo amount:_offset / _width];
}

- (void)handleMomentumWithDelta:(CGFloat)delta {
    DLog(@"handleMomentumWithDelta:%@ for %@", @(delta), self);
    self.wantsEvents = NO;
    _offset += delta;
    _offset = Clamp(_offset, -_width, _width);
    _momentum = delta;
    DLog(@"After handling momentum: %@", self);
    [self.swipeHandler didUpdateSwipe:self.userInfo amount:_offset / _width];
}

- (void)startDrag:(CGFloat)amount {
    DLog(@"startDrag:%@ for %@", @(amount), self);
    assert(!_userInfo);
    _userInfo = [self.swipeHandler didBeginSwipeWithAmount:amount / _width];
    assert(_userInfo);
    _offset = amount;
    _offset = Clamp(_offset, -_width, _width);
    _momentum = _offset;
    DLog(@"After starting drag: %@", self);
}

- (CGFloat)deltaXForEvent:(NSEvent *)event {
    return -event.scrollingDeltaX;
}

- (void)handleEvent:(NSEvent *)event
         transition:(iTermScrollWheelStateMachineStateTransition)transition {
    DLog(@"handleEvent:%@ before=%@ after=%@", iTermShortEventPhasesString(event), @(transition.before), @(transition.after));
    _state = transition.after;

    switch (transition.before) {
        case iTermScrollWheelStateMachineStateGround:
            switch (transition.after) {
                case iTermScrollWheelStateMachineStateDrag:
                    [self dragBy:[self deltaXForEvent:event]];
                    break;
                case iTermScrollWheelStateMachineStateTouchAndHold:
                    break;
                case iTermScrollWheelStateMachineStateMomentum:
                    [self handleMomentumWithDelta:[self deltaXForEvent:event]];
                    break;
                case iTermScrollWheelStateMachineStateStartDrag:
                    [self startDrag:[self deltaXForEvent:event]];
                    break;
                case iTermScrollWheelStateMachineStateGround:
                    break;
            }
            break;
        case iTermScrollWheelStateMachineStateStartDrag:
            switch (transition.after) {
                case iTermScrollWheelStateMachineStateDrag:
                    [self dragBy:[self deltaXForEvent:event]];
                    break;
                case iTermScrollWheelStateMachineStateGround:
                case iTermScrollWheelStateMachineStateMomentum:
                case iTermScrollWheelStateMachineStateStartDrag:
                case iTermScrollWheelStateMachineStateTouchAndHold:
                    assert(NO);
                    break;
            }
            break;
        case iTermScrollWheelStateMachineStateTouchAndHold:
            switch (transition.after) {
                case iTermScrollWheelStateMachineStateDrag:
                    [self dragBy:[self deltaXForEvent:event]];
                    break;
                case iTermScrollWheelStateMachineStateStartDrag:
                    [self startDrag:[self deltaXForEvent:event]];
                    break;
                case iTermScrollWheelStateMachineStateGround:
                    [self retireWithDirection:0];
                    break;
                case iTermScrollWheelStateMachineStateMomentum:
                case iTermScrollWheelStateMachineStateTouchAndHold:
                    assert(NO);
                    break;
            }
            break;
        case iTermScrollWheelStateMachineStateDrag:
            switch (transition.after) {
                case iTermScrollWheelStateMachineStateDrag:
                    [self dragBy:[self deltaXForEvent:event]];
                    break;
                case iTermScrollWheelStateMachineStateGround:
                    self.cancelStage = iTermSwipeStateCancelStageWait2Ticks;
                    [self.swipeHandler didEndSwipe:self.userInfo amount:[self deltaXForEvent:event]];
                    break;
                case iTermScrollWheelStateMachineStateMomentum:
                case iTermScrollWheelStateMachineStateStartDrag:
                case iTermScrollWheelStateMachineStateTouchAndHold:
                    assert(NO);
                    break;
            }
            break;
        case iTermScrollWheelStateMachineStateMomentum:
            switch (transition.after) {
                case iTermScrollWheelStateMachineStateMomentum:
                    [self handleMomentumWithDelta:[self deltaXForEvent:event]];
                    break;
                case iTermScrollWheelStateMachineStateGround:
                    self.cancelStage = [self cancelType];
                    self.wantsEvents = NO;
                    break;
                case iTermScrollWheelStateMachineStateDrag:
                case iTermScrollWheelStateMachineStateStartDrag:
                case iTermScrollWheelStateMachineStateTouchAndHold:
                    assert(NO);
                    break;
            }
            break;
    }
}

- (CGFloat)momentumForDistance:(CGFloat)distance {
    static CGFloat sumOfFrictionPowers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const CGFloat desiredDuration = 0.25;
        const CGFloat framesPerSecond = 60;
        const CGFloat numberOfFrames = round(desiredDuration * framesPerSecond);
        sumOfFrictionPowers = 0;
        for (CGFloat i = 0; i < numberOfFrames; i += 1) {
            sumOfFrictionPowers += (pow(1 - gSwipeFriction, i));
        }
    });
    return (distance / sumOfFrictionPowers);
}

- (void)setCancelStage:(iTermSwipeStateCancelStage)stage {
    DLog(@"setCancelStage %@ for %@", @(stage), self);
    if (stage == iTermSwipeStateCancelStageCanceledPositive) {
        if (_offset >= 0) {
            _momentum = [self momentumForDistance:_width - _offset];
        } else {
            _momentum = -[self momentumForDistance:_width + _offset];
        }
    } else if (stage == iTermSwipeStateCancelStageCanceledNegative) {
        if (_offset <= 0) {
            _momentum = -[self momentumForDistance:_width + _offset];
        } else {
            _momentum = [self momentumForDistance:_width - _offset];
        }
    }
    _cancelStage = stage;
}

- (void)setWantsEvents:(BOOL)wantsEvents {
    DLog(@"setWantsEvents %@ for %@", @(wantsEvents), self);
    _wantsEvents = wantsEvents;
}
@end

