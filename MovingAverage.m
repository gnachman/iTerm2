//
//  MovingAverage.m
//  iTerm
//
//  Created by George Nachman on 7/28/13.
//
//

#import "MovingAverage.h"

@implementation MovingAverage

@synthesize alpha = _alpha;
@synthesize value = _value;

- (id)init {
    self = [super init];
    if (self) {
        _alpha = 0.5;
    }
    return self;
}

- (void)startTimer {
    _time = [NSDate timeIntervalSinceReferenceDate];
}

- (NSTimeInterval)timeSinceTimerStarted {
    return [NSDate timeIntervalSinceReferenceDate] - _time;
}

- (void)addValue:(double)value {
    _value = _alpha * _value + (1.0 - _alpha) * value;
}

- (BOOL)haveStartedTimer {
    return _time > 0;
}

@end
