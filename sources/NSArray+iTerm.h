//
//  NSArray+iTerm.h
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import <Foundation/Foundation.h>

@interface NSArray<ObjectType> (iTerm)

- (NSArray *)objectsOfClasses:(NSArray<Class> *)classes;
- (NSAttributedString *)attributedComponentsJoinedByAttributedString:(NSAttributedString *)joiner;

// Returns an array where each object in self is replaced with block(object).
- (NSArray *)mapWithBlock:(id (^)(ObjectType anObject))block;
- (NSArray *)flatMapWithBlock:(NSArray *(^)(ObjectType anObject))block;

// Returns those elements of the array for which block(element) returns YES.
// block is called on every element in order.
- (NSArray *)filteredArrayUsingBlock:(BOOL (^)(ObjectType anObject))block;
- (ObjectType)objectPassingTest:(BOOL (^)(ObjectType element, NSUInteger index, BOOL *stop))block;

// Returns the first object that is a kind of `theClass` for which block returns YES.
- (id)objectOfClass:(Class)theClass passingTest:(BOOL (^)(id element, NSUInteger index, BOOL *stop))block;

- (BOOL)anyWithBlock:(BOOL (^)(ObjectType anObject))block;
- (BOOL)allWithBlock:(BOOL (^)(ObjectType anObject))block;

// Does the array contain at least one object not equal to @c anObject?
- (BOOL)containsObjectBesides:(ObjectType)anObject;
- (BOOL)containsObjectBesidesObjectsInArray:(NSArray *)array;

// Joins array components with commas. If there are three or more elements then
// an "and" is inserted before the last element. If elements are quoted and the
// locale places commas inside quotation marks then commas are inserted inside
// the quotation marks.
- (NSString *)componentsJoinedWithOxfordComma;

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

@end

@interface NSMutableArray<ObjectType> (iTerm)
- (void)reverse;
- (void)removeObjectsPassingTest:(BOOL (^)(ObjectType anObject))block;
@end
