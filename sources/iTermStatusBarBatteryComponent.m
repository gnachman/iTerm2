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
        result = [[iTermPowerManager sharedInstance] hasBattery];
    });
    return result;
}

- (NSImage *)statusBarComponentIcon {
    static dispatch_once_t onceToken;
    static NSImage *image;
    dispatch_once(&onceToken, ^{
        if ([self.class machineHasBattery]) {
            image = [NSImage it_cacheableImageNamed:@"StatusBarIconBattery" forClass:[self class]];
        } else {
            image = [NSImage it_cacheableImageNamed:@"StatusBarIconNoBattery" forClass:[self class]];
        }
    });
    return image;
}

- (BOOL)statusBarComponentIsEmpty {
    return ![self.class machineHasBattery];
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

- (CGFloat)statusBarComponentMinimumWidth {
    return iTermBatteryWidth;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return iTermBatteryWidth;
}

- (double)ceiling {
    return 1.0;
}

- (iTermStatusBarSparklinesModel *)sparklinesModel {
    NSArray<NSNumber *> *values = [[[iTermPowerManager sharedInstance] percentageSamples] mapWithBlock:^id(NSNumber *anObject) {
        return @(anObject.doubleValue / 100.0);
    }];
    iTermStatusBarTimeSeries *timeSeries = [[iTermStatusBarTimeSeries alloc] initWithValues:values];
    iTermStatusBarTimeSeriesRendition *rendition =
    [[iTermStatusBarTimeSeriesRendition alloc] initWithTimeSeries:timeSeries
                                                            color:[self statusBarTextColor]];
    return [[iTermStatusBarSparklinesModel alloc] initWithDictionary:@{ @"main": rendition}];
}

- (int)currentEstimate {
    const double x = [[[[iTermPowerManager sharedInstance] currentState] percentage] doubleValue];
    return x;
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
    if (!self.showPercentage) {
        return NSMakeSize(0, 0);
    }
    NSString *longestPercentage = @"100%";
    return [longestPercentage sizeWithAttributes:self.leftAttributes];
}

- (BOOL)isCharging {
    return [self.class machineHasBattery] && [[iTermPowerManager sharedInstance] connectedToPower];
}

- (NSImage *)rightImage {
    if (!self.isCharging) {
        return nil;
    }
    return _chargingImage;
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
