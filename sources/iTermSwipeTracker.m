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
    return !_liveState.isRetired;
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
        DLog(@"Not horizontal x=%0.2f y=%02.f", fabs(event.scrollingDeltaX), fabs(event.scrollingDeltaY));
        return NO; // Not horizontal
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
    CGFloat _offset;
    CGFloat _initialOffset;
    CGFloat _momentum;
    iTermScrollWheelStateMachineState _state;
    NSInteger _targetIndex;
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
    return [NSString stringWithFormat:@"<%@: %p width=%@ offset=%@ momentum=%@ state=%@ momentumStage=%@>",
            NSStringFromClass(self.class),
            self,
            @(_width),
            @(_offset),
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

    if (_offset < _initialOffset) {
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
            if (_offset == [self offsetOfTargetIndex]) {
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
                if ([self offsetIsAfterTargetIndex:_offset]) {
                    [self didCrossZero];
                    return;
                }
                [self retire];
                return;
            }
            if (![self offsetIsAfterTargetIndex:_offset]) {
                [self didCrossZero];
                return;
            }
            [self retire];
            return;
    }
}

- (void)applyForce:(CGFloat)force {
    DLog(@"Apply force %@ to %@", @(force), self);
    const CGFloat offsetBefore = _offset;
    _offset += _momentum;
    _momentum += force;
    DLog(@"After applying force: %@", self);
    if (([self offsetIsAfterTargetIndex:offsetBefore] && ![self offsetIsAfterTargetIndex:_offset]) ||
        (![self offsetIsAfterTargetIndex:offsetBefore] && [self offsetIsAfterTargetIndex:_offset])) {
        [self didCrossZero];
        return;
    }

    [self.swipeHandler swipeHandlerSetOffset:_offset forSession:self.userInfo];
    if ([self offsetIsAfterTargetIndex:_offset] && force < 0) {
        [self retire];
        return;
    }
    if (![self offsetIsAfterTargetIndex:_offset] && force > 0) {
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
    DLog(@"dragBy:%@ for %@", @(delta), self);
    _offset += delta;
    _momentum = delta;
    DLog(@"After drag: %@", self);
    [self.swipeHandler swipeHandlerSetOffset:_offset forSession:self.userInfo];
}

- (void)startDrag:(CGFloat)amount {
    DLog(@"startDrag:%@ for %@", @(amount), self);
    if (!_userInfo) {
        _initialOffset = _parameters.currentIndex * -_parameters.width;
        _offset = _initialOffset + amount;
        _userInfo = [self.swipeHandler swipeHandlerBeginSessionAtOffset:_initialOffset];
        if (fabs(_initialOffset - _offset) >= 1) {
            [self.swipeHandler swipeHandlerSetOffset:_offset forSession:_userInfo];
        }
        DLog(@"Set offset=%@ initialOffset=%@", @(_offset), @(_initialOffset));
    }
    assert(_userInfo);
    _momentum = amount;
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
    if (unroundedIndex == floor(unroundedIndex) || roundDirection < 0) {
        return clamp(floor(unroundedIndex));
    }
    return clamp(ceil(unroundedIndex));

}

- (void)setMomentumStage:(iTermSwipeStateMomentumStage)stage {
    DLog(@"setMomentumStage %@ for %@", @(stage), self);
    _momentumStage = stage;
    if (stage == iTermSwipeStateMomentumStagePositive) {
        _targetIndex = [self indexForOffset:_offset round:-1];
    } else if (stage == iTermSwipeStateMomentumStageNegative) {
        _targetIndex = [self indexForOffset:_offset round:1];
    }
    _momentum = [self momentumForDistance:[self offsetOfTargetIndex] - _offset];
    DLog(@"Set target index to %@ given offset %@, width %@, stage %@. Set momentum to %@.",
         @(_targetIndex), @(_offset), @(_parameters.width), @(stage), @(_momentum));
}

@end
