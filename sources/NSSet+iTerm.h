//
//  NSSet+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/30/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSSet<ObjectType> (iTerm)

- (NSSet *)filteredSetUsingBlock:(BOOL (NS_NOESCAPE ^)(ObjectType anObject))block;
- (NSSet *)mapWithBlock:(id (^NS_NOESCAPE)(ObjectType anObject))block;
- (NSSet *)flatMapWithBlock:(NSSet *(^)(ObjectType anObject))block;
- (ObjectType _Nullable)anyObjectPassingTest:(BOOL (^)(ObjectType element))block;
- (NSSet<ObjectType> *)setByIntersectingWithSet:(NSSet<ObjectType> *)other;

@end

NS_ASSUME_NONNULL_END
