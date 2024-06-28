//
//  iTermMutableOrderedSet.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/27/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermOrderedSet<__covariant ObjectType> : NSObject

@property (nonatomic, readonly) NSUInteger count;
@property (nullable, nonatomic, readonly) ObjectType firstObject;
@property (nullable, nonatomic, readonly) ObjectType lastObject;
@property (nonatomic, readonly) NSArray<ObjectType> *array;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithComparator:(NSComparisonResult (^)(ObjectType, ObjectType))comparator NS_DESIGNATED_INITIALIZER;

- (void)enumerateObjectsUsingBlock:(void (NS_NOESCAPE ^)(ObjectType obj, NSUInteger idx, BOOL *stop))block;
- (BOOL)containsObject:(ObjectType)obj;
- (ObjectType)objectAtIndexedSubscript:(NSInteger)i;
- (NSUInteger)indexOfObject:(ObjectType)object
              inSortedRange:(NSRange)range
                    options:(NSBinarySearchingOptions)opts;

@end

// Like NSOrderedSet but fast for insertion.
// Believe it or not NSMutableOrderedSet is just an array plus a hash table
// which makes inserting at head very costly.
@interface iTermMutableOrderedSet<ObjectType> : iTermOrderedSet<ObjectType>

- (void)removeObjectsAtIndexes:(NSIndexSet *)indexes;
- (void)removeAllObjects;
- (BOOL)insertObject:(ObjectType)object;
- (void)removeObjectsInRange:(NSRange)range;

@end

NS_ASSUME_NONNULL_END
