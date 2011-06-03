//
//  NSBezierPath_AMShading.h
//  ------------------------
//
//  Created by Andreas on 2005-06-01.
//  Copyright 2005 Andreas Mayer. All rights reserved.
//
//	based on http://www.cocoadev.com/index.pl?GradientFill


#import <Cocoa/Cocoa.h>


@interface NSBezierPath (AMShading)

- (void)customHorizontalFillWithCallbacks:(CGFunctionCallbacks)functionCallbacks firstColor:(NSColor *)firstColor secondColor:(NSColor *)secondColor;

- (void)linearGradientFillWithStartColor:(NSColor *)startColor endColor:(NSColor *)endColor;

- (void)bilinearGradientFillWithOuterColor:(NSColor *)outerColor innerColor:(NSColor *)innerColor;


@end
