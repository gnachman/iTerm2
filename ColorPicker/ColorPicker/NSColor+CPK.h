//
//  NSColor+CPK.h
//  ColorPicker
//
//  Created by George Nachman on 9/16/15.
//  Copyright (c) 2015 Google. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NSColor (CPK)

- (BOOL)isApproximatelyEqualToColor:(NSColor *)color;

// Safe to use on 10.8.
+ (NSColor *)cpk_colorWithHue:(CGFloat)hue
                   saturation:(CGFloat)saturation
                   brightness:(CGFloat)brightness
                        alpha:(CGFloat)alpha;

// Safe to use on 10.8.
+ (NSColor *)cpk_colorWithRed:(CGFloat)red
                        green:(CGFloat)green
                         blue:(CGFloat)blue
                        alpha:(CGFloat)alpha;

// Safe to use on 10.8.
+ (NSColor *)cpk_colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha;

@end
