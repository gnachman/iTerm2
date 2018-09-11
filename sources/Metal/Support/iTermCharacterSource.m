//
//  iTermCharacterSource.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/26/17.
//

#import <Cocoa/Cocoa.h>

#import "DebugLogging.h"
#import "iTermCharacterBitmap.h"
#import "iTermCharacterParts.h"
#import "iTermCharacterSource.h"
#import "iTermTextureArray.h"
#import "NSImage+iTerm.h"
#import "NSMutableData+iTerm.h"
#import "NSStringITerm.h"

#define ENABLE_DEBUG_CHARACTER_SOURCE_ALIGNMENT 0

extern void CGContextSetFontSmoothingStyle(CGContextRef, int);
extern int CGContextGetFontSmoothingStyle(CGContextRef);

static const CGFloat iTermFakeItalicSkew = 0.2;
static const CGFloat iTermCharacterSourceAntialiasedRetinaFakeBoldShiftPoints = 0.5;
static const CGFloat iTermCharacterSourceAntialiasedNonretinaFakeBoldShiftPoints = 0;
static const CGFloat iTermCharacterSourceAliasedFakeBoldShiftPoints = 1;

@implementation iTermCharacterSource {
    NSString *_string;
    NSFont *_font;
    CGSize _size;
    CGFloat _baselineOffset;
    CGFloat _scale;
    BOOL _useThinStrokes;
    BOOL _fakeBold;
    BOOL _fakeItalic;
    BOOL _antialiased;
    BOOL _postprocessed NS_AVAILABLE_MAC(10_14);
    
    CGSize _partSize;
    CTLineRef _lineRef;
    CGContextRef _cgContext;

    NSAttributedString *_attributedString;
    NSImage *_image;
    NSMutableData *_glyphsData;
    NSMutableData *_positionsBuffer;
    BOOL _haveDrawn;
    CGImageRef _imageRef;
    NSArray<NSNumber *> *_parts;
    int _radius;
    
    // If true then _isEmoji is valid.
    BOOL _haveTestedForEmoji;
}

+ (CGColorSpaceRef)colorSpace {
    static dispatch_once_t onceToken;
    static CGColorSpaceRef colorSpace;
    dispatch_once(&onceToken, ^{
        colorSpace = CGColorSpaceCreateDeviceRGB();
    });
    return colorSpace;
}

+ (CGContextRef)newBitmapContextOfSize:(CGSize)size {
    // In order to get subpixel antialiasing you have to use premultiplied first and byte order 32 host.
    // This influences the choice of pixel format for the textures containing glyphs.
    return CGBitmapContextCreate(NULL,
                                 size.width,
                                 size.height,
                                 8,
                                 size.width * 4,
                                 [iTermCharacterSource colorSpace],
                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
}

+ (CGContextRef)onePixelContext {
    static dispatch_once_t onceToken;
    static CGContextRef context;
    dispatch_once(&onceToken, ^{
        context = [self newBitmapContextOfSize:CGSizeMake(1, 1)];
    });
    return context;
}

+ (NSRect)boundingRectForCharactersInRange:(NSRange)range
                                      font:(NSFont *)font
                            baselineOffset:(CGFloat)baselineOffset
                                     scale:(CGFloat)scale {
    static NSMutableDictionary<NSArray *, NSValue *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });
    if (!font) {
        return NSMakeRect(0, 0, 1, 1);
    }
    NSArray *key = @[ NSStringFromRange(range),
                      font.fontName,
                      @(font.pointSize),
                      @(baselineOffset),
                      @(scale)];
    if (cache[key]) {
        return [cache[key] rectValue];
    }
    
    NSRect unionRect = NSZeroRect;
    for (NSInteger i = 0; i < range.length; i++) {
        @autoreleasepool {
            UTF32Char c = range.location + i;
            iTermCharacterSource *source = [[iTermCharacterSource alloc] initWithCharacter:[NSString stringWithLongCharacter:c]
                                                                                      font:font
                                                                                      size:CGSizeMake(font.pointSize * 10,
                                                                                                      font.pointSize * 10)
                                                                            baselineOffset:baselineOffset
                                                                                     scale:scale
                                                                            useThinStrokes:NO
                                                                                  fakeBold:YES
                                                                                fakeItalic:YES
                                                                               antialiased:YES
                                                                                    radius:0];
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

- (instancetype)initWithCharacter:(NSString *)string
                             font:(NSFont *)font
                             size:(CGSize)size
                   baselineOffset:(CGFloat)baselineOffset
                            scale:(CGFloat)scale
                   useThinStrokes:(BOOL)useThinStrokes
                         fakeBold:(BOOL)fakeBold
                       fakeItalic:(BOOL)fakeItalic
                      antialiased:(BOOL)antialiased
                           radius:(int)radius {
    ITDebugAssert(font);
    ITDebugAssert(size.width > 0 && size.height > 0);
    ITDebugAssert(scale > 0);

    if (string.length == 0) {
        return nil;
    }

    self = [super init];
    if (self) {
        _string = [string copy];
        _font = font;
        _partSize = size;
        _radius = radius;
        _size = CGSizeMake(size.width * self.maxParts,
                           size.height * self.maxParts);
        _baselineOffset = baselineOffset;
        _scale = scale;
        _useThinStrokes = useThinStrokes;
        _fakeBold = fakeBold;
        _fakeItalic = fakeItalic;

        _attributedString = [[NSAttributedString alloc] initWithString:string attributes:self.attributes];
        _lineRef = CTLineCreateWithAttributedString((CFAttributedStringRef)_attributedString);
        _cgContext = [iTermCharacterSource newBitmapContextOfSize:_size];
        _antialiased = antialiased;
    }
    return self;
}

- (void)dealloc {
    if (_lineRef) {
        CFRelease(_lineRef);
    }
    if (_cgContext) {
        CGContextRelease(_cgContext);
    }
    if (_imageRef) {
        CGImageRelease(_imageRef);
    }
}

- (int)maxParts {
    return _radius * 2 + 1;
}

#pragma mark - APIs

- (iTermCharacterBitmap *)bitmapForPart:(int)part {
    [self drawIfNeeded];
    const int radius = _radius;
    const int dx = iTermImagePartDX(part) + radius;
    const int dy = iTermImagePartDY(part) + radius;
    const size_t sourceRowSize = _size.width * 4;
    const size_t destRowSize = _partSize.width * 4;
    const NSUInteger length = destRowSize * _partSize.height;

    iTermCharacterBitmap *bitmap = [[iTermCharacterBitmap alloc] init];
    bitmap.data = [NSMutableData uninitializedDataWithLength:length];
    bitmap.size = _partSize;

    unsigned char *source = (unsigned char *)CGBitmapContextGetData(_cgContext);

#if ENABLE_DEBUG_CHARACTER_SOURCE_ALIGNMENT
    if (saveBitmapsForDebugging) {
        NSImage *image = [NSImage imageWithRawData:[NSData dataWithBytes:source length:bitmap.data.length]
                                              size:_partSize
                                     bitsPerSample:8
                                   samplesPerPixel:4
                                          hasAlpha:YES
                                    colorSpaceName:NSDeviceRGBColorSpace];
        [image saveAsPNGTo:[NSString stringWithFormat:@"/tmp/%@.%@.png", _string, @(part)]];

        NSData *bigData = [NSData dataWithBytes:source length:_size.width*_size.height*4];
        image = [NSImage imageWithRawData:bigData
                                     size:_size
                            bitsPerSample:8
                          samplesPerPixel:4
                                 hasAlpha:YES
                           colorSpaceName:NSDeviceRGBColorSpace];
        [image saveAsPNGTo:[NSString stringWithFormat:@"/tmp/big-%@.png", _string]];
    }
#endif

    if (@available(macOS 10.14, *)) {
        if (!_postprocessed && !_isEmoji) {
            // Copy red channel to alpha channel
            // Rendering over transparent looks bad. So we render white over black and then tweak the
            // alpha channel.
            for (int i = 0 ; i < _size.height * _size.width * 4; i += 4) {
                source[i + 3] = source[i];
                source[i + 0] = 255;
                source[i + 1] = 255;
                source[i + 2] = 255;
            }
            _postprocessed = YES;
        }
    }

    char *dest = (char *)bitmap.data.mutableBytes;

    // Flip vertically and copy. The vertical flip is for historical reasons
    // (i.e., if I had more time I'd undo it but it's annoying because there
    // are assumptions about vertical flipping all over the fragment shader).
    size_t destOffset = (_partSize.height - 1) * destRowSize;
    size_t sourceOffset = (dx * 4 * _partSize.width) + (dy * _partSize.height * sourceRowSize);
    for (int i = 0; i < _partSize.height; i++) {
        memcpy(dest + destOffset, source + sourceOffset, destRowSize);
        sourceOffset += sourceRowSize;
        destOffset -= destRowSize;
    }

    return bitmap;
}

- (NSArray<NSNumber *> *)parts {
    if (!_parts) {
        _parts = [self newParts];
    }
    return _parts;
}

#pragma mark - Private

#pragma mark Lazy Computations

- (NSArray<NSNumber *> *)newParts {
    CGRect boundingBox = self.frame;
    const int radius = _radius;
    NSMutableArray<NSNumber *> *result = [NSMutableArray array];
    for (int y = 0; y < self.maxParts; y++) {
        for (int x = 0; x < self.maxParts; x++) {
            CGRect partRect = CGRectMake(x * _partSize.width,
                                         y * _partSize.height,
                                         _partSize.width,
                                         _partSize.height);
            if (CGRectIntersectsRect(partRect, boundingBox)) {
                [result addObject:@(iTermImagePartFromDeltas(x - radius, y - radius))];
            }
        }
    }
    return [result copy];
}

- (NSImage *)newImageWithOffset:(CGPoint)offset {
    if (!_imageRef) {
        _imageRef = CGBitmapContextCreateImage(_cgContext);
    }
    CGImageRef part = CGImageCreateWithImageInRect(_imageRef,
                                                   CGRectMake(offset.x,
                                                              offset.y,
                                                              _partSize.width,
                                                              _partSize.height));
    NSImage *image = [[NSImage alloc] initWithCGImage:part size:_partSize];
    CGImageRelease(part);
    return image;
}

- (void)drawIfNeeded {
    if (!_haveDrawn) {
        const int radius = _radius;
        [self drawWithOffset:CGPointMake(_partSize.width * radius,
                                         _partSize.height * radius)];
    }
}

- (CGFloat)fakeBoldShift {
    if (_antialiased) {
        if (_scale > 1) {
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

- (CGRect)frameFlipped:(BOOL)flipped {
    if (_string.length == 0) {
        return CGRectZero;
    }
    CGContextRef cgContext = [iTermCharacterSource onePixelContext];

    CGRect frame = CTLineGetImageBounds(_lineRef, cgContext);
    const int radius = _radius;
    frame.origin.y -= _baselineOffset;
    frame.origin.x *= _scale;
    frame.origin.y *= _scale;
    frame.size.width *= _scale;
    frame.size.height *= _scale;

    if (_fakeItalic) {
        // Unfortunately it looks like CTLineGetImageBounds ignores the context's text matrix so we
        // have to guess what the frame's width would be when skewing it.
        const CGFloat heightAboveBaseline = NSMaxY(frame) + _baselineOffset * _scale;
        const CGFloat scaledSkew = iTermFakeItalicSkew * _scale;
        const CGFloat rightExtension = heightAboveBaseline * scaledSkew;
        if (rightExtension > 0) {
            frame.size.width += rightExtension;
        }
    }
    if (_fakeBold) {
        frame.size.width += self.fakeBoldShift;
    }

    frame.origin.x += radius * _partSize.width;
    frame.origin.y += radius * _partSize.height;
    if (flipped) {
        frame.origin.y = _size.height - frame.origin.y - frame.size.height;
    }

    CGPoint min = CGPointMake(floor(CGRectGetMinX(frame)),
                              floor(CGRectGetMinY(frame)));
    CGPoint max = CGPointMake(ceil(CGRectGetMaxX(frame)),
                              ceil(CGRectGetMaxY(frame)));
    frame = CGRectMake(min.x, min.y, max.x - min.x, max.y - min.y);

    return frame;
}

#pragma mark Drawing

- (void)drawWithOffset:(CGPoint)offset {
    CFArrayRef runs = CTLineGetGlyphRuns(_lineRef);
    CGContextSetShouldAntialias(_cgContext, _antialiased);

    const CGFloat skew = _fakeItalic ? iTermFakeItalicSkew : 0;

    if (_useThinStrokes) {
        CGContextSetShouldSmoothFonts(_cgContext, YES);
        // This seems to be available at least on 10.8 and later. The only reference to it is in
        // WebKit. This causes text to render just a little lighter, which looks nicer.
        CGContextSetFontSmoothingStyle(_cgContext, 16);
    }

    const CGFloat ty = offset.y - _baselineOffset * _scale;

    [self drawRuns:runs atOffset:CGPointMake(offset.x, ty) skew:skew];
    if (_fakeBold) {
        [self drawRuns:runs atOffset:CGPointMake(offset.x + self.fakeBoldShift * _scale, ty) skew:skew];
    }
    _haveDrawn = YES;
}

- (void)fillBackground {
    if (@available(macOS 10.14, *)) {
        if (_isEmoji) {
            CGContextSetRGBFillColor(_cgContext, 0, 0, 0, 0);
        } else {
            CGContextSetRGBFillColor(_cgContext, 0, 0, 0, 1);
        }
    } else {
        if (_isEmoji) {
            CGContextSetRGBFillColor(_cgContext, 1, 1, 1, 0);
        } else {
            CGContextSetRGBFillColor(_cgContext, 1, 1, 1, 1);
        }
    }
    CGContextFillRect(_cgContext, CGRectMake(0, 0, _size.width, _size.height));

#if ENABLE_DEBUG_CHARACTER_SOURCE_ALIGNMENT
    CGContextSetRGBStrokeColor(_cgContext, 1, 0, 0, 1);
    for (int x = 0; x < self.maxParts; x++) {
        for (int y = 0; y < self.maxParts; y++) {
            CGContextStrokeRect(_cgContext, CGRectMake(x * _partSize.width,
                                                       y * _partSize.height,
                                                       _partSize.width, _partSize.height));
        }
    }
#endif
}

- (void)drawRuns:(CFArrayRef)runs atOffset:(CGPoint)offset skew:(CGFloat)skew {
    BOOL haveSetTextMatrix = NO;

    for (CFIndex j = 0; j < CFArrayGetCount(runs); j++) {
        CTRunRef run = CFArrayGetValueAtIndex(runs, j);
        const size_t length = CTRunGetGlyphCount(run);
        const CGGlyph *buffer = [self glyphsInRun:run length:length];
        CGPoint *positions = [self positionsInRun:run length:length];
        CTFontRef runFont = CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);

        if (!_haveTestedForEmoji) {
            // About to render the first glyph, emoji or not, for this string.
            // This is our chance to discover if it's emoji. Chrome does the
            // same trick.
            _haveTestedForEmoji = YES;
            NSString *fontName = CFBridgingRelease(CTFontCopyFamilyName(runFont));
            _isEmoji = ([fontName isEqualToString:@"AppleColorEmoji"] ||
                        [fontName isEqualToString:@"Apple Color Emoji"]);

            // Now that we know we can do the setup operations that depend on
            // knowing if it's emoji.
            [self fillBackground];
            CGContextSetFillColorWithColor(_cgContext, [self.textColor CGColor]);
            CGContextSetStrokeColorWithColor(_cgContext, [self.textColor CGColor]);
        }
        if (!haveSetTextMatrix) {
            [self initializeTextMatrixInContext:_cgContext
                                       withSkew:skew
                                         offset:offset];
            haveSetTextMatrix = YES;
        }

        if (_isEmoji) {
            [self drawEmojiWithFont:runFont offset:offset buffer:buffer positions:positions length:length];
        } else {
            CTFontDrawGlyphs(runFont, buffer, (NSPoint *)positions, length, _cgContext);
#if ENABLE_DEBUG_CHARACTER_SOURCE_ALIGNMENT
            CGContextSetRGBStrokeColor(_cgContext, 0, 0, 1, 1);
            CGContextStrokeRect(_cgContext, CGRectMake(offset.x + positions[0].x,
                                                       offset.y + positions[0].y,
                                                       _partSize.width, _partSize.height));

            CGContextSetRGBStrokeColor(_cgContext, 1, 0, 1, 1);
            CGContextStrokeRect(_cgContext, CGRectMake(offset.x,
                                                       offset.y,
                                                       _partSize.width, _partSize.height));
#endif
        }
    }
}

- (NSColor *)textColor {
    if (@available(macOS 10.14, *)) {
        return [NSColor whiteColor];
    } else {
        return [NSColor blackColor];
    }
}

- (void)drawEmojiWithFont:(CTFontRef)runFont
                   offset:(CGPoint)offset
                   buffer:(const CGGlyph *)buffer
                positions:(CGPoint *)positions
                   length:(size_t)length {
    CGContextSaveGState(_cgContext);
    // You have to use the CTM with emoji. CGContextSetTextMatrix doesn't work.
    [self initializeCTMWithFont:runFont offset:offset];

    CTFontDrawGlyphs(runFont, buffer, (NSPoint *)positions, length, _cgContext);

    CGContextRestoreGState(_cgContext);
}

#pragma mark Core Text Helpers

- (const CGGlyph *)glyphsInRun:(CTRunRef)run length:(size_t)length {
    const CGGlyph *buffer = CTRunGetGlyphsPtr(run);
    if (buffer) {
        return buffer;
    }

    _glyphsData = [[NSMutableData alloc] initWithLength:sizeof(CGGlyph) * length];
    CTRunGetGlyphs(run, CFRangeMake(0, length), (CGGlyph *)_glyphsData.mutableBytes);
    return (const CGGlyph *)_glyphsData.mutableBytes;
}

- (CGPoint *)positionsInRun:(CTRunRef)run length:(size_t)length {
    _positionsBuffer = [[NSMutableData alloc] initWithLength:sizeof(CGPoint) * length];
    CTRunGetPositions(run, CFRangeMake(0, length), (CGPoint *)_positionsBuffer.mutableBytes);
    return (CGPoint *)_positionsBuffer.mutableBytes;

}

- (void)initializeTextMatrixInContext:(CGContextRef)cgContext
                             withSkew:(CGFloat)skew
                               offset:(CGPoint)offset {
    if (!_isEmoji) {
        // Can't use this with emoji.
        CGAffineTransform textMatrix = CGAffineTransformMake(_scale,        0.0,
                                                             skew * _scale, _scale,
                                                             offset.x,      offset.y);
        CGContextSetTextMatrix(cgContext, textMatrix);
    }
}

- (void)initializeCTMWithFont:(CTFontRef)runFont offset:(CGPoint)offset {
    CGContextConcatCTM(_cgContext, CTFontGetMatrix(runFont));
    CGContextTranslateCTM(_cgContext, offset.x, offset.y);
    CGContextScaleCTM(_cgContext, _scale, _scale);
}

- (NSDictionary *)attributes {
    static NSMutableParagraphStyle *paragraphStyle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.lineBreakMode = NSLineBreakByClipping;
        paragraphStyle.tabStops = @[];
        paragraphStyle.baseWritingDirection = NSWritingDirectionLeftToRight;
    });
    return @{ (NSString *)kCTLigatureAttributeName: @0,
              (NSString *)kCTForegroundColorAttributeName: (id)[self.textColor CGColor],
              NSFontAttributeName: _font,
              NSParagraphStyleAttributeName: paragraphStyle };
}

@end
