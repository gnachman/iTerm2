//
//  iTermStatusBarBatteryComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/7/19.
//

#import "iTermStatusBarBatteryComponent.h"
#import "iTermPowerManager.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSView+iTerm.h"

static const CGFloat iTermBatteryWidth = 120;

@implementation iTermStatusBarBatteryComponent {
    NSMutableArray<NSNumber *> *_samples;
    NSImage *_chargingImage;
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    self = [super initWithConfiguration:configuration scope:scope];
    if (self) {
        _samples = [NSMutableArray array];
        __weak __typeof(self) weakSelf = self;
        [[iTermPowerManager sharedInstance] addPowerStateSubscriber:self block:^(iTermPowerState *state) {
            [weakSelf update:state];
        }];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(powerManagerStateDidChange:)
                                                     name:iTermPowerManagerStateDidChange
                                                   object:nil];
        _chargingImage = [NSImage it_imageNamed:@"StatusBarIconCharging" forClass:self.class];
    }
    return self;
}

- (NSImage *)statusBarComponentIcon {
    return [NSImage it_imageNamed:@"StatusBarIconBattery" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return @"Battery Level";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Shows current battery level and its recent history.";
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return @"95% ▂▃▅▇ Batt";
}

- (BOOL)statusBarComponentCanStretch {
    return NO;
}

- (NSTimeInterval)statusBarComponentUpdateCadence {
    return 60;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return iTermBatteryWidth;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return iTermBatteryWidth;
}

- (NSArray<NSNumber *> *)values {
    return _samples;
}

- (int)currentEstimate {
    double x = _samples.lastObject.doubleValue;
    return x * 100;
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

- (CGFloat)textOffset {
    NSFont *font = self.advancedConfiguration.font ?: [iTermStatusBarAdvancedConfiguration defaultFont];
    const CGFloat containerHeight = self.view.superview.bounds.size.height;
    const CGFloat capHeight = font.capHeight;
    const CGFloat descender = font.descender - font.leading;  // negative (distance from bottom of bounding box to baseline)
    const CGFloat frameY = (containerHeight - self.view.frame.size.height) / 2;
    const CGFloat origin = containerHeight / 2.0 - frameY + descender - capHeight / 2.0;
    return origin;
}

- (NSSize)leftSize {
    NSString *longestPercentage = @"100%";
    return [longestPercentage sizeWithAttributes:self.leftAttributes];
}

- (CGSize)rightSize {
    CGSize size = [self.rightText sizeWithAttributes:self.rightAttributes];
    size.width += _chargingImage.size.width;
    return size;
}

- (NSString *)leftText {
    if (_samples.count == 0) {
        return @"";
    }
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

    if ([[iTermPowerManager sharedInstance] connectedToPower]) {
        NSImage *tintedImage = [_chargingImage it_imageWithTintColor:[self statusBarTextColor] ?: [self.delegate statusBarComponentDefaultTextColor]];
        [tintedImage drawInRect:NSMakeRect(NSMaxX(rect) - _chargingImage.size.width,
                                           [self.view retinaRound:(rect.size.height - _chargingImage.size.height) / 2.0],
                                           _chargingImage.size.width,
                                           _chargingImage.size.height)
                       fromRect:NSZeroRect
                      operation:NSCompositingOperationSourceOver
                       fraction:1];
    }

    [super drawRect:graphRect];
}

#pragma mark - Private

- (void)update:(iTermPowerState *)state {
    if (state.percentage == nil) {
        return;
    }
    [_samples addObject:@(state.percentage.doubleValue / 100.0)];
    while (_samples.count > self.maximumNumberOfValues) {
        [_samples removeObjectAtIndex:0];
    }
    [self invalidate];
}

- (void)powerManagerStateDidChange:(NSNotification *)notification {
    [self invalidate];
}

@end
