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
    if ([self count] < 3) {
        return [NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:1.0];
    }
    
    NSString *colorSpace = self[kEncodedColorDictionaryColorSpace];
    if ([colorSpace isEqualToString:kEncodedColorDictionarySRGBColorSpace]) {
        NSColor *srgb = [NSColor colorWithSRGBRed:[[self objectForKey:kEncodedColorDictionaryRedComponent] floatValue]
                                            green:[[self objectForKey:kEncodedColorDictionaryGreenComponent] floatValue]
                                             blue:[[self objectForKey:kEncodedColorDictionaryBlueComponent] floatValue]
                                            alpha:1.0];
        return [srgb colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    } else {
        return [NSColor colorWithCalibratedRed:[[self objectForKey:kEncodedColorDictionaryRedComponent] floatValue]
                                         green:[[self objectForKey:kEncodedColorDictionaryGreenComponent] floatValue]
                                          blue:[[self objectForKey:kEncodedColorDictionaryBlueComponent] floatValue]
                                         alpha:1.0];
    }
}

@end
