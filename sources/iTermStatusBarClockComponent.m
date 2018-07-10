//
//  iTermStatusBarClockComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/1/18.
//

#import "iTermStatusBarClockComponent.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermStatusBarClockComponentFormatKey = @"format";

@implementation iTermStatusBarClockComponent {
    NSDateFormatter *_dateFormatter;
}

+ (NSString *)statusBarComponentShortDescription {
    return @"Clock";
}

+ (NSString *)statusBarComponentDetailedDescription {
    return @"Shows current date and time with a configurable format.";
}

+ (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *formatKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Date Format:"
                                                          type:iTermStatusBarComponentKnobTypeText
                                                   placeholder:@"Date Format (Unicode TR 35)"
                                                  defaultValue:@"MM-dd hh:mm"
                                                           key:iTermStatusBarClockComponentFormatKey];
    return @[ formatKnob ];
}

- (id)statusBarComponentExemplar {
    return @"Clock";
}

+ (BOOL)statusBarComponentCanStretch {
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

- (void)statusBarComponentSetKnobValues:(NSDictionary *)knobValues {
    _dateFormatter = nil;
    [super statusBarComponentSetKnobValues:knobValues];
}

- (NSTimeInterval)statusBarComponentUpdateCadence {
    return 1;
}

@end

NS_ASSUME_NONNULL_END
