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

+ (NSDictionary *)dictionaryWithGridCoord:(VT100GridCoord)coord {
    return @{ @"x": @(coord.x),
              @"y": @(coord.y) };
}

- (VT100GridCoord)gridCoord {
    return VT100GridCoordMake([self[@"x"] intValue],
                              [self[@"y"] intValue]);
}

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
