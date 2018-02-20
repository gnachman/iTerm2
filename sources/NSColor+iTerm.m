//
//  NSColor+iTerm.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "NSColor+iTerm.h"
#import "DebugLogging.h"
#import "iTermSharedColor.h"
#import <simd/simd.h>

// Constants for converting RGB to luma.
static const double kRedComponentBrightness = 0.30;
static const double kGreenComponentBrightness = 0.59;
static const double kBlueComponentBrightness = 0.11;

NSString *const kEncodedColorDictionaryRedComponent = @"Red Component";
NSString *const kEncodedColorDictionaryGreenComponent = @"Green Component";
NSString *const kEncodedColorDictionaryBlueComponent = @"Blue Component";
NSString *const kEncodedColorDictionaryAlphaComponent = @"Alpha Component";
NSString *const kEncodedColorDictionaryColorSpace = @"Color Space";
NSString *const kEncodedColorDictionarySRGBColorSpace = @"sRGB";
NSString *const kEncodedColorDictionaryCalibratedColorSpace = @"Calibrated";

CGFloat PerceivedBrightness(CGFloat r, CGFloat g, CGFloat b) {
    return (kRedComponentBrightness * r +
            kGreenComponentBrightness * g +
            kBlueComponentBrightness * b);
}

@implementation NSColor (iTerm)

+ (NSColor *)colorWithString:(NSString *)s {
    if ([s hasPrefix:@"#"] && s.length == 7) {
        return [self colorFromHexString:s];
    }
    NSData *data = [[[NSData alloc] initWithBase64EncodedString:s options:0] autorelease];
    if (!data.length) {
        return nil;
    }
    @try {
        NSKeyedUnarchiver *decoder = [[[NSKeyedUnarchiver alloc] initForReadingWithData:data] autorelease];
        NSColor *color = [[[NSColor alloc] initWithCoder:decoder] autorelease];
        return color;
    }
    @catch (NSException *exception) {
        NSLog(@"Failed to decode color from string %@", s);
        DLog(@"Failed to decode color from string %@", s);
        return nil;
    }
}

- (NSString *)stringValue {
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *coder = [[[NSKeyedArchiver alloc] initForWritingWithMutableData:data] autorelease];
    coder.outputFormat = NSPropertyListBinaryFormat_v1_0;
    [self encodeWithCoder:coder];
    [coder finishEncoding];
    return [data base64EncodedStringWithOptions:0];
}

+ (NSColor *)colorWith8BitRed:(int)red
                        green:(int)green
                         blue:(int)blue {
    return [NSColor colorWithSRGBRed:red / 255.0
                               green:green / 255.0
                                blue:blue / 255.0
                               alpha:1];
}

+ (NSColor *)colorWith8BitRed:(int)red
                        green:(int)green
                         blue:(int)blue
                       muting:(double)muting
                backgroundRed:(CGFloat)bgRed
              backgroundGreen:(CGFloat)bgGreen
               backgroundBlue:(CGFloat)bgBlue {
    CGFloat r = (red / 255.0) * (1 - muting) + bgRed * muting;
    CGFloat g = (green / 255.0) * (1 - muting) + bgGreen * muting;
    CGFloat b = (blue / 255.0) * (1 - muting) + bgBlue * muting;

    return [NSColor colorWithSRGBRed:r
                               green:g
                                blue:b
                               alpha:1];
}

+ (void)getComponents:(CGFloat *)result
      forColorWithRed:(CGFloat)r
                green:(CGFloat)g
                 blue:(CGFloat)b
                alpha:(CGFloat)a
  perceivedBrightness:(CGFloat)t {
    vector_float4 c = simd_make_float4(r, g, b, a);
    vector_float4 x = ForceBrightness(c, t);
    result[0] = x.x;
    result[1] = x.y;
    result[2] = x.z;
    result[3] = x.w;
}

+ (NSColor *)colorForAnsi256ColorIndex:(int)index {
    double r, g, b;
    if (index >= 16 && index < 232) {
        int i = index - 16;
        r = (i / 36) ? ((i / 36) * 40 + 55) / 255.0 : 0.0;
        g = (i % 36) / 6 ? (((i % 36) / 6) * 40 + 55) / 255.0 : 0.0;
        b = (i % 6) ? ((i % 6) * 40 + 55) / 255.0 : 0.0;
    } else if (index >= 232 && index < 256) {
        int i = index - 232;
        r = g = b = (i * 10 + 8) / 255.0;
    } else {
        // The first 16 colors aren't supported here.
        return nil;
    }
    NSColor* srgb = [NSColor colorWithSRGBRed:r
                                        green:g
                                         blue:b
                                        alpha:1];
    return [srgb colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
}

+ (void)getComponents:(CGFloat *)result
        forComponents:(CGFloat *)mainComponents
  withContrastAgainstComponents:(CGFloat *)otherComponents
                minimumContrast:(CGFloat)minimumContrast {
    vector_float4 text = simd_make_float4(mainComponents[0],
                                          mainComponents[1],
                                          mainComponents[2],
                                          mainComponents[3]);
    vector_float4 background = simd_make_float4(otherComponents[0],
                                                otherComponents[1],
                                                otherComponents[2],
                                                1);
    vector_float4 x = ApplyMinimumContrast(text, background, minimumContrast);
    result[0] = x.x;
    result[1] = x.y;
    result[2] = x.z;
    result[3] = x.w;
}

- (int)nearestIndexIntoAnsi256ColorTable {
    NSColor *theColor = [self colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    int r = 5 * [theColor redComponent];
    int g = 5 * [theColor greenComponent];
    int b = 5 * [theColor blueComponent];
    return 16 + b + g * 6 + r * 36;
}

- (NSColor *)colorDimmedBy:(double)dimmingAmount towardsGrayLevel:(double)grayLevel {
    if (dimmingAmount == 0) {
        return self;
    }
    double r = [self redComponent];
    double g = [self greenComponent];
    double b = [self blueComponent];
    double alpha = [self alphaComponent];
    // This algorithm limits the dynamic range of colors as well as brightening
    // them. Both attributes change in proportion to the dimmingAmount.

    // Find a linear interpolation between kCenter and the requested color component
    // in proportion to 1- dimmingAmount.
    return [NSColor colorWithCalibratedRed:(1 - dimmingAmount) * r + dimmingAmount * grayLevel
                                     green:(1 - dimmingAmount) * g + dimmingAmount * grayLevel
                                      blue:(1 - dimmingAmount) * b + dimmingAmount * grayLevel
                                     alpha:alpha];
}

- (CGFloat)perceivedBrightness {
    NSColor *safeColor = [self colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    return PerceivedBrightness([safeColor redComponent],
                               [safeColor greenComponent],
                               [safeColor blueComponent]);
}

- (BOOL)isDark {
    return [self perceivedBrightness] < 0.5;
}

- (NSDictionary *)dictionaryValue {
    NSColor *color = [self colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    CGFloat red, green, blue, alpha;
    [color getRed:&red green:&green blue:&blue alpha:&alpha];
    return @{ kEncodedColorDictionaryColorSpace: kEncodedColorDictionarySRGBColorSpace,
              kEncodedColorDictionaryRedComponent: @(red),
              kEncodedColorDictionaryGreenComponent: @(green),
              kEncodedColorDictionaryBlueComponent: @(blue),
              kEncodedColorDictionaryAlphaComponent: @(alpha) };
}

- (NSColor *)colorByPremultiplyingAlphaWithColor:(NSColor *)background {
    CGFloat a[4];
    CGFloat b[4];
    [self getComponents:a];
    [background getComponents:b];
    CGFloat x[4];
    CGFloat alpha = a[3];
    for (int i = 0; i < 3; i++) {
        x[i] = a[i] * alpha + b[i] * (1 - alpha);
    }
    x[3] = b[3];
    return [NSColor colorWithColorSpace:self.colorSpace components:x count:4];
}

- (NSString *)hexString {
    NSDictionary *dict = [self dictionaryValue];
    int red = [dict[kEncodedColorDictionaryRedComponent] doubleValue] * 255;
    int green = [dict[kEncodedColorDictionaryGreenComponent] doubleValue] * 255;
    int blue = [dict[kEncodedColorDictionaryBlueComponent] doubleValue] * 255;
    return [NSString stringWithFormat:@"#%02x%02x%02x", red, green, blue];
}

+ (instancetype)colorFromHexString:(NSString *)hexString {
    if (![hexString hasPrefix:@"#"] || hexString.length != 7) {
        return nil;
    }

    NSScanner *scanner = [NSScanner scannerWithString:[hexString substringFromIndex:1]];
    unsigned long long ll;
    if (![scanner scanHexLongLong:&ll]) {
        return nil;
    }
    CGFloat red = (ll >> 16) & 0xff;
    CGFloat green = (ll >> 8) & 0xff;
    CGFloat blue = (ll >> 0) & 0xff;
    return [NSColor colorWithSRGBRed:red/255.0 green:green/255.0 blue:blue/255.0 alpha:1];
}

- (vector_float4)vector {
    CGFloat components[4];
    [self getComponents:components];
    return simd_make_float4(components[0],
                            components[1],
                            components[2],
                            components[3]);
}
@end
