//
//  MovingAverage.h
//  iTerm
//
//  Created by George Nachman on 7/28/13.
//
//

#import <Foundation/Foundation.h>

@interface MovingAverage : NSObject {
    double _alpha;
    double _value;
    NSTimeInterval _time;  // Time when -startTimer was called, or 0 if stopped.
    NSTimeInterval _timePaused;  // Time at which -pauseTimer was called.
}

@property (nonatomic, assign) double alpha;  // Initialized to 0.5. Small values make updates affect the moving average more.
@property (nonatomic, assign) double value;

- (void)startTimer;
- (void)pauseTimer;
- (void)resumeTimer;
@property (readonly) NSTimeInterval timeSinceTimerStarted;
- (void)addValue:(double)value;
- (BOOL)haveStartedTimer;

@end
