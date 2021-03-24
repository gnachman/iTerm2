//
//  iTermStatusBarNetworkUtilizationComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/21/18.
//

#import "iTermStatusBarNetworkUtilizationComponent.h"

#import "iTermNetworkUtilization.h"

#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSStringITerm.h"
#import "NSView+iTerm.h"

static const CGFloat iTermNetworkUtilizationWidth = 170;
static NSString *const iTermStatusBarNetworkUtilizationComponentKnobKeyDownloadColor = @"Network download color";
static NSString *const iTermStatusBarNetworkUtilizationComponentKnobKeyUploadColor = @"Network upload color";

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarNetworkUtilizationComponent {
    double _ceiling;
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    self = [super initWithConfiguration:configuration scope:scope];
    if (self) {
        _ceiling = 1;
        __weak __typeof(self) weakSelf = self;
        [[iTermNetworkUtilization sharedInstance] addSubscriber:self block:^(double down, double up) {
            [weakSelf updateWithDown:down up:up];
        }];
    }
    return self;
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    NSArray<iTermStatusBarComponentKnob *> *knobs = [super statusBarComponentKnobs];

    iTermStatusBarComponentKnob *downloadColorKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Download Color:"
                                                          type:iTermStatusBarComponentKnobTypeColor
                                                   placeholder:nil
                                                  defaultValue:nil
                                                           key:iTermStatusBarNetworkUtilizationComponentKnobKeyDownloadColor];
    iTermStatusBarComponentKnob *uploadColorKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Upload Color:"
                                                          type:iTermStatusBarComponentKnobTypeColor
                                                   placeholder:nil
                                                  defaultValue:nil
                                                           key:iTermStatusBarNetworkUtilizationComponentKnobKeyUploadColor];

    return [knobs arrayByAddingObjectsFromArray:@[downloadColorKnob, uploadColorKnob]];
}

- (NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconNetwork" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return @"Network Throughput";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Shows current network throughput.";
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return @"2 MB↓ ▃▃▅▂ 1 MB↑";
}

- (BOOL)statusBarComponentCanStretch {
    return NO;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return iTermNetworkUtilizationWidth;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return iTermNetworkUtilizationWidth;
}

- (NSColor *)uploadColor {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarNetworkUtilizationComponentKnobKeyUploadColor] colorValue] ?: [NSColor redColor];
}

- (NSColor *)downloadColor {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarNetworkUtilizationComponentKnobKeyDownloadColor] colorValue] ?: [NSColor blueColor];
}

- (iTermStatusBarSparklinesModel *)sparklinesModel {
    NSArray<iTermNetworkUtilizationSample *> *samples =
    [[iTermNetworkUtilization sharedInstance] samples];

    NSArray<NSNumber *> *readValues = [samples mapWithBlock:^id(iTermNetworkUtilizationSample *anObject) {
        return @(anObject.bytesPerSecondRead);
    }];
    iTermStatusBarTimeSeries *readTimeSeries = [[iTermStatusBarTimeSeries alloc] initWithValues:readValues];
    iTermStatusBarTimeSeriesRendition *readRendition =
    [[iTermStatusBarTimeSeriesRendition alloc] initWithTimeSeries:readTimeSeries
                                                            color:[self downloadColor]];

    NSArray<NSNumber *> *writeValues = [samples mapWithBlock:^id(iTermNetworkUtilizationSample *anObject) {
        return @(anObject.bytesPerSecondWrite);
    }];
    iTermStatusBarTimeSeries *writeTimeSeries = [[iTermStatusBarTimeSeries alloc] initWithValues:writeValues];
    iTermStatusBarTimeSeriesRendition *writeRendition =
    [[iTermStatusBarTimeSeriesRendition alloc] initWithTimeSeries:writeTimeSeries
                                                            color:[self uploadColor]];

    return [[iTermStatusBarSparklinesModel alloc] initWithDictionary:@{ @"read": readRendition,
                                                                        @"write": writeRendition  }];
}

- (double)ceiling {
    return _ceiling;
}

- (double)downThroughput {
    return [[[[iTermNetworkUtilization sharedInstance] samples] lastObject] bytesPerSecondRead];
}

- (double)upThroughput {
    return [[[[iTermNetworkUtilization sharedInstance] samples] lastObject] bytesPerSecondWrite];
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

- (NSString * _Nullable)leftText {
    return [NSString stringWithFormat:@"%@↓", [NSString it_formatBytesCompact:self.downThroughput]];
}

- (NSString * _Nullable)rightText {
    return [NSString stringWithFormat:@"%@↑", [NSString it_formatBytesCompact:self.upThroughput]];
}

- (CGSize)rightSize {
    NSString *longest = @"123.0 TB↑";
    return [longest sizeWithAttributes:self.rightAttributes];
}

- (CGSize)leftSize {
    NSString *longest = @"123.0 TB↓";
    return [longest sizeWithAttributes:self.leftAttributes];
}

#pragma mark - Private

- (void)updateWithDown:(double)down up:(double)up {
    _ceiling = self.sparklinesModel.maximumValue.doubleValue;
    [self invalidate];
}

@end

NS_ASSUME_NONNULL_END
