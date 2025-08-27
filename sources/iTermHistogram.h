//
//  iTermHistogram.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/19/17.
//

#import <Foundation/Foundation.h>

#import "iTermMetalConfig.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermHistogram : NSObject

@property (nonatomic, readonly) NSString *stringValue;
@property (nonatomic, readonly) NSString *sparklines;
@property (nonatomic, readonly) NSString *stringForTabularDisplay;
@property (nonatomic, readonly) int64_t count;
@property (nonatomic) int reservoirSize;
@property (nonatomic, readonly) double mean;

@property (nonatomic, readonly) double sum;
@property (nonatomic, readonly) double min;
@property (nonatomic, readonly) double max;

- (void)addValue:(double)value;
- (void)mergeFrom:(iTermHistogram *)other;
- (double)valueAtNTile:(double)ntile;
- (NSString *)sparklineGraphWithPrecision:(int)precision
                               multiplier:(double)multiplier
                                    units:(NSString *)units;
- (void)clear;
// p=0.5 returns median, p=0.95 returns 95th percentile value
- (double)percentile:(double)p;
- (NSString *)graphString;

@end

NS_ASSUME_NONNULL_END

