//
//  iTermStatusBarMemoryUtilizationComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/21/18.
//

#import "iTermStatusBarMemoryUtilizationComponent.h"

#import "iTermMemoryUtilization.h"

#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSStringITerm.h"
#import "NSView+iTerm.h"

static const CGFloat iTermMemoryUtilizationWidth = 120;

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarMemoryUtilizationComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    self = [super initWithConfiguration:configuration scope:scope];
    if (self) {
        __weak __typeof(self) weakSelf = self;
        [[iTermMemoryUtilization sharedInstance] addSubscriber:self block:^(double value) {
            [weakSelf update:value];
        }];
    }
    return self;
}

- (NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconRAM" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return @"Memory Utilization";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Shows current memory utilization.";
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return @"3.1 GB ▂▃▃▅ RAM";
}

- (BOOL)statusBarComponentCanStretch {
    return NO;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return iTermMemoryUtilizationWidth;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return iTermMemoryUtilizationWidth;
}

- (iTermStatusBarSparklinesModel *)sparklinesModel {
    NSArray<NSNumber *> *values = [[iTermMemoryUtilization sharedInstance] samples];
    iTermStatusBarTimeSeries *timeSeries = [[iTermStatusBarTimeSeries alloc] initWithValues:values];
    iTermStatusBarTimeSeriesRendition *rendition =
    [[iTermStatusBarTimeSeriesRendition alloc] initWithTimeSeries:timeSeries
                                                            color:[self statusBarTextColor]];
    return [[iTermStatusBarSparklinesModel alloc] initWithDictionary:@{ @"main": rendition}];
}

- (long long)currentEstimate {
    NSNumber *last = [[iTermMemoryUtilization sharedInstance] samples].lastObject;
    return  last.doubleValue * [[iTermMemoryUtilization sharedInstance] availableMemory];
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

- (CGSize)rightSize {
    return [self.rightText sizeWithAttributes:self.rightAttributes];
}

- (CGSize)leftSize {
    CGSize size = [self.leftText sizeWithAttributes:self.leftAttributes];
    size.width += 4;
    return size;
}

- (NSString * _Nullable)leftText {
    const long long estimate = self.currentEstimate;
    if (estimate == 0) {
        return @"";
    }
    return [NSString it_formatBytes:estimate];
}

- (NSString * _Nullable)rightText {
    return @"";
}

#pragma mark - Private

- (void)update:(double)value {
    [self invalidate];
}

@end

NS_ASSUME_NONNULL_END
