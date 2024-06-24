//
//  BTree.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermSortedBag<__covariant ObjectType> : NSObject<NSFastEnumeration>

@property (nonatomic, readonly, nullable) ObjectType firstObject;
@property (nonatomic, readonly, nullable) ObjectType lastObject;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) NSArray<ObjectType> *array;

- (BOOL)containsObject:(ObjectType)object;
- (NSInteger)indexOfObject:(ObjectType)object
                            options:(NSBinarySearchingOptions)options
                         comparator:(BOOL (^)(ObjectType, ObjectType))comparator;
- (nullable ObjectType)objectAtIndex:(NSInteger)index;
- (ObjectType)objectAtIndexedSubscript:(NSUInteger)idx;
- (void)enumerateObjectsUsingBlock:(void (NS_NOESCAPE ^)(id obj,
                                                         NSUInteger idx,
                                                         BOOL *stop))block;

@end

@interface iTermMutableSortedBag<ObjectType>: iTermSortedBag<ObjectType>

- (void)insertObject:(ObjectType)object;
- (void)removeAllObjects;
- (void)removeObjectsAtIndexes:(NSIndexSet *)indexSet;
- (void)removeObjectsInRange:(NSRange)range;

@end

NS_ASSUME_NONNULL_END
