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
