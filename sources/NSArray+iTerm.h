//
//  NSArray+iTerm.h
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import <Foundation/Foundation.h>

@interface NSArray (iTerm)

- (NSArray *)objectsOfClasses:(NSArray *)classes;
- (NSAttributedString *)attributedComponentsJoinedByAttributedString:(NSAttributedString *)joiner;

// Returns an array where each object in self is replaced with block(object).
- (NSArray *)mapWithBlock:(id (^)(id anObject))block;

@end
