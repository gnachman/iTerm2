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
#include <numeric>
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
        double value_for_percentile(const double &percentile) const {
            if (_values.size() == 0) {
                return std::nan("");
            }
            assert(percentile >= 0);
            assert(percentile <= 1);
            std::vector<double> sorted_values(_values);
            std::sort(std::begin(sorted_values),
                      std::end(sorted_values));
            const int index = static_cast<int>(std::floor(_values.size() * percentile));
            const int limit = static_cast<int>(_values.size()) - 1;
            const int safe_index = clamp(index, 0, limit);
            return sorted_values[safe_index];
        }

        std::vector<int> get_histogram() const {
            std::vector<int> result;
            const double n = _values.size();
            if (n == 0) {
                return result;
            }

            // https://en.wikipedia.org/wiki/Freedman%E2%80%93Diaconis_rule
            double binWidth = 2.0 * iqr() / pow(n, 1.0 / 3.0);
            if (binWidth <= 0) {
                result.push_back(_values.size());
                return result;
            }

            const double minimum = value_for_percentile(0);
            const double maximum = value_for_percentile(1);
            const double range = maximum - minimum;
            const double max_bins = 15;
            if (range / binWidth > max_bins) {
                binWidth = range / max_bins;
            }
            for (int i = 0; i < _values.size(); i++) {
                const int bucket = (_values[i] - minimum) / binWidth;
                if (result.size() <= bucket) {
                    result.resize(bucket + 1);
                }
                result[bucket]++;
            }
            return result;
        }

    private:
        int clamp(int i, int min, int max) const {
            return std::min(std::max(min, i), max);
        }

        double iqr() const {
            const double p25 = value_for_percentile(0.25);
            const double p75 = value_for_percentile(0.75);
            return p75 - p25;
        }
    };
}

@implementation iTermHistogram {
    double _sum;
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

- (void)clear {
    _sum = 0;
    _min = 0;
    _max = 0;
    _count = 0;
    delete _sampler;
    _sampler = new iTerm2::Sampler(100);
}

- (void)addValue:(double)value {
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
    _sum += other->_sum;
    _min = MIN(_min, other->_min);
    _max = MAX(_max, other->_max);
    _count += other->_count;
    _sampler->merge_from(*other->_sampler);
}

// 3.2.0beta1 had a TON of crashes in dtoa. Somehow I'm producing doubles that are so broken
// they can't be converted to ASCII.
static double iTermSaneDouble(const double d) {
    if (d != d) {
      return -666;
    }
    NSInteger i = d * 1000;
    return static_cast<double>(i) / 1000.0;
}

- (NSString *)stringValue {
    std::vector<int> buckets = _sampler->get_histogram();
    if (buckets.size() == 0) {
        return @"No events";
    }
    NSMutableString *string = [NSMutableString string];
    const int largestCount = *std::max_element(buckets.begin(), buckets.end());
    const int total = std::accumulate(buckets.begin(), buckets.end(), 0);
    const double minimum = _sampler->value_for_percentile(0);
    const double range = _sampler->value_for_percentile(1) - minimum;
    const double binWidth = range / buckets.size();
    for (int i = 0; i < buckets.size(); i++) {
        [string appendString:[self stringForBucket:i
                                             count:buckets[i]
                                      largestCount:largestCount
                                             total:total
                                  bucketLowerBound:minimum + i * binWidth
                                  bucketUpperBound:minimum + (i + 1) * binWidth]];
        [string appendString:@"\n"];
    }
    const double mean = (double)_sum / (double)_count;
    const double p50 = iTermSaneDouble(_sampler->value_for_percentile(0.5));
    const double p95 = iTermSaneDouble(_sampler->value_for_percentile(0.95));

    [string appendFormat:@"Count=%@ Sum=%@ Mean=%0.3f p_50=%0.3f p_95=%0.3f",
     @(_count), @(_sum), mean,
     p50,
     p95];
    return string;
}

- (NSString *)sparklines {
    if (_count == 0) {
        return @"No data";
    }
    NSMutableString *sparklines = [NSMutableString string];

    [sparklines appendString:[self sparklineGraphWithPrecision:4 multiplier:1 units:@""]];

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

- (double)valueAtNTile:(double)ntile {
    return _sampler->value_for_percentile(ntile);
}

- (NSString *)floatingPointFormatWithPrecision:(int)precision units:(NSString *)units {
    return [NSString stringWithFormat:@"%%0.%df%@", precision, units];
}

- (NSString *)sparklineGraphWithPrecision:(int)precision multiplier:(double)multiplier units:(NSString *)units {
    std::vector<int> buckets = _sampler->get_histogram();
    if (buckets.size() == 0) {
        return @"";
    }

    NSString *format = [self floatingPointFormatWithPrecision:precision units:units];
    const double lowerBound = multiplier * _sampler->value_for_percentile(0);
    const double upperBound = multiplier * _sampler->value_for_percentile(1);
    NSMutableString *sparklines = [NSMutableString stringWithFormat:format, lowerBound];
    [sparklines appendString:@" "];
    const double largestBucketCount = *std::max_element(buckets.begin(), buckets.end());
    for (int i = 0; i < buckets.size(); i++) {
        [sparklines appendString:[self sparkWithHeight:buckets[i] / largestBucketCount]];
    }
    [sparklines appendString:@" "];
    [sparklines appendFormat:format, upperBound];

    return sparklines;
}

#pragma mark - Private

- (NSString *)stringForBucket:(int)bucket
                       count:(int)count
                largestCount:(int)maxCount
                       total:(int)total
            bucketLowerBound:(double)bucketLowerBound
            bucketUpperBound:(double)bucketUpperBound {
    NSMutableString *stars = [NSMutableString string];
    const int n = count * iTermHistogramStringWidth / maxCount;
    for (int i = 0; i < n; i++) {
        [stars appendString:@"*"];
    }
    NSString *percent = [NSString stringWithFormat:@"%0.1f%%", 100.0 * static_cast<double>(count) / static_cast<double>(total)];
    return [NSString stringWithFormat:@"[%12.0f, %12.0f) %8d (%6s) |%@",
            bucketLowerBound,
            bucketUpperBound,
            count,
            percent.UTF8String,
            stars];
}

- (NSString *)sparkWithHeight:(double)fraction {
    if (fraction == 0) {
        return @" ";
    }

    NSArray *characters = @[ @"▁", @"▂", @"▃", @"▄", @"▅", @"▆", @"▇", @"█" ];
    int index = std::round(fraction * (characters.count - 1));
    return characters[index];
}

@end
