#import <Foundation/Foundation.h>
#import "AATree.h"

@class IntervalTreeEntry;

@interface Interval : NSObject
// Negative locations have special meaning. Don't use them.
@property(nonatomic, assign) long long location;
@property(nonatomic, assign) long long length;

+ (Interval *)intervalWithLocation:(long long)location length:(long long)length;
+ (Interval *)maxInterval;
// One more than the largest value in the interval.
- (long long)limit;
- (BOOL)intersects:(Interval *)other;

@end

@protocol IntervalTreeObject <NSObject>
@property(nonatomic, assign) IntervalTreeEntry *entry;
@end

// A node in the interval tree will contain one or more entries, each of which has an interval and an object. All intervals should have the same location.
@interface IntervalTreeEntry : NSObject
@property(nonatomic, retain) Interval *interval;
@property(nonatomic, retain) id<IntervalTreeObject> object;

+ (IntervalTreeEntry *)entryWithInterval:(Interval *)interval object:(id<IntervalTreeObject>)object;
@end

@interface IntervalTreeValue : NSObject
@property(nonatomic, assign) long long maxLimitAtSubtree;
@property(nonatomic, retain) NSMutableArray *entries;

// Largest limit of all entries
- (long long)maxLimit;

// Interval including intervals of all entries at this entry exactly
- (Interval *)spanningInterval;

@end

@interface IntervalTree : NSObject <AATreeDelegate> {
  AATree *_tree;
}

// |object| should implement -hash.
- (void)addObject:(id<IntervalTreeObject>)object withInterval:(Interval *)interval;
- (void)removeObject:(id<IntervalTreeObject>)object;
- (NSArray *)objectsInInterval:(Interval *)interval;
- (NSArray *)allObjects;
- (NSInteger)count;
- (BOOL)containsObject:(id<IntervalTreeObject>)object;

@end
