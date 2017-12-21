//
//  iTermHistogram.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/19/17.
//

#import "iTermHistogram.h"

#import <map>
#include <cmath>

static const NSInteger iTermHistogramStringWidth = 80;

@implementation iTermHistogram {
    std::map<int, int> _buckets;
    double _sum;
    int64_t _count;
    int _maxCount;
    double _min;
    double _max;
}

- (void)addValue:(double)value {
    double logValue = std::log(value) / std::log(2);

    int bucket = std::floor(logValue);
    int newCount = _buckets[bucket]++;
    _maxCount = std::max(_maxCount, newCount);
    if (_count == 0) {
        _min = _max = value;
    } else {
        _min = std::min(_min, value);
        _max = std::max(_max, value);
    }
    _sum += value;
    _count++;
}

- (NSString *)stringValue {
    NSMutableString *string = [NSMutableString string];
    if (_buckets.size() > 0) {
        const int min = _buckets.begin()->first;
        const int max = _buckets.rbegin()->first;
        for (int bucket = min; bucket <= max; bucket++) {
            [string appendString:[self stringForBucket:bucket]];
        }
    }
    [string appendString:@"\n"];
    [string appendFormat:@"Count=%@ Sum=%@ Mean=%@", @(_count), @(_sum), @(_sum / _count)];
    return string;
}

- (NSString *)sparklines {
    NSMutableString *sparklines = [NSMutableString string];

    if (_buckets.size() > 0) {
        const int min = _buckets.begin()->first;
        const int max = _buckets.rbegin()->first;
        for (int bucket = min; bucket <= max; bucket++) {
            [sparklines appendString:[self sparkForBucket:bucket]];
        }
    }

    return [NSString stringWithFormat:@"%@ %@ %@  Count=%@ Mean=%@", @(_min), sparklines, @(_max), @(_count), @(_sum / _count)];
}

#pragma mark - Private

- (NSString *)stringForBucket:(int)bucket {
    NSMutableString *stars = [NSMutableString string];
    const int n = _buckets[bucket] * iTermHistogramStringWidth / _maxCount;
    for (int i = 0; i < n; i++) {
        [stars appendString:@"*"];
    }
    return [NSString stringWithFormat:@"[%12@…%12@) %8@ |%@",
            @(pow(2, bucket)),
            @(pow(2, bucket + 1)),
            @(_buckets[bucket]),
            stars];
}

- (NSString *)sparkForBucket:(int)bucket {
    double fraction = (double)_buckets[bucket] / (double)_maxCount;
    NSArray *characters = @[ @"▁", @"▂", @"▃", @"▄", @"▅", @"▆", @"▇", @"█" ];
    int index = std::round(fraction * characters.count);
    return characters[index];
}

@end
