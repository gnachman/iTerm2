//
//  NSColorSpace+CPK.m
//  ColorPicker
//
//  Created by George Nachman on 12/15/21.
//  Copyright © 2021 Google. All rights reserved.
//

#import "NSColorSpace+CPK.h"

@implementation NSColorSpace(CPK)
- (NSString *)cpk_shortLocalizedName {
    if ([self isEqual:[NSColorSpace sRGBColorSpace]]) {
        return @"sRGB";
    }
    if ([self isEqual:[NSColorSpace displayP3ColorSpace]]) {
        return @"P3";
    }
    return @"Dev";
}

+ (NSColorSpace *)cpk_supportedColorSpaceForColorSpace:(NSColorSpace *)colorSpace {
    if (!colorSpace) {
        return [NSColorSpace sRGBColorSpace];
    }

    // If it's already one of the supported colorspaces, return it as-is
    if ([colorSpace isEqual:[NSColorSpace displayP3ColorSpace]]) {
        return [NSColorSpace displayP3ColorSpace];
    }
    if ([colorSpace isEqual:[NSColorSpace sRGBColorSpace]]) {
        return [NSColorSpace sRGBColorSpace];
    }
    if ([colorSpace isEqual:[NSColorSpace deviceRGBColorSpace]]) {
        return [NSColorSpace deviceRGBColorSpace];
    }

    // Check the colorspace model to determine the best match
    NSColorSpaceModel model = [colorSpace colorSpaceModel];

    // Default to P3. If you take a screenshot, you'll get the device's color space
    // (e.g., "LG UltraFine colorspace"). If we picked a small-gamut space like sRGB by default,
    // you'd lose the ability to pick certain colors.
    if (model == NSColorSpaceModelRGB) {
        return [NSColorSpace displayP3ColorSpace];
    }

    // For device colorspaces, use device RGB
    if (model == NSColorSpaceModelDeviceN) {
        return [NSColorSpace deviceRGBColorSpace];
    }

    return [NSColorSpace displayP3ColorSpace];
}
@end
