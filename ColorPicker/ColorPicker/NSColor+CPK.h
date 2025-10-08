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

+ (NSColor *)cpk_colorWithRed:(CGFloat)red
                        green:(CGFloat)green
                         blue:(CGFloat)blue
                        alpha:(CGFloat)alpha
                   colorSpace:(NSColorSpace *)colorSpace;

- (NSColor *)cpk_colorUsingColorSpace:(NSColorSpace *)colorSpace lossy:(out BOOL *)clippedPtr;

@end
