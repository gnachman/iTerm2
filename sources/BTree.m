//
//  BTree.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/24.
//

#import "BTree.h"

#import "iTerm2SharedARC-Swift.h"

@implementation iTermSortedBag {
@protected
    iTermTypeErasedSortedBag *_bag;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _bag = [[iTermTypeErasedSortedBag alloc] init];
    }
    return self;
}

- (id)firstObject {
    return _bag.firstObject;
}

- (id)lastObject {
    return _bag.lastObject;
}

- (NSUInteger)count {
    return _bag.count;
}

- (NSArray *)array {
    return _bag.array;
}

typedef NS_ENUM(unsigned long, BTreeEnumerationState) {
    BTreeEnumerationStateInitial = 0,
    BTreeEnumerationStateWorking = 1,
    BTreeEnumerationStateFinished = 2
};

- (void)enumerateObjectsUsingBlock:(void (NS_NOESCAPE ^)(id obj,
                                                         NSUInteger idx,
                                                         BOOL *stop))block {
    const NSUInteger count = _bag.count;
    for (NSUInteger i = 0; i < count; i++) {
        BOOL stop = NO;
        block(_bag[i], i, &stop);
        if (stop) {
            break;
        }
    }
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(__unsafe_unretained id _Nullable[])buffer
                                    count:(NSUInteger)len {
    NSUInteger count = 0;

    if (state->state == BTreeEnumerationStateInitial) {
        state->mutationsPtr = &state->extra[0];
        state->state = BTreeEnumerationStateWorking;
    }

    if (state->state == BTreeEnumerationStateWorking) {
        while ((count < len) && (state->extra[1] < [_bag count])) {
            buffer[count] = _bag[state->extra[1]];
            state->extra[1]++;
            count++;
        }
        state->itemsPtr = buffer;
        if (state->extra[1] >= [_bag count]) {
            state->state = BTreeEnumerationStateFinished;
        }
    }

    return count;
}

- (BOOL)containsObject:(id)object {
    return [_bag containsObject:object];
}

- (NSInteger)indexOfObject:(id)object
                            options:(NSBinarySearchingOptions)options comparator:(BOOL (^)(id _Nonnull, id _Nonnull))comparator {
    if (options & NSBinarySearchingInsertionIndex) {
        if (options & NSBinarySearchingFirstEqual) {
            return [_bag firstInsertionIndexOfObject:object comparator:comparator];
        }
        if (options & NSBinarySearchingLastEqual) {
            return [_bag lastInsertionIndexOfObject:object comparator:comparator];
        }
        return [_bag arbitraryInsertionIndexOfObject:object comparator:comparator];
    }
    if (options & NSBinarySearchingFirstEqual) {
        return [_bag firstIndexOfObject:object comparator:comparator];
    }
    assert(NO);  // not implemented
    return NSNotFound;
}

- (id)objectAtIndex:(NSInteger)index {
    return _bag[index];
}

- (id)objectAtIndexedSubscript:(NSUInteger)idx {
    return _bag[idx];
}

@end

@implementation iTermMutableSortedBag

- (void)insertObject:(id)object {
    [_bag insertObject:object];
}

- (void)removeAllObjects {
    [_bag removeAllObjects];
}

- (void)removeObjectsAtIndexes:(NSIndexSet *)indexSet {
    [_bag removeObjectsAtIndexes:indexSet];
}

- (void)removeObjectsInRange:(NSRange)range {
    [_bag removeObjectsInRange:range];
}

@end
