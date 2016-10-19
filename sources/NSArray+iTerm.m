//
//  NSArray+iTerm.m
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import "NSArray+iTerm.h"
#import "NSLocale+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSStringITerm.h"

@implementation NSArray (iTerm)

- (NSArray *)objectsOfClasses:(NSArray *)classes {
    NSMutableArray *result = [NSMutableArray array];
    for (NSObject *object in self) {
        for (Class validClass in classes) {
            if ([object isKindOfClass:validClass]) {
                [result addObject:object];
                break;
            }
        }
    }
    return result;
}

- (NSAttributedString *)attributedComponentsJoinedByAttributedString:(NSAttributedString *)joiner {
    NSMutableAttributedString *result = [[[NSMutableAttributedString alloc] init] autorelease];
    for (NSAttributedString *element in self) {
        [result appendAttributedString:element];
        if (element != self.lastObject) {
            [result appendAttributedString:joiner];
        }
    }
    return result;
}

- (NSArray *)mapWithBlock:(id (^)(id anObject))block {
    NSMutableArray *temp = [NSMutableArray array];
    for (id anObject in self) {
        id mappedObject = block(anObject);
        if (mappedObject) {
            [temp addObject:mappedObject];
        }
    }
    return temp;
}

- (NSArray *)flatMapWithBlock:(NSArray *(^)(id anObject))block {
    NSMutableArray *temp = [NSMutableArray array];
    for (id anObject in self) {
        NSArray *mappedObjects = block(anObject);
        if (mappedObjects) {
            [temp addObjectsFromArray:mappedObjects];
        }
    }
    return temp;
}

- (NSArray *)filteredArrayUsingBlock:(BOOL (^)(id anObject))block {
    NSIndexSet *indexes = [self indexesOfObjectsPassingTest:^BOOL(id  _Nonnull obj,
                                                                  NSUInteger idx,
                                                                  BOOL * _Nonnull stop) {
        return block(obj);
    }];
    return [self objectsAtIndexes:indexes];
}

- (id)objectPassingTest:(BOOL (^)(id element, NSUInteger index, BOOL *stop))block {
    NSUInteger index = [self indexOfObjectPassingTest:block];
    if (index == NSNotFound) {
        return nil;
    } else {
        return self[index];
    }
}

- (id)objectOfClass:(Class)theClass
        passingTest:(BOOL (^)(id element, NSUInteger index, BOOL *stop))block {
    NSUInteger index = [self indexOfObjectPassingTest:^BOOL(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj isKindOfClass:theClass]) {
            return block(obj, idx, stop);
        } else {
            return NO;
        }
    }];
    if (index == NSNotFound) {
        return nil;
    } else {
        return self[index];
    }
}


- (BOOL)anyWithBlock:(BOOL (^)(id anObject))block {
    for (id object in self) {
        if (block(object)) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)allWithBlock:(BOOL (^)(id anObject))block {
    BOOL foundException = NO;
    for (id object in self) {
        if (!block(object)) {
            foundException = YES;
            break;
        }
    }
    return !foundException;
}

- (BOOL)containsObjectBesides:(id)anObject {
    for (id object in self) {
        if (![object isEqual:anObject]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)containsObjectBesidesObjectsInArray:(NSArray *)array {
    for (id object in self) {
        if (![array containsObject:object]) {
            return YES;
        }
    }
    return NO;
}

- (NSArray *)arrayByRemovingLastObject {
    if (self.count <= 1) {
        return @[];
    } else {
        return [self subarrayWithRange:NSMakeRange(0, self.count - 1)];
    }
}

- (NSArray *)arrayByRemovingFirstObject {
    if (self.count <= 1) {
        return @[];
    } else {
        return [self subarrayWithRange:NSMakeRange(1, self.count - 1)];
    }
}

- (NSString *)componentsJoinedWithOxfordComma {
    if (self.count == 0) {
        return @"";
    } else if (self.count == 1) {
        return [self firstObject];
    } else if (self.count == 2) {
        return [self componentsJoinedByString:@" and "];
    } else {
        NSArray *allButLastArray = [self subarrayWithRange:NSMakeRange(0, self.count - 1)];
        NSString *allButLastString = [allButLastArray componentsJoinedByString:@", "];
        NSString *result = [NSString stringWithFormat:@"%@, and %@", allButLastString, self.lastObject];
        return result;
    }
}

- (NSArray *)subarrayToIndex:(NSUInteger)index {
    return [self subarrayWithRange:NSMakeRange(0, index)];
}

- (NSArray *)subarrayFromIndex:(NSUInteger)index {
    NSUInteger length;
    if (self.count >= index) {
        length = self.count - index;
    } else {
        length = 0;
    }
    return [self subarrayWithRange:NSMakeRange(index, length)];
}

- (NSArray *)arrayByRemovingObject:(id)objectToRemove {
    NSUInteger index = [self indexOfObject:objectToRemove];
    if (index == NSNotFound) {
        return self;
    } else {
        return [[self subarrayToIndex:index] arrayByAddingObjectsFromArray:[self subarrayFromIndex:index + 1]];
    }

}

- (NSUInteger)hashWithDJB2 {
    NSUInteger hash = 5381;
    for (id object in self) {
        NSUInteger objectHash = 0;
        if ([object respondsToSelector:@selector(hashWithDJB2)]) {
            // This handles string and other arrays, at least.
            objectHash = [object hashWithDJB2];
        } else if ([object isKindOfClass:[NSNumber class]]) {
            objectHash = [object unsignedIntegerValue];
        }
        hash = (hash * 33) ^ objectHash;
    }
    return hash;
}

- (BOOL)isEqualIgnoringOrder:(NSArray *)other {
    NSSet *mySet = [[[NSCountedSet alloc] initWithArray:self] autorelease];
    NSSet *otherSet = [[[NSCountedSet alloc] initWithArray:other] autorelease];
    return [mySet isEqual:otherSet];
}

- (NSArray *)arrayByRemovingDuplicates {
    return [[[[NSSet alloc] initWithArray:self] autorelease] allObjects];
}

- (NSString *)numbersAsHexStrings {
    NSMutableString *result = [NSMutableString string];
    NSString *separator = @"";
    for (NSNumber *number in self) {
        if (![number isKindOfClass:[NSNumber class]]) {
            continue;
        }
        [result appendFormat:@"%@0x%x", separator, number.intValue];
        separator = @" ";
    }
    return result;
}

- (NSArray *)intersectArray:(NSArray *)other {
    NSMutableArray *intersection = [NSMutableArray array];
    for (id obj in self) {
        if ([other containsObject:obj]) {
            [intersection addObject:obj];
        }
    }
    return intersection;
}

@end

@implementation NSMutableArray (iTerm)

- (void)reverse {
    if ([self count] == 0) {
        return;
    }
    NSUInteger i = 0;
    NSUInteger j = [self count] - 1;
    while (i < j) {
        [self exchangeObjectAtIndex:i withObjectAtIndex:j];
        i++;
        j--;
    }
}

- (void)removeObjectsPassingTest:(BOOL (^)(id anObject))block {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    [self enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (block(obj)) {
            [indexes addIndex:idx];
        }
    }];
    [self removeObjectsAtIndexes:indexes];
}

@end
