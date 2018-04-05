//
//  iTermHistogram.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/19/17.
//

#import <Foundation/Foundation.h>

@interface iTermHistogram : NSObject

@property (nonatomic, readonly) NSString *stringValue;
@property (nonatomic, readonly) NSString *sparklines;
@property (nonatomic, readonly) int64_t count;

- (void)addValue:(double)value;
- (void)mergeFrom:(iTermHistogram *)other;
- (double)valueAtNTile:(double)ntile;
- (NSString *)sparklineGraphWithPrecision:(int)precision
                               multiplier:(double)multiplier
                                    units:(NSString *)units;
- (void)clear;

@end
