//
//  iTermCumulativeSumCache.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 14.10.18.
//

#import "iTermCumulativeSumCache.h"

@implementation iTermCumulativeSumCache

- (instancetype)init {
    self = [super init];
    if (self) {
        _sums = [NSMutableArray array];
        _values = [NSMutableArray array];
    }
    return self;
}

- (NSInteger)sumOfValuesInRange:(NSRange)range {
    if (range.length == 0) {
        return 0;
    }
    const int lowIndex = range.location;
    const int highIndex = NSMaxRange(range) - 1;
    return _sums[highIndex].integerValue - _sums[lowIndex].integerValue + _values[lowIndex].integerValue;
}

- (NSInteger)sumOfAllValues {
    return [self sumOfValuesInRange:NSMakeRange(0, _sums.count)];
}

- (NSInteger)maximumSum {
    return _sums.lastObject.integerValue;
}

- (void)appendValue:(NSInteger)value {
    [_values addObject:@(value)];
    if (_sums.count == 0) {
        _offset = 0;
        [_sums addObject:@(value)];
    } else {
        [_sums addObject:@(value + [self maximumSum])];
    }
}

- (NSInteger)indexContainingValue:(NSInteger)value {
    // Subtract the offset because the offset is negative and our values are higher than what is exposed by the owner's interface.
    const NSInteger adjustedValue = value - _offset;
    const NSInteger insertionIndex = [_sums indexOfObject:@(adjustedValue)
                                            inSortedRange:NSMakeRange(0, _sums.count)
                                                  options:NSBinarySearchingInsertionIndex
                                          usingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
                                              return [obj1 compare:obj2];
                                          }];
    NSInteger index = insertionIndex;
    while (index + 1 < _sums.count &&
           _sums[index].integerValue == adjustedValue) {
        index++;
    }
    if (index == _sums.count) {
        return NSNotFound;
    }

    return index;
}

- (NSInteger)verboseIndexContainingValue:(NSInteger)value {
    NSLog(@"Search for insertion index for value %@", @(value));
    // Subtract the offset because the offset is negative and our values are higher than what is exposed by the owner's interface.
    const NSInteger adjustedValue = value - _offset;
    NSLog(@"adjusted value is %@ because offset is %@", @(adjustedValue), @(_offset));
    const NSInteger insertionIndex = [_sums indexOfObject:@(adjustedValue)
                                            inSortedRange:NSMakeRange(0, _sums.count)
                                                  options:NSBinarySearchingInsertionIndex
                                          usingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
                                              return [obj1 compare:obj2];
                                          }];
    NSLog(@"insertionIndex is %@", @(insertionIndex));
    NSInteger index = insertionIndex;
    while (index + 1 < _sums.count &&
           _sums[index].integerValue == adjustedValue) {
        index++;
        NSLog(@"advance index to %@ because the insertion index exactly equaled a sum", @(index));
    }
    if (index == _sums.count) {
        NSLog(@"Insertion is past the end");
        return NSNotFound;
    }
    NSLog(@"return index %@", @(index));
    return index;
}

- (void)removeFirstValue {
    _offset -= _values[0].integerValue;
    [_sums removeObjectAtIndex:0];
    [_values removeObjectAtIndex:0];
    if (_sums.count == 0) {
        _offset = 0;
    }
}

- (void)removeLastValue {
    [_sums removeLastObject];
    [_values removeLastObject];
    if (_sums.count == 0) {
        _offset = 0;
    }
}

- (void)setLastValue:(NSInteger)value {
    const NSInteger index = _sums.count - 1;
    assert(index >= 1);
    _values[index] = @(value);
    _sums[index] = @(_sums[index - 1].integerValue + value);
}

- (void)setFirstValue:(NSInteger)value {
    const NSInteger cachedNumLines = _values[0].integerValue;
    const NSInteger delta = value - cachedNumLines;
    if (_sums.count > 1) {
        // Only ok to _drop_ lines from the first block when there are others after it.
        assert(delta <= 0);
    }
    _offset += delta;
    _values[0] = @(value);
}

- (id)copyWithZone:(NSZone *)zone {
    iTermCumulativeSumCache *theCopy = [[iTermCumulativeSumCache alloc] init];
    theCopy->_sums = [_sums mutableCopy];
    theCopy->_values = [_values mutableCopy];
    theCopy->_offset = _offset;
    return theCopy;
}

@end
