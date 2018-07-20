//
//  iTermStatusBarCPUUtilizationComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/19/18.
//

#import "iTermStatusBarCPUUtilizationComponent.h"

#import "iTermCPUUtilization.h"
#import "NSDictionary+iTerm.h"
#import "NSStringITerm.h"

static const NSInteger iTermStatusBarCPUUtilizationComponentMaximumNumberOfSamples = 60;

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarCPUUtilizationComponent {
    NSMutableArray<NSNumber *> *_samples;
    iTermCPUUtilizationObserver _block;
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration {
    self = [super initWithConfiguration:configuration];
    if (self) {
        _samples = [NSMutableArray array];
        __weak __typeof(self) weakSelf = self;
        _block = ^(double value){
            [weakSelf update:value];
        };
        [[iTermCPUUtilization sharedInstance] addSubscriber:_block];
    }
    return self;
}

- (NSString *)statusBarComponentShortDescription {
    return @"CPU Utilization";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Shows current CPU utilization.";
}

- (id)statusBarComponentExemplar {
    return @"CPU [❚❚❚❚❚❚❚❚  ] 72%";
}

- (BOOL)statusBarComponentCanStretch {
    return NO;
}

- (nullable NSString *)stringValue {
    const NSInteger N = 10;
    NSArray<NSNumber *> *bins = [self binnedSamples:_samples count:N];
    NSString *sparklines = @"";
    for (NSInteger i = 0; i < bins.count; i++) {
        sparklines = [sparklines stringByAppendingString:[NSString sparkWithHeight:bins[i].doubleValue]];
    }
    sparklines = [[@" " stringRepeatedTimes:N - bins.count] stringByAppendingString:sparklines];
    return [NSString stringWithFormat:@"CPU [%@] %d%%", sparklines, (int)(_samples.lastObject.doubleValue * 100)];
}

- (nullable NSString *)stringValueForCurrentWidth {
    return self.stringValue;
}

- (NSTimeInterval)statusBarComponentUpdateCadence {
    return 1;
}

- (nullable NSArray<NSString *> *)stringVariants {
    return @[ self.stringValue ?: @"" ];
}

#pragma mark - Private

- (void)update:(double)value {
    [_samples addObject:@(value)];
    while (_samples.count > iTermStatusBarCPUUtilizationComponentMaximumNumberOfSamples) {
        [_samples removeObjectAtIndex:0];
    }
}

- (NSArray<NSNumber *> *)binnedSamples:(NSArray<NSNumber *> *)samples count:(NSInteger)count {
    if (samples.count < count) {
        return samples;
    }
    double samplesPerBin = (double)samples.count / (double)count;

    NSMutableArray<NSNumber *> *bins = [NSMutableArray array];
    for (NSInteger i = 0; i < count; i++) {
        double sum = 0;
        double start = samplesPerBin * i;
        double remaining = samplesPerBin;
        int j = floor(start);
        double weight = floor(start + 1) - start;
        while (remaining > 0 && j < samples.count) {
            sum += samples[j].doubleValue * weight;
            remaining -= weight;
            weight = MIN(1, remaining);
            j++;
        }
        assert(remaining < 0.01);
        [bins addObject:@(sum)];
    }
    return bins;
}
@end

NS_ASSUME_NONNULL_END
