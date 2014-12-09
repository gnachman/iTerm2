//
//  NSColor+iTerm.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Cocoa/Cocoa.h>

// Keys of -dictionaryValue. Use -[NSDictionary colorVaue] to convert to color.
extern NSString *const kEncodedColorDictionaryRedComponent;
extern NSString *const kEncodedColorDictionaryGreenComponent;
extern NSString *const kEncodedColorDictionaryBlueComponent;
extern NSString *const kEncodedColorDictionaryAlphaComponent;  // Optional, defaults to 1.0
extern NSString *const kEncodedColorDictionaryColorSpace;  // Optional, defaults to calibrated

// Values for kEncodedColorDictionaryColorSpace key
extern NSString *const kEncodedColorDictionarySRGBColorSpace;
extern NSString *const kEncodedColorDictionaryCalibratedColorSpace;

@interface NSColor (iTerm)

+ (NSColor *)colorWith8BitRed:(int)red
                        green:(int)green
                         blue:(int)blue
                         sRGB:(BOOL)sRGB;

+ (NSColor *)colorWith8BitRed:(int)red
                        green:(int)green
                         blue:(int)blue
                       muting:(double)muting
                backgroundRed:(CGFloat)bgRed
              backgroundGreen:(CGFloat)bgGreen
               backgroundBlue:(CGFloat)bgBlue
                         sRGB:(BOOL)sRGB;

+ (NSColor *)calibratedColorWithRed:(double)r
                              green:(double)g
                               blue:(double)b
                              alpha:(double)a
                perceivedBrightness:(CGFloat)t
                   towardComponents:(CGFloat *)baseColorComponents;

+ (NSColor*)colorWithComponents:(double *)mainComponents
    withContrastAgainstComponents:(double *)otherComponents
                  minimumContrast:(CGFloat)minimumContrast
                          mutedBy:(double)muting
                 towardComponents:(CGFloat *)baseColorComponents;

- (int)nearestIndexIntoAnsi256ColorTable;

// Returns colors for the standard 8-bit ansi color codes. Only indices between 16 and 255 are
// supported.
+ (NSColor *)colorForAnsi256ColorIndex:(int)index;

- (NSColor *)colorDimmedBy:(double)dimmingAmount towardsGrayLevel:(double)grayLevel;
- (CGFloat)perceivedBrightness;
- (BOOL)isDark;

- (NSDictionary *)dictionaryValue;
- (NSColor *)colorMutedBy:(double)muting towards:(NSColor *)baseColor;

@end
