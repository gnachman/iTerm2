//
//  CPKColor.h
//  ColorPicker
//
//  Created by George Nachman on 10/3/19.
//  Copyright © 2019 Google. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// A wrapper around NSColor that doesn't forget its hue and saturation.
// Some values of saturation and brightness make the hue and saturation
// irrelevant. For example, black and white are identical for all hues.
// Black is identical for all saturations.
// NSColor forgets its hue and saturation value in these situations,
// which leads to the UI getting confused when you momentarily change the
// selected color to black or white.
// CPKColor allows you to initialize it with a hue and saturation and later
// query for it and get the samet hing back, even for black and white.
@interface CPKColor : NSObject

@property (nonatomic, readonly) CGFloat hueComponent;
@property (nonatomic, readonly) CGFloat saturationComponent;
@property (nonatomic, readonly) CGFloat brightnessComponent;
@property (nonatomic, readonly) CGFloat redComponent;
@property (nonatomic, readonly) CGFloat greenComponent;
@property (nonatomic, readonly) CGFloat blueComponent;
@property (nonatomic, readonly) CGFloat alphaComponent;
@property (nonatomic, readonly) NSColor *color;

- (instancetype)initWithColor:(NSColor *)color NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithHue:(CGFloat)hue
                 saturation:(CGFloat)saturation
                 brightness:(CGFloat)brightness
                      alpha:(CGFloat)alpha
                 colorSpace:(NSColorSpace *)colorSpace;

- (instancetype)initWithRed:(CGFloat)red
                      green:(CGFloat)green
                       blue:(CGFloat)blue
                      alpha:(CGFloat)alpha
                 colorSpace:(NSColorSpace *)colorSpace;

- (instancetype)init NS_UNAVAILABLE;

- (CPKColor *)colorWithAlphaComponent:(CGFloat)alpha;

@end

NS_ASSUME_NONNULL_END
