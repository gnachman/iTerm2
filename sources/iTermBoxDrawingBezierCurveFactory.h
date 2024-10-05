//
//  iTermBoxDrawingBezierCurveFactory.h
//  iTerm2
//
//  Created by George Nachman on 7/15/16.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermBoxDrawingBezierCurveFactory : NSObject

+ (NSCharacterSet *)boxDrawingCharactersWithBezierPathsIncludingPowerline:(BOOL)includingPowerline;

// These are a subset of box drawing characters that are used in ASCII art and shouldn't be affected
// by minimum contrast.
+ (NSCharacterSet *)blockDrawingCharacters;

+ (void)drawCodeInCurrentContext:(UTF32Char)code
                        cellSize:(NSSize)cellSize
                           scale:(CGFloat)scale
                        isPoints:(BOOL)isPoints
                          offset:(CGPoint)offset
                           color:(CGColorRef)color
        useNativePowerlineGlyphs:(BOOL)useNativePowerlineGlyphs;

+ (BOOL)isPowerlineGlyph:(UTF32Char)code;
+ (BOOL)isDoubleWidthPowerlineGlyph:(UTF32Char)code;

@end
