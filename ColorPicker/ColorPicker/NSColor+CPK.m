//
//  NSColor+CPK.m
//  ColorPicker
//
//  Created by George Nachman on 9/16/15.
//  Copyright (c) 2015 Google. All rights reserved.
//

#import "NSColor+CPK.h"

@implementation NSColor (CPK)

+ (NSColor *)cpk_colorWithHue:(CGFloat)hue
                   saturation:(CGFloat)saturation
                   brightness:(CGFloat)brightness
                        alpha:(CGFloat)alpha {
    if ([self respondsToSelector:@selector(colorWithHue:saturation:brightness:alpha:)]) {
        return [self colorWithHue:hue saturation:saturation brightness:brightness alpha:alpha];
    } else {
        return [self colorWithCalibratedHue:hue
                                 saturation:saturation
                                 brightness:brightness
                                      alpha:alpha];
    }
}

+ (NSColor *)cpk_colorWithRed:(CGFloat)red
                        green:(CGFloat)green
                         blue:(CGFloat)blue
                        alpha:(CGFloat)alpha {
    if ([self respondsToSelector:@selector(colorWithRed:green:blue:alpha:)]) {
        return [self colorWithRed:red green:green blue:blue alpha:alpha];
    } else {
        return [self colorWithCalibratedRed:red
                                      green:green
                                       blue:blue
                                      alpha:alpha];
    }
}

+ (NSColor *)cpk_colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha {
    if ([self respondsToSelector:@selector(colorWithWhite:alpha:)]) {
        return [self colorWithWhite:white alpha:alpha];
    } else {
        return [NSColor colorWithCalibratedRed:white green:white blue:white alpha:alpha];
    }
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

@end
