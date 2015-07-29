//
//  NSDictionary+iTerm.m
//  iTerm
//
//  Created by George Nachman on 1/2/14.
//
//

#import "NSDictionary+iTerm.h"
#import "NSColor+iTerm.h"

static NSString *const kGridCoordXKey = @"x";
static NSString *const kGridCoordYKey = @"y";
static NSString *const kGridCoordAbsYKey = @"absY";
static NSString *const kGridCoordStartKey = @"start";
static NSString *const kGridCoordEndKey = @"end";
static NSString *const kGridCoordRange = @"Coord Range";
static NSString *const kGridRange = @"Range";
static NSString *const kGridRangeLocation = @"Location";
static NSString *const kGridRangeLength = @"Length";
static NSString *const kGridSizeWidth = @"Width";
static NSString *const kGridSizeHeight = @"Height";

@implementation NSDictionary (iTerm)

+ (NSDictionary *)dictionaryWithGridCoord:(VT100GridCoord)coord {
    return @{ kGridCoordXKey: @(coord.x),
              kGridCoordYKey: @(coord.y) };
}

- (VT100GridCoord)gridCoord {
    return VT100GridCoordMake([self[kGridCoordXKey] intValue],
                              [self[kGridCoordYKey] intValue]);
}

+ (NSDictionary *)dictionaryWithGridAbsCoord:(VT100GridAbsCoord)coord {
    return @{ kGridCoordXKey: @(coord.x),
              kGridCoordAbsYKey: @(coord.y) };
}

- (VT100GridAbsCoord)gridAbsCoord {
    return VT100GridAbsCoordMake([self[kGridCoordXKey] intValue],
                                 [self[kGridCoordAbsYKey] longLongValue]);
}

+ (NSDictionary *)dictionaryWithGridAbsCoordRange:(VT100GridAbsCoordRange)coordRange {
    return @{ kGridCoordStartKey: [self dictionaryWithGridAbsCoord:coordRange.start],
              kGridCoordEndKey: [self dictionaryWithGridAbsCoord:coordRange.end] };
}

- (VT100GridAbsCoordRange)gridAbsCoordRange {
    VT100GridAbsCoord start = [self[kGridCoordStartKey] gridAbsCoord];
    VT100GridAbsCoord end = [self[kGridCoordEndKey] gridAbsCoord];
    return VT100GridAbsCoordRangeMake(start.x, start.y, end.x, end.y);
}

+ (NSDictionary *)dictionaryWithGridCoordRange:(VT100GridCoordRange)coordRange {
    return @{ kGridCoordStartKey: [self dictionaryWithGridCoord:coordRange.start],
              kGridCoordEndKey: [self dictionaryWithGridCoord:coordRange.end] };
}

- (VT100GridCoordRange)gridCoordRange {
    VT100GridCoord start = [self[kGridCoordStartKey] gridCoord];
    VT100GridCoord end = [self[kGridCoordEndKey] gridCoord];
    return VT100GridCoordRangeMake(start.x, start.y, end.x, end.y);
}

+ (NSDictionary *)dictionaryWithGridWindowedRange:(VT100GridWindowedRange)range {
    return @{ kGridCoordRange: [NSDictionary dictionaryWithGridCoordRange:range.coordRange],
              kGridRange: [NSDictionary dictionaryWithGridRange:range.columnWindow] };
}

- (VT100GridWindowedRange)gridWindowedRange {
    VT100GridWindowedRange range;
    range.coordRange = [self[kGridCoordRange] gridCoordRange];
    range.columnWindow = [self[kGridRange] gridRange];
    return range;
}

+ (NSDictionary *)dictionaryWithGridRange:(VT100GridRange)range {
    return @{ kGridRangeLocation: @(range.location),
              kGridRangeLength: @(range.length) };
}

- (VT100GridRange)gridRange {
    return VT100GridRangeMake([self[kGridRangeLocation] intValue],
                              [self[kGridRangeLength] intValue]);
}

+ (NSDictionary *)dictionaryWithGridSize:(VT100GridSize)size {
    return @{ kGridSizeWidth: @(size.width),
              kGridSizeHeight: @(size.height) };
}

- (VT100GridSize)gridSize {
    return VT100GridSizeMake([self[kGridSizeWidth] intValue], [self[kGridSizeHeight] intValue]);
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

- (NSDictionary *)dictionaryByRemovingNullValues {
    NSMutableDictionary *temp = [NSMutableDictionary dictionary];
    for (id key in self) {
        id value = self[key];
        if (![value isKindOfClass:[NSNull class]]) {
            temp[key] = value;
        }
    }
    return temp;
}

@end
