//
//  iTermSwipeState+Private.hj.h
//  iTerm2
//
//  Created by George Nachman on 4/29/20.
//

#import "iTermSwipeState.h"

NS_ASSUME_NONNULL_BEGIN

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

@interface iTermSwipeState ()
@property (nonatomic, readonly) BOOL shouldTrack;
@property (nonatomic, readonly) BOOL isRetired;
@property (nonatomic, readonly) iTermSwipeStateMomentumStage momentumStage;

- (BOOL)handleEvent:(NSEvent *)event
         transition:(iTermScrollWheelStateMachineStateTransition)transition;

- (void)update:(NSTimeInterval)elapsedTime;

@end

NS_ASSUME_NONNULL_END
