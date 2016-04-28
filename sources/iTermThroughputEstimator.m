//
//  iTermThroughputEstimator.m
//  iTerm2
//
//  Created by George Nachman on 4/26/16.
//
//

#import "iTermThroughputEstimator.h"

@implementation iTermThroughputEstimator {
    // Stores the number of bytes received in each bucket. The last bucket is
    // the most recent one. Always holds the same number of values.
    NSMutableArray<NSNumber *> *_buckets;

    // Values of arguments of initWithHistoryOfDuration:secondsPerBucket:.
    NSTimeInterval _historyDuration;
    NSTimeInterval _secondsPerBucket;

    // Time this object was created.
    NSTimeInterval _startTime;

    // The "time index" for the last bucket. The time index is the number of
    // seconds since `_startTime` divided by `_secondsPerBucket`. It equals the
    // number of buckets elapsed since object creation.
    NSInteger _lastTimeIndex;
}

- (instancetype)initWithHistoryOfDuration:(NSTimeInterval)historyDuration
                         secondsPerBucket:(NSTimeInterval)secondsPerBucket {
    self = [super init];
    if (self) {
        _buckets = [[NSMutableArray alloc] init];
        _historyDuration = historyDuration;
        _secondsPerBucket = secondsPerBucket;
        _startTime = [NSDate timeIntervalSinceReferenceDate];
        for (NSInteger i = 0; i < MAX(1, round(historyDuration / secondsPerBucket)); i++) {
            [_buckets addObject:@0];
        }
        assert(_buckets.count > 0);
    }
    return self;
}

- (void)dealloc {
    [_buckets release];
    [super dealloc];
}

- (NSInteger)estimatedThroughput {
    const double delta = [self eraseBucketsIfNeeded];
    const double timeSpentInCurrentBucket = fmod(delta, _secondsPerBucket);
    // We want to weight the current bucket in proportion to how much time it
    // has left so as not to under-count it, but to keep the variance from
    // getting out of control there's a cap on this weight.
    const double weightForCurrentBucket = MIN(10, _secondsPerBucket / timeSpentInCurrentBucket);
    const NSUInteger numberOfBuckets = _buckets.count;

    __block double weightedSum = 0;
    __block double weight = 1;
    [_buckets enumerateObjectsUsingBlock:^(NSNumber *_Nonnull number, NSUInteger index, BOOL *_Nonnull stop) {
        double value = [number doubleValue];
        if (index == numberOfBuckets - 1) {
//            NSLog(@"Time left in current bucket is %0.2f so increase value %0.0f by %0.0f to %0.0f",
//                  1.0 - timeSpentInCurrentBucket, value, 1.0 / weightForCurrentBucket, value / weightForCurrentBucket);
            value *= weightForCurrentBucket;
        }
        weightedSum += value * weight;
        weight *= 2;
    }];
    double averageValuePerBucket = weightedSum / (weight - 1.0);
    double estimatedThroughput = averageValuePerBucket / _secondsPerBucket;
//    NSLog(@"weightedSum=%0.0f averageValuePerBucket=%0.0f weight=%0.0f result=%0.0f %@",
//          weightedSum, averageValuePerBucket, weight, estimatedThroughput, _buckets);
    return estimatedThroughput;
}

- (void)addByteCount:(NSInteger)count {
    [self eraseBucketsIfNeeded];
    const NSUInteger numberOfBuckets = _buckets.count;

    NSNumber *lastNumber = _buckets.lastObject;
    NSNumber *newLastNumber = @(lastNumber.integerValue + count);
    [_buckets replaceObjectAtIndex:numberOfBuckets - 1 withObject:newLastNumber];
}

// Returns the amount of time since _startTime.
- (double)eraseBucketsIfNeeded {
    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    const NSTimeInterval delta = now - _startTime;
    const NSInteger timeIndex = floor(delta / _secondsPerBucket);
    const NSUInteger numberOfBuckets = _buckets.count;
    const NSInteger numberOfBucketsToErase = MIN(numberOfBuckets, timeIndex - _lastTimeIndex);
    _lastTimeIndex = timeIndex;
    [_buckets removeObjectsInRange:NSMakeRange(0, numberOfBucketsToErase)];
    for (NSInteger i = 0; i < numberOfBucketsToErase; i++) {
        [_buckets addObject:@0];
    }
    return delta;
}

@end
