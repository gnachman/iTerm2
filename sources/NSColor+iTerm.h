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

NS_ASSUME_NONNULL_BEGIN

// Keys of -dictionaryValue. Use -[NSDictionary colorValue] to convert to color.
extern NSString *const kEncodedColorDictionaryRedComponent;
extern NSString *const kEncodedColorDictionaryGreenComponent;
extern NSString *const kEncodedColorDictionaryBlueComponent;
extern NSString *const kEncodedColorDictionaryAlphaComponent;  // Optional, defaults to 1.0
extern NSString *const kEncodedColorDictionaryColorSpace;  // Optional, defaults to calibrated

// Values for kEncodedColorDictionaryColorSpace key
extern NSString *const kEncodedColorDictionarySRGBColorSpace;
extern NSString *const kEncodedColorDictionaryCalibratedColorSpace;
extern NSString *const kEncodedColorDictionaryP3ColorSpace;

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

// Based on Rec. 709 standard
CGFloat iTermPerceptualBrightnessSRGB(iTermSRGBColor srgb);

// Distance will be in 0-1. Warning: this doesn't work very well. For example,
// ((l=15.6, a=29.6, b=24.0) = srgb (.31,.05,0) has a distance from pure black of .41
CGFloat iTermLABDistance(iTermLABColor lhs, iTermLABColor rhs);

@interface NSColor (iTerm)

@property(nonatomic, readonly) CGFloat perceivedBrightness;
@property(nonatomic, readonly) BOOL isDark;
@property(nonatomic, readonly) NSString *shortDescription;

@property(nonatomic, readonly) NSDictionary *dictionaryValue;
@property(nonatomic, readonly) NSString *stringValue;
@property(nonatomic, readonly) iTermSRGBColor itermSRGBColor;

// This is some janky NTSC shit
CGFloat PerceivedBrightness(CGFloat r, CGFloat g, CGFloat b);

// This will return the color in the app's standard colorspace.
+ (NSColor * _Nullable)colorWithString:(NSString *)s;

// This will preserve the colorspace of the encoded color.
+ (NSColor *)colorPreservingColorspaceFromString:(NSString *)s;

+ (NSColor *)colorWith8BitRed:(int)red
                        green:(int)green
                         blue:(int)blue;

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
+ (void)getComponents:(CGFloat * _Nullable)result
        forComponents:(CGFloat *)mainComponents
  withContrastAgainstComponents:(CGFloat *)otherComponents
                minimumContrast:(CGFloat)minimumContrast;

+ (NSColor *)it_colorInDefaultColorSpaceWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;

- (int)nearestIndexIntoAnsi256ColorTable;

- (iTermLABColor)labColor;
+ (instancetype)withLABColor:(iTermLABColor)lab;

// Returns colors for the standard 8-bit ansi color codes. Only indices between 16 and 255 are
// supported.
+ (NSColor * _Nullable)colorForAnsi256ColorIndex:(int)index;

- (NSColor *)colorDimmedBy:(double)dimmingAmount towardsGrayLevel:(double)grayLevel;

// Return the color you'd get by rendering self over background.
- (NSColor *)colorByPremultiplyingAlphaWithColor:(NSColor *)background;

// p3:#rrggbb or #rrggbb (srgb implicitly)
// converts to the app-standard colorspace
- (NSString *)hexString;

- (NSString *)hexStringPreservingColorSpace;

// #rrggbb
- (NSString *)srgbHexString;

+ (instancetype _Nullable)colorFromHexString:(NSString *)hexString;

- (NSColor *)it_colorByDimmingByAmount:(double)dimmingAmount;

- (NSColor *)it_colorWithAppearance:(NSAppearance *)appearance;
- (NSColor *)it_colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
- (NSColor *)it_colorInDefaultColorSpace;

// Unlike -colorSpace, this is safe to use from Swift. It does not throw an exception, but returns nil for catalog colors and such.
@property (nonatomic, readonly) NSColorSpace * _Nullable it_colorSpace;

- (BOOL)isApproximatelyEqualToColor:(NSColor *)other epsilon:(double)e;
- (NSColor *)blendedWithColor:(NSColor *)color weight:(CGFloat)weight;
@property (nonatomic, readonly) vector_float4 vector;

+ (instancetype)colorWithVector:(vector_float4)vector colorSpace:(NSColorSpace *)colorSpace;

@end

@interface NSColorSpace(iTerm)
+ (instancetype)it_defaultColorSpace;
@end

NS_ASSUME_NONNULL_END
