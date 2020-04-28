//
//  iTermScrollWheelStateMachine.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/26/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, iTermScrollWheelStateMachineState) {
    iTermScrollWheelStateMachineStateGround,
    iTermScrollWheelStateMachineStateStartDrag,
    iTermScrollWheelStateMachineStateDrag,
    iTermScrollWheelStateMachineStateTouchAndHold,
};

extern NSString *iTermShortEventPhasesString(NSEvent *event);

@interface iTermScrollWheelStateMachine : NSObject
@property (nonatomic, readonly) iTermScrollWheelStateMachineState state;

- (void)handleEvent:(NSEvent *)event;

@end

NS_ASSUME_NONNULL_END
