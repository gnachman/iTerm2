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
#import "iTermSquash.h"

#warning DNS
#undef DLog
#define DLog NSLog

const CGFloat gSwipeFriction = 0.1;

typedef enum {
    iTermSwipeStateMomentumStageNone,
    // No possibility of momentum events. Continue toward 1.
    iTermSwipeStateMomentumStagePositive,
    // No possibility of momentum events. Continue toward -1.
    iTermSwipeStateMomentumStageNegative
}  iTermSwipeStateMomentumStage;

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
@property (nonatomic, readonly) iTermSwipeStateMomentumStage momentumStage;

- (void)handleEvent:(NSEvent *)event
         transition:(iTermScrollWheelStateMachineStateTransition)transition;

- (void)update;

@end

@implementation iTermSwipeTracker {
    iTermScrollWheelStateMachine *_stateMachine;
    iTermSwipeState *_liveState;
    iTermGCDTimer *_timer;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _stateMachine = [[iTermScrollWheelStateMachine alloc] init];
    }
    return self;
}

- (BOOL)shouldTrack {
    return _liveState != nil && !_liveState.isRetired;
}

- (BOOL)handleEvent:(NSEvent *)event {
    if (!event.window) {
        return NO;
    }
    const BOOL handled = [self internalHandleEvent:event];
    if (!handled) {
        return NO;
    }

    if (![self shouldTrack]) {
        return NO;
    }

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
            [self updateTimer];
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
        _liveState.momentumStage == iTermSwipeStateMomentumStageNone &&
        fabs(event.scrollingDeltaX) <= fabs(event.scrollingDeltaY)) {
        DLog(@"Not horizontal x=%0.2f y=%0.2f", fabs(event.scrollingDeltaX), fabs(event.scrollingDeltaY));
        return NO;
    }

    iTermScrollWheelStateMachineStateTransition transition = {
        .before = _stateMachine.state
    };
    [_stateMachine handleEvent:event];
    transition.after = _stateMachine.state;

    if (!_liveState || _liveState.isRetired) {
        return [self createStateForEventIfNeeded:event transition:transition];
    }
    [_liveState handleEvent:event transition:transition];
    return YES;
}

- (BOOL)createStateForEventIfNeeded:(NSEvent *)event
                         transition:(iTermScrollWheelStateMachineStateTransition)transition {
    if (transition.before == iTermScrollWheelStateMachineStateStartDrag ||
        transition.after != iTermScrollWheelStateMachineStateStartDrag) {
        DLog(@"Can't create state for transition %@ -> %@", @(transition.before),
             @(transition.after));
        return NO;
    }
    DLog(@"Create new live state");
    _liveState = [self.delegate swipeTrackerWillBeginNewSwipe:self];
    [_liveState handleEvent:event transition:transition];
    [self updateTimer];
    if (!_liveState) {
        DLog(@"fail: live state is nil");
        return NO;
    }
    DLog(@"Success");
    return YES;
}

- (void)updateTimer {
    if (!_liveState || _liveState.momentumStage == iTermSwipeStateMomentumStageNone) {
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
    [self updateTimer];
}

@end

@implementation iTermSwipeState {
    iTermSwipeHandlerParameters _parameters;
    CGFloat _width;
    CGFloat _rawOffset;
    CGFloat _initialOffset;
    CGFloat _momentum;
    iTermScrollWheelStateMachineState _state;
    NSInteger _targetIndex;
    BOOL _started;
}

- (instancetype)initWithSwipeHandler:(id<iTermSwipeHandler>)handler {
    assert(handler);
    self = [super init];
    if (self) {
        _parameters = [handler swipeHandlerParameters];
        if (_parameters.count == 0 || _parameters.width <= 0) {
            return nil;
        }
        assert(_parameters.width > 0);
        assert(_parameters.count > 0);
        assert(_parameters.currentIndex < _parameters.count);
        _swipeHandler = handler;
        DLog(@"New swipe state %@", self);
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p width=%@ offset=%@ (%@) momentum=%@ state=%@ momentumStage=%@>",
            NSStringFromClass(self.class),
            self,
            @(_width),
            @(self.squashedOffset),
            @(_rawOffset),
            @(_momentum),
            @(_state),
            @(self.momentumStage)];
}

- (iTermSwipeStateMomentumStage)desiredMomentumStage {
    if (_momentum < -1) {
        return iTermSwipeStateMomentumStageNegative;
    }
    if (_momentum > 1) {
        return iTermSwipeStateMomentumStagePositive;
    }

    if (self.squashedOffset < _initialOffset) {
        return iTermSwipeStateMomentumStagePositive;
    }
    return iTermSwipeStateMomentumStageNegative;
}

// Retirement means that the state is completely finished.
- (void)retire {
    DLog(@"Retire %@", self);
    assert(!_isRetired);
    self.momentumStage = iTermSwipeStateMomentumStageNone;
    _isRetired = YES;
    [self.swipeHandler swipeHandlerEndSession:self.userInfo
                                      atIndex:_targetIndex];
}

- (CGFloat)offsetOfTargetIndex {
    return _targetIndex * -_parameters.width;
}

- (BOOL)offsetIsAfterTargetIndex:(CGFloat)offset {
    return offset > [self offsetOfTargetIndex];
}

- (void)update {
    DLog(@"Update %@", self);
    assert(!_isRetired);
    const CGFloat force = -_momentum * gSwipeFriction;
    switch (self.momentumStage) {
        case iTermSwipeStateMomentumStageNone:
            DLog(@"Nothing to do");
            return;
        case iTermSwipeStateMomentumStagePositive:
        case iTermSwipeStateMomentumStageNegative:
            if (self.squashedOffset == [self offsetOfTargetIndex]) {
                // Super unlikely. This should only happen if the offset was just right when the touch up occurred.
                [self retire];
                return;
            }
            if (fabs(force) > 0.1) {
                [self applyForce:force];
                return;
            }
            DLog(@"Force less than threshold (%f). Will retire.", force);
            if (force < 0) {
                if ([self offsetIsAfterTargetIndex:self.squashedOffset]) {
                    [self didCrossZero];
                    return;
                }
                [self retire];
                return;
            }
            if (![self offsetIsAfterTargetIndex:self.squashedOffset]) {
                [self didCrossZero];
                return;
            }
            [self retire];
            return;
    }
}

- (void)applyForce:(CGFloat)force {
    DLog(@"Apply force %@ to %@", @(force), self);
    const CGFloat offsetBefore = self.squashedOffset;
    _rawOffset += _momentum;
    _momentum += force;
    DLog(@"After applying force: %@", self);
    if (([self offsetIsAfterTargetIndex:offsetBefore] && ![self offsetIsAfterTargetIndex:self.squashedOffset]) ||
        (![self offsetIsAfterTargetIndex:offsetBefore] && [self offsetIsAfterTargetIndex:self.squashedOffset])) {
        [self didCrossZero];
        return;
    }

    [self.swipeHandler swipeHandlerSetOffset:self.squashedOffset forSession:self.userInfo];
    if ([self offsetIsAfterTargetIndex:self.squashedOffset] && force < 0) {
        [self retire];
        return;
    }
    if (![self offsetIsAfterTargetIndex:self.squashedOffset] && force > 0) {
        [self retire];
    }
}

- (void)didCrossZero {
    DLog(@"Zero crossing");
    [self.swipeHandler swipeHandlerSetOffset:[self offsetOfTargetIndex] forSession:self.userInfo];
    [self retire];
    self.momentumStage = iTermSwipeStateMomentumStageNone;
}

- (void)dragBy:(CGFloat)delta {
    if (!_started) {
        if (fabs(delta) > 10) {
            _started = YES;
        } else {
            DLog(@"Ignore drag by %0.0f because it's not enough to get started", delta);
            return;
        }
    }
    DLog(@"dragBy:%@ for %@", @(delta), self);
    _rawOffset += delta;
    _momentum = delta;
    DLog(@"After drag: %@", self);
    [self.swipeHandler swipeHandlerSetOffset:self.squashedOffset forSession:self.userInfo];
}

- (void)startDrag:(CGFloat)delta {
    DLog(@"startDrag:%@ for %@", @(delta), self);
    if (!_userInfo) {
        _initialOffset = _parameters.currentIndex * -_parameters.width;
        _rawOffset = _initialOffset + delta;
        _userInfo = [self.swipeHandler swipeHandlerBeginSessionAtOffset:_initialOffset];
        if (fabs(_initialOffset - _rawOffset) >= 1) {
            [self.swipeHandler swipeHandlerSetOffset:self.squashedOffset forSession:_userInfo];
        }
        DLog(@"Set offset=%@ initialOffset=%@", @(self.squashedOffset), @(_initialOffset));
    } else {
        DLog(@"Resume existing session. Update raw & initial offsets");
        _parameters.currentIndex = [self indexForOffset:self.squashedOffset round:0];
        _initialOffset = _rawOffset;
        _rawOffset += delta;
    }
    assert(_userInfo);
    _momentum = delta;
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
                    self.momentumStage = iTermSwipeStateMomentumStageNone;
                    [self dragBy:[self deltaXForEvent:event]];
                    break;
                case iTermScrollWheelStateMachineStateTouchAndHold:
                    break;
                case iTermScrollWheelStateMachineStateStartDrag:
                    self.momentumStage = iTermSwipeStateMomentumStageNone;
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
                    [self retire];
                    break;
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
                    [self retire];
                    break;
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
                    self.momentumStage = [self desiredMomentumStage];
                    if (self.momentumStage == iTermSwipeStateMomentumStageNone) {
                        [self.swipeHandler swipeHandlerEndSession:self.userInfo
                                                          atIndex:_targetIndex];
                    }
                    break;
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
    // A little extra for rounding errors.
    return (distance / sumOfFrictionPowers) * 1.02;
}

// roundDirection < 0: round down
// roundDirection = 0: round to nearest (or away from 0 if halfway)
// roundDirection > 0: round up
- (NSInteger)indexForOffset:(CGFloat)offset round:(int)roundDirection {
    CGFloat unroundedIndex = -round(offset) / _parameters.width;
    NSInteger (^clamp)(NSInteger) = ^NSInteger(NSInteger i) {
        if (i < 0) {
            return 0;
        }
        if (i >= self->_parameters.count) {
            return self->_parameters.count - 1;
        }
        return i;
    };
    if (roundDirection < 0) {
        return clamp(floor(unroundedIndex));
    }
    if (roundDirection > 0) {
        return clamp(ceil(unroundedIndex));
    }
    return clamp(round(unroundedIndex));
}

- (void)setMomentumStage:(iTermSwipeStateMomentumStage)stage {
    DLog(@"setMomentumStage %@ for %@", @(stage), self);
    _momentumStage = stage;
    if (stage == iTermSwipeStateMomentumStagePositive) {
        _targetIndex = [self indexForOffset:self.squashedOffset round:-1];
    } else if (stage == iTermSwipeStateMomentumStageNegative) {
        _targetIndex = [self indexForOffset:self.squashedOffset round:1];
    } else {
        return;
    }
    // Clamp it
    _targetIndex = MAX(MIN(_targetIndex,
                           _parameters.currentIndex + 1),
                       _parameters.currentIndex - 1);
    assert(_targetIndex >= 0);
    assert(_targetIndex < _parameters.count);
    _momentum = [self momentumForDistance:[self offsetOfTargetIndex] - _rawOffset];
    DLog(@"Set target index to %@ given offset %@, width %@, stage %@. Set momentum to %@.",
         @(_targetIndex), @(self.squashedOffset), @(_parameters.width), @(stage), @(_momentum));
}

- (CGFloat)squashedOffset {
    const CGFloat relativeOffset = _rawOffset - _initialOffset;
    const CGFloat softMovementLimit = _parameters.width;
    const CGFloat wiggle = _parameters.width / 4.0;
    const CGFloat shifted = relativeOffset + softMovementLimit;
    const CGFloat squashedShifted = iTermSquash(shifted,
                                                softMovementLimit * 2,
                                                wiggle);
    const CGFloat squashedRelativeOffset = squashedShifted - softMovementLimit;
    const CGFloat squashed = squashedRelativeOffset + _initialOffset;
    DLog(@"Squash %0.0f (initial=%0.0f) -> %0.0f (width=%0.0f)", _rawOffset, _initialOffset, squashed, _parameters.width);
    return squashed;
}

@end
