//
//  iTermBoxDrawingBezierCurveFactory.h
//  iTerm2
//
//  Created by George Nachman on 7/15/16.
//
//

#import <Cocoa/Cocoa.h>

// Every character in boxDrawingCharactersWithBezierPathsIncludingPowerline: (either value) and
// blockDrawingCharacters is at least this. Callers use it to skip set lookups for ordinary text.
// If you add a smaller character to one of those sets, lower this.
static const UTF32Char iTermBoxDrawingCharacterLowerBound = 0x2500;

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
