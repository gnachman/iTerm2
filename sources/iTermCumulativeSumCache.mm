//
//  iTermCumulativeSumCache.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 14.10.18.
//

#import "iTermCumulativeSumCache.h"

extern "C" {
#import "DebugLogging.h"
}
#include <algorithm>
#include <deque>

@implementation iTermCumulativeSumCache {
    std::deque<NSInteger> _sums;
    std::deque<NSInteger> _values;
}

- (void)dump {
    int i = 0;
    for (auto sum_i : _sums) {
        DLog(@"_sums[%@] = %@", @(i++), @(sum_i));
    }

    i = 0;
    for (auto value_i : _values) {
        DLog(@"_values[%@] = %@", @(i++), @(value_i));
    }
}

- (NSInteger)sumOfValuesInRange:(NSRange)range {
    assert(range.location < NSIntegerMax);
    const NSInteger location = range.location;
    const NSInteger length = range.length;
    const NSInteger limit = location + length;
    if (length == 0) {
        return 0;
    }

    const int lowIndex = MAX(0, location);
    const int highIndex = MAX(0, limit) - 1;
    if (highIndex < lowIndex) {
        return 0;
    }
    return _sums[highIndex] - _sums[lowIndex] + _values[lowIndex];
}

- (NSInteger)sumOfAllValues {
    return [self sumOfValuesInRange:NSMakeRange(0, _sums.size())];
}

- (NSInteger)maximumSum {
    if (_sums.empty()) {
        return 0;
    }
    return _sums.back();
}

- (void)appendValue:(NSInteger)value {
    _values.push_back(value);
    if (_sums.empty()) {
        _offset = 0;
        _sums.push_back(value);
    } else {
        _sums.push_back(value + self.maximumSum);
    }
}

- (NSInteger)indexContainingValue:(NSInteger)value {
    // Subtract the offset because the offset is negative and our values are higher than what is exposed by the owner's interface.
    const NSInteger adjustedValue = value - _offset;
    auto it = std::lower_bound(_sums.begin(), _sums.end(), adjustedValue);
    if (it == _sums.end()) {
        return NSNotFound;
    }
    // it refers to the first element in _sums greater or equal to value.
    if (*it == adjustedValue) {
        it++;
        if (it == _sums.end()) {
            return NSNotFound;
        }
    }
    return it - _sums.begin();  // get index of iterator
}

- (NSInteger)verboseIndexContainingValue:(NSInteger)value {
    DLog(@"Search for insertion index for value %@", @(value));
    // Subtract the offset because the offset is negative and our values are higher than what is exposed by the owner's interface.
    const NSInteger adjustedValue = value - _offset;
    DLog(@"adjusted value is %@ because offset is %@", @(adjustedValue), @(_offset));
    auto it = std::lower_bound(_sums.begin(), _sums.end(), adjustedValue);
    if (it == _sums.end()) {
        DLog(@"lower bound is past the end");
        return NSNotFound;
    }
    DLog(@"lower bound is %@", @(it - _sums.begin()));
    // it refers to the first element in _sums greater or equal to value.
    if (*it == adjustedValue) {
        DLog(@"lower bound is exactly a bucket boundary");
        it++;
        if (it == _sums.end()) {
            DLog(@"lower bound is past the end");
            return NSNotFound;
        }
    }
    const NSInteger index = it - _sums.begin();  // get index of iterator
    DLog(@"Return %@", @(index));
    return index;
}

- (void)removeFirstValue {
    _offset -= _values[0];
    _sums.erase(_sums.begin());
    _values.erase(_values.begin());
    if (_sums.empty()) {
        _offset = 0;
    }
}

- (void)removeLastValue {
    _sums.pop_back();
    _values.pop_back();
    if (_sums.empty()) {
        _offset = 0;
    }
}

- (void)setLastValue:(NSInteger)value {
    const NSInteger index = _sums.size() - 1;
    assert(index >= 1);
    _values[index] = value;
    _sums[index] = _sums[index - 1] + value;
}

- (void)setFirstValue:(NSInteger)value {
    const NSInteger cachedNumLines = _values[0];
    const NSInteger delta = value - cachedNumLines;
    if (_sums.size() > 1) {
        // Only ok to _drop_ lines from the first block when there are others after it.
        assert(delta <= 0);
    }
    _offset += delta;
    _values[0] = value;
}

- (id)copyWithZone:(NSZone *)zone {
    iTermCumulativeSumCache *theCopy = [[iTermCumulativeSumCache alloc] init];
    theCopy->_sums = _sums;
    theCopy->_values = _values;
    theCopy->_offset = _offset;
    return theCopy;
}

- (NSInteger)valueAtIndex:(NSInteger)index {
    return _values[index];
}

- (NSInteger)sumAtIndex:(NSInteger)index {
    return _sums[index];
}

- (NSInteger)count {
    return _values.size();
}

@end
