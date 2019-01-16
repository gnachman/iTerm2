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

@implementation iTermStatusBarMemoryUtilizationComponent {
    NSMutableArray<NSNumber *> *_samples;
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    self = [super initWithConfiguration:configuration scope:scope];
    if (self) {
        _samples = [NSMutableArray array];
        __weak __typeof(self) weakSelf = self;
        [[iTermMemoryUtilization sharedInstance] addSubscriber:self block:^(long long value) {
            [weakSelf update:value];
        }];
    }
    return self;
}

- (NSImage *)statusBarComponentIcon {
    return [NSImage it_imageNamed:@"StatusBarIconRAM" forClass:[self class]];
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

- (NSTimeInterval)statusBarComponentUpdateCadence {
    return 1;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return iTermMemoryUtilizationWidth;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return iTermMemoryUtilizationWidth;
}

- (NSArray<NSNumber *> *)values {
    return _samples;
}

- (long long)currentEstimate {
    return  _samples.lastObject.doubleValue * [[iTermMemoryUtilization sharedInstance] availableMemory];
}

- (void)drawTextWithRect:(NSRect)rect
                    left:(NSString *)left
                   right:(NSString *)right
               rightSize:(CGSize)rightSize {
    NSRect textRect = rect;
    textRect.size.height = rightSize.height;
    textRect.origin.y = [self textOffset];
    [left drawInRect:textRect withAttributes:[self.leftAttributes it_attributesDictionaryWithAppearance:self.view.effectiveAppearance]];
    [right drawInRect:textRect withAttributes:[self.rightAttributes it_attributesDictionaryWithAppearance:self.view.effectiveAppearance]];
}

- (CGFloat)textOffset {
    NSFont *font = self.advancedConfiguration.font ?: [iTermStatusBarAdvancedConfiguration defaultFont];
    const CGFloat containerHeight = self.view.superview.bounds.size.height;
    const CGFloat capHeight = font.capHeight;
    const CGFloat descender = font.descender - font.leading;  // negative (distance from bottom of bounding box to baseline)
    const CGFloat frameY = (containerHeight - self.view.frame.size.height) / 2;
    const CGFloat origin = containerHeight / 2.0 - frameY + descender - capHeight / 2.0;
    return origin;
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

- (CGSize)rightSize {
    return [self.rightText sizeWithAttributes:self.rightAttributes];
}

- (NSString *)leftText {
    return [NSString it_formatBytes:self.currentEstimate];
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

    NSRect graphRect = [self graphRectForRect:rect
                                     leftSize:[self.leftText sizeWithAttributes:self.leftAttributes]
                                    rightSize:rightSize];

    [super drawRect:graphRect];
}

#pragma mark - Private

- (void)update:(double)value {
    double available = [[iTermMemoryUtilization sharedInstance] availableMemory];
    [_samples addObject:@(value / available)];
    while (_samples.count > self.maximumNumberOfValues) {
        [_samples removeObjectAtIndex:0];
    }
}

@end

NS_ASSUME_NONNULL_END
