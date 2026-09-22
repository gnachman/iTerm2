//
//  MetalGlyphContextResidueTests.m
//  ModernTests
//
//  Regression test for issue 13071: with the GPU renderer and a profile that has
//  antialiasing turned off, bold spaces draw the font's "~" glyph.
//
//  iTermCharacterSource rasterizes every glyph into one CGContext shared by the
//  whole session, and after each glyph clears only that glyph's measured bounding
//  rect. The rect comes from CTLineGetImageBounds, which consults the context's
//  shouldAntialias flag -- but -[iTermCharacterSource drawWithOffset:iteration:]
//  sets that flag inside the save/restore pair around the draw, so the measurement
//  always happens with antialiasing ON even when the glyph was rasterized aliased.
//  For Monaco 12 at 1x the aliased "~" lands at y 7..9 while the antialiased bounds
//  say y 2.18..4.37, far outside the 2px fudge factor, so the ink survives the clear.
//
//  -[iTermASCIITexture initWithAttributes:...] builds a texture by walking codes
//  32...126, so "~" (126) is the last glyph drawn and SPACE (32) is the first glyph
//  of the NEXT texture built from the same context. Space has no ink of its own and
//  -bitmapForPart: copies the whole cell tile, so the leftover tilde becomes the
//  space glyph. The plain texture is built first against a freshly cleared context
//  and is fine; bold/italic/thin-strokes textures are built lazily later and
//  inherit the residue, which is why only bold spaces are affected.
//

#import <XCTest/XCTest.h>

#import "FontSizeEstimator.h"
#import "PTYFontInfo.h"
#import "ScreenChar.h"
#import "iTermASCIITexture.h"
#import "iTermCharacterBitmap.h"
#import "iTermCharacterParts.h"
#import "iTermCharacterSource.h"

// iTermFontTable is a Swift class (@objc(iTermFontTable) FontTable). ModernTests
// has no bridging header and cannot import iTerm2SharedARC-Swift.h, so declare the
// two members this test needs.
@interface iTermFontTable : NSObject
- (instancetype)initWithAscii:(PTYFontInfo *)ascii
                     nonAscii:(PTYFontInfo *)nonAscii
                  browserZoom:(CGFloat)browserZoom;
@property (nonatomic, readonly) NSFont *fontForCharacterSizeCalculations;
@end

@interface MetalGlyphContextResidueTests : XCTestCase
@end

@implementation MetalGlyphContextResidueTests {
    CGContextRef _context;
    int _radius;
}

- (void)tearDown {
    if (_context) {
        CGContextRelease(_context);
        _context = NULL;
    }
    [super tearDown];
}

// Mirrors the creation loop in -[iTermASCIITexture initWithAttributes:descriptor:device:creation:].
// Returns the bitmap of the center part of SPACE, which is what the texture's
// slice for code 32 gets filled with.
- (iTermCharacterBitmap *)spaceBitmapFromASCIITextureBuildWithBold:(BOOL)bold
                                                        descriptor:(iTermCharacterSourceDescriptor *)descriptor {
    iTermCharacterBitmap *spaceCenter = nil;
    iTermCharacterSourceAttributes *attributes =
        [iTermCharacterSourceAttributes characterSourceAttributesWithThinStrokes:NO
                                                                           bold:bold
                                                                         italic:NO];
    for (int code = iTermASCIITextureMinimumCharacter; code <= iTermASCIITextureMaximumCharacter; code++) {
        NSString *string = [NSString stringWithFormat:@"%c", code];
        iTermCharacterSource *source =
            [[iTermCharacterSource alloc] initWithCharacter:string
                                                 descriptor:descriptor
                                                 attributes:attributes
                                                 boxDrawing:NO
                                                     radius:_radius
                                   useNativePowerlineGlyphs:NO
                                              lineAttribute:iTermLineAttributeSingleWidth
                                                    context:_context];
        for (NSNumber *part in source.parts) {
            iTermCharacterBitmap *bitmap = [source bitmapForPart:part.intValue];
            if (code == ' ' && part.intValue == iTermImagePartFromDeltas(0, 0)) {
                spaceCenter = bitmap;
            }
        }
    }
    return spaceCenter;
}

- (NSUInteger)inkByteCountOf:(iTermCharacterBitmap *)bitmap {
    const unsigned char *bytes = bitmap.data.bytes;
    NSUInteger count = 0;
    for (NSUInteger i = 0; i < bitmap.data.length; i++) {
        if (bytes[i]) {
            count++;
        }
    }
    return count;
}

- (NSString *)renderBitmap:(iTermCharacterBitmap *)bitmap {
    const unsigned char *bytes = bitmap.data.bytes;
    const int w = bitmap.size.width;
    const int h = bitmap.size.height;
    NSMutableString *result = [NSMutableString string];
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            const NSUInteger i = (y * w + x) * 4;
            if (i + 3 >= bitmap.data.length) {
                continue;
            }
            const unsigned char any = bytes[i] | bytes[i + 1] | bytes[i + 2] | bytes[i + 3];
            [result appendString:any ? @"#" : @"."];
        }
        [result appendString:@"\n"];
    }
    return result;
}

- (void)testSpaceGlyphStaysBlankWhenAntialiasingIsDisabled {
    // Monaco 12 at 1x is the configuration from issue 13071 that reproduces here;
    // the reporter was on a non-Retina external display.
    NSFont *font = [NSFont fontWithName:@"Monaco" size:12];
    XCTAssertNotNil(font, @"Monaco is a system font and should always be present");
    PTYFontInfo *fontInfo = [PTYFontInfo fontInfoWithFont:font];
    iTermFontTable *fontTable = [[iTermFontTable alloc] initWithAscii:fontInfo
                                                             nonAscii:nil
                                                          browserZoom:1];
    const CGFloat scale = 1;

    // The cell metrics -[PTYTextView setFontTable:horizontalSpacing:verticalSpacing:]
    // computes for this font.
    FontSizeEstimator *estimator =
        [FontSizeEstimator fontSizeEstimatorForFont:fontTable.fontForCharacterSizeCalculations];
    CGSize cellSizeWithoutSpacing = estimator.size;
    cellSizeWithoutSpacing.width = ceil(cellSizeWithoutSpacing.width);
    cellSizeWithoutSpacing.height = ceil(cellSizeWithoutSpacing.height + font.leading);
    const CGSize cellSize = CGSizeMake(cellSizeWithoutSpacing.width * scale,
                                       cellSizeWithoutSpacing.height * scale);

    // A 1x1 scratch context, like +[PTYSession onePixelContext].
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    const CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host;
    CGContextRef onePixelContext = CGBitmapContextCreate(NULL, 1, 1, 8, 4, colorSpace, bitmapInfo);

    // The glyph size -[PTYSession updateMetalDriver] computes on the monochrome path.
    const NSRange asciiRange = NSMakeRange(iTermASCIITextureMinimumCharacter,
                                           iTermASCIITextureMaximumCharacter - iTermASCIITextureMinimumCharacter + 1);
    const NSRect boundingRect = [iTermCharacterSource boundingRectForCharactersInRange:asciiRange
                                                                            fontTable:fontTable
                                                                                scale:scale
                                                                          useBoldFont:YES
                                                                        useItalicFont:YES
                                                                     usesNonAsciiFont:NO
                                                                              context:onePixelContext];
    const CGSize glyphSize = CGSizeMake(round(1 + MAX(cellSize.width, NSMaxX(boundingRect))),
                                        round(1 + MAX(cellSize.height, NSMaxY(boundingRect))));

    iTermCharacterSourceDescriptor *descriptor =
        [iTermCharacterSourceDescriptor characterSourceDescriptorWithFontTable:fontTable
                                                                  asciiOffset:CGSizeZero
                                                                    glyphSize:glyphSize
                                                                     cellSize:cellSize
                                                       cellSizeWithoutSpacing:cellSizeWithoutSpacing
                                                                        scale:scale
                                                                  useBoldFont:YES
                                                                useItalicFont:YES
                                                             usesNonAsciiFont:NO
                                                             asciiAntiAliased:NO
                                                          nonAsciiAntiAliased:NO];

    // The shared per-session context, sized as -[PTYSession setMetalContextSize:] does.
    _radius = iTermTextureMapMaxCharacterParts / 2;
    const int maxParts = _radius * 2 + 1;
    const size_t width = (size_t)glyphSize.width * maxParts;
    const size_t height = (size_t)glyphSize.height * maxParts;
    _context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, colorSpace, bitmapInfo);
    XCTAssertTrue(_context != NULL);
    CGContextClearRect(_context, CGRectMake(0, 0, width, height));

    // The plain texture is built first, against a freshly cleared context.
    iTermCharacterBitmap *plainSpace = [self spaceBitmapFromASCIITextureBuildWithBold:NO
                                                                           descriptor:descriptor];
    // The bold texture is built later, from the same context.
    iTermCharacterBitmap *boldSpace = [self spaceBitmapFromASCIITextureBuildWithBold:YES
                                                                          descriptor:descriptor];

    CGContextRelease(onePixelContext);
    CGColorSpaceRelease(colorSpace);

    XCTAssertNotNil(plainSpace, @"no center part for the plain space glyph");
    XCTAssertNotNil(boldSpace, @"no center part for the bold space glyph");

    XCTAssertEqual([self inkByteCountOf:plainSpace], 0,
                   @"plain SPACE should be blank but has ink:\n%@", [self renderBitmap:plainSpace]);
    XCTAssertEqual([self inkByteCountOf:boldSpace], 0,
                   @"bold SPACE should be blank but picked up leftover ink from the previous "
                   @"ASCII texture build:\n%@", [self renderBitmap:boldSpace]);
}

@end
