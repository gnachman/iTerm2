#import <Foundation/Foundation.h>

// Called on state transition with the event (character) as its argument.
typedef void (^VT100StateAction)(unsigned char character);

@class VT100StateTransition;

@interface VT100State : NSObject

@property(nonatomic, readonly) NSString *name;
@property(nonatomic, retain) NSObject *identifier;
@property(nonatomic, copy) VT100StateAction entryAction;
@property(nonatomic, copy) VT100StateAction exitAction;

+ (instancetype)stateWithName:(NSString *)name identifier:(NSObject *)identifier;

- (void)addStateTransitionForCharacter:(unsigned char)character
                                    to:(VT100State *)state
                            withAction:(VT100StateAction)action;
- (void)addStateTransitionForCharacterRange:(NSRange)characterRange
                                         to:(VT100State *)state
                                 withAction:(VT100StateAction)action;
- (VT100StateTransition *)stateTransitionForCharacter:(unsigned char)character;


@end

