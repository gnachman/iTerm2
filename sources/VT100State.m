#import "VT100State.h"
#import "VT100StateTransition.h"

@interface VT100State()
@property(nonatomic, copy) NSString *name;
@end

@implementation VT100State {
    NSMutableDictionary *_transitions;
}

+ (instancetype)stateWithName:(NSString *)name identifier:(NSObject *)identifier {
    VT100State *state = [[[self alloc] initWithName:name] autorelease];
    state.identifier = identifier;
    return state;
}

- (instancetype)initWithName:(NSString *)name {
    self = [super init];
    if (self) {
        _name = [name copy];
        _transitions = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_name release];
    [_transitions release];
    [_identifier release];
    [_entryAction release];
    [_exitAction release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %@>", [self class], self, _name];
}

- (void)addStateTransitionForCharacter:(unsigned char)character
                                    to:(VT100State *)state
                            withAction:(VT100StateAction)action {
    _transitions[@(character)] = [VT100StateTransition transitionToState:state withAction:action];
}

- (void)addStateTransitionForCharacterRange:(NSRange)characterRange
                                         to:(VT100State *)state
                                 withAction:(VT100StateAction)action {
    for (int j = 0; j < characterRange.length; j++) {
        [self addStateTransitionForCharacter:j + characterRange.location
                                          to:state
                                  withAction:action];
    }
}

- (VT100StateTransition *)stateTransitionForCharacter:(unsigned char)character {
    return _transitions[@(character)];
}

@end
