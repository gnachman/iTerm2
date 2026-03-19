//
//  iTermCharacterSourceTestHelper.m
//  iTerm2
//
//  Created by George Nachman on 3/14/26.
//

#import "iTermCharacterSourceTestHelper.h"
#import "iTermCharacterSource.h"
#import "iTermCharacterBitmap.h"
#import "iTerm2SharedARC-Swift.h"

@implementation iTermCharacterSourceTestHelper

+ (iTermCharacterSourceDescriptor *)descriptorWithFontTable:(iTermFontTable *)fontTable
                                                      scale:(CGFloat)scale
                                                  glyphSize:(CGSize)glyphSize {
    return [iTermCharacterSourceDescriptor characterSourceDescriptorWithFontTable:fontTable
                                                                       asciiOffset:CGSizeZero
                                                                         glyphSize:glyphSize
                                                                          cellSize:glyphSize
                                                            cellSizeWithoutSpacing:glyphSize
                                                                             scale:scale
                                                                       useBoldFont:NO
                                                                     useItalicFont:NO
                                                                  usesNonAsciiFont:NO
                                                                  asciiAntiAliased:YES
                                                               nonAsciiAntiAliased:YES];
}

+ (iTermCharacterSourceAttributes *)defaultAttributes {
    return [iTermCharacterSourceAttributes characterSourceAttributesWithThinStrokes:NO
                                                                               bold:NO
                                                                             italic:NO];
}

+ (iTermCharacterSourceAttributes *)attributesWithBold:(BOOL)bold italic:(BOOL)italic {
    return [iTermCharacterSourceAttributes characterSourceAttributesWithThinStrokes:NO
                                                                               bold:bold
                                                                             italic:italic];
}

+ (nullable iTermCharacterSource *)characterSourceWithCharacter:(NSString *)character
                                                     descriptor:(iTermCharacterSourceDescriptor *)descriptor
                                                     attributes:(iTermCharacterSourceAttributes *)attributes
                                                         radius:(int)radius
                                                        context:(CGContextRef)context {
    return [[iTermCharacterSource alloc] initWithCharacter:character
                                                descriptor:descriptor
                                                attributes:attributes
                                                boxDrawing:NO
                                                    radius:radius
                                  useNativePowerlineGlyphs:NO
                                                   context:context];
}

+ (NSRect)drawAndGetFrameForSource:(iTermCharacterSource *)source {
    // Trigger drawing by requesting a bitmap
    [source bitmapForPart:0];
    return source.frame;
}

+ (BOOL)drawAndVerifyClearingForSource:(iTermCharacterSource *)source
                               context:(CGContextRef)context
                           contextSize:(CGSize)size {
    // Trigger drawing by requesting a bitmap
    [source bitmapForPart:0];

    // After drawing, the context should be cleared
    return [self contextIsEmpty:context size:size];
}

+ (BOOL)contextIsEmpty:(CGContextRef)context size:(CGSize)size {
    const unsigned char *data = CGBitmapContextGetData(context);
    const size_t bytesPerRow = CGBitmapContextGetBytesPerRow(context);
    const int width = (int)size.width;
    const int height = (int)size.height;

    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            const size_t offset = y * bytesPerRow + x * 4;
            // Check alpha channel (BGRA format, alpha at offset+3)
            if (data[offset + 3] != 0) {
                return NO;
            }
        }
    }
    return YES;
}

+ (NSRect)pixelBoundsInContext:(CGContextRef)context size:(CGSize)size {
    const unsigned char *data = CGBitmapContextGetData(context);
    const size_t bytesPerRow = CGBitmapContextGetBytesPerRow(context);
    const int width = (int)size.width;
    const int height = (int)size.height;

    int minX = width, maxX = 0;
    int minY = height, maxY = 0;

    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            const size_t offset = y * bytesPerRow + x * 4;
            if (data[offset + 3] != 0) {
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
            }
        }
    }

    if (minX > maxX || minY > maxY) {
        return NSZeroRect;
    }

    return NSMakeRect(minX, minY, maxX - minX + 1, maxY - minY + 1);
}

@end
