//
//  iTermCharacterSource.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/26/17.
//

#import <Cocoa/Cocoa.h>

#import "iTermCharacterSource.h"
#import "iTermCharacterSource+Private.h"

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermBoxDrawingBezierCurveFactory.h"
#import "iTermCharacterBitmap.h"
#import "iTermCharacterParts.h"
#import "iTermData.h"
#import "iTermTextureArray.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSMutableData+iTerm.h"
#import "NSStringITerm.h"
#import "PTYFontInfo.h"
#import "iTermGlyphCharacterSource.h"
#import "iTermRegularCharacterSource.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#define ENABLE_DEBUG_CHARACTER_SOURCE_ALIGNMENT 0

extern void CGContextSetFontSmoothingStyle(CGContextRef, int);
extern int CGContextGetFontSmoothingStyle(CGContextRef);

static const CGFloat iTermFakeItalicSkew = 0.2;
static const CGFloat iTermCharacterSourceAntialiasedRetinaFakeBoldShiftPoints = 0.5;
static const CGFloat iTermCharacterSourceAntialiasedNonretinaFakeBoldShiftPoints = 0;
static const CGFloat iTermCharacterSourceAliasedFakeBoldShiftPoints = 1;

@implementation iTermCharacterSourceDescriptor

+ (instancetype)characterSourceDescriptorWithFontTable:(iTermFontTable *)fontTable
                                           asciiOffset:(CGSize)asciiOffset
                                             glyphSize:(CGSize)glyphSize
                                              cellSize:(CGSize)cellSize
                                cellSizeWithoutSpacing:(CGSize)cellSizeWithoutSpacing
                                                 scale:(CGFloat)scale
                                           useBoldFont:(BOOL)useBoldFont
                                         useItalicFont:(BOOL)useItalicFont
                                      usesNonAsciiFont:(BOOL)useNonAsciiFont
                                      asciiAntiAliased:(BOOL)asciiAntiAliased
                                   nonAsciiAntiAliased:(BOOL)nonAsciiAntiAliased {
    iTermCharacterSourceDescriptor *descriptor = [[iTermCharacterSourceDescriptor alloc] init];
    
    descriptor.fontTable = fontTable;
    descriptor.asciiOffset = asciiOffset;
    descriptor.glyphSize = glyphSize;
    descriptor.cellSize = cellSize;
    descriptor.cellSizeWithoutSpacing = cellSizeWithoutSpacing;
    descriptor.scale = scale;
    descriptor.useBoldFont = useBoldFont;
    descriptor.useItalicFont = useItalicFont;
    descriptor.useNonAsciiFont = useNonAsciiFont;
    descriptor.asciiAntiAliased = asciiAntiAliased;
    descriptor.nonAsciiAntiAliased = nonAsciiAntiAliased;

    return descriptor;
}

- (NSString *)description {
    NSDictionary *dict = [self dictionaryValue];
    NSString *props = [[[dict.allKeys sortedArrayUsingSelector:@selector(compare:)] mapWithBlock:^id(NSString *key) {
        return [NSString stringWithFormat:@"%@=“%@”", key, dict[key]];
    }] componentsJoinedByString:@" "];
    return [NSString stringWithFormat:@"<%@: %p %@>",
            NSStringFromClass([self class]), self, props];
}

- (NSDictionary *)dictionaryValue {
    return @{ @"fontTable": _fontTable ?: [NSNull null],
              @"asciiOffset": NSStringFromSize(_asciiOffset),
              @"glyphSize": @(_glyphSize),
              @"cellSize": @(_cellSize),
              @"cellSizeWithoutSpacing": @(_cellSizeWithoutSpacing),
              @"scale": @(_scale),
              @"useBoldFont": @(_useBoldFont),
              @"useItalicFont": @(_useItalicFont),
              @"useNonAsciiFont": @(_useNonAsciiFont),
              @"asciiAntiAliased": @(_asciiAntiAliased),
              @"nonAsciiAntiAliased": @(_nonAsciiAntiAliased) };
}

- (CGFloat)baselineOffset {
    return _fontTable.baselineOffset;
}

@end

@interface iTermCharacterSourceAttributes()
@property (nonatomic, readwrite) BOOL useThinStrokes;
@property (nonatomic, readwrite) BOOL bold;
@property (nonatomic, readwrite) BOOL italic;
@end

@implementation iTermCharacterSourceAttributes

+ (instancetype)characterSourceAttributesWithThinStrokes:(BOOL)useThinStrokes
                                                    bold:(BOOL)bold
                                                  italic:(BOOL)italic {
    iTermCharacterSourceAttributes *attributes = [[iTermCharacterSourceAttributes alloc] init];
    attributes.useThinStrokes = useThinStrokes;
    attributes.bold = bold;
    attributes.italic = italic;
    return attributes;
}

@end


@implementation iTermCharacterSource {
@protected
    iTermCharacterSourceAttributes *_attributes;
    BOOL _antialiased;
    BOOL _fakeItalic;

    // Large enough to hold glyphSize * maxParts in both horizontal and vertical direction.
    BOOL _postprocessed NS_AVAILABLE_MAC(10_14);

    // These have size _bytesPerRow * _numberOfRows.
    NSMutableArray<NSMutableData *> *_datas;

    NSImage *_image;
    BOOL _haveDrawn;
    NSArray<NSNumber *> *_parts;

    // If true then _isEmoji is valid.
    BOOL _haveTestedForEmoji;
    NSInteger _numberOfIterationsNeeded;
    iTermBitmapData *_postprocessedData;
    // These metrics are for _context.
    NSInteger _bytesPerRow;
    NSInteger _numberOfRows;

}

+ (NSRect)boundingRectForCharactersInRange:(NSRange)range
                                 fontTable:(iTermFontTable *)fontTable
                                     scale:(CGFloat)scale
                               useBoldFont:(BOOL)useBoldFont
                             useItalicFont:(BOOL)useItalicFont
                          usesNonAsciiFont:(BOOL)useNonAsciiFont
                                   context:(CGContextRef)context {
    static NSMutableDictionary<NSArray *, NSValue *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });
    if (!fontTable) {
        return NSMakeRect(0, 0, 1, 1);
    }
    CGFloat pointSize;
    if (useNonAsciiFont) {
        pointSize = MAX(fontTable.asciiFont.font.pointSize,
                        fontTable.defaultNonASCIIFont.font.pointSize);
    } else {
        pointSize = fontTable.asciiFont.font.pointSize;
    }
    NSArray *key = @[ NSStringFromRange(range),
                      fontTable.asciiFont.font.fontName ?: @"",
                      fontTable.defaultNonASCIIFont.font.fontName ?: @"",
                      fontTable.configHash,
                      @(pointSize),
                      @(fontTable.baselineOffset),
                      @(scale),
                      @(useBoldFont),
                      @(useItalicFont),
                      @(useNonAsciiFont)];
    if (cache[key]) {
        return [cache[key] rectValue];
    }

    const CGSize bigSize = CGSizeMake(round(pointSize * 10),
                                      round(pointSize * 10));
    iTermCharacterSourceDescriptor *descriptor = [iTermCharacterSourceDescriptor characterSourceDescriptorWithFontTable:fontTable
                                                                                                            asciiOffset:CGSizeZero
                                                                                                              glyphSize:bigSize
                                                                                                               cellSize:bigSize
                                                                                                 cellSizeWithoutSpacing:bigSize
                                                                                                                  scale:scale
                                                                                                            useBoldFont:useBoldFont
                                                                                                          useItalicFont:useItalicFont
                                                                                                       usesNonAsciiFont:useNonAsciiFont
                                                                                                       asciiAntiAliased:YES
                                                                                                    nonAsciiAntiAliased:YES];

    iTermCharacterSourceAttributes *attributes = [iTermCharacterSourceAttributes characterSourceAttributesWithThinStrokes:NO
                                                                                                                     bold:YES
                                                                                                                   italic:YES];
    NSRect unionRect = NSZeroRect;
    for (NSInteger i = 0; i < range.length; i++) {
        @autoreleasepool {
            UTF32Char c = range.location + i;
            iTermCharacterSource *source = [[iTermCharacterSource alloc] initWithCharacter:[NSString stringWithLongCharacter:c]
                                                                                descriptor:descriptor
                                                                                attributes:attributes
                                                                                boxDrawing:NO
                                                                                    radius:0
                                                                  useNativePowerlineGlyphs:NO
                                                                             lineAttribute:iTermLineAttributeSingleWidth
                                                                                   context:context];
            CGRect frame = [source frameFlipped:NO];
            unionRect = NSUnionRect(unionRect, frame);
        }
    }
    unionRect.size.width = ceil(unionRect.size.width / scale);
    unionRect.size.height = ceil(unionRect.size.height / scale);
    unionRect.origin.x /= scale;
    unionRect.origin.y /= scale;
    cache[key] = [NSValue valueWithRect:unionRect];
    return unionRect;
}


- (instancetype)initWithFontID:(unsigned int)fontID
                      fakeBold:(BOOL)fakeBold
                    fakeItalic:(BOOL)fakeItalic
                   glyphNumber:(unsigned short)glyphNumber
                      position:(NSPoint)position
                    descriptor:(iTermCharacterSourceDescriptor *)descriptor
                    attributes:(iTermCharacterSourceAttributes *)attributes
                        radius:(int)radius
                 lineAttribute:(iTermLineAttribute)lineAttribute
                       context:(CGContextRef)context {
    return [[iTermGlyphCharacterSource alloc] initWithFontID:fontID
                                                    fakeBold:fakeBold
                                                  fakeItalic:fakeItalic
                                                 glyphNumber:glyphNumber
                                                    position:position
                                                  descriptor:descriptor
                                                  attributes:attributes
                                                      radius:radius
                                               lineAttribute:lineAttribute
                                                     context:context];
}

- (instancetype)initWithCharacter:(NSString *)string
                       descriptor:(iTermCharacterSourceDescriptor *)descriptor
                       attributes:(iTermCharacterSourceAttributes *)attributes
                       boxDrawing:(BOOL)boxDrawing
                           radius:(int)radius
         useNativePowerlineGlyphs:(BOOL)useNativePowerlineGlyphs
                    lineAttribute:(iTermLineAttribute)lineAttribute
                          context:(CGContextRef)context {
    return [[iTermRegularCharacterSource alloc] initWithCharacter:string
                                                       descriptor:descriptor
                                                       attributes:attributes
                                                       boxDrawing:boxDrawing
                                                           radius:radius
                                         useNativePowerlineGlyphs:useNativePowerlineGlyphs
                                                    lineAttribute:lineAttribute
                                                          context:context];
}

- (instancetype)initWithFont:(NSFont *)font
                    fakeBold:(BOOL)fakeBold
                  fakeItalic:(BOOL)fakeItalic
                 antialiased:(BOOL)antialiased
                  descriptor:(iTermCharacterSourceDescriptor *)descriptor
                  attributes:(iTermCharacterSourceAttributes *)attributes
                      radius:(int)radius
                     context:(CGContextRef)context {
    self = [super init];
    if (self) {
        _font = font;
        _descriptor = descriptor;
        _fakeBold = fakeBold;
        _fakeItalic = fakeItalic;
        _antialiased = antialiased;
        _attributes = attributes;
        _radius = radius;
        _size = CGSizeMake(ceil(descriptor.glyphSize.width) * self.maxParts,
                           ceil(descriptor.glyphSize.height) * self.maxParts);
        _context = context;
        _bytesPerRow = CGBitmapContextGetBytesPerRow(_context);
        _numberOfRows = CGBitmapContextGetHeight(_context);
        CGContextRetain(context);
    }
    return self;
}

- (void)dealloc {
    CGContextRelease(_context);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p font=%@>",
            NSStringFromClass([self class]),
            self,
            _font];
}

#pragma mark - Methods that subclasses must override

- (void)drawIteration:(NSInteger)iteration atOffset:(CGPoint)offset skew:(CGFloat)skew {
    [self doesNotRecognizeSelector:_cmd];
}

- (CGSize)desiredOffset {
    [self doesNotRecognizeSelector:_cmd];
    return CGSizeZero;
}

- (CGRect)frameFlipped:(BOOL)flipped {
    [self doesNotRecognizeSelector:_cmd];
    return CGRectZero;
}

- (NSString *)debugName {
    [self doesNotRecognizeSelector:_cmd];
    return @"bug";
}

#pragma mark - Helpers

- (int)maxParts {
    return _radius * 2 + 1;
}

// Returns the line attribute for this character source. Overridden in
// iTermRegularCharacterSource to return the actual line attribute.
- (iTermLineAttribute)lineAttribute {
    return iTermLineAttributeSingleWidth;
}

// Returns the horizontal scale factor applied during drawing (for double-width/height lines).
- (CGFloat)drawHScale {
    return 1.0;
}

// Returns the vertical scale factor applied during drawing (for double-height lines).
- (CGFloat)drawVScale {
    return 1.0;
}

// Returns the max of horizontal and vertical scale. Used to decide whether
// to use the large-context clearing path.
- (CGFloat)drawScale {
    return MAX([self drawHScale], [self drawVScale]);
}

// Subclasses must implement this.
- (void)drawIfNeeded {
    if (!_haveDrawn) {
        CGSize offset = [self desiredOffset];
        NSInteger iteration = 0;
        do {
            const int radius = _radius;
            // This has the side-effect of setting _numberOfIterationsNeeded
            [self drawWithOffset:CGPointMake(_descriptor.glyphSize.width * radius + offset.width,
                                             _descriptor.glyphSize.height * radius + offset.height)
                       iteration:iteration];
            iteration += 1;
        } while (iteration < _numberOfIterationsNeeded);
    }
}

#if DEBUG
- (void)verifyContextEmptyForIteration:(NSInteger)iteration {
    if ([self drawScale] > 1) {
        // The double-width context is shared across concurrent render passes.
        // Pre-clear it fully before each use. Skip the assertion check since
        // another thread may write between the clear and the verify.
        memset(CGBitmapContextGetData(_context), 0,
               CGBitmapContextGetBytesPerRow(_context) * CGBitmapContextGetHeight(_context));
        return;
    }
    const unsigned char *data = CGBitmapContextGetData(_context);
    const size_t bytesPerRow = CGBitmapContextGetBytesPerRow(_context);
    const int contextWidth = (int)_size.width;
    const int contextHeight = (int)_size.height;

    for (int y = 0; y < contextHeight; y++) {
        for (int x = 0; x < contextWidth; x++) {
            const size_t off = y * bytesPerRow + x * 4;
            if (data[off + 3] != 0) {
                unsigned char r = data[off + 2];
                unsigned char g = data[off + 1];
                unsigned char b = data[off + 0];
                unsigned char a = data[off + 3];
                NSLog(@"DEBUG: Context not empty before drawing '%@'. "
           @"Pixel at (%d,%d): R=%d G=%d B=%d A=%d. "
           @"iteration=%d",
           self.debugName, x, y, r, g, b, a, (int)iteration);

                // Save image showing pre-existing pixels
                CGImageRef imageRef = CGBitmapContextCreateImage(_context);
                if (imageRef) {
                    NSString *filename = [NSString stringWithFormat:@"/tmp/glyph_predraw_%@_%d.png",
                             self.debugName, (int)iteration];
                    NSURL *url = [NSURL fileURLWithPath:filename];
                    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(
                                                                                        (__bridge CFURLRef)url,
                                                                                        (__bridge CFStringRef)UTTypePNG.identifier,
                                                                                        1, NULL);
                    if (destination) {
                        CGImageDestinationAddImage(destination, imageRef, nil);
                        CGImageDestinationFinalize(destination);
                        CFRelease(destination);
                        NSLog(@"  Saved pre-draw image to: %@", filename);
                    }
                    CGImageRelease(imageRef);
                }

                ITAssertWithMessage(NO, @"Context not empty before drawing '%@'. "
                                    @"Pixel at (%d,%d): R=%d G=%d B=%d A=%d",
                                    self.debugName, x, y, r, g, b, a);
            }
        }
    }
}
#endif

- (void)drawWithOffset:(CGPoint)offset iteration:(NSInteger)iteration {
#if DEBUG
    [self verifyContextEmptyForIteration:iteration];
#endif

    CGAffineTransform textMatrix = CGContextGetTextMatrix(_context);
    CGContextSaveGState(_context);

    const CGFloat hScale = [self drawHScale];
    const CGFloat scale = _descriptor.scale;
    const iTermLineAttribute attr = [self lineAttribute];

    if (attr == iTermLineAttributeDoubleHeightTop ||
        attr == iTermLineAttributeDoubleHeightBottom) {
        // Clip to one cell height at the center row to prevent the 2x-tall
        // glyph's unwanted half from bleeding, matching the legacy
        // renderer's CGContextClipToRect(..., _cellSize.height).
        // The bitmap context is in pixels (no CTM) but draw offsets use
        // point values; the text matrix applies descriptor.scale. So the
        // clip height must be cellSize * scale to cover one cell in pixels.
        CGContextClipToRect(_context,
                            CGRectMake(0,
                                       _descriptor.glyphSize.height * _radius,
                                       _size.width,
                                       _descriptor.cellSize.height * scale));
    }

    // Apply just the DWL horizontal scale via CTM, matching the legacy
    // renderer's CGContextScaleCTM(ctx, 2.0, 1.0).
    if (hScale > 1) {
        CGContextScaleCTM(_context, hScale, 1.0);
    }

    const CGFloat skew = _fakeItalic ? iTermFakeItalicSkew : 0;
    // For double-height lines, shift the draw origin so only the desired
    // vertical half of the 2x glyph lands in the parts grid.
    // In CG coordinates (y-up), shifting DOWN means decreasing ty.
    CGFloat ty = offset.y - _descriptor.baselineOffset * scale;
    if (attr == iTermLineAttributeDoubleHeightTop) {
        // Shift baseline down by ascent so the top of the 2x glyph aligns
        // with where the normal glyph top would be.
        ty -= (_descriptor.cellSize.height + _descriptor.baselineOffset) * scale;
    } else if (attr == iTermLineAttributeDoubleHeightBottom) {
        // Shift baseline up by descent so the bottom of the 2x glyph aligns
        // with where the normal glyph bottom would be.
        ty -= _descriptor.baselineOffset * scale;
    }

    CGFloat ox = offset.x;
    if (hScale > 1) {
        ox /= hScale;
    }

    [self drawIteration:iteration
               atOffset:CGPointMake(ox, ty)
                   skew:skew];
    _haveDrawn = YES;

    // Restore GState before debug drawing so the CTM is identity.
    CGContextRestoreGState(_context);

#if ENABLE_DEBUG_CHARACTER_SOURCE_ALIGNMENT
    CGContextSetRGBStrokeColor(_context, 1, 0, 0, 1);
    CGContextSetLineWidth(_context, 0.5);
    for (int x = 0; x < self.maxParts; x++) {
        for (int y = 0; y < self.maxParts; y++) {
            CGContextStrokeRect(_context, CGRectMake(x * _descriptor.glyphSize.width,
                                                     y * _descriptor.glyphSize.height,
                                                     _descriptor.glyphSize.width,
                                                     _descriptor.glyphSize.height));
        }
    }
#endif

    const NSUInteger length = CGBitmapContextGetBytesPerRow(_context) * CGBitmapContextGetHeight(_context);
    NSMutableData *data = [NSMutableData dataWithBytes:CGBitmapContextGetData(_context)
                                                length:length];
    [_datas addObject:data];

    if (_debug) {
        // Step 1: Create a CGImage from the CGBitmapContext
        CGImageRef imageRef = CGBitmapContextCreateImage(_context);

        // Step 2: Create a URL for the output file
        NSURL *url = [NSURL fileURLWithPath:[NSString stringWithFormat:@"/tmp/full.%@.%@,%@.%@.png", self.debugName, @(offset.x), @(offset.y), @(iteration)]];

        // Step 3: Write the CGImage to disk as PNG
        CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url,
                                                                            (__bridge CFStringRef)UTTypePNG.identifier,
                                                                            1,
                                                                            NULL);
        CGImageDestinationAddImage(destination, imageRef, nil);

        if (!CGImageDestinationFinalize(destination)) {
            NSLog(@"Failed to write image to /tmp/image.png");
        }

        // Clean up
        CFRelease(destination);
        CGImageRelease(imageRef);
    }
    CGContextSetTextMatrix(_context, textMatrix);

    // Clear the drawn area, ready for next iteration/character.
    // For emoji, clear the entire context because CTLineGetImageBounds returns unreliable
    // bounds. For regular text, clear only the calculated bounds for speed.
    // Must happen after RestoreGState to ensure no transforms affect the clear.
    // Use frameFlipped:NO because CGContextClearRect uses native CoreGraphics
    // coordinates (origin at bottom-left), not flipped coordinates.
    CGRect drawnRect;
    if (_isEmoji) {
        drawnRect = CGRectMake(0, 0, _size.width, _size.height);
    } else {
        drawnRect = [self frameFlipped:NO];
        if ([self drawScale] > 1) {
            // Scaled glyphs can overflow beyond _size. Clear the entire context.
            drawnRect = CGRectMake(0, 0, CGBitmapContextGetWidth(_context),
                                        CGBitmapContextGetHeight(_context));
        }
    }

    if ([self drawScale] > 1) {
        // TODO: This is slow and with just a little math it could be avoided.
        // Use memset for scaled glyphs. Clear the full backing store.
        memset(CGBitmapContextGetData(_context), 0, _bytesPerRow * _numberOfRows);
    } else {
        CGContextClearRect(_context, drawnRect);
    }

    // Skip the post-draw verify for scaled glyphs — the verify bounds don't
    // correctly account for the scaled drawing area.
    if ([self drawScale] > 1) {
        return;
    }

#if DEBUG
    // Verify the drawn area is actually clear
    {
        const unsigned char *data = CGBitmapContextGetData(_context);
        const size_t bytesPerRow = CGBitmapContextGetBytesPerRow(_context);
        const int contextWidth = (int)_size.width;
        const int contextHeight = (int)_size.height;

        // Find actual pixel bounds in the entire context
        int actualMinX = contextWidth, actualMaxX = 0;
        int actualMinY = contextHeight, actualMaxY = 0;
        for (int y = 0; y < contextHeight; y++) {
            for (int x = 0; x < contextWidth; x++) {
                const size_t off = y * bytesPerRow + x * 4;
                if (data[off + 3] != 0) {
                    if (x < actualMinX) actualMinX = x;
                    if (x > actualMaxX) actualMaxX = x;
                    if (y < actualMinY) actualMinY = y;
                    if (y > actualMaxY) actualMaxY = y;
                }
            }
        }

        BOOL hasRemainingPixels = (actualMinX <= actualMaxX && actualMinY <= actualMaxY);
        if (hasRemainingPixels) {
            // Sample the first remaining pixel
            const size_t sampleOff = actualMinY * bytesPerRow + actualMinX * 4;
            unsigned char b = data[sampleOff + 0];
            unsigned char g = data[sampleOff + 1];
            unsigned char r = data[sampleOff + 2];
            unsigned char a = data[sampleOff + 3];

            NSLog(@"DEBUG iTermCharacterSource clearing failed for '%@':", self.debugName);
            NSLog(@"  Context size: %d x %d", contextWidth, contextHeight);
            NSLog(@"  Clear rect: %@", NSStringFromRect(drawnRect));
            NSLog(@"  Remaining pixels: (%d,%d) to (%d,%d)", actualMinX, actualMinY, actualMaxX, actualMaxY);
            NSLog(@"  Sample pixel at (%d,%d): R=%d G=%d B=%d A=%d", actualMinX, actualMinY, r, g, b, a);
            NSLog(@"  Scale: %f, glyphSize: %@, radius: %d",
                  _descriptor.scale, NSStringFromSize(_descriptor.glyphSize), _radius);
            NSLog(@"  baselineOffset: %f", _descriptor.baselineOffset);
            NSLog(@"  font: %@", _font);
            NSLog(@"  fakeItalic: %d, fakeBold: %d", _fakeItalic, _fakeBold);

            // Save post-clear image (remaining pixels) for inspection
            CGImageRef postImageRef = CGBitmapContextCreateImage(_context);
            if (postImageRef) {
                NSString *filename = [NSString stringWithFormat:@"/tmp/glyph_debug_%@_after.png", self.debugName];
                NSURL *url = [NSURL fileURLWithPath:filename];
                CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url,
                                                                                     (__bridge CFStringRef)UTTypePNG.identifier,
                                                                                     1, NULL);
                if (destination) {
                    CGImageDestinationAddImage(destination, postImageRef, nil);
                    CGImageDestinationFinalize(destination);
                    CFRelease(destination);
                    NSLog(@"  Saved post-clear image to: %@", filename);
                }
                CGImageRelease(postImageRef);
            }
            ITAssertWithMessage(NO,
                                @"Context not fully cleared after drawing '%@'. "
                                @"Clear rect: %@ Remaining: (%d,%d)-(%d,%d)",
                                self.debugName, NSStringFromRect(drawnRect),
                                actualMinX, actualMinY, actualMaxX, actualMaxY);
        }
    }
#endif
}

// Initializes a bunch of state that depends on knowing the font.
- (void)initializeStateIfNeededWithFont:(CTFontRef)runFont {
    if (_haveTestedForEmoji) {
        return;
    }

    // About to render the first glyph, emoji or not, for this string.
    // This is our chance to discover if it's emoji. Chrome does the
    // same trick.
    _haveTestedForEmoji = YES;

    NSString *fontName = CFBridgingRelease(CTFontCopyFamilyName(runFont));
    _isEmoji = ([fontName isEqualToString:@"AppleColorEmoji"] ||
                [fontName isEqualToString:@"Apple Color Emoji"]);
    _numberOfIterationsNeeded = 1;
    if (!_isEmoji) {
        if (iTermTextIsMonochrome()) {
            _numberOfIterationsNeeded = 4;
        }
    }

    ITAssertWithMessage(_context, @"context is null for size %@", NSStringFromSize(_size));
    _datas = [NSMutableArray array];
}

- (void)setTextColorForIteration:(NSInteger)iteration context:(CGContextRef)context {
    ITAssertWithMessage(context, @"nil context for iteration %@/%@", @(iteration), @(_numberOfIterationsNeeded));
    CGColorRef color = [[self textColorForIteration:iteration] CGColor];
    CGContextSetFillColorWithColor(context, color);
    CGContextSetStrokeColorWithColor(context, color);
}

// Per-iteration initialization. Only call this once per iteration.
- (void)initializeIteration:(NSInteger)iteration
                     offset:(CGPoint)offset
                       skew:(CGFloat)skew
                    context:(CGContextRef)context {
    CGContextSetShouldAntialias(context, _antialiased);

    if (_antialiased) {
        BOOL shouldSmooth;
        int style = -1;
        if (iTermTextIsMonochrome()) {
            if (_attributes.useThinStrokes) {
                shouldSmooth = NO;
            } else {
                shouldSmooth = YES;
            }
        } else {
            // User enabled subpixel AA
            shouldSmooth = YES;
        }
        if (shouldSmooth) {
            if (_attributes.useThinStrokes) {
                // This seems to be available at least on 10.8 and later. The only reference to it is in
                // WebKit. This causes text to render just a little lighter, which looks nicer.
                // It does not work in Mojave without subpixel AA.
                style = 16;
            } else {
                style = 0;
            }
        }
        CGContextSetShouldSmoothFonts(context, shouldSmooth);
        if (style >= 0) {
            CGContextSetFontSmoothingStyle(context, style);
        }
    } else {
        CGContextSetFontSmoothingStyle(context, YES);  // Issue 7394.
    }
    [self initializeTextMatrixInContext:context
                               withSkew:skew
                                 offset:offset];
}

- (void)prepareToDrawIteration:(NSInteger)iteration
                        offset:(CGPoint)offset
                       runFont:(CTFontRef)runFont
                          skew:(CGFloat)skew
                   initialized:(BOOL)haveInitializedThisIteration {
    [self initializeStateIfNeededWithFont:runFont];

    CGContextRef context = _context;
    // Non-monochrome non-emoji needs white background for subpixel antialiasing.
    // The context starts transparent and is cleared to transparent after each
    // iteration, so we need to fill with white before the first draw.
    // Use frameFlipped:NO because CGContextFillRect uses native CoreGraphics
    // coordinates (origin at bottom-left), not flipped coordinates.
    if (iteration == 0 && !iTermTextIsMonochrome() && !_isEmoji) {
        CGRect rect = [self frameFlipped:NO];
        CGContextSetRGBFillColor(context, 1, 1, 1, 1);
        CGContextFillRect(context, rect);
    }
    [self setTextColorForIteration:iteration
                           context:context];
    if (!haveInitializedThisIteration) {
        [self initializeIteration:iteration
                           offset:offset
                             skew:skew
                          context:context];
    }
}

- (NSColor *)textColorForIteration:(NSInteger)iteration {
    if (iTermTextIsMonochrome()) {
        switch (iteration) {
            case 0:
                return [NSColor it_colorInDefaultColorSpaceWithRed:0 green:0 blue:0 alpha:1];
            case 1:
                return [NSColor it_colorInDefaultColorSpaceWithRed:1 green:0 blue:0 alpha:1];
            case 2:
                return [NSColor it_colorInDefaultColorSpaceWithRed:0 green:1 blue:0 alpha:1];
            case 3:
                return [NSColor it_colorInDefaultColorSpaceWithRed:1 green:1 blue:1 alpha:1];
        }
        ITAssertWithMessage(NO, @"bogus iteration %@", @(iteration));
    }
    return [NSColor blackColor];
}

- (void)initializeTextMatrixInContext:(CGContextRef)cgContext
                             withSkew:(CGFloat)skew
                               offset:(CGPoint)offset {
    if (!_isEmoji) {
        // Can't use this with emoji.
        const CGFloat hScale = [self drawHScale];
        const CGFloat vScale = [self drawVScale];
        // For DWL lines, retina + DWL scales are in the CTM, so the text
        // matrix matches the legacy renderer: a=1, d=vScale.
        // DWL horizontal scale is in the CTM. Retina scale stays in the
        // text matrix for both axes.
        const CGFloat xScale = _descriptor.scale;
        const CGFloat yScale = _descriptor.scale * vScale;
        CGAffineTransform textMatrix = CGAffineTransformMake(xScale,        0.0,
                                                             skew * xScale, yScale,
                                                             offset.x,      offset.y);
        CGContextSetTextMatrix(cgContext, textMatrix);
    } else {
        CGContextSetTextMatrix(cgContext, CGAffineTransformIdentity);
    }
}

- (void)initializeCTMWithFont:(CTFontRef)runFont
                       offset:(CGPoint)offset
                    iteration:(NSInteger)iteration
                      context:(CGContextRef)context {
    CGContextConcatCTM(context, CTFontGetMatrix(runFont));
    CGContextTranslateCTM(context, offset.x, offset.y);
    CGContextScaleCTM(context, _descriptor.scale, _descriptor.scale * [self drawVScale]);
}

- (iTermCharacterBitmap *)bitmapForPart:(int)part {
    [self drawIfNeeded];
    const int radius = _radius;
    const int dx = iTermImagePartDX(part) + radius;
    const int dy = iTermImagePartDY(part) + radius;
    const NSInteger glyphWidth = ceil(_descriptor.glyphSize.width);
    const size_t destRowSize = glyphWidth * 4;
    const NSInteger glyphHeight = ceil(_descriptor.glyphSize.height);
    const NSUInteger length = destRowSize * glyphHeight;

    if (iTermTextIsMonochrome()) {
        if (!_postprocessed && !_isEmoji) {
            [self performPostProcessing];
        }
    }
    const unsigned char *bitmapBytes = _postprocessedData.bytes;
    NSInteger sourceLength = ceil(_size.width) * 4 * ceil(_size.height);
    size_t sourceRowSize = ceil(_size.width) * 4;
    if (!bitmapBytes) {
        bitmapBytes = _datas[0].bytes;
        sourceLength = _numberOfRows * _bytesPerRow;
        sourceRowSize = _bytesPerRow;
    }

    iTermCharacterBitmap *bitmap = [[iTermCharacterBitmap alloc] init];
    bitmap.data = [NSMutableData uninitializedDataWithLength:length];
    bitmap.size = NSMakeSize(glyphWidth, glyphHeight);

    char *dest = (char *)bitmap.data.mutableBytes;

    // Flip vertically and copy. The vertical flip is for historical reasons
    // (i.e., if I had more time I'd undo it but it's annoying because there
    // are assumptions about vertical flipping all over the fragment shader).
    ssize_t destOffset = (glyphHeight - 1) * destRowSize;
    ssize_t sourceOffset = (dx * 4 * glyphWidth) + (dy * glyphHeight * sourceRowSize);
    for (int i = 0;
         (destOffset >= 0 &&
          i < glyphHeight &&
          sourceOffset + destRowSize <= sourceLength);
         i++) {
        memcpy(dest + destOffset, bitmapBytes + sourceOffset, destRowSize);
        sourceOffset += sourceRowSize;
        destOffset -= destRowSize;
    }

    if (_debug) {
        NSImage *image = [NSImage imageWithRawData:bitmap.data
                                              size:bitmap.size
                                        scaledSize:bitmap.size
                                     bitsPerSample:8
                                   samplesPerPixel:4
                                          hasAlpha:YES
                                    colorSpaceName:NSDeviceRGBColorSpace];
        [image saveAsPNGTo:[NSString stringWithFormat:@"/tmp/%@.%@.%@.%@.png", _font.familyName,
                            [@[_attributes.bold ? @"Bold" : @"",
                              _attributes.italic ? @"Italic" : @"",
                              _attributes.useThinStrokes ? @"Thin" : @""] componentsJoinedByString:@""],
                            self.debugName, @(part)]];

        NSData *bigData = [NSData dataWithBytes:bitmapBytes length:sourceLength];
        image = [NSImage imageWithRawData:bigData
                                     size:_size
                               scaledSize:_size
                            bitsPerSample:8
                          samplesPerPixel:4
                                 hasAlpha:YES
                           colorSpaceName:NSDeviceRGBColorSpace];
        [image saveAsPNGTo:[NSString stringWithFormat:@"/tmp/big-%@.png", self.debugName]];
    }

    return bitmap;
}

- (NSArray<NSNumber *> *)parts {
    if (!_parts) {
        _parts = [self newParts];
    }
    return _parts;
}

- (NSArray<NSNumber *> *)newParts {
    CGRect boundingBox = self.frame;

    const iTermLineAttribute attr = [self lineAttribute];
    const int radius = _radius;
    NSMutableArray<NSNumber *> *result = [NSMutableArray array];
    for (int y = 0; y < self.maxParts; y++) {
        for (int x = 0; x < self.maxParts; x++) {
            CGRect partRect = CGRectMake(x * _descriptor.glyphSize.width,
                                         y * _descriptor.glyphSize.height,
                                         _descriptor.glyphSize.width,
                                         _descriptor.glyphSize.height);
            if (CGRectIntersectsRect(partRect, boundingBox)) {
                const int dy = y - radius;
                // For double-height lines, only include parts from the
                // relevant vertical half. The draw shift in drawWithOffset:
                // positions the glyph so top-half pixels land at dy <= 0
                // and bottom-half pixels at dy > 0.
                if (attr == iTermLineAttributeDoubleHeightTop && dy > 0) {
                    continue;
                }
                if (attr == iTermLineAttributeDoubleHeightBottom && dy < 0) {
                    continue;
                }
                [result addObject:@(iTermImagePartFromDeltas(x - radius, dy))];
            }
        }
    }
    return [result copy];
}

- (CGFloat)fakeBoldShift {
    if (_antialiased) {
        if (_descriptor.scale > 1) {
            return iTermCharacterSourceAntialiasedRetinaFakeBoldShiftPoints;
        } else {
            return iTermCharacterSourceAntialiasedNonretinaFakeBoldShiftPoints;
        }
    } else {
        return iTermCharacterSourceAliasedFakeBoldShiftPoints;
    }
}

- (CGRect)frame {
    return [self frameFlipped:YES];
}

// Dumps the alpha channel of data, which has dimensions of _size.
- (void)logStringRepresentationOfAlphaChannelOfBitmapDataBytes:(unsigned char *)data {
    for (int y = 0; y < _size.height; y++) {
        NSMutableString *line = [NSMutableString string];
        int width = _size.width;
        for (int x = 0; x < width; x++) {
            int offset = y * width * 4 + x*4 + 3;
            if (data[offset]) {
                [line appendString:@"X"];
            } else {
                [line appendString:@" "];
            }
        }
        NSLog(@"%@", line);
    }
}

// NOTE: This is only called for monochrome (non-subpixel-antialiased) text.
- (void)performPostProcessing {
    // Be conservative and allocate more space than needed if there's any imprecision.
    const NSInteger destinationLength = ceil(_size.width) * 4 * ceil(_size.height);
    _postprocessedData = [iTermBitmapData dataOfLength:destinationLength];
    unsigned char *destination = _postprocessedData.mutableBytes;

    unsigned char *data[4];
    for (int i = 0; i < 4; i++) {
        data[i] = _datas[i].mutableBytes;
    }

    // Byte arrays in _datas[j] have this size.
    const NSInteger readBound = _numberOfRows * _bytesPerRow;

    // The destination has this size.
    const NSInteger writeBound = destinationLength;

    // Don't attempt to access past this limit. In theory these would be the
    // same. In practice there were crashes I can't explain.
    const NSInteger bound = MIN(readBound, writeBound);

    // i indexes into the array of pixels, always to the red value.
    for (int i = 0 ; i + 3 < bound; i += 4) {
        // j indexes a destination color component and a source bitmap.
        for (int j = 0; j < 4; j++) {
            destination[i + j] = data[j][i + 3];
        }
    }
    _postprocessed = YES;
    [_postprocessedData checkForOverrunWithInfo:[NSString stringWithFormat:@"Size is %@", NSStringFromSize(_size)]];
}

- (NSRect)frameForBoundingRect:(NSRect)frame flipped:(BOOL)flipped {
    const int radius = _radius;
    frame.origin.y -= _descriptor.baselineOffset;
    frame.origin.x *= _descriptor.scale;
    frame.origin.y *= _descriptor.scale;
    frame.size.width *= _descriptor.scale;
    frame.size.height *= _descriptor.scale;

    if (_fakeItalic) {
        // Unfortunately it looks like CTLineGetImageBounds ignores the context's text matrix so we
        // have to guess what the frame's width would be when skewing it.
        // The skew transform shifts x based on y: x' = x + skew * y
        // Points above baseline (positive y) shift right; points below (descenders) shift left.
        const CGFloat scaledSkew = iTermFakeItalicSkew * _descriptor.scale;

        // Top of glyph shifts right
        const CGFloat heightAboveBaseline = NSMaxY(frame) + _descriptor.baselineOffset * _descriptor.scale;
        const CGFloat rightExtension = heightAboveBaseline * scaledSkew;
        if (rightExtension > 0) {
            frame.size.width += rightExtension;
        }

        // Bottom of glyph (descender) shifts left
        const CGFloat heightBelowBaseline = -(NSMinY(frame) + _descriptor.baselineOffset * _descriptor.scale);
        const CGFloat leftExtension = heightBelowBaseline * scaledSkew;
        if (leftExtension > 0) {
            frame.origin.x -= leftExtension;
            frame.size.width += leftExtension;
        }
    }
    if (_fakeBold) {
        frame.size.width += self.fakeBoldShift;
    }

    CGSize offset = [self desiredOffset];
    frame.origin.x += radius * _descriptor.glyphSize.width + offset.width;
    frame.origin.y += radius * _descriptor.glyphSize.height + offset.height;
    if (flipped) {
        frame.origin.y = _size.height - frame.origin.y - frame.size.height;
    }

    // Add buffer for antialiasing fringe pixels and because CGRect's max
    // coordinates are exclusive.
    const CGFloat buffer = 2;
    CGPoint min = CGPointMake(floor(CGRectGetMinX(frame)) - buffer,
                              floor(CGRectGetMinY(frame)) - buffer);
    CGPoint max = CGPointMake(ceil(CGRectGetMaxX(frame)) + buffer,
                              ceil(CGRectGetMaxY(frame)) + buffer);
    frame = CGRectMake(min.x, min.y, max.x - min.x, max.y - min.y);
    DLog(@"%@ Bounding box for character '%@' in font %@ is %@ at scale %@",
         self, self.debugName, _font, NSStringFromRect(frame), @(_descriptor.scale));

    return frame;
}

- (void)drawEmojiWithFont:(CTFontRef)runFont
                   offset:(CGPoint)offset
                   buffer:(const CGGlyph *)buffer
                positions:(CGPoint *)positions
                   length:(size_t)length
                iteration:(NSInteger)iteration
                  context:(CGContextRef)context {
    CGAffineTransform textMatrix = CGContextGetTextMatrix(context);
    CGContextSaveGState(context);
    // You have to use the CTM with emoji. CGContextSetTextMatrix doesn't work.
    [self initializeCTMWithFont:runFont offset:offset iteration:iteration context:context];

    CTFontDrawGlyphs(runFont, buffer, (NSPoint *)positions, length, context);

    CGContextRestoreGState(context);
    CGContextSetTextMatrix(context, textMatrix);
}


@end

