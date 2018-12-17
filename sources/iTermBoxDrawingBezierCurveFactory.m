//
//  iTermBoxDrawingBezierCurveFactory.m
//  iTerm2
//
//  Created by George Nachman on 7/15/16.
//
//

#import "iTermBoxDrawingBezierCurveFactory.h"

#import "iTermAdvancedSettingsModel.h"
#import "charmaps.h"
#import "iTermImageCache.h"
#import "NSArray+iTerm.h"
#import "NSImage+iTerm.h"

@implementation iTermBoxDrawingBezierCurveFactory

+ (NSCharacterSet *)boxDrawingCharactersWithBezierPathsIncludingPowerline:(BOOL)includingPowerline {
    if (includingPowerline) {
        return [self boxDrawingCharactersWithBezierPathsIncludingPowerline];
    } else {
        return [self boxDrawingCharactersWithBezierPathsExcludingPowerline];
    }
}

+ (NSCharacterSet *)boxDrawingCharactersWithBezierPathsIncludingPowerline {
    static NSCharacterSet *sBoxDrawingCharactersWithBezierPaths;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if ([iTermAdvancedSettingsModel disableCustomBoxDrawing]) {
            sBoxDrawingCharactersWithBezierPaths = [NSCharacterSet characterSetWithCharactersInString:@""];
        } else {
            /*
            U+E0A0        Version control branch
            U+E0A1        LN (line) symbol
            U+E0A2        Closed padlock
            U+E0B0        Rightwards black arrowhead
            U+E0B1        Rightwards arrowhead
            U+E0B2        Leftwards black arrowhead
            U+E0B3        Leftwards arrowhead
             */
            NSMutableCharacterSet *temp = [[self boxDrawingCharactersWithBezierPathsExcludingPowerline] mutableCopy];
            [temp addCharactersInRange:NSMakeRange(0xE0A0, 3)];
            [temp addCharactersInRange:NSMakeRange(0xE0B0, 4)];
            sBoxDrawingCharactersWithBezierPaths = temp;
        };
    });
    return sBoxDrawingCharactersWithBezierPaths;
}

+ (NSCharacterSet *)boxDrawingCharactersWithBezierPathsExcludingPowerline {
    static NSCharacterSet *sBoxDrawingCharactersWithBezierPaths;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if ([iTermAdvancedSettingsModel disableCustomBoxDrawing]) {
            sBoxDrawingCharactersWithBezierPaths = [NSCharacterSet characterSetWithCharactersInString:@""];
        } else {
            sBoxDrawingCharactersWithBezierPaths = [NSCharacterSet characterSetWithCharactersInString:@"─━│┃┌┍┎┏┐┑┒┓└┕┖┗┘┙┚┛├┝┞┟┠┡┢┣┤"
                                                     @"┥┦┧┨┩┪┫┬┭┮┯┰┱┲┳┴┵┶┷┸┹┺┻┼┽┾┿╀╁╂╃╄╅╆╇╈╉╊╋═║╒╓╔╕╖╗╘╙╚╛╜╝╞╟╠╡╢╣╤╥╦╧╨╩╪╫╬╴╵╶╷╸╹╺╻╼╽╾╿"
                                                     @"╯╮╰╭╱╲╳▀▁▂▃▄▅▆▇█▉▊▋▌▍▎▏▐▔▕▖▗▘▙▚▛▜▝▞▟"];
        };
    });
    return sBoxDrawingCharactersWithBezierPaths;
}

+ (NSArray<NSBezierPath *> *)bezierPathsForSolidBoxesForCode:(unichar)code
                                                    cellSize:(NSSize)cellSize
                                                       scale:(CGFloat)scale {
    NSArray<NSString *> *parts = nil;

    // First two characters give the letter + number of origin in eighths.
    // Then come two digits giving width and height in eighths.
    switch (code) {
        case 0xE0A0:  // Version control branch
        case 0xE0A1:  // LN (line) symbol
        case 0xE0A2:  // Closed padlock
        case 0xE0B0:  // Rightward black arrowhead
        case 0xE0B1:  // Rightwards arrowhead
        case 0xE0B2:  // Leftwards black arrowhead
        case 0xE0B3:  // Leftwards arrowhead
            return nil;

        case iTermUpperHalfBlock: // ▀
            parts = @[ @"a084" ];
            break;
        case iTermLowerOneEighthBlock: // ▁
            parts = @[ @"a781" ];
            break;
        case iTermLowerOneQuarterBlock: // ▂
            parts = @[ @"a682" ];
            break;
        case iTermLowerThreeEighthsBlock: // ▃
            parts = @[ @"a583" ];
            break;
        case iTermLowerHalfBlock: // ▄
            parts = @[ @"a484" ];
            break;
        case iTermLowerFiveEighthsBlock: // ▅
            parts = @[ @"a385" ];
            break;
        case iTermLowerThreeQuartersBlock: // ▆
            parts = @[ @"a286" ];
            break;
        case iTermLowerSevenEighthsBlock: // ▇
            parts = @[ @"a187" ];
            break;
        case iTermFullBlock: // █
            parts = @[ @"a088" ];
            break;
        case iTermLeftSevenEighthsBlock: // ▉
            parts = @[ @"a078" ];
            break;
        case iTermLeftThreeQuartersBlock: // ▊
            parts = @[ @"a068" ];
            break;
        case iTermLeftFiveEighthsBlock: // ▋
            parts = @[ @"a058" ];
            break;
        case iTermLeftHalfBlock: // ▌
            parts = @[ @"a048" ];
            break;
        case iTermLeftThreeEighthsBlock: // ▍
            parts = @[ @"a038" ];
            break;
        case iTermLeftOneQuarterBlock: // ▎
            parts = @[ @"a028" ];
            break;
        case iTermLeftOneEighthBlock: // ▏
            parts = @[ @"a018" ];
            break;
        case iTermRightHalfBlock: // ▐
            parts = @[ @"e048" ];
            break;
        case iTermUpperOneEighthBlock: // ▔
            parts = @[ @"a081" ];
            break;
        case iTermRightOneEighthBlock: // ▕
            parts = @[ @"h018" ];
            break;
        case iTermQuadrantLowerLeft: // ▖
            parts = @[ @"a444" ];
            break;
        case iTermQuadrantLowerRight: // ▗
            parts = @[ @"e444" ];
            break;
        case iTermQuadrantUpperLeft: // ▘
            parts = @[ @"a044" ];
            break;
        case iTermQuadrantUpperLeftAndLowerLeftAndLowerRight: // ▙
            parts = @[ @"a044", @"a444", @"e444" ];
            break;
        case iTermQuadrantUpperLeftAndLowerRight: // ▚
            parts = @[ @"a044", @"e444" ];
            break;
        case iTermQuadrantUpperLeftAndUpperRightAndLowerLeft: // ▛
            parts = @[ @"a044", @"e044", @"a444" ];
            break;
        case iTermQuadrantUpperLeftAndUpperRightAndLowerRight: // ▜
            parts = @[ @"a044", @"e044", @"e444" ];
            break;
        case iTermQuadrantUpperRight: // ▝
            parts = @[ @"e044" ];
            break;
        case iTermQuadrantUpperRightAndLowerLeft: // ▞
            parts = @[ @"e044", @"a444" ];
            break;
        case iTermQuadrantUpperRightAndLowerLeftAndLowerRight: // ▟
            parts = @[ @"e044", @"a444", @"e444" ];
            break;

        case iTermLightShade: // ░
        case iTermMediumShade: // ▒
        case iTermDarkShade: // ▓
            return nil;
    }

    return [parts mapWithBlock:^id(NSString *part) {
        const char *bytes = part.UTF8String;

        CGFloat xo = cellSize.width * (CGFloat)(bytes[0] - 'a') / 8.0;
        CGFloat yo = cellSize.height * (CGFloat)(bytes[1] - '0') / 8.0;
        CGFloat w = cellSize.width / 8.0 * (CGFloat)(bytes[2] - '0');
        CGFloat h = cellSize.height / 8.0 * (CGFloat)(bytes[3] - '0');

        return [NSBezierPath bezierPathWithRect:NSMakeRect(xo, yo, w, h)];
    }];
}

+ (void)performBlockWithoutAntialiasing:(void (^)(void))block {
    NSImageInterpolation saved = [[NSGraphicsContext currentContext] imageInterpolation];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationNone];
    block();
    [[NSGraphicsContext currentContext] setImageInterpolation:saved];
}

+ (void)drawPowerlineCode:(unichar)code cellSize:(NSSize)cellSize color:(NSColor *)color {
    switch (code) {
        case 0xE0A0:
            [self drawPDFWithName:@"PowerlineVersionControlBranch" cellSize:cellSize stretch:NO color:color antialiased:YES];
            break;

        case 0xE0A1:
            [self drawPDFWithName:@"PowerlineLN" cellSize:cellSize stretch:NO color:color antialiased:NO];
            break;

        case 0xE0A2:
            [self drawPDFWithName:@"PowerlinePadlock" cellSize:cellSize stretch:NO color:color antialiased:YES];
            break;
        case 0xE0B0:
            [self drawPDFWithName:@"PowerlineSolidRightArrow" cellSize:cellSize stretch:YES color:color antialiased:YES];
            break;
        case 0xE0B2:
            [self drawPDFWithName:@"PowerlineSolidLeftArrow" cellSize:cellSize stretch:YES color:color antialiased:YES];
            break;
        case 0xE0B1:
            [self drawPDFWithName:@"PowerlineLineRightArrow" cellSize:cellSize stretch:YES color:color antialiased:YES];
            break;
        case 0xE0B3:
            [self drawPDFWithName:@"PowerlineLineLeftArrow" cellSize:cellSize stretch:YES color:color antialiased:YES];
            break;
    }
}

+ (NSImage *)bitmapForImage:(NSImage *)image {
    NSSize size = image.size;
    return [NSImage imageOfSize:size drawBlock:^{
        [image drawInRect:NSMakeRect(0, 0, size.width, size.height)
                 fromRect:NSZeroRect
                operation:NSCompositingOperationSourceOver
                 fraction:1];
    }];
}

+ (NSImage *)imageForPDFNamed:(NSString *)pdfName
                     cellSize:(NSSize)cellSize
                  antialiased:(BOOL)antialiased
                        color:(NSColor *)color {
    static iTermImageCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[iTermImageCache alloc] initWithByteLimit:1024 * 1024];
    });
    NSImage *image = [cache imageWithName:pdfName size:cellSize color:color];
    if (image) {
        return image;
    }

    if (color) {
        image = [cache imageWithName:pdfName size:cellSize color:nil];
    }
    
    if (!image) {
        image = [self newImageForPDFNamed:pdfName
                                 cellSize:cellSize
                              antialiased:antialiased];
        image = [self bitmapForImage:image];
        [cache addImage:image name:pdfName size:cellSize color:nil];
    }
    if (color) {
        image = [image imageWithColor:color];
        image = [self bitmapForImage:image];
        [cache addImage:image name:pdfName size:cellSize color:color];
    }
    return image;
}

+ (NSImage *)newImageForPDFNamed:(NSString *)pdfName
                        cellSize:(NSSize)cellSize
                     antialiased:(BOOL)antialiased {
    if (!antialiased) {
        __block NSImage *image = nil;
        [self performBlockWithoutAntialiasing:^{
            image = [self newImageForPDFNamed:pdfName
                                     cellSize:cellSize
                                  antialiased:YES];
        }];
        return image;
    }

    NSString *pdfPath = [[NSBundle bundleForClass:self] pathForResource:pdfName ofType:@"pdf"];
    NSData* pdfData = [NSData dataWithContentsOfFile:pdfPath];
    NSPDFImageRep *pdfImageRep = [NSPDFImageRep imageRepWithData:pdfData];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(pdfImageRep.size.width * 2,
                                                              pdfImageRep.size.height * 2)];
    [image addRepresentation:pdfImageRep];
    return image;
}

+ (NSRect)drawingDestinationForImageOfSize:(NSSize)imageSize
                           destinationSize:(NSSize)destinationSize
                                   stretch:(BOOL)stretch {
    const CGFloat pdfAspectRatio = imageSize.width / imageSize.height;
    const CGFloat cellAspectRatio = destinationSize.width / destinationSize.height;

    if (stretch) {
        return NSMakeRect(0, 0, destinationSize.width, destinationSize.height);
    }
    
    if (pdfAspectRatio > cellAspectRatio) {
        // PDF is wider than cell, so letterbox top and bottom
        const CGFloat letterboxHeight = (destinationSize.height - destinationSize.width / pdfAspectRatio) / 2;
        return NSMakeRect(0, letterboxHeight, destinationSize.width, destinationSize.height - letterboxHeight * 2);
    }

    // PDF is taller than cell so pillarbox left and right
    const CGFloat pillarboxWidth = (destinationSize.width - destinationSize.height * pdfAspectRatio) / 2;
    return NSMakeRect(pillarboxWidth, 0, destinationSize.width - pillarboxWidth * 2, destinationSize.height);
}

+ (void)drawPDFWithName:(NSString *)pdfName
               cellSize:(NSSize)cellSize
                stretch:(BOOL)stretch
                  color:(NSColor *)color
            antialiased:(BOOL)antialiased {
   
    NSImage *image = [self imageForPDFNamed:pdfName
                                   cellSize:cellSize
                                antialiased:antialiased
                                      color:color];
    NSImageRep *imageRep = [[image representations] firstObject];
    NSRect destination = [self drawingDestinationForImageOfSize:imageRep.size
                                                destinationSize:cellSize
                                                        stretch:stretch];
    [imageRep drawInRect:destination
                fromRect:NSZeroRect
               operation:NSCompositingOperationSourceOver
                fraction:1
          respectFlipped:YES
                   hints:nil];
}

+ (void)drawCodeInCurrentContext:(unichar)code
                        cellSize:(NSSize)cellSize
                           scale:(CGFloat)scale
                          offset:(CGPoint)offset
                           color:(NSColor *)color
        useNativePowerlineGlyphs:(BOOL)useNativePowerlineGlyphs {
    if (useNativePowerlineGlyphs) {
        switch (code) {
            case 0xE0A0:  // Version control branch
            case 0xE0A1:  // LN (line) symbol
            case 0xE0A2:  // Closed padlock
            case 0xE0B0:  // Rightward black arrowhead
            case 0xE0B1:  // Rightwards arrowhead
            case 0xE0B2:  // Leftwards black arrowhead
            case 0xE0B3:  // Leftwards arrowhead
                [self drawPowerlineCode:code
                               cellSize:cellSize
                                  color:color];
                return;
        }
    }
    
    BOOL solid = NO;
    NSArray<NSBezierPath *> *paths = [iTermBoxDrawingBezierCurveFactory bezierPathsForBoxDrawingCode:code
                                                                                            cellSize:cellSize
                                                                                               scale:scale
                                                                                              offset:offset
                                                                                               solid:&solid];
    for (NSBezierPath *path in paths) {
        if (solid) {
            [path fill];
        } else {
            [path setLineWidth:scale];
            [path stroke];
        }
    }
}

+ (NSArray<NSBezierPath *> *)bezierPathsForBoxDrawingCode:(unichar)code
                                                 cellSize:(NSSize)cellSize
                                                    scale:(CGFloat)scale
                                                   offset:(CGPoint)offset
                                                    solid:(out BOOL *)solid {
    NSArray<NSBezierPath *> *solidBoxPaths = [self bezierPathsForSolidBoxesForCode:code
                                                                          cellSize:cellSize
                                                                             scale:scale];
    if (solidBoxPaths) {
        if (solid) {
            *solid = YES;
        }
        return solidBoxPaths;
    }
    if (solid) {
        *solid = NO;
    }
    //          l         hc-1    hc-1/2    hc    hc+1/2      hc+1             r
    //          a         b       c         d     e           f                g
    // t        1
    //
    // vc-1     2
    // vc-1/2   3
    // vc       4
    // vc+1/2   5
    // vc+1     6
    //
    // b        7
    NSString *components = nil;
    switch (code) {
        case iTermBoxDrawingCodeLightHorizontal:  // ─
            components = @"a4g4";
            break;
        case iTermBoxDrawingCodeHeavyHorizontal:  // ━
            components = @"a3g3 a5g5";
            break;
        case iTermBoxDrawingCodeLightVertical:  // │
            components = @"d1d7";
            break;
        case iTermBoxDrawingCodeHeavyVertical:  // ┃
            components = @"c1c7 e1e7";
            break;

        case iTermBoxDrawingCodeLightTripleDashHorizontal:  // ┄
        case iTermBoxDrawingCodeHeavyTripleDashHorizontal:  // ┅
        case iTermBoxDrawingCodeLightTripleDashVertical:  // ┆
        case iTermBoxDrawingCodeHeavyTripleDashVertical:  // ┇
        case iTermBoxDrawingCodeLightQuadrupleDashHorizontal:  // ┈
        case iTermBoxDrawingCodeHeavyQuadrupleDashHorizontal:  // ┉
        case iTermBoxDrawingCodeLightQuadrupleDashVertical:  // ┊
        case iTermBoxDrawingCodeHeavyQuadrupleDashVertical:  // ┋
            return nil;

        case iTermBoxDrawingCodeLightDownAndRight:  // ┌
            components = @"g4d4 d4d7";
            break;
        case iTermBoxDrawingCodeDownLightAndRightHeavy:  // ┍
            components = @"g3d3 d3d7 g5d5";
            break;
        case iTermBoxDrawingCodeDownHeavyAndRightLight:  // ┎
            components = @"g4c4 c4c7 e4e7";
            break;
        case iTermBoxDrawingCodeHeavyDownAndRight:  // ┏
            components = @"g3c3 c3c7 g5e5 e5e7";
            break;
        case iTermBoxDrawingCodeLightDownAndLeft:  // ┐
            components = @"a4d4 d4d7";
            break;
        case iTermBoxDrawingCodeDownLightAndLeftHeavy:  // ┑
            components = @"a3d3 d3d7 a5d5";
            break;
        case iTermBoxDrawingCodeDownHeavyAndLeftLight:  // ┒
            components = @"a4e4 e4e7 c4c7";
            break;
        case iTermBoxDrawingCodeHeavyDownAndLeft:  // ┓
            components = @"a3e3 e3e7 a5c5 c5c7";
            break;
        case iTermBoxDrawingCodeLightUpAndRight:  // └
            components = @"d1d4 d4g4";
            break;
        case iTermBoxDrawingCodeUpLightAndRightHeavy:  // ┕
            components = @"d1d5 d5g5 d3g3";
            break;
        case iTermBoxDrawingCodeUpHeavyAndRightLight:  // ┖
            components = @"c1c4 c4g4 e1e4";
            break;
        case iTermBoxDrawingCodeHeavyUpAndRight:  // ┗
            components = @"c1c5 c5g5 e1e3 e3g3";
            break;
        case iTermBoxDrawingCodeLightUpAndLeft:  // ┘
            components = @"a4d4 d4d1";
            break;
        case iTermBoxDrawingCodeUpLightAndLeftHeavy:  // ┙
            components = @"a5d5 d5d1 a3d3";
            break;
        case iTermBoxDrawingCodeUpHeavyAndLeftLight:  // ┚
            components = @"a4e4 e4e1 c4c1";
            break;
        case iTermBoxDrawingCodeHeavyUpAndLeft:  // ┛
            components = @"a5e5 e5e1 a3c3 c3c1";
            break;
        case iTermBoxDrawingCodeLightVerticalAndRight:  // ├
            components = @"d1d7 d4g4";
            break;
        case iTermBoxDrawingCodeVerticalLightAndRightHeavy:  // ┝
            components = @"d1d7 d3g3 d5g5";
            break;
        case iTermBoxDrawingCodeUpHeavyAndRightDownLight:  // ┞
            components = @"c1c4 e1e4 e4g4 d4d7";
            break;
        case iTermBoxDrawingCodeDownHeavyAndRightUpLight:  // ┟
            components = @"d1d4 d4g4 c4c7 e4e7";
            break;
        case iTermBoxDrawingCodeVerticalHeavyAndRightLight:  // ┠
            components = @"c1c7 e1e7 e4g4";
            break;
        case iTermBoxDrawingCodeDownLightAndRightUpHeavy:  // ┡
            components = @"c1c4 c4g4 e1e3 e3g3 d4d7";
            break;
        case iTermBoxDrawingCodeUpLightAndRightDownHeavy:  // ┢
            components = @"d1d4 c7c3 c3g3 e7e5 e5g5";
            break;
        case iTermBoxDrawingCodeHeavyVerticalAndRight:  // ┣
            components = @"c1c7 e1e3 e3g3 g5e5 e5e7";
            break;
        case iTermBoxDrawingCodeLightVerticalAndLeft:  // ┤
            components = @"d1d7 a4d4";
            break;
        case iTermBoxDrawingCodeVerticalLightAndLeftHeavy:  // ┥
            components = @"d1d7 a3d3 a5d5";
            break;
        case iTermBoxDrawingCodeUpHeavyAndLeftDownLight:  // ┦
            components = @"c1c4 e1e4 a4d4 d4d7";
            break;
        case iTermBoxDrawingCodeDownHeavyAndLeftUpLight:  // ┧
            components = @"d1d4 d4a4 c4c7 e4e7";
            break;
        case iTermBoxDrawingCodeVerticalHeavyAndLeftLight:  // ┨
            components = @"a4c4 c1c7 e1e7";
            break;
        case iTermBoxDrawingCodeDownLightAndLeftUpHeavy:  // ┩
            components = @"c1c3 c3a3 e1e5 e5a5 d4d7";
            break;
        case iTermBoxDrawingCodeUpLightAndLeftDownHeavy:  // ┪
            components = @"a3d3 d3d7 a5c5 c5c7 d1d4";
            break;
        case iTermBoxDrawingCodeHeavyVerticalAndLeft:  // ┫
            components = @"a3c3 c3c1 a5c5 c5c7 e1e7";
            break;
        case iTermBoxDrawingCodeLightDownAndHorizontal:  // ┬
            components = @"a4g4 d4d7";
            break;
        case iTermBoxDrawingCodeLeftHeavyAndRightDownLight:  // ┭
            components = @"a3d3 a5d5 d7d4 d4g4";
            break;
        case iTermBoxDrawingCodeRightHeavyAndLeftDownLight:  // ┮
            components = @"a4d4 d4d7 d3g3 d5g5";
            break;
        case iTermBoxDrawingCodeDownLightAndHorizontalHeavy:  // ┯
            components = @"a3g3 a5g5 d5d7";
            break;
        case iTermBoxDrawingCodeDownHeavyAndHorizontalLight:  // ┰
            components = @"a4g4 c4c7 e4e7";
            break;
        case iTermBoxDrawingCodeRightLightAndLeftDownHeavy:  // ┱
            components = @"a3e3 e3e7 a5c5 c5c7 d4g4";
            break;
        case iTermBoxDrawingCodeLeftLightAndRightDownHeavy:  // ┲
            components = @"a4d4 c7c3 c3g3 e7e5 e5g5";
            break;
        case iTermBoxDrawingCodeHeavyDownAndHorizontal:  // ┳
            components = @"a3g3 a5c5 c5c7 e7e5 e5g5";
            break;
        case iTermBoxDrawingCodeLightUpAndHorizontal:  // ┴
            components = @"a4g4 d1d4";
            break;
        case iTermBoxDrawingCodeLeftHeavyAndRightUpLight:  // ┵
            components = @"d1d4 d4g4 a3d3 a5d5";
            break;
        case iTermBoxDrawingCodeRightHeavyAndLeftUpLight:  // ┶
            components = @"a4d4 d4d1 d3g3 d5g5";
            break;
        case iTermBoxDrawingCodeUpLightAndHorizontalHeavy:  // ┷
            components = @"a3g3 a5g5 d1d4";
            break;
        case iTermBoxDrawingCodeUpHeavyAndHorizontalLight:  // ┸
            components = @"a4g4 c1c4 e1e4";
            break;
        case iTermBoxDrawingCodeRightLightAndLeftUpHeavy:  // ┹
            components = @"a3c3 c3c1 a5e5 e5e1 d4g4";
            break;
        case iTermBoxDrawingCodeLeftLightAndRightUpHeavy:  // ┺
            components = @"a4d4 c1c5 c5g5 d1d3 d3g3";
            break;
        case iTermBoxDrawingCodeHeavyUpAndHorizontal:  // ┻
            components = @"a5g5 a3c3 c3c1 e1e3 e3g3";
            break;
        case iTermBoxDrawingCodeLightVerticalAndHorizontal:  // ┼
            components = @"a4g4 d1d7";
            break;
        case iTermBoxDrawingCodeLeftHeavyAndRightVerticalLight:  // ┽
            components = @"d1d7 d4g4 a3d3 a5d5";
            break;
        case iTermBoxDrawingCodeRightHeavyAndLeftVerticalLight:  // ┾
            components = @"d1d7 a4d4 d3g3 d5g5";
            break;
        case iTermBoxDrawingCodeVerticalLightAndHorizontalHeavy:  // ┿
            components = @"d1d7 a3g3 a5g5";
            break;
        case iTermBoxDrawingCodeUpHeavyAndDownHorizontalLight:  // ╀
            components = @"a4g4 d4d7 c1c4 e1e4";
            break;
        case iTermBoxDrawingCodeDownHeavyAndUpHorizontalLight:  // ╁
            components = @"a4g4 d1d4 c4c7 e4e7";
            break;
        case iTermBoxDrawingCodeVerticalHeavyAndHorizontalLight:  // ╂
            components = @"a4g4 c1c7 e1e7";
            break;
        case iTermBoxDrawingCodeLeftUpHeavyAndRightDownLight:  // ╃
            components = @"a3c3 c3c1 a5e5 e5e1 d7d4 d4g4";
            break;
        case iTermBoxDrawingCodeRightUpHeavyAndLeftDownLight:  // ╄
            components = @"a4d4 d4d7 c1c5 c5g5 e1e3 e3g3";
            break;
        case iTermBoxDrawingCodeLeftDownHeavyAndRightUpLight:  // ╅
            components = @"d1d4 d4g4 a3e3 e3e7 a5c5 c5c7";
            break;
        case iTermBoxDrawingCodeRightDownHeavyAndLeftUpLight:  // ╆
            components = @"a4d4 d4d1 c7c3 c3g3 e7e5 e5g5";
            break;
        case iTermBoxDrawingCodeDownLightAndUpHorizontalHeavy:  // ╇
            components = @"a5g5 a3c3 c3c1 e1e3 e3g3 d4d7";
            break;
        case iTermBoxDrawingCodeUpLightAndDownHorizontalHeavy:  // ╈
            components = @"d1d4 a3g3 a5c5 c5c7 e7e5 e5g5";
            break;
        case iTermBoxDrawingCodeRightLightAndLeftVerticalHeavy:  // ╉
            components = @"a3c3 c3c1 a5c5 c5c7 e1e7 d4g4";
            break;
        case iTermBoxDrawingCodeLeftLightAndRightVerticalHeavy:  // ╊
            components = @"a4c4 c1c7 e1e3 e3g3 e7e5 e5g5";
            break;
        case iTermBoxDrawingCodeHeavyVerticalAndHorizontal:  // ╋
            components = @"a3g3 a5g5 c1c7 e1e7";
            break;

        case iTermBoxDrawingCodeLightDoubleDashHorizontal:  // ╌
        case iTermBoxDrawingCodeHeavyDoubleDashHorizontal:  // ╍
        case iTermBoxDrawingCodeLightDoubleDashVertical:  // ╎
        case iTermBoxDrawingCodeHeavyDoubleDashVertical:  // ╏
            return nil;

        case iTermBoxDrawingCodeDoubleHorizontal:  // ═
            components = @"a2g2 a6g6";
            break;
        case iTermBoxDrawingCodeDoubleVertical:  // ║
            components = @"b1b7 f1f7";
            break;
        case iTermBoxDrawingCodeDownSingleAndRightDouble:  // ╒
            components = @"g2d2 d2d7 g6d6";
            break;
        case iTermBoxDrawingCodeDownDoubleAndRightSingle:  // ╓
            components = @"g4b4 b4b7 f4f7";
            break;
        case iTermBoxDrawingCodeDoubleDownAndRight:  // ╔
            components = @"g2b2 b2b7 g6f6 f6f7";
            break;
        case iTermBoxDrawingCodeDownSingleAndLeftDouble:  // ╕
            components = @"a2d2 d2d7 a6d6";
            break;
        case iTermBoxDrawingCodeDownDoubleAndLeftSingle:  // ╖
            components = @"a4f4 f4f7 b4b7";
            break;
        case iTermBoxDrawingCodeDoubleDownAndLeft:  // ╗
            components = @"a2f2 f2f7 a6b6 b6b7";
            break;
        case iTermBoxDrawingCodeUpSingleAndRightDouble:  // ╘
            components = @"d1d6 d6g6 d2g2";
            break;
        case iTermBoxDrawingCodeUpDoubleAndRightSingle:  // ╙
            components = @"b1b4 b4g4 f1f4";
            break;
        case iTermBoxDrawingCodeDoubleUpAndRight:  // ╚
            components = @"b1b6 b6g6 f1f2 f2g2";
            break;
        case iTermBoxDrawingCodeUpSingleAndLeftDouble:  // ╛
            components = @"a2d2 a6d6 d6d1";
            break;
        case iTermBoxDrawingCodeUpDoubleAndLeftSingle:  // ╜
            components = @"a4f4 f4f1 b4b1";
            break;
        case iTermBoxDrawingCodeDoubleUpAndLeft:  // ╝
            components = @"a2b2 b2b1 a6f6 f6f1";
            break;
        case iTermBoxDrawingCodeVerticalSingleAndRightDouble:  // ╞
            components = @"d1d7 d2g2 d6g6";
            break;
        case iTermBoxDrawingCodeVerticalDoubleAndRightSingle:  // ╟
            components = @"b1b7 f1f7 f4g4";
            break;
        case iTermBoxDrawingCodeDoubleVerticalAndRight:  // ╠
            components = @"b1b7 f1f2 f2g2 f7f6 f6g6";
            break;
        case iTermBoxDrawingCodeVerticalSingleAndLeftDouble:  // ╡
            components = @"d1d7 a2d2 a6d6";
            break;
        case iTermBoxDrawingCodeVerticalDoubleAndLeftSingle:  // ╢
            components = @"a4b4 b1b7 f1f7";
            break;
        case iTermBoxDrawingCodeDoubleVerticalAndLeft:  // ╣
            components = @"a2b2 b2b1 a6b6 b6b7 f1f7";
            break;
        case iTermBoxDrawingCodeDownSingleAndHorizontalDouble:  // ╤
            components = @"a2g2 a6g6 d6d7";
            break;
        case iTermBoxDrawingCodeDownDoubleAndHorizontalSingle:  // ╥
            components = @"a4g4 b4b7 f4f7";
            break;
        case iTermBoxDrawingCodeDoubleDownAndHorizontal:  // ╦
            components = @"a2g2 a6b6 b6b7 f7f6 f6g6";
            break;
        case iTermBoxDrawingCodeUpSingleAndHorizontalDouble:  // ╧
            components = @"a6g6 a2g2 d1d2";
            break;
        case iTermBoxDrawingCodeUpDoubleAndHorizontalSingle:  // ╨
            components = @"a4g4 b1b4 f1f4";
            break;
        case iTermBoxDrawingCodeDoubleUpAndHorizontal:  // ╩
            components = @"a2b2 b2b1 f1f2 f2g2 a6g6";
            break;
        case iTermBoxDrawingCodeVerticalSingleAndHorizontalDouble:  // ╪
            components = @"a2g2 a6g6 d1d7";
            break;
        case iTermBoxDrawingCodeVerticalDoubleAndHorizontalSingle:  // ╫
            components = @"b1b7 f1f7 a4g4";
            break;
        case iTermBoxDrawingCodeDoubleVerticalAndHorizontal:  // ╬
            components = @"a2b2 b2b1 f1f2 f2g2 g6f6 f6f7 b7b6 b6a6";
            break;
        case iTermBoxDrawingCodeLightArcDownAndRight:  // ╭
            components = @"g4d7d4d4";
            break;
        case iTermBoxDrawingCodeLightArcDownAndLeft:  // ╮
            components = @"a4d7d4d4";
            break;
        case iTermBoxDrawingCodeLightArcUpAndLeft:  // ╯
            components = @"a4d1d4d4";
            break;
        case iTermBoxDrawingCodeLightArcUpAndRight:  // ╰
            components = @"d1g4d4d4";
            break;
        case iTermBoxDrawingCodeLightDiagonalUpperRightToLowerLeft:  // ╱
            components = @"a7g1";
            break;
        case iTermBoxDrawingCodeLightDiagonalUpperLeftToLowerRight:  // ╲
            components = @"a1g7";
            break;
        case iTermBoxDrawingCodeLightDiagonalCross:  // ╳
            components = @"a7g1 a1g7";
            break;
        case iTermBoxDrawingCodeLightLeft:  // ╴
            components = @"a4d4";
            break;
        case iTermBoxDrawingCodeLightUp:  // ╵
            components = @"d1d4";
            break;
        case iTermBoxDrawingCodeLightRight:  // ╶
            components = @"d4g4";
            break;
        case iTermBoxDrawingCodeLightDown:  // ╷
            components = @"d4d7";
            break;
        case iTermBoxDrawingCodeHeavyLeft:  // ╸
            components = @"a3d3 a5d5";
            break;
        case iTermBoxDrawingCodeHeavyUp:  // ╹
            components = @"c1c4 e1e4";
            break;
        case iTermBoxDrawingCodeHeavyRight:  // ╺
            components = @"d3g3 d5g5";
            break;
        case iTermBoxDrawingCodeHeavyDown:  // ╻
            components = @"c4c7 e4e7";
            break;
        case iTermBoxDrawingCodeLightLeftAndHeavyRight:  // ╼
            components = @"a4d4 d3g3 d5g5";
            break;
        case iTermBoxDrawingCodeLightUpAndHeavyDown:  // ╽
            components = @"d1d4 c4c7 e4e7";
            break;
        case iTermBoxDrawingCodeHeavyLeftAndLightRight:  // ╾
            components = @"a3d3 a5d5 d4g4";
            break;
        case iTermBoxDrawingCodeHeavyUpAndLightDown:  // ╿
            components = @"c1c4 e1e4 d4d7";
            break;
    }

    if (!components) {
        return nil;
    }

    CGFloat horizontalCenter = cellSize.width / 2.0;
    CGFloat verticalCenter = cellSize.height / 2.0;

    const char *bytes = [components UTF8String];
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineWidth:scale];
    int lastX = -1;
    int lastY = -1;
    int i = 0;
    int length = components.length;
    CGFloat xs[] = {
        0,
        horizontalCenter - scale,
        horizontalCenter - scale/2,
        horizontalCenter,
        horizontalCenter + scale/2,
        horizontalCenter + scale,
        cellSize.width
    };
    CGFloat ys[] = {
        0,
        verticalCenter - scale,
        verticalCenter - scale/2,
        verticalCenter,
        verticalCenter + scale/2,
        verticalCenter + scale,
        cellSize.height

    };
    CGFloat (^centerPoint)(CGFloat) = ^CGFloat(CGFloat value) {
        CGFloat nearest = value;
        if (nearest > 0) {
            return nearest + scale / 2;
        } else {
            return 0;
        }
    };
    CGPoint (^makePoint)(CGFloat, CGFloat) = ^CGPoint(CGFloat x, CGFloat y) {
        return CGPointMake(centerPoint(x) + offset.x,
                           centerPoint(y) + offset.y);
    };
    while (i + 4 <= length) {
        int x1 = bytes[i++] - 'a';
        int y1 = bytes[i++] - '1';
        int x2 = bytes[i++] - 'a';
        int y2 = bytes[i++] - '1';

        if (x1 != lastX || y1 != lastY) {
            [path moveToPoint:makePoint((xs[x1]),
                                          (ys[y1]))];
        }
        if (i < length && isalpha(bytes[i])) {
            int cx1 = bytes[i++] - 'a';
            int cy1 = bytes[i++] - '1';
            int cx2 = bytes[i++] - 'a';
            int cy2 = bytes[i++] - '1';
            [path curveToPoint:makePoint((xs[x2]), (ys[y2]))
                 controlPoint1:makePoint((xs[cx1]), (ys[cy1]))
                 controlPoint2:makePoint((xs[cx2]), (ys[cy2]))];
        } else {
            [path lineToPoint:makePoint((xs[x2]), (ys[y2]))];
        }

        i++;

        lastX = x2;
        lastY = y2;
    }

    return @[ path ];
}

+ (NSBezierPath *)bezierPathForPoints:(NSArray *)points
                   extendPastCenterBy:(NSPoint)extension
                             cellSize:(NSSize)cellSize {
    CGFloat cx = cellSize.width / 2.0;
    CGFloat cy = cellSize.height / 2.0;
    CGFloat xs[] = { 0, cx - 1, cx, cx + 1, cellSize.width };
    CGFloat ys[] = { 0, cy - 1, cy, cy + 1, cellSize.height };
    NSBezierPath *path = [NSBezierPath bezierPath];
    BOOL first = YES;
    for (NSNumber *n in points) {
        CGFloat x = xs[n.intValue % 5];
        CGFloat y = ys[n.intValue / 5];
        if ((n.intValue % 5 == 2) && (n.intValue / 5 == 2)) {
            x += extension.x;
            y += extension.y;
        }
        NSPoint p = NSMakePoint(x, y);
        if (first) {
            [path moveToPoint:p];
            first = NO;
        } else {
            [path lineToPoint:p];
        }
    }
    return path;
}

@end
