//
//  iTermStatusBarCPUUtilizationComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/19/18.
//

#import "iTermStatusBarCPUUtilizationComponent.h"

#import "iTermCPUUtilization.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope+Session.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSStringITerm.h"
#import "NSView+iTerm.h"

static const CGFloat iTermCPUUtilizationWidth = 120;

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarCPUUtilizationComponent {
    iTermVariableReference *_sshRef;
    NSArray<NSNumber *> *_previousValues;
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    self = [super initWithConfiguration:configuration scope:scope];
    if (self) {
        __weak __typeof(self) weakSelf = self;
        // scope will be nil in status bar configuration UI but not during normal use.
        if (scope.ID) {
            [[iTermCPUUtilization instanceForSessionID:scope.ID] addSubscriber:self block:^(double value) {
                [weakSelf update:value];
            }];
            _sshRef.onChangeBlock = ^{
                [weakSelf sshLevelDidChange];
            };
        }
    }
    return self;
}

- (nullable NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconCPU" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return @"CPU Utilization";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Shows current CPU utilization.";
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return @"12% ▃▃▅▂ CPU";
}

- (BOOL)statusBarComponentCanStretch {
    return NO;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return iTermCPUUtilizationWidth;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return iTermCPUUtilizationWidth;
}

- (iTermStatusBarSparklinesModel *)sparklinesModel {
    NSMutableArray<NSNumber *> *values = [[[iTermCPUUtilization instanceForSessionID:self.scope.ID] samples] mutableCopy];
    // The data source may change when sshing but the drawing code doesn't expect retroactive changes.
    NSInteger i = _previousValues.count;
    while (i > 0 && values.count < _previousValues.count) {
        i -= 1;
        [values insertObject:_previousValues[i] atIndex:0];
    }
    _previousValues = values;
    iTermStatusBarTimeSeries *timeSeries = [[iTermStatusBarTimeSeries alloc] initWithValues:values];
    iTermStatusBarTimeSeriesRendition *rendition =
    [[iTermStatusBarTimeSeriesRendition alloc] initWithTimeSeries:timeSeries
                                                            color:[self statusBarTextColor]];
    return [[iTermStatusBarSparklinesModel alloc] initWithDictionary:@{ @"main": rendition}];
}

- (int)currentEstimate {
    double alpha = 0.7;
    NSArray<NSNumber *> *const samples = [[iTermCPUUtilization instanceForSessionID:self.scope.ID] samples];
    NSArray<NSNumber *> *lastSamples = samples;
    const NSInteger maxSamplesToUse = 4;
    double x = samples.lastObject.doubleValue;
    if (lastSamples.count > maxSamplesToUse) {
        lastSamples = [lastSamples subarrayWithRange:NSMakeRange(lastSamples.count - maxSamplesToUse,
                                                                 maxSamplesToUse)];
    }
    for (NSNumber *number in lastSamples) {
        x *= (1.0 - alpha);
        x += number.doubleValue * alpha;
    }
    return x * 100;
}

- (NSFont *)font {
    return self.advancedConfiguration.font ?: [iTermStatusBarAdvancedConfiguration defaultFont];
}

- (NSDictionary *)leftAttributes {
    NSMutableParagraphStyle *leftAlignStyle =
        [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    [leftAlignStyle setAlignment:NSTextAlignmentLeft];
    [leftAlignStyle setLineBreakMode:NSLineBreakByTruncatingTail];

    return @{ NSParagraphStyleAttributeName: leftAlignStyle,
              NSFontAttributeName: self.font,
              NSForegroundColorAttributeName: self.textColor };
}

- (NSDictionary *)rightAttributes {
    NSMutableParagraphStyle *rightAlignStyle =
        [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    [rightAlignStyle setAlignment:NSTextAlignmentRight];
    [rightAlignStyle setLineBreakMode:NSLineBreakByTruncatingTail];
    return @{ NSParagraphStyleAttributeName: rightAlignStyle,
              NSFontAttributeName: self.font,
              NSForegroundColorAttributeName: self.textColor };
}

- (NSSize)leftSize {
    NSString *longestPercentage = @"100%";
    return [longestPercentage sizeWithAttributes:self.leftAttributes];
}

- (CGSize)rightSize {
    return [self.rightText sizeWithAttributes:self.rightAttributes];
}

- (NSString * _Nullable)leftText {
    return [NSString stringWithFormat:@"%d%%", self.currentEstimate];
}

- (NSString * _Nullable)rightText {
    return @"";
}

#pragma mark - Private

- (void)update:(double)value {
    [self invalidate];
}

- (void)sshLevelDidChange {
    [self invalidate];
}

@end

NS_ASSUME_NONNULL_END
