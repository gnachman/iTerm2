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

@end

@interface NSMutableArray<ObjectType> (iTerm)
- (void)reverse;
- (void)removeObjectsPassingTest:(BOOL (^)(ObjectType anObject))block;
@end
