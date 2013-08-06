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
    NSTimeInterval _time;
}

@property (nonatomic, assign) double alpha;  // Initialized to 0.5.
@property (nonatomic, assign) double value;

- (void)startTimer;
- (NSTimeInterval)timeSinceTimerStarted;
- (void)addValue:(double)value;
- (BOOL)haveStartedTimer;

@end
