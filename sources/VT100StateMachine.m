#import "VT100StateMachine.h"
#import "DebugLogging.h"
#import "VT100State.h"

@implementation VT100StateMachine {
    NSMutableArray *_states;
    VT100State *_currentState;  // weak
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _states = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_states release];
    [_userInfo release];
    [_groundState release];
    [super dealloc];
}

- (void)addState:(VT100State *)state {
    [_states addObject:state];
}

- (void)setGroundState:(VT100State *)groundState {
    [_groundState autorelease];
    _groundState = [groundState retain];
    if (!_currentState) {
        _currentState = _groundState;
    }
}

- (void)handleCharacter:(unsigned char)character {
    VT100StateTransition *transition = [_currentState stateTransitionForCharacter:character];
    DLog(@"Handle %c (0x%02x): transition from %@ to %@",
         character, character, _currentState, transition.toState);

    if (transition) {
        VT100State *toState = transition.toState;
        BOOL changingState = (toState != _currentState);

        if (changingState && _currentState.exitAction) {
            _currentState.exitAction(character);
        }

        if (transition.action) {
            transition.action(character);
        }

        if (changingState && toState.entryAction) {
            toState.entryAction(character);
        }

        _currentState = toState;
    }
}

- (id)copyWithZone:(NSZone *)zone {
    VT100StateMachine *theCopy = [[VT100StateMachine alloc] init];
    [theCopy.states addObjectsFromArray:self.states];
    theCopy.currentState = self.currentState;
    theCopy.groundState = self.groundState;
    return theCopy;
}

- (VT100State *)stateWithIdentifier:(NSObject *)identifier {
    for (VT100State *state in _states) {
        if ([state.identifier isEqual:identifier]) {
            return state;
        }
    }
    return nil;
}

@end

