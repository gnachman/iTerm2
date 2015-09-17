//
//  NSColor+CPK.m
//  ColorPicker
//
//  Created by George Nachman on 9/16/15.
//  Copyright (c) 2015 Google. All rights reserved.
//

#import "NSColor+CPK.h"

@implementation NSColor (CPK)

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
