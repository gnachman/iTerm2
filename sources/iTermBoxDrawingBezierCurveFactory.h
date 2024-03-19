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

+ (void)drawCodeInCurrentContext:(unichar)code
                        cellSize:(NSSize)cellSize
                           scale:(CGFloat)scale
                        isPoints:(BOOL)isPoints
                          offset:(CGPoint)offset
                           color:(CGColorRef)color
        useNativePowerlineGlyphs:(BOOL)useNativePowerlineGlyphs;

+ (BOOL)isPowerlineGlyph:(unichar)code;
+ (BOOL)isDoubleWidthPowerlineGlyph:(unichar)code;

@end
