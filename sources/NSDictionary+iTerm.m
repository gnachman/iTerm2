//
//  NSDictionary+iTerm.m
//  iTerm
//
//  Created by George Nachman on 1/2/14.
//
//

#import "NSDictionary+iTerm.h"
#import "NSColor+iTerm.h"

@implementation NSDictionary (iTerm)

- (BOOL)boolValueDefaultingToYesForKey:(id)key
{
    id object = [self objectForKey:key];
    if (object) {
        return [object boolValue];
    } else {
        return YES;
    }
}

- (NSColor *)colorValue {
    return [self colorValueWithDefaultAlpha:1.0];
}

- (NSColor *)colorValueWithDefaultAlpha:(CGFloat)alpha {
    if ([self count] < 3) {
        return [NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:1.0];
    }

    NSNumber *alphaNumber = self[kEncodedColorDictionaryAlphaComponent];
    if (alphaNumber) {
        alpha = alphaNumber.doubleValue;
    }
    NSString *colorSpace = self[kEncodedColorDictionaryColorSpace];
    // XXX chopps colorspace default -- want some way to specify default to non-calibrated if from external.
    // XXX we do not want to save colorspaces in calibrated as they aren't portable then.
    // XXX checking for colorSpace == nil here though doesn't work great as things keep getting darker
    // XXX as we save and load spaces.
    if ([colorSpace isEqualToString:kEncodedColorDictionarySRGBColorSpace]) {
        NSColor *srgb = [NSColor colorWithSRGBRed:[[self objectForKey:kEncodedColorDictionaryRedComponent] floatValue]
                                            green:[[self objectForKey:kEncodedColorDictionaryGreenComponent] floatValue]
                                             blue:[[self objectForKey:kEncodedColorDictionaryBlueComponent] floatValue]
                                            alpha:alpha];
        return [srgb colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    } else {
        return [NSColor colorWithCalibratedRed:[[self objectForKey:kEncodedColorDictionaryRedComponent] floatValue]
                                         green:[[self objectForKey:kEncodedColorDictionaryGreenComponent] floatValue]
                                          blue:[[self objectForKey:kEncodedColorDictionaryBlueComponent] floatValue]
                                         alpha:alpha];
    }
}

@end
