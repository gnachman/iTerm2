//
//  MovingAverage.m
//  iTerm
//
//  Created by George Nachman on 7/28/13.
//
//

#import "MovingAverage.h"

@implementation MovingAverage {
    NSTimeInterval _time;  // Time when -startTimer was called, or 0 if stopped.
    NSTimeInterval _timePaused;  // Time at which -pauseTimer was called.
    BOOL _initialized;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _alpha = 0.5;
    }
    return self;
}

- (void)startTimer {
    _time = [NSDate timeIntervalSinceReferenceDate];
    _timePaused = 0;
}

- (BOOL)timerStarted {
    return _time > 0;
}

- (NSTimeInterval)timeSinceTimerStarted {
    if (_timePaused) {
        return _timePaused - _time;
    } else {
        return [NSDate timeIntervalSinceReferenceDate] - _time;
    }
}

- (void)addValue:(double)value {
    if (_initialized) {
        _value = _alpha * _value + (1.0 - _alpha) * value;
    } else {
        _initialized = YES;
        _value = value;
    }
}

- (BOOL)haveStartedTimer {
    return _time > 0;
}

- (void)pauseTimer {
    assert([self haveStartedTimer]);
    assert(_timePaused == 0);
    _timePaused = [NSDate timeIntervalSinceReferenceDate];
}

- (void)resumeTimer {
    assert(_timePaused > 0);
    assert(_time > 0);
    NSTimeInterval lengthOfPreviousRun = _timePaused - _time;
    _time = [NSDate timeIntervalSinceReferenceDate] - lengthOfPreviousRun;
    _timePaused = 0;
}

@end
