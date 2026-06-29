//
//  iTermMutableOrderedSet.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/27/24.
//

#import "iTermMutableOrderedSet.h"
#import "iTerm2SharedARC-Swift.h"

@implementation iTermOrderedSet {
@protected
    iTermMutableOrderedSetImpl *_impl;
}

- (instancetype)initWithComparator:(NSComparisonResult (^)(id, id))comparator {
    self = [super init];
    if (self) {
        _impl = [[iTermMutableOrderedSetImpl alloc] initWithComparator:comparator];
    }
    return self;
}

- (NSUInteger)count {
    return _impl.count;
}

- (void)enumerateObjectsUsingBlock:(void (^NS_NOESCAPE)(id, NSUInteger, BOOL *))block {
    NSInteger i = 0;
    for (id obj in _impl) {
        BOOL stop = NO;
        block(obj, i, &stop);
        if (stop) {
            return;
        }
        i += 1;
    }
}

- (BOOL)containsObject:(id)obj {
    return [_impl containsObject:obj];
}

- (id)objectAtIndexedSubscript:(NSInteger)i {
    return _impl[i];
}

- (NSUInteger)firstIndexOfObject:(id)object
              inSortedRange:(NSRange)range
                    options:(NSBinarySearchingOptions)opts {
    NSComparator cmp = _impl.compare;

    // The smallest index where the target value could still be located, but it may end up being more than the actual index of the first equal value after the loop.
    NSUInteger low = range.location;

    // The largest index where the target value could still be located, but it may be adjusted to the left boundary of the first equal value.
    NSUInteger high = NSMaxRange(range);

    while (low < high) {
        NSUInteger mid = low + (high - low) / 2;
        id midObject = _impl[mid];
        NSComparisonResult result = cmp(object, midObject);

        if (result == NSOrderedAscending) {
            high = mid;
        } else if (result == NSOrderedDescending) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }

    if (low < NSMaxRange(range) && cmp(object, _impl[low]) == NSOrderedSame) {
        return low;
    }
    if (opts & NSBinarySearchingInsertionIndex) {
        return low;
    }

    return NSNotFound;
}

- (NSUInteger)lastIndexOfObject:(id)object
              inSortedRange:(NSRange)range
                    options:(NSBinarySearchingOptions)opts {
    NSComparator cmp = _impl.compare;

    // The smallest index where the target value could still be located, but it could be adjusted to the right boundary of the last equal value.
    NSUInteger low = range.location;

    // One past the largest index where the target value could still be located, but it may end up being less than the actual index of the last equal value after the loop.
    NSUInteger high = NSMaxRange(range);

    while (low < high) {
        NSUInteger mid = low + (high - low) / 2;
        id midObject = _impl[mid];
        NSComparisonResult result = cmp(object, midObject);

        if (result == NSOrderedAscending) {
            high = mid;
        } else if (result == NSOrderedDescending) {
            low = mid + 1;
        } else {
            low = mid + 1;
        }
    }

    if (low > range.location && cmp(object, _impl[low - 1]) == NSOrderedSame) {
        return low - 1;
    }
    if (opts & NSBinarySearchingInsertionIndex) {
        return low;
    }

    return NSNotFound;
}

- (NSUInteger)indexOfObject:(id)object
              inSortedRange:(NSRange)range
                    options:(NSBinarySearchingOptions)opts {
    if (opts & NSBinarySearchingFirstEqual) {
        return [self firstIndexOfObject:object inSortedRange:range options:opts];
    }
    if (opts & NSBinarySearchingLastEqual) {
        return [self lastIndexOfObject:object inSortedRange:range options:opts];
    }
    NSComparator cmp = _impl.compare;

    // The smallest index in the current search range where the target value might still be found.
    NSUInteger low = range.location;

    // One past the largest index in the current search range where the target value might still be found.
    NSUInteger high = NSMaxRange(range);

    while (low < high) {
        NSUInteger mid = low + (high - low) / 2;
        id midObject = _impl[mid];
        NSComparisonResult result = cmp(object, midObject);

        if (result == NSOrderedAscending) {
            high = mid;
        } else if (result == NSOrderedDescending) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }

    if (opts & NSBinarySearchingInsertionIndex) {
        return low;
    }

    return NSNotFound;
}

- (id)firstObject {
    if (_impl.count > 0) {
        return _impl[0];
    }
    return nil;
}

- (id)lastObject {
    if (_impl.count > 0) {
        return _impl[_impl.count - 1];
    }
    return nil;
}

- (NSArray *)array {
    return _impl.array;
}

@end

@implementation iTermMutableOrderedSet

- (void)removeObjectsAtIndexes:(NSIndexSet *)indexes {
    [indexes enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        [_impl removeObjectAtIndex:idx];
    }];
}

- (BOOL)insertObject:(id)object {
    return [_impl insertObject:object];
}

- (void)removeAllObjects {
    _impl = [[iTermMutableOrderedSetImpl alloc] initWithComparator:_impl.compare];
}

- (void)removeObjectsInRange:(NSRange)range {
    [self removeObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:range]];
}

@end
