//
//  iTermCumulativeSumCache.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 14.10.18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Stores an array of non-decreasing positive integer values. Provides access to quickly:
// - Modify the first and last value
// - Append a value
// - Remove the first or last value
// - Locate the bucket whose range contains a value
// - Sum a subrange of values
@interface iTermCumulativeSumCache : NSObject<NSCopying>

@property (nonatomic) NSInteger offset;
@property (nonatomic, readonly) NSInteger sumOfAllValues;
@property (nonatomic, readonly) NSInteger count;

// Returns NSNotFound if the value is largest than the maximum
// Runs in O(log(N)) time for N=number of buckets.
- (NSInteger)indexContainingValue:(NSInteger)value;

// Debug version of the above
- (NSInteger)verboseIndexContainingValue:(NSInteger)value;

// Remove the first or last value in O(1) time.
- (void)removeFirstValue;
- (void)removeLastValue;

// Update the first or last value in O(1) time.
- (void)setLastValue:(NSInteger)value;
- (void)setFirstValue:(NSInteger)value;

// Add a value to the end in O(1) time.
- (void)appendValue:(NSInteger)value;

// Sum values in a range in O(1) time.
- (NSInteger)sumOfValuesInRange:(NSRange)range;

- (NSInteger)valueAtIndex:(NSInteger)index;
- (NSInteger)sumAtIndex:(NSInteger)index;
- (void)dump;

@end

NS_ASSUME_NONNULL_END
