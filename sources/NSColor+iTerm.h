//
//  NSColor+iTerm.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Cocoa/Cocoa.h>
#import <simd/simd.h>

@class NSAppearance;

// Keys of -dictionaryValue. Use -[NSDictionary colorValue] to convert to color.
extern NSString *const kEncodedColorDictionaryRedComponent;
extern NSString *const kEncodedColorDictionaryGreenComponent;
extern NSString *const kEncodedColorDictionaryBlueComponent;
extern NSString *const kEncodedColorDictionaryAlphaComponent;  // Optional, defaults to 1.0
extern NSString *const kEncodedColorDictionaryColorSpace;  // Optional, defaults to calibrated

// Values for kEncodedColorDictionaryColorSpace key
extern NSString *const kEncodedColorDictionarySRGBColorSpace;
extern NSString *const kEncodedColorDictionaryCalibratedColorSpace;

static inline float SIMDPerceivedBrightness(vector_float4 x) {
    static const vector_float4 y = (vector_float4){ 0.30, 0.59, 0.11, 0 };
    return simd_dot(x, y);
}

// Note: these are in 0…1. These represent LINEAR values. NSColor has sRGB values which are not linear.
typedef struct {
    CGFloat r;
    CGFloat g;
    CGFloat b;
} iTermRGBColor;

// Note: nonlinear values, like NSColor
typedef struct {
    CGFloat r;
    CGFloat g;
    CGFloat b;
} iTermSRGBColor;

typedef struct {
    CGFloat l;  // 0…100
    CGFloat a;  // -100…100
    CGFloat b;  // -100…100
} iTermLABColor;

iTermRGBColor iTermLinearizeSRGB(iTermSRGBColor srgb);
iTermSRGBColor iTermCompressRGB(iTermRGBColor rgb);

iTermLABColor iTermLABFromSRGB(iTermSRGBColor srgb);
iTermSRGBColor iTermSRGBFromLAB(iTermLABColor lab);

// Distance will be in 0-1. Warning: this doesn't work very well. For example,
// ((l=15.6, a=29.6, b=24.0) = srgb (.31,.05,0) has a distance from pure black of .41
CGFloat iTermLABDistance(iTermLABColor lhs, iTermLABColor rhs);

@interface NSColor (iTerm)

@property(nonatomic, readonly) CGFloat perceivedBrightness;
@property(nonatomic, readonly) BOOL isDark;
@property(nonatomic, readonly) NSString *shortDescription;

@property(nonatomic, readonly) NSDictionary *dictionaryValue;
@property(nonatomic, readonly) NSString *stringValue;

CGFloat PerceivedBrightness(CGFloat r, CGFloat g, CGFloat b);

+ (NSColor *)colorWithString:(NSString *)s;
+ (NSColor *)colorWith8BitRed:(int)red
                        green:(int)green
                         blue:(int)blue;

+ (NSColor *)colorWith8BitRed:(int)red
                        green:(int)green
                         blue:(int)blue
                       muting:(double)muting
                backgroundRed:(CGFloat)bgRed
              backgroundGreen:(CGFloat)bgGreen
               backgroundBlue:(CGFloat)bgBlue;

// Modify r,g,b to have brightness t, placing the values in result which should hold 4 CGFloats.
+ (void)getComponents:(CGFloat *)result
      forColorWithRed:(CGFloat)r
                green:(CGFloat)g
                 blue:(CGFloat)b
                alpha:(CGFloat)a
  perceivedBrightness:(CGFloat)t;

// Fill in result with four values by modifying mainComponents to have at least
// minimumContrast against otherComponents. All arrays are
// red,green,blue,alpha. Alpha is copied over from mainComponents to result.
+ (void)getComponents:(CGFloat *)result
        forComponents:(CGFloat *)mainComponents
  withContrastAgainstComponents:(CGFloat *)otherComponents
                minimumContrast:(CGFloat)minimumContrast;

- (int)nearestIndexIntoAnsi256ColorTable;

- (iTermLABColor)labColor;
+ (instancetype)withLABColor:(iTermLABColor)lab;

// Returns colors for the standard 8-bit ansi color codes. Only indices between 16 and 255 are
// supported.
+ (NSColor *)colorForAnsi256ColorIndex:(int)index;

- (NSColor *)colorDimmedBy:(double)dimmingAmount towardsGrayLevel:(double)grayLevel;

// Return the color you'd get by rendering self over background.
- (NSColor *)colorByPremultiplyingAlphaWithColor:(NSColor *)background;

- (NSString *)hexString;
+ (instancetype)colorFromHexString:(NSString *)hexString;

- (NSColor *)it_colorByDimmingByAmount:(double)dimmingAmount;

- (NSColor *)it_colorWithAppearance:(NSAppearance *)appearance;

@end
