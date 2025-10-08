//
//  NSColor+CPK.m
//  ColorPicker
//
//  Created by George Nachman on 9/16/15.
//  Copyright (c) 2015 Google. All rights reserved.
//

#import "NSColor+CPK.h"

@implementation NSColor (CPK)

+ (NSColor *)cpk_colorWithRed:(CGFloat)red
                        green:(CGFloat)green
                         blue:(CGFloat)blue
                        alpha:(CGFloat)alpha
                   colorSpace:(NSColorSpace *)colorSpace {
    CGFloat components[] = {
        red, green, blue, alpha
    };
    return [NSColor colorWithColorSpace:colorSpace components:components count:4];
}

- (BOOL)isApproximatelyEqualToColor:(NSColor *)color {
    int myRed = self.redComponent * 255;
    int myGreen = self.greenComponent * 255;
    int myBlue = self.blueComponent * 255;
    int myAlpha = self.alphaComponent * 255;

    int otherRed = color.redComponent * 255;
    int otherGreen = color.greenComponent * 255;
    int otherBlue = color.blueComponent * 255;
    int otherAlpha = color.alphaComponent * 255;

    return (myRed == otherRed &&
            myGreen == otherGreen &&
            myBlue == otherBlue &&
            myAlpha == otherAlpha);
}

- (NSColor *)cpk_colorUsingColorSpace:(NSColorSpace *)colorSpace lossy:(out BOOL *)clippedPtr {
    NSColor *converted = [self colorUsingColorSpace:colorSpace];
    BOOL clipped = NO;
    if ([colorSpace isEqual:NSColorSpace.sRGBColorSpace]) {
        NSColor *extended = [self colorUsingColorSpace:NSColorSpace.extendedSRGBColorSpace];
        clipped = (extended.redComponent < 0 ||
                   extended.redComponent > 1 ||
                   extended.greenComponent < 0 ||
                   extended.greenComponent > 1 ||
                   extended.blueComponent < 0 ||
                   extended.blueComponent > 1);
    } else if ([colorSpace isEqual:NSColorSpace.deviceRGBColorSpace]) {
        NSColor *deviceRGB = [self colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
        NSColor *backformed = [deviceRGB colorUsingColorSpace:self.colorSpace];
        const CGFloat epsilon = 0.005;
        clipped = (fabs(backformed.redComponent - self.redComponent) > epsilon ||
                   fabs(backformed.greenComponent - self.greenComponent) > epsilon ||
                   fabs(backformed.blueComponent - self.blueComponent) > epsilon);
    }
    if (clippedPtr) {
        *clippedPtr = clipped;
    }
    return converted;
}

@end
