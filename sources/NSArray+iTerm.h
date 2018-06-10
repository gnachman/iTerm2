//
//  NSArray+iTerm.h
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import <Foundation/Foundation.h>

@class iTermTuple;

@interface NSArray<ObjectType> (iTerm)

+ (NSArray<NSNumber *> *)sequenceWithRange:(NSRange)range;

- (NSArray *)objectsOfClasses:(NSArray<Class> *)classes;
- (NSAttributedString *)attributedComponentsJoinedByAttributedString:(NSAttributedString *)joiner;

// Returns an array where each object in self is replaced with block(object).
- (NSArray *)mapWithBlock:(id (^)(ObjectType anObject))block;
- (NSArray *)flatMapWithBlock:(NSArray *(^)(ObjectType anObject))block;

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
- (NSArray *)mininumsWithComparator:(NSComparisonResult (^)(id, id))comparator;

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
- (BOOL)isEqualIgnoringOrder:(NSArray *)other;

// May reorder the whole array.
- (NSArray<ObjectType> *)arrayByRemovingDuplicates;

// This must be an array of NSNumber*s with 32-bit int values.
// If self is @[ 1, 18 ] the output is @"0x1 0x12"
- (NSString *)numbersAsHexStrings;

// Returns one of:
// For N > 2 elements: @"element1, element2, ..., elementN-1, and elementN"
// For N=2 elements:   @"element1 and element2"
// For N=1 element:    @"element1"
// For N=0 elements:   @""
- (NSString *)componentsJoinedWithOxfordComma;

- (NSArray *)intersectArray:(NSArray *)other;

// Given a collection of file URLs return the file URL that is their deepest common ancestor.
// For example, given an input of:
// /a/b/c
// /a/b/c/d
// /a/b/x
//
// returns /a/b
- (NSURL *)lowestCommonAncestorOfURLs;

- (NSArray<ObjectType> *)subarrayFromIndex:(NSUInteger)index;

- (void)enumerateCoalescedObjectsWithComparator:(BOOL (^)(ObjectType obj1, ObjectType obj2))comparator
                                          block:(void (^)(ObjectType object, NSUInteger count))block;

- (NSArray<iTermTuple *> *)tuplesWithFirstObjectEqualTo:(id)firstObject;
- (NSDictionary<id, NSArray<ObjectType> *> *)classifyWithBlock:(id (^)(ObjectType))block;
- (ObjectType)uncheckedObjectAtIndex:(NSInteger)index;

@end

@interface NSMutableArray<ObjectType> (iTerm)
- (void)reverse;
- (void)removeObjectsPassingTest:(BOOL (^)(ObjectType anObject))block;
@end
