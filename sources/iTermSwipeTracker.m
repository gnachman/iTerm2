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
NSString *const iTermSwipeHandlerCancelSwipe = @"iTermSwipeHandlerCancelSwipe";

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
@property (nonatomic, readonly) NSTimeInterval actualInterval;

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
    CFTimeInterval _scheduledTime;
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

    _scheduledTime = CACurrentMediaTime();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_interval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf didFire];
    });
}

- (void)didFire {
    if (!_valid) {
        return;
    }
    _actualInterval = CACurrentMediaTime() - _scheduledTime;
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
@property (nonatomic, readonly) BOOL shouldTrack;

- (BOOL)handleEvent:(NSEvent *)event
         transition:(iTermScrollWheelStateMachineStateTransition)transition;

- (void)update:(NSTimeInterval)elapsedTime;

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
    return _liveState.shouldTrack;
}

- (BOOL)handleEvent:(NSEvent *)event {
    if (!event.window) {
        return NO;
    }
    DLog(@"Handle event before tracking loop: %@", event);
    const BOOL handled = [self internalHandleEvent:event];
    if (!handled) {
        DLog(@"Event not used");
        return NO;
    }

    if (![self shouldTrack]) {
        DLog(@"Not starting tracking loop");
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

    iTermScrollWheelStateMachineStateTransition transition = {
        .before = _stateMachine.state
    };
    [_stateMachine handleEvent:event];
    transition.after = _stateMachine.state;

    if (!_liveState || _liveState.isRetired) {
        if (fabs(event.scrollingDeltaX) < fabs(event.scrollingDeltaY)) {
            DLog(@"Not creating new state because not horizontal: %@", event);
            return NO;
        }
        if (transition.before != iTermScrollWheelStateMachineStateGround) {
            DLog(@"Not creating a new state because not starting in ground state");
            return NO;
        }
        return [self createStateForEventIfNeeded:event transition:transition];
    }
    return [_liveState handleEvent:event transition:transition];
}

- (BOOL)createStateForEventIfNeeded:(NSEvent *)event
                         transition:(iTermScrollWheelStateMachineStateTransition)transition {
    if (transition.before == iTermScrollWheelStateMachineStateStartDrag ||
        transition.after == iTermScrollWheelStateMachineStateDrag ||
        transition.after == iTermScrollWheelStateMachineStateGround) {
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
    DLog(@"Success - created a new live event");
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
    [_liveState update:timer.actualInterval];
    [self updateTimer];
}

@end

@implementation iTermSwipeState {
    // Set up at initialization time. If you drag-release-drag-again then the currentIndex gets
    // updated in place.
    iTermSwipeHandlerParameters _parameters;

    // Usually negative. How far to scroll the big container view. Can be extremely huge.
    // Use -squashedOffset, which is a not-too-huge value computed from this.
    CGFloat _rawOffset;

    // The offset where scrolling began. If you touch-up and touch-down then this can get updated.
    CGFloat _initialOffset;

    // Used when in the ground state to animate toward the destination frame. Gives the speed in
    // points per 1/60 sec.
    CGFloat _momentum;

    // Used to decipher NSEvents into meaningful things.
    iTermScrollWheelStateMachineState _state;

    // Which tab we are animating towards after drag while in ground state. Nil if no drag started.
    NSNumber *_targetIndexNumber;

    // When NO, ignore drags. When YES, animate in response to drags.
    BOOL _dragStarted;

    // Used to relate cancel notifications with the swipe state that's being canceled.
    NSString *_identifier;

    // While in the Scroll state while _dragStarted is NO, these grow for each scroll event until
    // we have enough info to decide if this is a vertical or horizontal scroll.
    CGFloat _preScrollAccumulatedDeltaX;
    CGFloat _preScrollAccumulatedDeltaY;
}

- (instancetype)initWithSwipeHandler:(id<iTermSwipeHandler>)handler {
    assert(handler);
    self = [super init];
    if (self) {
        _parameters = [handler swipeHandlerParameters];
        _identifier = [[NSUUID UUID] UUIDString];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cancelSwipe:)
                                                     name:iTermSwipeHandlerCancelSwipe
                                                   object:_identifier];
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
    return [NSString stringWithFormat:@"<%@: %p width=%@ offset=%@ (%@) momentum=%@ state=%@ momentumStage=%@ targetIndex=%@>",
            NSStringFromClass(self.class),
            self,
            @(_parameters.width),
            @(self.squashedOffset),
            @(_rawOffset),
            @(_momentum),
            @(_state),
            @(self.momentumStage),
            _targetIndexNumber];
}

- (void)cancelSwipe:(NSNotification *)notification {
    DLog(@"Cancel swipe by notification.\n%@", [NSThread callStackSymbols]);
    [self retire];
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
                                      atIndex:_targetIndexNumber ? _targetIndexNumber.integerValue : NSNotFound];
    _targetIndexNumber = nil;
}

- (CGFloat)offsetOfTargetIndex {
    assert(_targetIndexNumber);
    return _targetIndexNumber.integerValue * -_parameters.width;
}

- (BOOL)offsetIsAfterTargetIndex:(CGFloat)offset {
    assert(_targetIndexNumber);
    return offset > [self offsetOfTargetIndex];
}

- (void)update:(NSTimeInterval)elapsed {
    DLog(@"Update %@", self);
    assert(!_isRetired);
    const NSTimeInterval frameDuration = 1.0 / 60.0;
    const int iterations = MAX(1, floor(elapsed / frameDuration));
    DLog(@"Apply force %d times given elapsed time of %0.3f", iterations, elapsed);
    for (int i = 0; i < iterations && !self.isRetired; i++) {
        [self reallyUpdate];
    }
}

- (void)reallyUpdate {
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

- (BOOL)shouldDrag:(NSEvent *)event state:(iTermScrollWheelStateMachineState)state {
    if (_dragStarted) {
        if (state == iTermScrollWheelStateMachineStateStartDrag) {
            [self startDrag];
        }
        return YES;
    }
    _preScrollAccumulatedDeltaX += fabs(event.scrollingDeltaX);
    _preScrollAccumulatedDeltaY += fabs(event.scrollingDeltaY);

    // If you've moved at least 10 in the any direction and the accumulated slope is under this
    // value then we infer you meant to scroll vertically.
    const CGFloat slopeThreshold = 0.4;

    if ((_preScrollAccumulatedDeltaY + _preScrollAccumulatedDeltaX) >= 10 &&
        _preScrollAccumulatedDeltaY > slopeThreshold * _preScrollAccumulatedDeltaX) {
        [self retire];
        DLog(@"Abort: Accumulated pre-scroll deltas are dx=%0.1f dy=%0.1f",
             _preScrollAccumulatedDeltaX, _preScrollAccumulatedDeltaY);
        return NO;
    }
    if (_preScrollAccumulatedDeltaX > 10) {
        DLog(@"Start dragging: Accumulated pre-scroll deltas are dx=%0.1f dy=%0.1f",
             _preScrollAccumulatedDeltaX, _preScrollAccumulatedDeltaY);
        [self startDrag];
        _dragStarted = YES;
    } else {
        DLog(@"Not ready to drag yet: Accumulated pre-scroll deltas are dx=%0.1f dy=%0.1f",
             _preScrollAccumulatedDeltaX, _preScrollAccumulatedDeltaY);
    }
    return _dragStarted;
}

- (void)dragBy:(CGFloat)delta {
    DLog(@"dragBy:%@ for %@", @(delta), self);
    _rawOffset += delta;
    _momentum = delta;
    DLog(@"After drag: %@", self);
    [self.swipeHandler swipeHandlerSetOffset:self.squashedOffset forSession:self.userInfo];
}

- (BOOL)shouldTrack {
    if (_isRetired) {
        return NO;
    }
    return YES;
}

- (void)startDrag {
    DLog(@"startDrag for %@", self);
    if (!_userInfo) {
        _initialOffset = _parameters.currentIndex * -_parameters.width;
        _rawOffset = _initialOffset;
        _userInfo = [self.swipeHandler swipeHandlerBeginSessionAtOffset:_initialOffset
                                                             identifier:_identifier];
        if (fabs(_initialOffset - _rawOffset) >= 1) {
            [self.swipeHandler swipeHandlerSetOffset:self.squashedOffset forSession:_userInfo];
        }
        DLog(@"Set offset=%@ initialOffset=%@", @(self.squashedOffset), @(_initialOffset));
    } else {
        DLog(@"Resume existing session. Update raw & initial offsets");
        _parameters.currentIndex = [self indexForOffset:self.squashedOffset round:0];
        _initialOffset = _rawOffset;
    }
    assert(_userInfo);
    _momentum = 0;
    DLog(@"After starting drag: %@", self);
}

- (BOOL)handleEvent:(NSEvent *)event
         transition:(iTermScrollWheelStateMachineStateTransition)transition {
    DLog(@"handleEvent:%@ before=%@ after=%@ dy=%0.1f", iTermShortEventPhasesString(event), @(transition.before), @(transition.after), event.scrollingDeltaY);
    _state = transition.after;

    switch (transition.before) {
        case iTermScrollWheelStateMachineStateGround:
            switch (transition.after) {
                case iTermScrollWheelStateMachineStateStartDrag:
                case iTermScrollWheelStateMachineStateDrag:
                    self.momentumStage = iTermSwipeStateMomentumStageNone;
                    if ([self shouldDrag:event state:transition.after]) {
                        [self dragBy:event.scrollingDeltaX];
                    } else {
                        return NO;
                    }
                    break;
                case iTermScrollWheelStateMachineStateTouchAndHold:
                    break;
                case iTermScrollWheelStateMachineStateGround:
                    break;
            }
            break;
        case iTermScrollWheelStateMachineStateStartDrag:
            switch (transition.after) {
                case iTermScrollWheelStateMachineStateDrag:
                    if ([self shouldDrag:event state:transition.after]) {
                        [self dragBy:event.scrollingDeltaX];
                    } else {
                        return NO;
                    }
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
                case iTermScrollWheelStateMachineStateStartDrag:
                case iTermScrollWheelStateMachineStateDrag:
                    if ([self shouldDrag:event state:transition.after]) {
                        [self dragBy:event.scrollingDeltaX];
                    } else {
                        return NO;
                    }
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
                    if ([self shouldDrag:event state:transition.after]) {
                        [self dragBy:event.scrollingDeltaX];
                    } else {
                        return NO;
                    }
                    break;
                case iTermScrollWheelStateMachineStateGround:
                    if (!_dragStarted) {
                        [self retire];
                        return NO;
                    }
                    self.momentumStage = [self desiredMomentumStage];
                    assert(self.momentumStage != iTermSwipeStateMomentumStageNone);
                    break;
                case iTermScrollWheelStateMachineStateStartDrag:
                case iTermScrollWheelStateMachineStateTouchAndHold:
                    assert(NO);
                    break;
            }
            break;
    }
    return YES;
}

- (CGFloat)momentumForDistance:(CGFloat)distance {
    static CGFloat sumOfFrictionPowers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // This is only approximate because animation stops whens velocity drops under 1. The
        // actual duration could end up being quite a bit shorter than the target, especially
        // if the distance is small compared to the duration.
        const CGFloat desiredDuration = 0.125;
        const CGFloat framesPerSecond = 60;
        const CGFloat numberOfFrames = round(desiredDuration * framesPerSecond);
        sumOfFrictionPowers = 0;
        for (CGFloat i = 0; i < numberOfFrames; i += 1) {
            sumOfFrictionPowers += (pow(1 - gSwipeFriction, i));
            DLog(@"i=%d sum=%f", (int)i, sumOfFrictionPowers);
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
        _targetIndexNumber = @([self indexForOffset:self.squashedOffset round:-1]);
    } else if (stage == iTermSwipeStateMomentumStageNegative) {
        _targetIndexNumber = @([self indexForOffset:self.squashedOffset round:1]);
    } else {
        return;
    }
    // Clamp it
    _targetIndexNumber = @(MAX(MIN(_targetIndexNumber.integerValue,
                                   _parameters.currentIndex + 1),
                               _parameters.currentIndex - 1));
    assert(_targetIndexNumber.integerValue >= 0);
    assert(_targetIndexNumber.integerValue < _parameters.count);
    _momentum = [self momentumForDistance:[self offsetOfTargetIndex] - _rawOffset];
    DLog(@"Set target index to %@ given offset %@, width %@, stage %@. Set momentum to %@.",
         _targetIndexNumber, @(self.squashedOffset), @(_parameters.width), @(stage), @(_momentum));
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
    DLog(@"Squash %0.0f (initial=%0.0f) -> %0.0f (width=%0.0f)",
         _rawOffset, _initialOffset, squashed, _parameters.width);
    return squashed;
}

@end
