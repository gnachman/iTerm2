//
//  NSSet+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/30/20.
//

#import "NSSet+iTerm.h"
#import "NSObject+iTerm.h"

@implementation NSSet (iTerm)

- (NSSet *)filteredSetUsingBlock:(BOOL (NS_NOESCAPE ^)(id anObject))block {
    NSMutableSet *result = [NSMutableSet set];
    [self enumerateObjectsUsingBlock:^(id  _Nonnull obj, BOOL * _Nonnull stop) {
        if (block(obj)) {
            [result addObject:obj];
        }
    }];
    return result;
}

- (NSSet *)mapWithBlock:(id (^NS_NOESCAPE)(id anObject))block {
    NSMutableSet *result = [NSMutableSet set];
    [self enumerateObjectsUsingBlock:^(id  _Nonnull obj, BOOL * _Nonnull stop) {
        id mapped = block(obj);
        if (mapped) {
            [result addObject:mapped];
        }
    }];
    return result;
}

- (NSSet *)flatMapWithBlock:(NSSet *(^)(id anObject))block {
    NSMutableSet *result = [NSMutableSet set];
    [self enumerateObjectsUsingBlock:^(id  _Nonnull obj, BOOL * _Nonnull stop) {
        id mapped = block(obj);
        if (!mapped) {
            return;
        }
        NSArray *array = [NSArray castFrom:mapped];
        if (array) {
            [result addObjectsFromArray:array];
            return;
        }
        NSSet *set = [NSSet castFrom:mapped];
        if (set) {
            [result addObjectsFromArray:set.allObjects];
            return;
        }
        [result addObject:mapped];
    }];
    return result;
}

- (id)anyObjectPassingTest:(BOOL (^)(id element))block {
    for (id object in self) {
        if (block(object)) {
            return object;
        }
    }
    return nil;
}

- (NSSet *)setByIntersectingWithSet:(NSSet *)other {
    NSMutableSet *intersection = [self mutableCopy];
    [intersection intersectSet:other];
    return intersection;
}

@end
