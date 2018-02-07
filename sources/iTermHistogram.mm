//
//  iTermHistogram.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/19/17.
//

#import "iTermHistogram.h"

#include <algorithm>
#include <cmath>
#include <map>
#include <vector>

static const NSInteger iTermHistogramStringWidth = 20;

namespace iTerm2 {
    class Sampler {
        std::vector<double> _values;
        const int _capacity;
        int _weight;

    public:
        explicit Sampler(const int &capacity) : _capacity(capacity), _weight(0) {
            _values.reserve(capacity);
        }

        void add(const double &value) {
            // Reservoir sampling
            if (_values.size() < _capacity) {
                _values.push_back(value);
            } else {
                uint32_t r = arc4random_uniform(_weight + 1);
                if (r < _capacity) {
                    _values[r] = value;
                }
            }
            _weight++;
            assert(_values.size() > 0);
            assert(_values.size() <= _capacity);
        }

        const int &get_weight() const {
            return _weight;
        }

        void merge_from(const Sampler &other) {
            assert(other._capacity == _capacity);
            if (other._weight == 0) {
                return;
            }
            if (_weight == 0) {
                _values = other._values;
                _weight = other._weight;
                return;
            }
            assert(_values.size() > 0);
            assert(_values.size() <= _capacity);
            assert(other._values.size() > 0);
            std::vector<double> merged_values;

            // Shuffle the two values array because we want to sample from them. Make copies so this
            // method can take a const argument and not have unnecessary side-effects.
            std::vector<double> other_values(other._values);
            std::vector<double> this_values(_values);
            std::random_shuffle(other_values.begin(), other_values.end());
            std::random_shuffle(this_values.begin(), this_values.end());

            // The goal of this algorithm is for the resulting values to have
            // been sampled with the same probability. If one sampler has Ni values with a weight of
            // Wi then each value was selected with probability Ni/Wi. After merging, each value should be
            // selected with probability T=Nm/(W1+W2) where Nm is the number of elements in the merged
            // vector and W1 and W2 are the weights of the two samplers.
            const double Nm = MIN(_capacity,
                                  this_values.size() + other_values.size());
            // Values from vector i (with Si elements) have already been selected with probability Si/Wi.
            // If we pick an element from that vector with probability Pi then its total probability
            // of having been selected is T = Pi * Si/Wi. We want T = Nm/(W1+W2) for selected elements,
            // so we can solve for Pi.
            //
            // T = Nm / (W1 + W2)
            // T = P * (Si / Wi)
            // Nm / (W1 + W2) = Pi * (Si / Wi)
            // Pi = Nm / ((W1 + W2) * (Si / Wi))
            //
            // The number of elements to select is floor(_capacity * Pi). Use floor to avoid
            // selecting more elements than can fit. It introduces a bit of error, but this thing
            // is approximate anyway.
            const double W1 = _weight;
            const double W2 = other._weight;
            const double S1 = this_values.size();
            const double S2 = other_values.size();
            const double P1 = Nm / ((W1 + W2) * (S1 / W1));
            const double P2 = Nm / ((W1 + W2) * (S2 / W2));
            const double N1 = std::floor(S1 * P1);
            const double N2 = std::floor(S2 * P2);

            merged_values.insert(std::end(merged_values),
                                 std::begin(this_values),
                                 std::begin(this_values) + N1);
            merged_values.insert(std::end(merged_values),
                                 std::begin(other_values),
                                 std::begin(other_values) + N2);
            _values = merged_values;
            assert(_values.size() <= _capacity);
            assert(_values.size() > 0);
            _weight = W1 + W2;
        }

        // percentile in [0, 1)
        double value_for_percentile(const double &percentile) {
            if (_values.size() == 0) {
                return std::nan("");
            }
            assert(percentile >= 0);
            assert(percentile < 1);
            std::vector<double> sorted_values(_values);
            std::sort(std::begin(sorted_values),
                      std::end(sorted_values));
            const size_t index = std::floor(_values.size() * percentile);
            return sorted_values[index];
        }

    private:
    };
}
@implementation iTermHistogram {
    std::map<int, int> _buckets;
    double _sum;
    int _maxCount;
    double _min;
    double _max;
    iTerm2::Sampler *_sampler;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sampler = new iTerm2::Sampler(100);
    }
    return self;
}

- (void)dealloc {
    delete _sampler;
}

- (void)addValue:(double)value {
    double logValue = std::log(value + 1) / std::log(M_SQRT2);

    int bucket = std::min(255.0, std::floor(logValue));
    int newCount = _buckets[bucket];
    newCount++;
    _buckets[bucket] = newCount;
    _maxCount = std::max(_maxCount, newCount);
    if (_count == 0) {
        _min = _max = value;
    } else {
        _min = std::min(_min, value);
        _max = std::max(_max, value);
    }
    _sum += value;
    _count++;
    _sampler->add(value);
}

- (void)mergeFrom:(iTermHistogram *)other {
    if (other == nil) {
        return;
    }
    for (auto pair : other->_buckets) {
        _buckets[pair.first] += pair.second;
        _maxCount = std::max(_maxCount, _buckets[pair.first]);
    }
    _sum += other->_sum;
    _min = MIN(_min, other->_min);
    _max = MAX(_max, other->_max);
    _count += other->_count;
    _sampler->merge_from(*other->_sampler);
}

- (NSString *)stringValue {
    if (_count == 0) {
        return @"No events";
    }
    NSMutableString *string = [NSMutableString string];
    if (_buckets.size() > 0) {
        const int min = _buckets.begin()->first;
        const int max = _buckets.rbegin()->first;
        for (int bucket = min; bucket <= max; bucket++) {
            [string appendString:[self stringForBucket:bucket]];
            [string appendString:@"\n"];
        }
    }
    [string appendFormat:@"Count=%@ Sum=%@ Mean=%0.3f p_50=%0.3f p_95=%0.3f",
     @(_count), @(_sum), (double)_sum / (double)_count,
     _sampler->value_for_percentile(0.5),
     _sampler->value_for_percentile(0.95)];
    return string;
}

- (NSString *)sparklines {
    if (_count == 0) {
        return @"No data";
    }
    NSMutableString *sparklines = [NSMutableString string];

    if (_buckets.size() > 0) {
        const int min = _buckets.begin()->first;
        const int max = _buckets.rbegin()->first;
        for (int bucket = min; bucket <= max; bucket++) {
            [sparklines appendString:[self sparkForBucket:bucket]];
        }
    }

    return [NSString stringWithFormat:@"%@ %@ %@  Count=%@ Mean=%@ p50=%@ p95=%@ Sum=%@",
            @(_min),
            sparklines,
            @(_max),
            @(_count),
            @(_sum / _count),
            @(_sampler->value_for_percentile(0.5)),
            @(_sampler->value_for_percentile(0.95)),
            @(_sum)];
}

#pragma mark - Private

- (NSString *)stringForBucket:(int)bucket {
    NSMutableString *stars = [NSMutableString string];
    const int n = _buckets[bucket] * iTermHistogramStringWidth / _maxCount;
    for (int i = 0; i < n; i++) {
        [stars appendString:@"*"];
    }
    NSString *percent = [NSString stringWithFormat:@"%0.1f%%", 100.0 * static_cast<double>(_buckets[bucket]) / static_cast<double>(_count)];
    return [NSString stringWithFormat:@"[%12.0f, %12.0f) %8d (%6s) |%@",
            pow(M_SQRT2, bucket) - 1,
            pow(M_SQRT2, bucket + 1) - 1,
            _buckets[bucket],
            percent.UTF8String,
            stars];
}

- (NSString *)sparkForBucket:(int)bucket {
    double fraction = (double)_buckets[bucket] / (double)_maxCount;
    NSArray *characters = @[ @"▁", @"▂", @"▃", @"▄", @"▅", @"▆", @"▇", @"█" ];
    int index = std::round(fraction * (characters.count - 1));
    return characters[index];
}

@end
