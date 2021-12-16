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
    return self.localizedName;
}
@end
