//
//  MovingAverage.h
//  iTerm
//
//  Created by George Nachman on 7/28/13.
//
//

#import <Foundation/Foundation.h>

@interface MovingAverage : NSObject

@property(nonatomic, assign) double alpha;  // Initialized to 0.5. Small values make updates affect the moving average more.
@property(nonatomic, assign) double value;
@property(nonatomic, readonly) NSTimeInterval timeSinceTimerStarted;
@property(nonatomic, readonly) BOOL timerStarted;

- (void)startTimer;
- (void)pauseTimer;
- (void)resumeTimer;
- (void)addValue:(double)value;
- (BOOL)haveStartedTimer;
- (void)reset;

@end
