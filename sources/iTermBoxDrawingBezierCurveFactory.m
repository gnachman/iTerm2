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

// NOTE: If you change this also update bezierPathsForSolidBoxesForCode:cellSize:scale:
// These characters are not affected by minimum contrast rules because they tend to be next to
// an empty space whose background color should match.
+ (NSCharacterSet *)blockDrawingCharacters {
    static NSCharacterSet *characterSet;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *temp = [[NSMutableCharacterSet alloc] init];
        unichar chars[] = {
            iTermUpperHalfBlock,  // ▀
            iTermLowerOneEighthBlock,  // ▁
            iTermLowerOneQuarterBlock,  // ▂
            iTermLowerThreeEighthsBlock,  // ▃
            iTermLowerHalfBlock,  // ▄
            iTermLowerFiveEighthsBlock,  // ▅
            iTermLowerThreeQuartersBlock,  // ▆
            iTermLowerSevenEighthsBlock,  // ▇
            iTermFullBlock,  // █
            iTermLeftSevenEighthsBlock,  // ▉
            iTermLeftThreeQuartersBlock,  // ▊
            iTermLeftFiveEighthsBlock,  // ▋
            iTermLeftHalfBlock,  // ▌
            iTermLeftThreeEighthsBlock,  // ▍
            iTermLeftOneQuarterBlock,  // ▎
            iTermLeftOneEighthBlock,  // ▏
            iTermRightHalfBlock,  // ▐
            iTermUpperOneEighthBlock,  // ▔
            iTermRightOneEighthBlock,  // ▕
            iTermQuadrantLowerLeft,  // ▖
            iTermQuadrantLowerRight,  // ▗
            iTermQuadrantUpperLeft,  // ▘
            iTermQuadrantUpperLeftAndLowerLeftAndLowerRight,  // ▙
            iTermQuadrantUpperLeftAndLowerRight,  // ▚
            iTermQuadrantUpperLeftAndUpperRightAndLowerLeft,  // ▛
            iTermQuadrantUpperLeftAndUpperRightAndLowerRight,  // ▜
            iTermQuadrantUpperRight,  // ▝
            iTermQuadrantUpperRightAndLowerLeft,  // ▞
            iTermQuadrantUpperRightAndLowerLeftAndLowerRight,  // ▟
            iTermLightShade,  // ░
            iTermMediumShade,  // ▒
            iTermDarkShade,  // ▓

            // Powerline. See https://github.com/ryanoasis/powerline-extra-symbols
            0xe0b0,
            0xe0b2,
            0xe0b4,
            0xe0b6,
            0xe0b8,
            0xe0ba,
            0xe0bc,
            0xe0be,
            0xe0c0,
            0xe0c2,
            0xe0c8,
            0xe0ca,
            0xe0d1,
            0xe0d2,
            0xe0d4,
            0xe0d6,
            0xe0d7
        };
        for (size_t i = 0; i < sizeof(chars) / sizeof(*chars); i++) {
            [temp addCharactersInRange:NSMakeRange(chars[i], 1)];
        }
        characterSet = [temp copy];
    });
    return characterSet;
}

typedef NS_OPTIONS(NSUInteger, iTermPowerlineDrawingOptions) {
    iTermPowerlineDrawingOptionsNone = 0,
    iTermPowerlineDrawingOptionsMirrored = 1 << 0,
    iTermPowerlineDrawingOptionsHalfWidth = 1 << 1,

    iTermPowerlineDrawingOptionsFullBleedLeft = 1 << 2,
    iTermPowerlineDrawingOptionsFullBleedRight = 1 << 3,
};

+ (NSDictionary<NSNumber *, NSArray *> *)powerlineExtendedSymbols {
    if (![iTermAdvancedSettingsModel supportPowerlineExtendedSymbols]) {
        return @{};
    }
    return @{ @(0xE0A3): @[@"uniE0A3_column-number", @(iTermPowerlineDrawingOptionsNone)],
              @(0xE0B0): @[@"uniE0B0_Powerline_normal-left", 
                           @(iTermPowerlineDrawingOptionsFullBleedLeft)],
              @(0xE0B2): @[@"uniE0B2_Powerline_normal-right", 
                           @(iTermPowerlineDrawingOptionsFullBleedRight)],
              @(0xE0B4): @[@"uniE0B4_right-half-circle-thick", 
                           @(iTermPowerlineDrawingOptionsFullBleedLeft)],
              @(0xE0B5): @[@"uniE0B5_right-half-circle-thin", @(iTermPowerlineDrawingOptionsNone)],
              @(0xE0B6): @[@"uniE0B6_left-half-circle-thick", @(
                           iTermPowerlineDrawingOptionsFullBleedRight)],
              @(0xE0B7): @[@"uniE0B7_left-half-circle-thin", @(iTermPowerlineDrawingOptionsNone)],
              @(0xE0B8): @[@"uniE0B8_lower-left-triangle", 
                           @(iTermPowerlineDrawingOptionsFullBleedLeft)],
              @(0xE0C0): @[@"uniE0C0_flame-thick", @(
                           iTermPowerlineDrawingOptionsFullBleedLeft)],
              @(0xE0C1): @[@"uniE0C1_flame-thin", @(iTermPowerlineDrawingOptionsNone)],
              @(0xE0C2): @[@"uniE0C0_flame-thick", @(
                           iTermPowerlineDrawingOptionsMirrored |
                           iTermPowerlineDrawingOptionsFullBleedLeft)],
              @(0xE0C3): @[@"uniE0C1_flame-thin", @(iTermPowerlineDrawingOptionsMirrored)],
              @(0xE0CE): @[@"uniE0CE_lego_separator", @(iTermPowerlineDrawingOptionsNone)],
              @(0xE0CF): @[@"uniE0CF_lego_separator_thin", @(iTermPowerlineDrawingOptionsNone)],
              @(0xE0D1): @[@"uniE0D1_lego_block_sideways", @(
                           iTermPowerlineDrawingOptionsFullBleedLeft)],

              // These were exported to PDF using FontForge
              @(0xE0C4): @[@"uniE0C4_PowerlineExtraSymbols", @(iTermPowerlineDrawingOptionsNone)],
              @(0xE0C5): @[@"uniE0C4_PowerlineExtraSymbols", @(iTermPowerlineDrawingOptionsMirrored)],
              @(0xE0C6): @[@"uniE0C6_PowerlineExtraSymbols", @(iTermPowerlineDrawingOptionsNone)],
              @(0xE0C7): @[@"uniE0C6_PowerlineExtraSymbols", @(iTermPowerlineDrawingOptionsMirrored)],
              @(0xE0C8): @[@"uniE0C8_PowerlineExtraSymbols", 
                           @(iTermPowerlineDrawingOptionsFullBleedLeft)],
              @(0xE0C9): @[@"uniE0C9_PowerlineExtraSymbols", @(
                           iTermPowerlineDrawingOptionsFullBleedLeft)],
              @(0xE0CA): @[@"uniE0C8_PowerlineExtraSymbols", @(iTermPowerlineDrawingOptionsMirrored)],
              @(0xE0CB): @[@"uniE0C9_PowerlineExtraSymbols", @(
                           iTermPowerlineDrawingOptionsMirrored |
                           iTermPowerlineDrawingOptionsFullBleedRight)],
              @(0xE0CC): @[@"uniE0CC_PowerlineExtraSymbols", @(iTermPowerlineDrawingOptionsNone)],
              @(0xE0CD): @[@"uniE0CD_PowerlineExtraSymbols", @(iTermPowerlineDrawingOptionsNone)],
              @(0xE0D0): @[@"uniE0D0_PowerlineExtraSymbols", @(iTermPowerlineDrawingOptionsNone)],
              @(0xE0D2): @[@"uniE0D2_PowerlineExtraSymbols", @(
                           iTermPowerlineDrawingOptionsHalfWidth)],
              @(0xE0D4): @[@"uniE0D2_PowerlineExtraSymbols", @(
                           iTermPowerlineDrawingOptionsHalfWidth |
                           iTermPowerlineDrawingOptionsMirrored)],
              @(0xE0D6): @[@"uniE0D6_Powerline_normal-right-inverse-cutout", @(
                           iTermPowerlineDrawingOptionsFullBleedLeft)],
              @(0xE0D7): @[@"uniE0D7_Powerline_normal-left-inverse-cutout", @(
                           iTermPowerlineDrawingOptionsFullBleedRight)],
    };
}

+ (NSSet<NSNumber *> *)doubleWidthPowerlineSymbols {
    if (![iTermAdvancedSettingsModel makeSomePowerlineSymbolsWide]) {
        return [NSSet set];
    }
    return [NSSet setWithArray:@[ @(0xE0B8), @(0xE0B9), @(0xE0BA), @(0xE0BB),
                                  @(0xE0BC), @(0xE0BD), @(0xE0BE), @(0xE0BF),
                                  @(0xE0C0), @(0xE0C1), @(0xE0C2), @(0xE0C3),
                                  @(0xE0C4), @(0xE0C5), @(0xE0C6), @(0xE0C7),
                                  @(0xE0C8), @(0xE0C9), @(0xE0CA), @(0xE0CB),
                                  @(0xE0CC), @(0xE0CD), @(0xE0CE), @(0xE0CF),
                                  @(0xE0D0), @(0xE0D1), @(0xE0D2),
                                  @(0xE0D4)]];
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
            [temp addCharactersInRange:NSMakeRange(0xE0B0, 4)];
            [temp addCharactersInRange:NSMakeRange(0xE0B9, 7)];

            // Extended power line glyphs
            for (NSNumber *code in self.powerlineExtendedSymbols) {
                [temp addCharactersInRange:NSMakeRange(code.integerValue, 1)];
            }

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

// NOTE: If you change this also update blockDrawingCharacters
+ (NSArray<NSBezierPath *> *)bezierPathsForSolidBoxesForCode:(unichar)code
                                                    cellSize:(NSSize)cellSize
                                                      offset:(CGPoint)offset
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

        xo += offset.x;
        yo += offset.y;

        return [NSBezierPath bezierPathWithRect:NSMakeRect(xo, yo, w, h)];
    }];
}

+ (void)performBlockWithoutAntialiasing:(void (^)(void))block {
    NSImageInterpolation saved = [[NSGraphicsContext currentContext] imageInterpolation];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationNone];
    block();
    [[NSGraphicsContext currentContext] setImageInterpolation:saved];
}

+ (void)drawPowerlineCode:(unichar)code
cellSize:(NSSize)regularCellSize
color:(CGColorRef)color
scale:(CGFloat)scale
isPoints:(BOOL)isPoints
offset:(CGPoint)offset {

    NSSize cellSize = regularCellSize;
    if ([[iTermBoxDrawingBezierCurveFactory doubleWidthPowerlineSymbols] containsObject:@(code)]) {
        cellSize.width *= 2;
    }
    switch (code) {
        case 0xE0A0:
            [self drawPDFWithName:@"PowerlineVersionControlBranch" options:0 cellSize:cellSize stretch:NO color:color antialiased:YES offset:offset];
            break;

        case 0xE0A1:
            [self drawPDFWithName:@"PowerlineLN" options:0 cellSize:cellSize stretch:NO color:color antialiased:NO offset:offset];
            break;

        case 0xE0A2:
            [self drawPDFWithName:@"PowerlinePadlock" options:0 cellSize:cellSize stretch:NO color:color antialiased:YES offset:offset];
            break;
        case 0xE0B0:
            [self drawPDFWithName:@"PowerlineSolidRightArrow" options:0 cellSize:cellSize stretch:YES color:color antialiased:YES offset:offset];
            break;
        case 0xE0B2:
            [self drawPDFWithName:@"PowerlineSolidLeftArrow" options:0 cellSize:cellSize stretch:YES color:color antialiased:YES offset:offset];
            break;
        case 0xE0B1:
            [self drawPDFWithName:@"PowerlineLineRightArrow" options:0 cellSize:cellSize stretch:YES color:color antialiased:YES offset:offset];
            break;
        case 0xE0B3:
            [self drawPDFWithName:@"PowerlineLineLeftArrow" options:0 cellSize:cellSize stretch:YES color:color antialiased:YES offset:offset];
            break;
        case 0xE0B9:  // (Extended) Negative slope diagonal line
        case 0xE0BF:
            [self drawComponents:@"a1g7" cellSize:cellSize scale:scale isPoints:isPoints offset:offset color:color solid:NO];
            break;

        case 0xE0BA:  // (Extended) Lower right triangle
            [self drawComponents:@"a7g1 g1g7 g7a7" cellSize:cellSize scale:scale isPoints:isPoints offset:offset color:color solid:YES];
            break;

        case 0xE0BB:  // (Extended) Positive slope diagonal line
        case 0XE0BD:  // same
            [self drawComponents:@"a7g1" cellSize:cellSize scale:scale isPoints:isPoints offset:offset color:color solid:NO];
            break;

        case 0xE0BC:  // (Extended) Upper left triangle
            [self drawComponents:@"a1g1 g1a7 a7a1" cellSize:cellSize scale:scale isPoints:isPoints offset:offset color:color solid:YES];
            break;

        case 0xE0BE:  // (Extended) Top right triangle
            [self drawComponents:@"g1a1 a1g7 g7g1" cellSize:cellSize scale:scale isPoints:isPoints offset:offset color:color solid:YES];
            break;
    }
}

+ (void)drawComponents:(NSString *)components
              cellSize:(NSSize)cellSize
                 scale:(CGFloat)scale
              isPoints:(BOOL)isPoints
                offset:(CGPoint)offset
                 color:(CGColorRef)color
                 solid:(BOOL)solid {
    NSArray<NSBezierPath *> *paths = [self bezierPathsForComponents:components
                                                           cellSize:cellSize
                                                              scale:scale
                                                           isPoints:isPoints
                                                             offset:offset];
    if (!paths) {
        return;
    }
    CGContextRef cgContext = [[NSGraphicsContext currentContext] CGContext];
    CGContextSaveGState(cgContext);
    CGContextClipToRect(cgContext, CGRectMake(0, 0, cellSize.width, cellSize.height));
    [self drawPaths:paths color:color scale:scale isPoints:isPoints solid:solid];
    CGContextRestoreGState(cgContext);
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
                        color:(CGColorRef)colorRef {
    static iTermImageCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[iTermImageCache alloc] initWithByteLimit:1024 * 1024];
    });
    NSColor *color = [NSColor colorWithCGColor:colorRef];
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

    NSString *path = [[NSBundle bundleForClass:self] pathForResource:pdfName ofType:@"pdf"];
    NSImage *image;
    NSImageRep *imageRep;
    
    if (path) {
        NSData* pdfData = [NSData dataWithContentsOfFile:path];
        imageRep = [NSPDFImageRep imageRepWithData:pdfData];
    } else {
        path = [[NSBundle bundleForClass:self] pathForResource:pdfName ofType:@"eps"];
        NSData *data = [NSData dataWithContentsOfFile:path];
        imageRep = [NSEPSImageRep imageRepWithData:data];
    }

    double cellProportion = cellSize.width / cellSize.height;
    double imageProportion = imageRep.size.width / imageRep.size.height;

    int cellWidth;
    int cellHeight;
    if (imageProportion > cellProportion) { // the image is wider than the cell
        cellWidth = cellSize.width * 2;
        cellHeight = cellWidth * imageRep.size.height / imageRep.size.width;
    } else {
        cellHeight = cellSize.height * 2;
        cellWidth = cellHeight * imageRep.size.width / imageRep.size.height;
    }
    
    image = [[NSImage alloc] initWithSize:NSMakeSize(cellWidth,
                                                     cellHeight)];
    [image addRepresentation:imageRep];

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
               options:(iTermPowerlineDrawingOptions)options
               cellSize:(NSSize)cellSize
                stretch:(BOOL)stretch
                  color:(CGColorRef)color
            antialiased:(BOOL)antialiased 
                 offset:(CGPoint)offset {
    NSImage *image = [self imageForPDFNamed:pdfName
                                   cellSize:cellSize
                                antialiased:antialiased
                                      color:color];
    NSImageRep *imageRep = [[image representations] firstObject];
    NSRect destination = [self drawingDestinationForImageOfSize:imageRep.size
                                                destinationSize:cellSize
                                                        stretch:stretch];
    destination.origin.x += offset.x;
    destination.origin.y += offset.y;
    NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
    [ctx saveGraphicsState];
    if (options & iTermPowerlineDrawingOptionsMirrored) {
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:cellSize.width yBy:0];
        [transform scaleXBy:-1 yBy:1];
        [transform concat];
    }
    if (options & iTermPowerlineDrawingOptionsHalfWidth) {
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform scaleXBy:0.5 yBy:1];
        [transform concat];
    }
    [imageRep drawInRect:destination
                fromRect:NSZeroRect
               operation:NSCompositingOperationSourceOver
                fraction:1
          respectFlipped:YES
                   hints:nil];
    [self drawBleedForImage:(NSImageRep *)imageRep
                destination:destination
                    options:options
                      color:[NSColor colorWithCGColor:color]];
    [ctx restoreGraphicsState];
}

+ (void)drawBleedForImage:imageRep 
destination:(NSRect)destination
options:(iTermPowerlineDrawingOptions)options
color:(NSColor *)color {
    const CGFloat size = 1;
    [color set];
    if (options & iTermPowerlineDrawingOptionsFullBleedLeft) {
        NSRectFill(NSMakeRect(NSMinX(destination), NSMinY(destination), size, NSHeight(destination)));
    }
    if (options & iTermPowerlineDrawingOptionsFullBleedRight) {
        NSRectFill(NSMakeRect(NSMaxX(destination) - size, NSMinY(destination), size, NSHeight(destination)));
    }
}

+ (BOOL)isPowerlineGlyph:(unichar)code {
    switch (code) {
        case 0xE0A0:  // Version control branch
        case 0xE0A1:  // LN (line) symbol
        case 0xE0A2:  // Closed padlock
        case 0xE0B0:  // Rightward black arrowhead
        case 0xE0B1:  // Rightwards arrowhead
        case 0xE0B2:  // Leftwards black arrowhead
        case 0xE0B3:  // Leftwards arrowhead
        case 0xE0B9:  // (Extended) Negative slope diagonal line
        case 0xE0BF:  // same
        case 0xE0BA:  // (Extended) Lower right triangle
        case 0xE0BB:  // (Extended) Positive slope diagonal line
        case 0XE0BD:  // same
        case 0xE0BC:  // (Extended) Upper left triangle
        case 0xE0BE:  // (Extended) Top right triangle
            return YES;
    }
    return NO;
}

+ (BOOL)isDoubleWidthPowerlineGlyph:(unichar)code {
    return [[iTermBoxDrawingBezierCurveFactory doubleWidthPowerlineSymbols] containsObject:@(code)];
}

+ (BOOL)haveCustomGlyph:(unichar)code {
    return self.powerlineExtendedSymbols[@(code)] != nil;
}

+ (void)drawCustomGlyphForCode:(unichar)code cellSize:(NSSize)cellSize color:(CGColorRef)color offset:(CGPoint)offset {
    NSSize adjustedCellSize = cellSize;
    if ([[iTermBoxDrawingBezierCurveFactory doubleWidthPowerlineSymbols] containsObject:@(code)]) {
        adjustedCellSize.width *= 2;
    }
    NSArray *array = self.powerlineExtendedSymbols[@(code)];
    NSString *name = array[0];
    NSNumber *options = array[1];
    [self drawPDFWithName:name
                  options:(iTermPowerlineDrawingOptions)options.unsignedIntegerValue
                 cellSize:adjustedCellSize
                  stretch:YES
                    color:color
              antialiased:YES
                   offset:offset];
}

+ (void)drawCodeInCurrentContext:(unichar)code
                        cellSize:(NSSize)cellSize
                           scale:(CGFloat)scale
                        isPoints:(BOOL)isPoints
                          offset:(CGPoint)offset
                           color:(CGColorRef)colorRef
        useNativePowerlineGlyphs:(BOOL)useNativePowerlineGlyphs {
    if (useNativePowerlineGlyphs && [self isPowerlineGlyph:code]) {
        [self drawPowerlineCode:code
                       cellSize:cellSize
                          color:colorRef
                          scale:scale
                       isPoints:isPoints
                         offset:offset];
        return;
    }
    if (useNativePowerlineGlyphs && [self haveCustomGlyph:code]) {
        [self drawCustomGlyphForCode:code
                            cellSize:cellSize
                               color:colorRef
                              offset:offset];
        return;
    }
    if (code == iTermFullBlock) {
        // Fast path
        CGContextRef context = [[NSGraphicsContext currentContext] CGContext];
        CGContextSetFillColorWithColor(context, colorRef);
        CGContextFillRect(context, CGRectMake(offset.x, offset.y, cellSize.width, cellSize.height));
        return;
    }
    BOOL solid = NO;
    NSArray<NSBezierPath *> *paths = [iTermBoxDrawingBezierCurveFactory bezierPathsForBoxDrawingCode:code
                                                                                            cellSize:cellSize
                                                                                               scale:scale
                                                                                            isPoints:isPoints
                                                                                              offset:offset
                                                                                               solid:&solid];
    [self drawPaths:paths color:colorRef scale:scale isPoints:isPoints solid:solid];
}

+ (void)drawPaths:(NSArray<NSBezierPath *> *)paths
            color:(CGColorRef)colorRef
            scale:(CGFloat)scale
         isPoints:(BOOL)isPoints
            solid:(BOOL)solid {
    NSColor *color = [NSColor colorWithCGColor:colorRef];
    [color set];
    for (NSBezierPath *path in paths) {
        if (solid) {
            [path fill];
        } else {
            [path setLineWidth:isPoints ? 1.0 : scale];
            [path stroke];
        }
    }
}

+ (NSArray<NSBezierPath *> *)bezierPathsForBoxDrawingCode:(unichar)code
                                                 cellSize:(NSSize)cellSize
                                                    scale:(CGFloat)scale
                                                 isPoints:(BOOL)isPoints
                                                   offset:(CGPoint)offset
                                                    solid:(out BOOL *)solid {
    NSArray<NSBezierPath *> *solidBoxPaths = [self bezierPathsForSolidBoxesForCode:code
                                                                          cellSize:cellSize
                                                                            offset:offset
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
    return [self bezierPathsForComponents:components
                                 cellSize:cellSize
                                    scale:scale
                                 isPoints:isPoints
                                   offset:offset];
}

+ (NSArray<NSBezierPath *> *)bezierPathsForComponents:(NSString *)components
                                             cellSize:(NSSize)cellSize
                                                scale:(CGFloat)scale
                                             isPoints:(BOOL)isPoints
                                               offset:(CGPoint)offset {
    CGFloat horizontalCenter = cellSize.width / 2.0;
    CGFloat verticalCenter = cellSize.height / 2.0;

    const char *bytes = [components UTF8String];
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineWidth:scale];
    int lastX = -1;
    int lastY = -1;
    int i = 0;
    int length = components.length;

    CGFloat fullPoint;
    CGFloat halfPoint;
    // The purpose of roundedUpHalfPoint is to change how we draw thick center lines in lowdpi vs highdpi.
    // In high DPI, they will be 3 pixels wide and actually centered.
    // In low DPI, thick centered lines will be 2 pixels wide and off center.
    // Center - halfpoint and center + roundedUpHalfPoint form a pair of coordinates that give this result.
    CGFloat roundedUpHalfPoint;
    CGFloat xShift;
    CGFloat yShift;

    if (isPoints && scale >= 2) {
        // Legacy renderer, high DPI
        fullPoint = 1.0;
        roundedUpHalfPoint = halfPoint = 0.5;
        yShift = xShift = 0;
    } else if (scale >= 2) {
        // GPU renderer, high DPI
        fullPoint = 2.0;
        roundedUpHalfPoint = halfPoint = 1.0;
        yShift = xShift = 1.0;
    } else {
        // Low DPI
        halfPoint = 0;
        roundedUpHalfPoint = 1.0;
        fullPoint = 1.0;
        yShift = xShift = -0.5;
    }


    CGFloat xs[] = {
        0,
        horizontalCenter - fullPoint + xShift,
        horizontalCenter - halfPoint + xShift,
        horizontalCenter + xShift,
        horizontalCenter + roundedUpHalfPoint + xShift,
        horizontalCenter + fullPoint + xShift,
        cellSize.width - halfPoint + xShift,
    };
    CGFloat ys[] = {
        0,
        verticalCenter - fullPoint + yShift,
        verticalCenter - halfPoint + yShift,
        verticalCenter + yShift,
        verticalCenter + roundedUpHalfPoint + yShift,
        verticalCenter + fullPoint + yShift,
        cellSize.height - halfPoint + yShift,
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
