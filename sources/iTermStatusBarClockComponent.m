//
//  iTermStatusBarClockComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/1/18.
//

#import "iTermStatusBarClockComponent.h"
#import "NSDictionary+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermStatusBarClockComponentFormatKey = @"format";

@implementation iTermStatusBarClockComponent {
    NSDateFormatter *_dateFormatter;
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
    return @[ formatKnob ];
}

+ (NSDictionary *)statusBarComponentDefaultKnobs {
    NSDictionary *fromSuper = [super statusBarComponentDefaultKnobs];
    return [fromSuper dictionaryByMergingDictionary:@{ iTermStatusBarClockComponentFormatKey: @"MM-dd hh:mm" }];
}

- (id)statusBarComponentExemplar {
    return @"Clock";
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (NSDateFormatter *)dateFormatter {
    if (!_dateFormatter) {
        _dateFormatter = [[NSDateFormatter alloc] init];
        NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
        _dateFormatter.dateFormat = knobValues[iTermStatusBarClockComponentFormatKey] ?: @"MM-dd hh:mm";
    }
    return _dateFormatter;
}

- (nullable NSString *)stringValue {
    return [self.dateFormatter stringFromDate:[NSDate date]];
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
