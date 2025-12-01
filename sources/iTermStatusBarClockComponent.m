//
//  iTermStatusBarClockComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/1/18.
//

#import "iTermStatusBarClockComponent.h"

#import "NSArray+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "iTermObject.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "iTermVariableScope+Session.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermStatusBarClockComponentFormatKey = @"format";
static NSString *const iTermStatusBarClockComponentLocalizeKey = @"localize";
static NSString *const iTermStatusBarClockComponentSSHSyncKey = @"ssh_offset";
static NSString *const iTermStatusBarClockComponentSSHSyncTimeZoneKey = @"ssh_tz";

@implementation iTermStatusBarClockComponent {
    NSDateFormatter *_dateFormatter;
    iTermVariableReference *_sshref;
    iTermVariableReference *_hostref;
    NSTimeInterval _offset;
    NSTimeZone *_timeZone;
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(iTermVariableScope * _Nullable)scope {
    self = [super initWithConfiguration:configuration scope:scope];
    if (self) {
        if (scope) {
            __weak __typeof(self) weakSelf = self;
            _sshref = [[iTermVariableReference alloc] initWithPath:iTermVariableKeySSHIntegrationLevel vendor:scope];
            _sshref.onChangeBlock = ^{
                [weakSelf fetchTimeOffset];
            };
            _hostref = [[iTermVariableReference alloc] initWithPath:iTermVariableKeySessionHostname vendor:scope];
            _hostref.onChangeBlock = ^{
                [weakSelf fetchTimeOffset];
            };
            [self fetchTimeOffset];
        }
    }
    return self;
}

- (void)fetchTimeOffset {
    id obj = [self.scope valueForVariableName:iTermVariableKeySSHIntegrationLevel];
    if (!obj) {
        return;
    }
    NSNumber *number = [NSNumber castFrom:obj];
    if (!number) {
        return;
    }
    const int level = [number intValue];
    if (level < 2) {
        [self setTimeOffset:0 timeZoneName:nil];
        return;
    }
    __weak __typeof(self) weakSelf = self;
    iTermCallMethodByIdentifier(self.scope.ID,
                                @"iterm2.get_time_offset",
                                @{},
                                ^(id obj, NSError *error) {
        if (error) {
            [weakSelf setTimeOffset:0 timeZoneName:nil];
        } else {
            NSDictionary *dict = [NSDictionary castFrom:obj];
            NSNumber *offset = [NSNumber castFrom:dict[@"offset"]];
            NSString *tz = [NSString castFrom:dict[@"tz"]];
            if (offset && tz) {
                [weakSelf setTimeOffset:offset.doubleValue timeZoneName:tz];
            }
        }
    });
    // Update every 15 minutes in case something changes (server time, DST, who knows: time is hell)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * 60 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf fetchTimeOffset];
    });
}

- (void)setTimeOffset:(NSTimeInterval)timeOffset
         timeZoneName:(NSString * _Nullable)timeZoneName {
    _offset = timeOffset;
    if (timeZoneName) {
        _timeZone = [NSTimeZone timeZoneWithAbbreviation:timeZoneName] ?: [[NSTimeZone alloc] initWithName:timeZoneName];
    } else {
        _timeZone = nil;
    }
    _dateFormatter = nil;
}

- (nullable NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconClock" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return @"Clock";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Shows current date and time with a configurable format.";
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *formatKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Date Format:"
                                                          type:iTermStatusBarComponentKnobTypeText
                                                   placeholder:@"Date Format (Unicode TR 35)"
                                                  defaultValue:self.class.statusBarComponentDefaultKnobs[iTermStatusBarClockComponentFormatKey]
                                                           key:iTermStatusBarClockComponentFormatKey];
    formatKnob.helpURL = [NSURL URLWithString:@"https://iterm2.com/clock-status-bar-component-help"];
    iTermStatusBarComponentKnob *dateFormatIsTemplate =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Localize Date Format"
                                                          type:iTermStatusBarComponentKnobTypeCheckbox
                                                   placeholder:nil
                                                  defaultValue:@YES
                                                           key:iTermStatusBarClockComponentLocalizeKey];
    iTermStatusBarComponentKnob *syncKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Show server time in SSH integration?"
                                                      type:iTermStatusBarComponentKnobTypeCheckbox
                                               placeholder:nil
                                              defaultValue:@YES
                                                       key:iTermStatusBarClockComponentSSHSyncKey];
    iTermStatusBarComponentKnob *syncTimeZoneKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Use server time zone in SSH integration?"
                                                      type:iTermStatusBarComponentKnobTypeCheckbox
                                               placeholder:nil
                                              defaultValue:@YES
                                                       key:iTermStatusBarClockComponentSSHSyncTimeZoneKey];
    return [ @[ formatKnob, dateFormatIsTemplate, syncKnob, syncTimeZoneKnob, [super statusBarComponentKnobs] ] flattenedArray];
}

+ (NSDictionary *)statusBarComponentDefaultKnobs {
    NSDictionary *fromSuper = [super statusBarComponentDefaultKnobs];
    return [fromSuper dictionaryByMergingDictionary:@{ iTermStatusBarClockComponentFormatKey: @"M/dd h:mm" }];
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return [[self dateFormatter] stringFromDate:[NSDate date]];
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (BOOL)sshTimeZoneEnabled {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarClockComponentSSHSyncTimeZoneKey] ?: @YES boolValue];
}

- (NSDateFormatter *)dateFormatter {
    if (!_dateFormatter) {
        _dateFormatter = [[NSDateFormatter alloc] init];
        NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
        NSString *template = knobValues[iTermStatusBarClockComponentFormatKey] ?: @"M/dd h:mm";
        if ([knobValues[iTermStatusBarClockComponentLocalizeKey] ?: @YES boolValue]) {
            _dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:template options:0 locale:[NSLocale currentLocale]];
        } else {
            _dateFormatter.dateFormat = template;
        }
        if (self.sshTimeZoneEnabled && _timeZone != nil) {
            _dateFormatter.timeZone = _timeZone;
        }
    }
    return _dateFormatter;
}

- (BOOL)sshTimeEnabled {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarClockComponentSSHSyncKey] ?: @YES boolValue];
}

- (nullable NSString *)stringValue {
    NSTimeInterval offset = 0;
    if (_offset != 0 && self.sshTimeEnabled) {
        offset = _offset;
    }
    NSDate *date = [NSDate dateWithTimeIntervalSinceNow:offset];
    NSString *string = [self.dateFormatter stringFromDate:date];
    if ((_offset != 0 || _timeZone != nil) &&
        (self.sshTimeEnabled || self.sshTimeZoneEnabled)) {
        string = [string stringByAppendingString:@" 🌐︎"];
    }
    return string;
}

- (nullable NSString *)stringValueForCurrentWidth {
    return self.stringValue;
}

- (void)statusBarComponentSetKnobValues:(NSDictionary *)knobValues {
    _dateFormatter = nil;
    [super statusBarComponentSetKnobValues:knobValues];
}

- (NSTimeInterval)statusBarComponentUpdateCadence {
    return 1;
}

- (nullable NSArray<NSString *> *)stringVariants {
    return @[ self.stringValue ?: @"" ];
}

@end

NS_ASSUME_NONNULL_END
