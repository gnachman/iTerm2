//
//  iTermStatusBarBatteryComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/7/19.
//

#import "iTermStatusBarBatteryComponent.h"

#import "iTermPowerManager.h"
#import "NSArray+iTerm.h"
#import "NSDateFormatterExtras.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSView+iTerm.h"

static const CGFloat iTermBatteryWidth = 120;
static NSString *const iTermBatteryComponentKnobKeyShowPercentage = @"ShowPercentage";
static NSString *const iTermBatteryComponentKnobKeyShowTime = @"ShowTime";

@implementation iTermStatusBarBatteryComponent {
    NSImage *_chargingImage;
}


- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    self = [super initWithConfiguration:configuration scope:scope];
    if (self) {
        __weak __typeof(self) weakSelf = self;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(powerManagerStateDidChange:)
                                                     name:iTermPowerManagerStateDidChange
                                                   object:nil];
        _chargingImage = [NSImage it_imageNamed:@"StatusBarIconCharging" forClass:self.class];
        [[iTermPowerManager sharedInstance] addPowerStateSubscriber:self block:^(iTermPowerState *state) {
            [weakSelf update:state];
        }];
    }
    return self;
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *showPercentageKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Show Percentage"
                                                      type:iTermStatusBarComponentKnobTypeCheckbox
                                               placeholder:nil
                                              defaultValue:@YES
                                                       key:iTermBatteryComponentKnobKeyShowPercentage];
    iTermStatusBarComponentKnob *showEstimatedTimeKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Show Estimated Time"
                                                      type:iTermStatusBarComponentKnobTypeCheckbox
                                               placeholder:nil
                                              defaultValue:@NO
                                                       key:iTermBatteryComponentKnobKeyShowTime];
    return [@[ showPercentageKnob, showEstimatedTimeKnob ] arrayByAddingObjectsFromArray:[super statusBarComponentKnobs]];
}

+ (BOOL)machineHasBattery {
    static dispatch_once_t onceToken;
    static BOOL result;
    dispatch_once(&onceToken, ^{
        if ([[iTermPowerManager sharedInstance] currentState] == nil) {
            result = NO;
        } else {
            result = YES;
        }
    });
    return result;
}

- (NSImage *)statusBarComponentIcon {
    static dispatch_once_t onceToken;
    static NSImage *image;
    dispatch_once(&onceToken, ^{
        if ([self.class machineHasBattery]) {
            image = [NSImage it_imageNamed:@"StatusBarIconBattery" forClass:[self class]];
        } else {
            image = [NSImage it_imageNamed:@"StatusBarIconNoBattery" forClass:[self class]];
        }
    });
    return image;
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
    return [[[iTermPowerManager sharedInstance] percentageSamples] mapWithBlock:^id(NSNumber *percentage) {
        return @(percentage.doubleValue / 100.0);
    }];
}

- (int)currentEstimate {
    const double x = [[[[iTermPowerManager sharedInstance] currentState] percentage] doubleValue];
    return x;
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
    if (!self.showPercentage) {
        return NSMakeSize(0, 0);
    }
    NSString *longestPercentage = @"100%";
    return [longestPercentage sizeWithAttributes:self.leftAttributes];
}

- (BOOL)isCharging {
    return [self.class machineHasBattery] && [[iTermPowerManager sharedInstance] connectedToPower];
}

- (CGSize)rightSize {
    CGSize size = [@"" sizeWithAttributes:self.rightAttributes];
    if (self.showTimeOnRight) {
        size.width += [@"55:55" sizeWithAttributes:self.rightAttributes].width;
        const BOOL charging = self.isCharging;
        if (!charging) {
            return size;
        }
    }
    size.width += _chargingImage.size.width;
    return size;
}

- (BOOL)showPercentage {
    NSDictionary *knobs = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobs[iTermBatteryComponentKnobKeyShowPercentage] ?: @YES boolValue];
}

- (BOOL)showTime {
    const BOOL charging = self.isCharging;
    if (self.currentEstimate == 100 && charging) {
        return NO;
    }
    iTermPowerState *currentState = [[iTermPowerManager sharedInstance] currentState];
    if ([currentState time].doubleValue < 1) {
        return NO;
    }
    if (currentState.charging != charging) {
        return NO;
    }
    NSDictionary *knobs = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobs[iTermBatteryComponentKnobKeyShowTime] ?: @NO boolValue];
}

- (BOOL)showTimeOnRight {
    return (self.showTime &&
            self.showPercentage);
}

- (NSString *)leftText {
    if ([[[iTermPowerManager sharedInstance] currentState] percentage] == nil) {
        return @"";
    }
    if (self.showPercentage) {
        return [NSString stringWithFormat:@"%d%%", self.currentEstimate];
    }
    if (self.showTime) {
        return [NSDateFormatter durationString:[[[[iTermPowerManager sharedInstance] currentState] time] doubleValue]];
    }
    return @"";
}

- (NSString *)rightText {
    if ([[[iTermPowerManager sharedInstance] currentState] percentage] == nil) {
        return @"";
    }
    if (self.showTimeOnRight) {
        return [NSDateFormatter durationString:[[[[iTermPowerManager sharedInstance] currentState] time] doubleValue]];
    }
    return @"";
}

- (void)drawRect:(NSRect)rect {
    CGSize rightSize = self.rightSize;

    NSRect textRect = rect;
    const BOOL charging = self.isCharging;
    if (self.showTimeOnRight && charging) {
        textRect.size.width -= _chargingImage.size.width;
    }
    [self drawTextWithRect:textRect
                      left:self.leftText
                     right:self.rightText
                 rightSize:rightSize];

    NSRect graphRect = [self graphRectForRect:rect leftSize:self.leftSize rightSize:rightSize];

    if (charging) {
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
    [self invalidate];
}

- (void)powerManagerStateDidChange:(NSNotification *)notification {
    [self invalidate];
}

@end
