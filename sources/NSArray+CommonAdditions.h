//
//  NSArray+CommonAdditions.h
//  iTerm2
//
//  Created by George Nachman on 2/24/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSArray<ObjectType> (CommonAdditions)

- (NSArray<ObjectType> *)subarrayFromIndex:(NSUInteger)index;

// Returns an array where each object in self is replaced with block(object).
- (NSArray *)mapWithBlock:(id _Nullable (^NS_NOESCAPE)(ObjectType anObject))block;

@end

NS_ASSUME_NONNULL_END
