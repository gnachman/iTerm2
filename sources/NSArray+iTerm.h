//
//  NSArray+iTerm.h
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import <Foundation/Foundation.h>

@interface NSArray (iTerm)

- (NSArray *)objectsOfClasses:(NSArray<Class> *)classes;
- (NSAttributedString *)attributedComponentsJoinedByAttributedString:(NSAttributedString *)joiner;

// Returns an array where each object in self is replaced with block(object).
- (NSArray *)mapWithBlock:(id (^)(id anObject))block;

// Returns those elements of the array for which block(element) returns YES.
// block is called on every element in order.
- (NSArray *)filteredArrayUsingBlock:(BOOL (^)(id anObject))block;

// Does the array contain at least one object not equal to @c anObject?
- (BOOL)containsObjectBesides:(id)anObject;

@end

@interface NSMutableArray (iTerm)
- (void)reverse;
@end
