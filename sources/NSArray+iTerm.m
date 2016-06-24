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

- (NSString *)componentsJoinedWithOxfordComma {
    if (self.count <= 1) {
        return [self firstObject];
    } else if (self.count == 2) {
        return [NSString stringWithFormat:@"%@ and %@", self[0], self[1]];
    } else {
        NSArray *namesWithCommas = [[self arrayByRemovingLastObject] mapWithBlock:^id(NSString *name) {
            return [name stringByInsertingTerminalPunctuation:@","];
        }];
        // Given an input of A B C and “x” “y” “z” then namesWithCommas will be
        // A, B, and “x,” “y,”
        return [[[namesWithCommas componentsJoinedByString:@" "] stringByAppendingString:@" and "] stringByAppendingString:self.lastObject];
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

@end
