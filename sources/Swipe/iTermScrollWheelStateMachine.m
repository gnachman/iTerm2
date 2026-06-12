//
//  iTermScrollWheelStateMachine.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/26/20.
//

#import "iTermScrollWheelStateMachine.h"

#import "DebugLogging.h"

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

static BOOL EqualPhases(NSEventPhase lhs, NSEventPhase rhs) {
    if (rhs == 0) {
        return lhs == 0;
    }
    return !!(lhs & rhs);
}

- (void)handleEvent:(NSEvent *)event {
    static struct {
        iTermScrollWheelStateMachineState fromState;
        NSEventPhase phase;
        NSEventPhase momentumPhase;
        iTermScrollWheelStateMachineState toState;
    } transitions[] = {
        { iTermScrollWheelStateMachineStateGround,
            NSEventPhaseBegan,
            NSEventPhaseNone,
            iTermScrollWheelStateMachineStateStartDrag },
        { iTermScrollWheelStateMachineStateGround,
            NSEventPhaseMayBegin,
            NSEventPhaseNone,
            iTermScrollWheelStateMachineStateTouchAndHold },
        { iTermScrollWheelStateMachineStateGround,
            NSEventPhaseNone,
            NSEventPhaseChanged,
            iTermScrollWheelStateMachineStateGround },
        // I'm not sure what this is or why it only happens sometimes. TODO
        { iTermScrollWheelStateMachineStateGround,
            NSEventPhaseNone,
            NSEventPhaseBegan,
            iTermScrollWheelStateMachineStateGround },
        { iTermScrollWheelStateMachineStateGround,
            NSEventPhaseNone,
            NSEventPhaseEnded,
            iTermScrollWheelStateMachineStateGround },
        { iTermScrollWheelStateMachineStateGround,
            NSEventPhaseChanged,
            NSEventPhaseNone,
            iTermScrollWheelStateMachineStateGround },
        { iTermScrollWheelStateMachineStateGround,
            NSEventPhaseEnded,
            NSEventPhaseNone,
            iTermScrollWheelStateMachineStateGround },


        { iTermScrollWheelStateMachineStateStartDrag,
            NSEventPhaseChanged,
            NSEventPhaseNone,
            iTermScrollWheelStateMachineStateDrag },
        { iTermScrollWheelStateMachineStateStartDrag,
            NSEventPhaseEnded,
            NSEventPhaseNone,
            iTermScrollWheelStateMachineStateGround },


        { iTermScrollWheelStateMachineStateDrag,
            NSEventPhaseEnded,
            NSEventPhaseNone,
            iTermScrollWheelStateMachineStateGround },
        { iTermScrollWheelStateMachineStateDrag,
            NSEventPhaseChanged,
            NSEventPhaseNone,
            iTermScrollWheelStateMachineStateDrag },
        { iTermScrollWheelStateMachineStateDrag,
            NSEventPhaseNone,
            NSEventPhaseChanged,
            iTermScrollWheelStateMachineStateGround },


        { iTermScrollWheelStateMachineStateTouchAndHold,
            NSEventPhaseBegan,
            NSEventPhaseNone,
            iTermScrollWheelStateMachineStateStartDrag },
        { iTermScrollWheelStateMachineStateTouchAndHold,
            NSEventPhaseCancelled,
            NSEventPhaseNone,
            iTermScrollWheelStateMachineStateGround }
    };
    const iTermScrollWheelStateMachineState initialState = self.state;
    const NSEventPhase phase = event.phase;
    const NSEventPhase momentumPhase = event.momentumPhase;
    for (int i = 0; i < sizeof(transitions) / sizeof(*transitions); i++) {
        if (initialState != transitions[i].fromState) {
            continue;
        }
        if (!EqualPhases(phase, transitions[i].phase)) {
            continue;
        }
        if (!EqualPhases(momentumPhase, transitions[i].momentumPhase)) {
            continue;
        }
        self.state = transitions[i].toState;
        return;
    }
    [self unexpectedEvent:event];
}

- (void)unexpectedEvent:(NSEvent *)event {
    DLog(@"Ignore unexpected event in state %@: %@",
         [self stateString:self.state], iTermShortEventPhasesString(event));
}

- (void)setState:(iTermScrollWheelStateMachineState)state {
    DLog(@"setState %@ -> %@", [self stateString:_state], [self stateString:state]);
    _state = state;
}

@end
