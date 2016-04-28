//
//  iTermThroughputEstimator.h
//  iTerm2
//
//  Created by George Nachman on 4/26/16.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermThroughputEstimator : NSObject

// Gives the estimated throughput in bytes per second.
@property(nonatomic, readonly) NSInteger estimatedThroughput;

// The choice of these parameters has a strong influence on how throughput is estimated.
// Time is divided into buckets of duration `secondsPerbucket`, going back `historyDuration`
// seconds. As byte counts are added, they are placed in the current time bucket. For estimation,
// the most recent bucket is weighted twice as much as its predecessor, four times as
// much as the second-to-most-recent bucket, etc. Smaller buckets bias recent history more and also
// increase variance, especially if buckets approach having only values of 0 or 1.
- (instancetype)initWithHistoryOfDuration:(NSTimeInterval)historyDuration
                         secondsPerBucket:(NSTimeInterval)secondsPerBucket;

- (void)addByteCount:(NSInteger)count;

@end

NS_ASSUME_NONNULL_END
