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

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarNetworkUtilizationComponent {
    NSMutableArray<NSArray<NSNumber *> *> *_samples;
    double _ceiling;
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    self = [super initWithConfiguration:configuration scope:scope];
    if (self) {
        _ceiling = 1;
        _samples = [NSMutableArray array];
        __weak __typeof(self) weakSelf = self;
        [[iTermNetworkUtilization sharedInstance] addSubscriber:self block:^(double down, double up) {
            [weakSelf updateWithDown:down up:up];
        }];
    }
    return self;
}

- (NSImage *)statusBarComponentIcon {
    return [NSImage it_imageNamed:@"StatusBarIconNetwork" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return @"Network Throughput";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Shows current network throughput.";
}

- (id)statusBarComponentExemplar {
    return @"2 MB↓ ▃▃▅▂ 1 MB↑";
}

- (BOOL)statusBarComponentCanStretch {
    return NO;
}

- (NSTimeInterval)statusBarComponentUpdateCadence {
    return 1;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return iTermNetworkUtilizationWidth;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return iTermNetworkUtilizationWidth;
}

- (NSArray *)values {
    return _samples;
}

- (NSInteger)numberOfTimeSeries {
    return 2;
}

- (double)ceiling {
    return _ceiling;
}

- (double)downThroughput {
    return _samples.lastObject[0].doubleValue;
}

- (double)upThroughput {
    return _samples.lastObject[1].doubleValue;
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

- (NSString *)leftText {
    return [NSString stringWithFormat:@"%@↓", [NSString it_formatBytesCompact:self.downThroughput]];
}

- (NSString *)rightText {
    return [NSString stringWithFormat:@"%@↑", [NSString it_formatBytesCompact:self.upThroughput]];
}

- (CGSize)rightSize {
    return [self.rightText sizeWithAttributes:self.rightAttributes];
}

- (CGSize)leftSize {
    return [self.leftText sizeWithAttributes:self.leftAttributes];
}

- (void)drawRect:(NSRect)rect {
    CGSize rightSize = self.rightSize;

    [self drawTextWithRect:rect
                      left:self.leftText
                     right:self.rightText
                 rightSize:rightSize];

    NSRect graphRect = [self graphRectForRect:rect
                                     leftSize:self.leftSize
                                    rightSize:rightSize];

    [super drawRect:graphRect];
}

#pragma mark - Private

- (void)updateWithDown:(double)down up:(double)up {
    [_samples addObject:@[ @(down), @(up) ]];
    while (_samples.count > self.maximumNumberOfValues) {
        [_samples removeObjectAtIndex:0];
    }
    _ceiling = [[[_samples flatMapWithBlock:^NSArray *(NSArray<NSNumber *> *anObject) {
        return anObject;
    }] maxWithBlock:^NSComparisonResult(NSNumber *n1, NSNumber *n2) {
        return [n1 compare:n2];
    }] doubleValue];
}

@end

NS_ASSUME_NONNULL_END
