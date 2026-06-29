#import <Foundation/Foundation.h>
#import "VT100StateTransition.h"
#import "VT100State.h"

@interface VT100StateMachine : NSObject<NSCopying>

@property(nonatomic, strong) VT100State *groundState;
@property(nonatomic, weak) VT100State *currentState;
@property(nonatomic, readonly) NSMutableArray *states;
@property(nonatomic, strong) NSDictionary *userInfo;

- (void)addState:(VT100State *)state;
- (void)handleCharacter:(unsigned char)character;
- (VT100State *)stateWithIdentifier:(NSObject *)identifier;

@end

