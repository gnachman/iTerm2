//
//  NSArray+iTerm.m
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import "NSArray+iTerm.h"

#import "iTermMalloc.h"
#import "iTermTuple.h"
#import "iTermWeakBox.h"
#import "NSData+iTerm.h"
#import "NSLocale+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

@implementation NSArray (iTerm)

+ (instancetype)mapIntegersFrom:(NSInteger)min to:(NSInteger)noninclusiveUpperBound block:(id (^NS_NOESCAPE)(NSInteger i))block {
    assert(min <= noninclusiveUpperBound);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:noninclusiveUpperBound - min];
    for (NSInteger i = min; i < noninclusiveUpperBound; i++) {
        id obj = block(i);
        if (obj) {
            [result addObject:obj];
        }
    }
    return result;
}

- (NSIndexSet *)it_indexSetWithIndexesOfObjects:(NSArray *)objects {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (id object in objects) {
        const NSInteger index = [self indexOfObject:object];
        if (index == NSNotFound) {
            continue;
        }
        [indexes addIndex:index];
    }
    return indexes;
}

- (NSIndexSet *)it_indexSetWithObjectsPassingTest:(BOOL (^ NS_NOESCAPE)(id))block {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    [self enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (block(obj)) {
            [indexes addIndex:idx];
        }
    }];
    return indexes;
}

+ (NSArray<NSNumber *> *)sequenceWithRange:(NSRange)range {
    NSMutableArray<NSNumber *> *temp = [NSMutableArray array];
    for (NSUInteger i = 0; i < range.length; i++) {
        [temp addObject:@(i + range.location)];
    }
    return temp;
}

+ (NSArray<NSString *> *)stringSequenceWithRange:(NSRange)range {
    NSMutableArray<NSString *> *temp = [NSMutableArray array];
    for (NSUInteger i = 0; i < range.length; i++) {
        [temp addObject:[@(i + range.location) stringValue]];
    }
    return temp;
}

- (NSArray *)it_arrayByRemovingObjectsAtIndexes:(NSIndexSet *)indexes {
    NSMutableArray *result = [self mutableCopy];
    [result removeObjectsAtIndexes:indexes];
    return [result autorelease];
}

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

- (NSArray *)mapEnumeratedWithBlock:(id (^NS_NOESCAPE)(NSUInteger, id anObject, BOOL *stop))block {
    NSMutableArray *temp = [NSMutableArray array];
    [self enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        id mappedObject = block(idx, obj, stop);
        if (mappedObject) {
            [temp addObject:mappedObject];
        }
    }];
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

- (NSArray *)flattenedArray {
    NSMutableArray *result = [NSMutableArray array];
    for (id object in self) {
        if ([object isKindOfClass:[NSArray class]]) {
            [result addObjectsFromArray:object];
        } else {
            [result addObject:object];
        }
    }
    return result;
}

- (NSArray *)filteredArrayUsingBlock:(BOOL (^NS_NOESCAPE)(id))block {
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

- (id)maxWithComparator:(NSComparisonResult (^)(id, id))comparator {
    id max = nil;
    for (id object in self) {
        if (max == nil || comparator(max, object) == NSOrderedAscending) {
            max = object;
        }
    }
    return max;
}

- (NSArray *)minimumsWithComparator:(NSComparisonResult (^ NS_NOESCAPE)(id, id))comparator {
    id min = nil;
    for (id object in self) {
        if (min == nil || comparator(min, object) == NSOrderedDescending) {
            min = object;
        }
    }
    NSMutableArray *result = [NSMutableArray array];
    if (min) {
        for (id object in self) {
            if (comparator(object, min) == NSOrderedSame) {
                [result addObject:object];
            }
        }
    }
    return result;
}

- (NSArray *)maximumsWithComparator:(NSComparisonResult (^ NS_NOESCAPE)(id, id))comparator {
    return [self minimumsWithComparator:^NSComparisonResult(id lhs, id rhs) {
        return comparator(rhs, lhs);
    }];
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
    return [self componentsJoinedWithOxfordCommaAndConjunction:@"and"];
}

- (NSString *)componentsJoinedWithOxfordCommaAndConjunction:(NSString *)conjunction {
    if (self.count == 0) {
        return @"";
    } else if (self.count == 1) {
        return [self firstObject];
    } else if (self.count == 2) {
        return [self componentsJoinedByString:[NSString stringWithFormat:@" %@ ", conjunction]];
    } else {
        NSArray *allButLastArray = [self subarrayWithRange:NSMakeRange(0, self.count - 1)];
        NSString *allButLastString = [allButLastArray componentsJoinedByString:@", "];
        NSString *result = [NSString stringWithFormat:@"%@, %@ %@", allButLastString, conjunction, self.lastObject];
        return result;
    }
}

- (NSArray *)subarrayToIndex:(NSUInteger)index {
    if (self.count < index) {
        return self;
    }
    return [self subarrayWithRange:NSMakeRange(0, index)];
}


- (NSArray *)subarrayToIndexInclusive:(NSUInteger)index {
    return [self subarrayToIndex:index + 1];
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

- (NSData *)hashWithSHA256 {
    NSData *hash = [[NSData data] it_sha256];
    for (id object in self) {
        NSData *objectHash = nil;
        if ([object respondsToSelector:@selector(hashWithSHA256)]) {
            // This handles string and other arrays, at least.
            objectHash = [object hashWithSHA256];
        } else {
            objectHash = hash;
        }

        hash = [[hash dataByAppending:objectHash] it_sha256];
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

- (NSArray *)arrayByRemovingDuplicatesStably {
    NSMutableSet *members = [NSMutableSet set];
    NSMutableArray *result = [NSMutableArray array];
    [self enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([members containsObject:obj]) {
            return;
        }
        [members addObject:obj];
        [result addObject:obj];
    }];
    return result;
}

- (NSArray *)uniq {
    return [self uniqWithComparator:^BOOL(id obj1, id obj2) {
        return [obj1 isEqual:obj2];
    }];
}

- (NSArray *)uniqWithComparator:(BOOL (^)(id, id))block {
    __block id last = nil;
    return [self filteredArrayUsingBlock:^BOOL(id anObject) {
        BOOL result;
        if (!last) {
            result = YES;
        } else if (block(anObject, last)) {
            result = NO;
        } else {
            result = YES;
        }
        last = anObject;
        return result;
    }];
}

- (NSString *)numbersAsHexStrings {
    NSMutableString *result = [NSMutableString string];
    NSString *separator = @"";
    for (NSNumber *number in self) {
        if (![number isKindOfClass:[NSNumber class]]) {
            continue;
        }
        if (number.intValue == 0) {
            [result appendFormat:@"%@C-Space", separator];
        } else {
            [result appendFormat:@"%@0x%x", separator, number.intValue];
        }
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

- (id)reduceWithBlock:(id (^)(id first, id second))block {
    id reduction = self.firstObject;
    for (NSInteger i = 0; i < self.count; i++) {
        reduction = block(reduction, i + 1 < self.count ? self[i + 1] : nil);
    }
    return reduction;
}

- (id)reduceWithFirstValue:(id)firstValue block:(id (^)(id first, id second))block {
    id reduction = firstValue;
    for (NSInteger i = 0; i < self.count; i++) {
        reduction = block(reduction, self[i]);
    }
    return reduction;
}

- (NSURL *)lowestCommonAncestorOfURLs {
    if (self.count == 0) {
        return nil;
    }
    if (self.count == 1) {
        return self[0];
    }
    NSArray<NSArray<NSString *> *> *componentsArrays = [self mapWithBlock:^id(NSURL *url) {
        return [url.path pathComponents];
    }];
    NSArray<NSNumber *> *counts = [componentsArrays mapWithBlock:^id(NSArray<NSString *> *anObject) {
        return @(anObject.count);
    }];
    NSInteger shortestCount = [[counts reduceWithBlock:^NSNumber *(NSNumber *first, NSNumber *second) {
        if (second) {
            return @(MIN(first.integerValue, second.integerValue));
        } else {
            return first;
        }
    }] integerValue];
    NSInteger i = 0;
    for (i = 0; i < shortestCount; i++) {
        NSString *value = componentsArrays.firstObject[i];
        const BOOL allShareAncestor = [componentsArrays allWithBlock:^BOOL(NSArray<NSString *> *anObject) {
            return [anObject[i] isEqualToString:value];
        }];
        if (!allShareAncestor) {
            break;
        }
    }
    NSString *path = [[componentsArrays.firstObject subarrayWithRange:NSMakeRange(0, i)] componentsJoinedByString:@"/"];
    return [NSURL fileURLWithPath:path];
}

- (void)enumerateCoalescedObjectsWithComparator:(BOOL (^)(id obj1, id obj2))comparator
                                          block:(void (^)(id object, NSUInteger count))block {
    id previous = self.firstObject;
    NSUInteger count = 1;
    const NSUInteger n = self.count;
    for (NSUInteger i = 1; i < n; i++) {
        id thisObject = self[i];
        const BOOL isEqual = comparator(previous, thisObject);
        if (isEqual) {
            count++;
        } else {
            block(previous, count);
            previous = thisObject;
            count = 1;
        }
    }
    if (previous) {
        block(previous, count);
    }
}

- (NSArray<iTermTuple *> *)tuplesWithFirstObjectEqualTo:(id)firstObject {
    return [self filteredArrayUsingBlock:^BOOL(id anObject) {
        return [anObject isEqual:firstObject];
    }];
}

- (NSDictionary<id, NSArray *> *)classifyWithBlock:(id (^)(id))block {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [self enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        id theClass = block(obj);
        if (theClass) {
            NSMutableArray *array = dict[theClass];
            if (!array) {
                array = [NSMutableArray array];
                dict[theClass] = array;
            }
            [array addObject:obj];
        }
    }];
    return dict;
}

- (NSDictionary<id, NSArray *> *)classifyUniquelyWithBlock:(id (^)(id))block {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [self enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        id theClass = block(obj);
        if (theClass) {
            assert(!dict[theClass]);
            dict[theClass] = obj;
        }
    }];
    return dict;
}

- (id)uncheckedObjectAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.count) {
        return nil;
    } else {
        return [self objectAtIndex:index];
    }
}

- (NSUInteger)indexOfMaxWithBlock:(NSComparisonResult (^)(id, id))block {
    __block NSUInteger maxIndex = NSNotFound;
    __block id max = nil;
    [self enumerateObjectsUsingBlock:^(id  _Nonnull object, NSUInteger idx, BOOL * _Nonnull stop) {
        if (max) {
            NSComparisonResult result = block(max, object);
            if (result == NSOrderedAscending) {
                max = object;
                maxIndex = idx;
            }
        } else {
            max = object;
            maxIndex = idx;
        }
    }];
    return maxIndex;
}

- (id)maxWithBlock:(NSComparisonResult (^)(id, id))block {
    id max = nil;
    for (id object in self) {
        if (max) {
            NSComparisonResult result = block(max, object);
            if (result == NSOrderedAscending) {
                max = object;
            }
        } else {
            max = object;
        }
    }
    return max;
}

- (id)minWithBlock:(NSComparisonResult (^)(id, id))block {
    id min = nil;
    for (id object in self) {
        if (min) {
            NSComparisonResult result = block(min, object);
            if (result == NSOrderedDescending) {
                min = object;
            }
        } else {
            min = object;
        }
    }
    return min;
}

- (NSArray<id> *)it_arrayByDroppingLastN:(NSUInteger)n {
    if (n >= self.count) {
        return @[];
    }
    return [self subarrayToIndex:self.count - n];
}

- (NSArray *)it_arrayByKeepingFirstN:(NSUInteger)n {
    if (n >= self.count) {
        return self;
    }
    return [self subarrayToIndex:n];
}

- (NSArray *)it_arrayByKeepingLastN:(NSUInteger)n {
    if (n >= self.count) {
        return self;
    }
    return [self subarrayFromIndex:self.count - n];
}

// Convert an array like ["a", "b", "b", "c"] into
// ["a", "2 instances of \"b\"", "c"].
- (NSArray *)countedInstancesStrings {
    NSDictionary *classified = [self classifyWithBlock:^id(id object) {
        return object;
    }];
    NSArray *sortedKeys = [classified.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return [sortedKeys mapWithBlock:^id(NSString *key) {
        NSArray *values = classified[key];
        const NSInteger count = values.count;
        if (count > 1) {
            return [NSString stringWithFormat:@"%@ instances of \"%@\"", @(count), key];
        } else {
            return values.firstObject;
        }
    }];
}

- (NSDictionary *)keyValuePairsWithBlock:(iTermTuple * (^)(id object))block {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (id object in self) {
        iTermTuple *tuple = block(object);
        if (tuple) {
            result[tuple.firstObject] = tuple.secondObject;
        }
    }
    return result;
}

- (id)it_jsonSafeValue {
    return [self mapWithBlock:^id(id anObject) {
        if ([anObject respondsToSelector:_cmd]) {
            return [anObject it_jsonSafeValue];
        } else {
            return nil;
        }
    }];
}

- (instancetype)it_arrayByRemovingObjectsPassingTest:(BOOL (^)(id anObject))block {
    NSMutableArray *mutableArray = [self mutableCopy];
    [mutableArray removeObjectsPassingTest:block];
    return mutableArray;
}

- (NSArray<iTermTuple *> *)zip:(NSArray *)other {
    NSMutableArray<iTermTuple *> *result = [NSMutableArray array];
    for (NSInteger i = 0; i < MIN(other.count, self.count); i++) {
        [result addObject:[iTermTuple tupleWithObject:self[i] andObject:other[i]]];
    }
    return result;
}

- (double)sumOfNumbers {
    double sum = 0;
    for (NSNumber *number in self) {
        sum += number.doubleValue;
    }
    return sum;
}

- (NSArray *)it_arrayByReplacingOccurrencesOf:(id)pattern with:(id)replacement {
    return [self mapWithBlock:^id(id obj) {
        if ([obj isEqual:pattern]) {
            return replacement;
        } else {
            return obj;
        }
    }];
}

- (char **)nullTerminatedCStringArray {
    char **array = iTermMalloc(sizeof(char *) * (self.count + 1));
    [self enumerateObjectsUsingBlock:^(NSString *_Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        array[idx] = strdup(obj.UTF8String);
    }];
    array[self.count] = NULL;
    return array;
}

void iTermFreeeNullTerminatedCStringArray(char **array) {
    for (size_t i = 0; array[i] != NULL; i++) {
        free((void *)array[i]);
    }
    free(array);
}

- (NSArray *)reversed {
    const NSUInteger count = self.count;
    if (count < 2) {
        return self;
    }
    return [self mapEnumeratedWithBlock:^id(NSUInteger i, id object, BOOL *stop) {
        return self[count - i - 1];
    }];
}

- (NSArray *)arrayByStrongifyingWeakBoxes {
    if (self.count == 0) {
        return @[];
    }
    return [self mapWithBlock:^id(id anObject) {
        iTermWeakBox *box = [iTermWeakBox castFrom:anObject];
        return box.object;
    }];
}

- (NSArray *)arrayByRemovingNulls {
    return [self filteredArrayUsingBlock:^BOOL(id anObject) {
        return ![anObject isKindOfClass:[NSNull class]];
    }];
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

