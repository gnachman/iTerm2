//
//  iTermStatusBarCPUUtilizationComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/19/18.
//

#import "iTermStatusBarCPUUtilizationComponent.h"

#import "iTermCPUUtilization.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSStringITerm.h"
#import "NSView+iTerm.h"

static const CGFloat iTermCPUUtilizationWidth = 120;

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarCPUUtilizationComponent {
    NSMutableArray<NSNumber *> *_samples;
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    self = [super initWithConfiguration:configuration scope:scope];
    if (self) {
        _samples = [NSMutableArray array];
        __weak __typeof(self) weakSelf = self;
        [[iTermCPUUtilization sharedInstance] addSubscriber:self block:^(double value) {
            [weakSelf update:value];
        }];
    }
    return self;
}

- (NSImage *)statusBarComponentIcon {
    return [NSImage it_imageNamed:@"StatusBarIconCPU" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return @"CPU Utilization";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Shows current CPU utilization.";
}

- (id)statusBarComponentExemplar {
    return @"12% ▃▃▅▂ CPU";
}

- (BOOL)statusBarComponentCanStretch {
    return NO;
}

- (NSTimeInterval)statusBarComponentUpdateCadence {
    return 1;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return iTermCPUUtilizationWidth;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return iTermCPUUtilizationWidth;
}

- (NSArray<NSNumber *> *)values {
    return _samples;
}

- (int)currentEstimate {
    double alpha = 0.7;
    NSArray<NSNumber *> *lastSamples = _samples;
    const NSInteger maxSamplesToUse = 4;
    double x = _samples.lastObject.doubleValue;
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

- (void)drawTextWithRect:(NSRect)rect
                    left:(NSString *)left
                   right:(NSString *)right
               rightSize:(CGSize)rightSize {
    NSRect textRect = rect;
    textRect.size.height = rightSize.height;
    textRect.origin.y = (self.view.bounds.size.height - rightSize.height) / 2.0;
    [left drawInRect:textRect withAttributes:[self.leftAttributes it_attributesDictionaryWithAppearance:self.view.effectiveAppearance]];
    [right drawInRect:textRect withAttributes:[self.rightAttributes it_attributesDictionaryWithAppearance:self.view.effectiveAppearance]];
}

- (NSRect)graphRectForRect:(NSRect)rect
                  leftSize:(CGSize)leftSize
                 rightSize:(CGSize)rightSize {
    NSRect graphRect = rect;
    const CGFloat margin = 4;
    CGFloat rightWidth = rightSize.width + margin;
    CGFloat leftWidth = leftSize.width + margin;
    graphRect.origin.x += leftWidth;
    graphRect.size.width -= (leftWidth + rightWidth);
    graphRect = NSInsetRect(graphRect, 0, [self.view retinaRound:-self.font.descender] + self.statusBarComponentVerticalOffset);

    return graphRect;
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

- (NSString *)leftText {
    return [NSString stringWithFormat:@"%d%%", self.currentEstimate];
}

- (NSString *)rightText {
    return @"";
}

- (void)drawRect:(NSRect)rect {
    CGSize rightSize = self.rightSize;
    
    [self drawTextWithRect:rect
                      left:self.leftText
                     right:self.rightText
                 rightSize:rightSize];

    NSRect graphRect = [self graphRectForRect:rect leftSize:self.leftSize rightSize:rightSize];

    [super drawRect:graphRect];
}

#pragma mark - Private

- (void)update:(double)value {
    [_samples addObject:@(value)];
    while (_samples.count > self.maximumNumberOfValues) {
        [_samples removeObjectAtIndex:0];
    }
}

@end

NS_ASSUME_NONNULL_END
