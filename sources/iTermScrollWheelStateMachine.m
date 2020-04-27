//
//  iTermScrollWheelStateMachine.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/26/20.
//

#import "iTermScrollWheelStateMachine.h"

#import "DebugLogging.h"

#warning DNS
#undef DLog
#define DLog NSLog

@interface iTermScrollWheelStateMachine()
@property (nonatomic, readwrite) iTermScrollWheelStateMachineState state;
@end

@implementation iTermScrollWheelStateMachine

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p state=%@>", NSStringFromClass(self.class), self, [self stateString:self.state]];
}

- (NSString *)stateString:(iTermScrollWheelStateMachineState)state {
    switch (state) {
        case iTermScrollWheelStateMachineStateGround:
            return @"Ground";
        case iTermScrollWheelStateMachineStateStartDrag:
            return @"StartDrag";
        case iTermScrollWheelStateMachineStateDrag:
            return @"Drag";
        case iTermScrollWheelStateMachineStateTouchAndHold:
            return @"TouchAndHold";
        case iTermScrollWheelStateMachineStateMomentum:
            return @"Momentum";
    }
    return [@(self.state) stringValue];
}

static NSString *iTermStringForEventPhase(NSEventPhase eventPhase) {
    NSMutableArray<NSString *> *phase = [NSMutableArray array];
    if (eventPhase & NSEventPhaseBegan) {
        [phase addObject:@"Began"];
    }
    if (eventPhase & NSEventPhaseEnded) {
        [phase addObject:@"Ended"];
    }
    if (eventPhase & NSEventPhaseChanged) {
        [phase addObject:@"Changed"];
    }
    if (eventPhase & NSEventPhaseCancelled) {
        [phase addObject:@"Cancelled"];
    }
    if (eventPhase & NSEventPhaseStationary) {
        [phase addObject:@"Stationary"];
    }
    if (eventPhase & NSEventPhaseMayBegin) {
        [phase addObject:@"MayBegin"];
    }
    if (!phase.count) {
        [phase addObject:@"None"];
    }
    return [phase componentsJoinedByString:@"|"];
}

NSString *iTermShortEventPhasesString(NSEvent *event) {
    return [NSString stringWithFormat:@"<NSEvent: %p phase=%@, momentumPhase=%@, scrollingDeltaX=%f>",
            event,
            iTermStringForEventPhase(event.phase),
            iTermStringForEventPhase(event.momentumPhase),
            event.scrollingDeltaX];
}

- (void)handleEvent:(NSEvent *)event {
    DLog(@"handleEvent:%@ for %@", iTermShortEventPhasesString(event), self);
    switch (self.state) {
        case iTermScrollWheelStateMachineStateGround:
            if (!!(event.phase & NSEventPhaseBegan) && (event.momentumPhase == NSEventPhaseNone)) {
                self.state = iTermScrollWheelStateMachineStateStartDrag;
                return;
            }
            if (!!(event.phase & NSEventPhaseMayBegin) && (event.momentumPhase == NSEventPhaseNone)) {
                self.state = iTermScrollWheelStateMachineStateTouchAndHold;
                return;
            }
            if ((event.phase == NSEventPhaseNone) && !!(event.momentumPhase & NSEventPhaseChanged)) {
//                self.state = iTermScrollWheelStateMachineStateMomentum;
                self.state = iTermScrollWheelStateMachineStateGround;
                return;
            }
            if ((event.phase == NSEventPhaseNone) && !!(event.momentumPhase & NSEventPhaseBegan)) {
                // I'm not sure what this is or why it only happens sometimes. TODO
//                self.state = iTermScrollWheelStateMachineStateMomentum;
                self.state = iTermScrollWheelStateMachineStateGround;
                return;
            }
            if ((event.phase == NSEventPhaseNone) && !!(event.momentumPhase & NSEventPhaseEnded)) {
                self.state = iTermScrollWheelStateMachineStateGround;
                return;
            }
            return;
        case iTermScrollWheelStateMachineStateStartDrag:
            if (!!(event.phase & NSEventPhaseChanged) && (event.momentumPhase == NSEventPhaseNone)) {
                self.state = iTermScrollWheelStateMachineStateDrag;
                return;
            }
            [self unexpectedEvent:event];
            return;
        case iTermScrollWheelStateMachineStateDrag:
            if (!!(event.phase & NSEventPhaseEnded) && (event.momentumPhase == NSEventPhaseNone)) {
                self.state = iTermScrollWheelStateMachineStateGround;
                return;
            }
            if (!!(event.phase & NSEventPhaseChanged) && (event.momentumPhase == NSEventPhaseNone)) {
                self.state = iTermScrollWheelStateMachineStateDrag;
                return;
            }
            [self unexpectedEvent:event];
            return;
        case iTermScrollWheelStateMachineStateTouchAndHold:
            if (!!(event.phase & NSEventPhaseBegan) && (event.momentumPhase == NSEventPhaseNone)) {
                self.state = iTermScrollWheelStateMachineStateStartDrag;
                return;
            }
            if (!!(event.phase & NSEventPhaseCancelled) && (event.momentumPhase == NSEventPhaseNone)) {
                self.state = iTermScrollWheelStateMachineStateGround;
                return;
            }
            [self unexpectedEvent:event];
            return;
        case iTermScrollWheelStateMachineStateMomentum:
            assert(NO);
//            if ((event.phase == NSEventPhaseNone) && !!(event.momentumPhase & NSEventPhaseChanged)) {
//                self.state = iTermScrollWheelStateMachineStateMomentum;
//                return;
//            }
//            if ((event.phase == NSEventPhaseNone) && !!(event.momentumPhase & NSEventPhaseEnded)) {
//                self.state = iTermScrollWheelStateMachineStateGround;
//                return;
//            }
//            [self unexpectedEvent:event];
//            return;
    }
}

- (void)unexpectedEvent:(NSEvent *)event {
    DLog(@"Ignore unexpected event in state %@: %@", @(self.state), iTermShortEventPhasesString(event));
}

- (void)setState:(iTermScrollWheelStateMachineState)state {
    DLog(@"setState %@ -> %@", [self stateString:_state], [self stateString:state]);
    _state = state;
}

@end
