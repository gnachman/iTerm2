//
//  iTermSwipeState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/29/20.
//

#import "iTermSwipeState.h"
#import "iTermSwipeState+Private.h"

#import "DebugLogging.h"
#import "iTermSquash.h"

static const CGFloat gSwipeFriction = 0.1;

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

- (void)badStateTransition:(iTermScrollWheelStateMachineStateTransition)transition
                     event:(NSEvent *)event {
    ITBetaAssert(NO, @"Unexpected state transition %@ -> %@: %@", @(transition.before), @(transition.after), event);
    [self retire];
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
                    // A side note in issue 9591
                    break;
                case iTermScrollWheelStateMachineStateTouchAndHold:
                    [self badStateTransition:transition event:event];
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
                    [self badStateTransition:transition event:event];
                    break;
            }
            break;
    }
    return YES;
}

// To move by distance d in time T, we will move by m on each frame. Then m will be decreased by gSwipeFriction. This function calculates the initial value of m.
// More formally:
// v(t) = v(t - 1) * 0.9  (for t > 0)
// Solve for v(0), which is what this function returns.
//
// v(0) + 0.9*v(0) + 0.9*v(1) + ... + 0.9*v(T-1) = d
// v(0) * (0.9^0 + 0.9^1 + ... + 0.9^(T-1)) = d
// d / (0.9^0 + 0.9^1 + ... + 0.9^(T-1)) = v(0)
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
