#import <Foundation/Foundation.h>
#import "AATree.h"

@class IntervalTreeEntry;

@interface Interval : NSObject<NSCopying>
// Negative locations have special meaning. Don't use them.
@property(nonatomic, assign) long long location;
@property(nonatomic, assign) long long length;
@property(nonatomic, readonly) long long limit;

+ (instancetype)intervalWithLocation:(long long)location length:(long long)length;
+ (Interval *)maxInterval;
// One more than the largest value in the interval.
- (BOOL)intersects:(Interval *)other;
- (BOOL)isEqualToInterval:(Interval *)interval;

// Serialized value.
- (NSDictionary *)dictionaryValue;

@end

@protocol IntervalTreeImmutableObject<NSObject>
@property(nonatomic, readonly) IntervalTreeEntry *entry;

// Serialized value.
- (NSDictionary *)dictionaryValue;
@end

@protocol IntervalTreeObject <IntervalTreeImmutableObject, NSObject>
// Deserialize from dictionaryValue.
- (instancetype)initWithDictionary:(NSDictionary *)dict;

@property(nonatomic, weak) IntervalTreeEntry *entry;

// Serialized value.
- (NSDictionary *)dictionaryValue;

- (instancetype)copyOfIntervalTreeObject;

@end

@protocol IntervalTreeImmutableEntry<NSObject>
@property(nonatomic, readonly) Interval *interval;
@property(nonatomic, readonly) id<IntervalTreeImmutableObject> object;
@end

// A node in the interval tree will contain one or more entries, each of which has an interval and an object. All intervals should have the same location.
@interface IntervalTreeEntry : NSObject<IntervalTreeImmutableEntry>
@property(nonatomic, retain) Interval *interval;
@property(nonatomic, retain) id<IntervalTreeObject> object;

+ (IntervalTreeEntry *)entryWithInterval:(Interval *)interval object:(id<IntervalTreeObject>)object;
@end

@protocol IntervalTreeReading<NSObject>

@property(nonatomic, readonly) NSString *debugString;
- (NSArray<IntervalTreeImmutableObject> *)objectsInInterval:(Interval *)interval;
- (NSArray<IntervalTreeImmutableObject> *)allObjects;
- (BOOL)containsObject:(id<IntervalTreeImmutableObject>)object;

// Returns the object with the highest limit
- (NSArray<IntervalTreeImmutableObject> *)objectsWithLargestLimit;
// Returns the object with the smallest limit
- (NSArray<IntervalTreeImmutableObject> *)objectsWithSmallestLimit;

// Returns the object with the largest location
- (NSArray<IntervalTreeImmutableObject> *)objectsWithLargestLocation;

// Returns the object with the largest location before (but NOT AT) |location|.
- (NSArray<IntervalTreeImmutableObject> *)objectsWithLargestLocationBefore:(long long)location;

- (NSArray<IntervalTreeImmutableObject> *)objectsWithLargestLimitBefore:(long long)limit;
- (NSArray<IntervalTreeImmutableObject> *)objectsWithSmallestLimitAfter:(long long)limit;

// Enumerates backwards by location (NOT LIMIT)
- (NSEnumerator<IntervalTreeImmutableObject> *)reverseEnumeratorAt:(long long)start;

- (NSEnumerator<IntervalTreeImmutableObject> *)reverseLimitEnumeratorAt:(long long)start;
- (NSEnumerator<IntervalTreeImmutableObject> *)forwardLimitEnumeratorAt:(long long)start;
- (NSEnumerator<IntervalTreeImmutableObject> *)reverseLimitEnumerator;
- (NSEnumerator<IntervalTreeImmutableObject> *)forwardLimitEnumerator;

// Serialize, adding offset to interval locations (useful for taking the tail
// of an interval tree).
- (NSDictionary *)dictionaryValueWithOffset:(long long)offset;
@end


@interface IntervalTree : NSObject <AATreeDelegate, IntervalTreeReading, NSCopying>

@property(nonatomic, readonly) NSInteger count;
@property(nonatomic, readonly) NSString *debugString;

// Deserialize
- (instancetype)initWithDictionary:(NSDictionary *)dict;

// |object| should implement -hash.
- (void)addObject:(id<IntervalTreeObject>)object withInterval:(Interval *)interval;
- (void)removeObject:(id<IntervalTreeObject>)object;
- (NSArray<IntervalTreeObject> *)objectsInInterval:(Interval *)interval;
- (NSArray<IntervalTreeObject> *)allObjects;
- (BOOL)containsObject:(id<IntervalTreeObject>)object;

// Returns the object with the highest limit
- (NSArray<IntervalTreeObject> *)objectsWithLargestLimit;
// Returns the object with the smallest limit
- (NSArray<IntervalTreeObject> *)objectsWithSmallestLimit;

// Returns the object with the largest location
- (NSArray<IntervalTreeObject> *)objectsWithLargestLocation;

// Returns the object with the largest location before (but NOT AT) |location|.
- (NSArray<IntervalTreeObject> *)objectsWithLargestLocationBefore:(long long)location;

- (NSArray<IntervalTreeObject> *)objectsWithLargestLimitBefore:(long long)limit;
- (NSArray<IntervalTreeObject> *)objectsWithSmallestLimitAfter:(long long)limit;

// Enumerates backwards by location (NOT LIMIT)
- (NSEnumerator<IntervalTreeObject> *)reverseEnumeratorAt:(long long)start;

- (NSEnumerator<IntervalTreeObject> *)reverseLimitEnumeratorAt:(long long)start;
- (NSEnumerator<IntervalTreeObject> *)forwardLimitEnumeratorAt:(long long)start;
- (NSEnumerator<IntervalTreeObject> *)reverseLimitEnumerator;
- (NSEnumerator<IntervalTreeObject> *)forwardLimitEnumerator;

- (void)sanityCheck;

// Serialize, adding offset to interval locations (useful for taking the tail
// of an interval tree).
- (NSDictionary *)dictionaryValueWithOffset:(long long)offset;

@end

