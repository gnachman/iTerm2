//
//  NSColor+iTerm.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Cocoa/Cocoa.h>

@interface NSColor (iTerm)

+ (NSColor *)colorWith8BitRed:(int)red
                        green:(int)green
                         blue:(int)blue;

+ (NSColor *)calibratedColorWithRed:(double)r
                              green:(double)g
                               blue:(double)b
                              alpha:(double)a
                perceivedBrightness:(CGFloat)t;

+ (NSColor*)colorWithComponents:(double *)mainComponents
    withContrastAgainstComponents:(double *)otherComponents
                  minimumContrast:(CGFloat)minimumContrast;

- (int)nearestIndexIntoAnsi256ColorTable;

// Returns colors for the standard 8-bit ansi color codes. Only indices between 16 and 255 are
// supported.
+ (NSColor *)colorForAnsi256ColorIndex:(int)index;

- (NSColor *)colorDimmedBy:(double)dimmingAmount towardsGrayLevel:(double)grayLevel;
- (CGFloat)perceivedBrightness;
- (BOOL)isDark;

@end
