//
//  NSArray+iTerm.h
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import <Foundation/Foundation.h>
#import "NSArray+CommonAdditions.h"

@class iTermTuple;

@interface NSArray<ObjectType> (iTerm)

+ (NSArray<NSNumber *> *)sequenceWithRange:(NSRange)range;
+ (NSArray<NSString *> *)stringSequenceWithRange:(NSRange)range;
- (NSIndexSet *)it_indexSetWithIndexesOfObjects:(NSArray *)objects;
- (NSIndexSet *)it_indexSetWithObjectsPassingTest:(BOOL (^ NS_NOESCAPE)(ObjectType object))block;

- (NSArray<ObjectType> *)it_arrayByRemovingObjectsAtIndexes:(NSIndexSet *)indexes;

- (NSArray *)objectsOfClasses:(NSArray<Class> *)classes;
- (NSAttributedString *)attributedComponentsJoinedByAttributedString:(NSAttributedString *)joiner;

- (NSArray *)mapEnumeratedWithBlock:(id (^NS_NOESCAPE)(NSUInteger i, id object, BOOL *stop))block;
- (NSArray *)flatMapWithBlock:(NSArray *(^)(ObjectType anObject))block;

- (NSArray<ObjectType> *)flattenedArray;

- (id)reduceWithBlock:(id (^)(ObjectType first, ObjectType second))block;
- (id)reduceWithFirstValue:(id)firstValue block:(id (^)(id first, ObjectType second))block;

// Returns those elements of the array for which block(element) returns YES.
// block is called on every element in order.
- (NSArray *)filteredArrayUsingBlock:(BOOL (NS_NOESCAPE ^)(ObjectType anObject))block;
- (ObjectType)objectPassingTest:(BOOL (^)(ObjectType element, NSUInteger index, BOOL *stop))block;

// Returns the first object that is a kind of `theClass` for which block returns YES.
- (id)objectOfClass:(Class)theClass passingTest:(BOOL (^)(id element, NSUInteger index, BOOL *stop))block;

- (BOOL)anyWithBlock:(BOOL (^)(ObjectType anObject))block;
- (BOOL)allWithBlock:(BOOL (^)(ObjectType anObject))block;
- (ObjectType)maxWithComparator:(NSComparisonResult (^)(ObjectType a, ObjectType b))comparator;

// All objects equal to the minimum value.
- (NSArray *)minimumsWithComparator:(NSComparisonResult (^ NS_NOESCAPE)(id, id))comparator;
- (NSArray *)maximumsWithComparator:(NSComparisonResult (^ NS_NOESCAPE)(id, id))comparator;

// Does the array contain at least one object not equal to @c anObject?
- (BOOL)containsObjectBesides:(ObjectType)anObject;
- (BOOL)containsObjectBesidesObjectsInArray:(NSArray *)array;

// Returns an array by taking this one and removing the last object, if there
// is one.
- (NSArray<ObjectType> *)arrayByRemovingLastObject;
- (NSArray<ObjectType> *)arrayByRemovingFirstObject;

- (NSArray<ObjectType> *)arrayByRemovingObject:(ObjectType)objectToRemove;

// Hashes elements of class NSArray, NSString, NSNumber, and any other element
// that responds to hashWithDJB2. Other elements do not modify the hash.
- (NSUInteger)hashWithDJB2;
- (NSData *)hashWithSHA256;
- (BOOL)isEqualIgnoringOrder:(NSArray *)other;

// May reorder the whole array.
- (NSArray<ObjectType> *)arrayByRemovingDuplicates;

// Removes dups, does not reorder array.
- (NSArray<ObjectType> *)arrayByRemovingDuplicatesStably;

// Removes consecutive duplicates. Is stable.
- (NSArray<ObjectType> *)uniq;
- (NSArray<ObjectType> *)uniqWithComparator:(BOOL (^)(ObjectType obj1, ObjectType obj2))block;

// This must be an array of NSNumber*s with 32-bit int values.
// If self is @[ 1, 18 ] the output is @"0x1 0x12"
- (NSString *)numbersAsHexStrings;

// Returns one of:
// For N > 2 elements: @"element1, element2, ..., elementN-1, and elementN"
// For N=2 elements:   @"element1 and element2"
// For N=1 element:    @"element1"
// For N=0 elements:   @""
- (NSString *)componentsJoinedWithOxfordComma;
- (NSString *)componentsJoinedWithOxfordCommaAndConjunction:(NSString *)conjunction;

- (NSArray *)intersectArray:(NSArray *)other;

// Given a collection of file URLs return the file URL that is their deepest common ancestor.
// For example, given an input of:
// /a/b/c
// /a/b/c/d
// /a/b/x
//
// returns /a/b
- (NSURL *)lowestCommonAncestorOfURLs;

- (NSArray<ObjectType> *)subarrayToIndex:(NSUInteger)index;
- (NSArray<ObjectType> *)subarrayToIndexInclusive:(NSUInteger)index;

- (void)enumerateCoalescedObjectsWithComparator:(BOOL (^)(ObjectType obj1, ObjectType obj2))comparator
                                          block:(void (^)(ObjectType object, NSUInteger count))block;

- (NSArray<iTermTuple *> *)tuplesWithFirstObjectEqualTo:(id)firstObject;
- (NSDictionary<id, NSArray<ObjectType> *> *)classifyWithBlock:(id (^)(ObjectType))block;
- (NSDictionary<id, ObjectType> *)classifyUniquelyWithBlock:(id (^)(ObjectType))block;
- (ObjectType)uncheckedObjectAtIndex:(NSInteger)index;

- (NSUInteger)indexOfMaxWithBlock:(NSComparisonResult (^)(ObjectType obj1, ObjectType obj2))block;
- (ObjectType)maxWithBlock:(NSComparisonResult (^)(ObjectType obj1, ObjectType obj2))block;
- (ObjectType)minWithBlock:(NSComparisonResult (^)(ObjectType obj1, ObjectType obj2))block;
- (NSArray<ObjectType> *)it_arrayByDroppingLastN:(NSUInteger)n;
- (NSArray<ObjectType> *)it_arrayByKeepingFirstN:(NSUInteger)n;
- (NSArray<ObjectType> *)it_arrayByKeepingLastN:(NSUInteger)n;

- (NSArray *)countedInstancesStrings;
- (NSDictionary *)keyValuePairsWithBlock:(iTermTuple * (^)(ObjectType object))block;
- (id)it_jsonSafeValue;
- (instancetype)it_arrayByRemovingObjectsPassingTest:(BOOL (^)(ObjectType anObject))block;

- (NSArray<iTermTuple *> *)zip:(NSArray *)other;

- (double)sumOfNumbers;
- (NSArray *)it_arrayByReplacingOccurrencesOf:(id)pattern with:(id)replacement;
- (char **)nullTerminatedCStringArray;
- (NSArray<ObjectType> *)reversed;
+ (instancetype)mapIntegersFrom:(NSInteger)min to:(NSInteger)noninclusiveUpperBound block:(ObjectType (^NS_NOESCAPE)(NSInteger i))block;

- (NSArray *)arrayByStrongifyingWeakBoxes;
- (NSArray<ObjectType> *)arrayByRemovingNulls;

@end

void iTermFreeeNullTerminatedCStringArray(char **array);

@interface NSMutableArray<ObjectType> (iTerm)
- (void)reverse;
- (void)removeObjectsPassingTest:(BOOL (^)(ObjectType anObject))block;
@end

