//
//  iTermCharacterSource.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/26/17.
//

#import <Cocoa/Cocoa.h>

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "iTermBoxDrawingBezierCurveFactory.h"
#import "iTermCharacterBitmap.h"
#import "iTermCharacterParts.h"
#import "iTermCharacterSource.h"
#import "iTermData.h"
#import "iTermTextureArray.h"
#import "NSImage+iTerm.h"
#import "NSMutableData+iTerm.h"
#import "NSStringITerm.h"
#import "PTYFontInfo.h"

#define ENABLE_DEBUG_CHARACTER_SOURCE_ALIGNMENT 0

extern void CGContextSetFontSmoothingStyle(CGContextRef, int);
extern int CGContextGetFontSmoothingStyle(CGContextRef);

static const CGFloat iTermFakeItalicSkew = 0.2;
static const CGFloat iTermCharacterSourceAntialiasedRetinaFakeBoldShiftPoints = 0.5;
static const CGFloat iTermCharacterSourceAntialiasedNonretinaFakeBoldShiftPoints = 0;
static const CGFloat iTermCharacterSourceAliasedFakeBoldShiftPoints = 1;

@interface iTermCharacterSourceDescriptor()
@property (nonatomic, readwrite, strong) PTYFontInfo *asciiFontInfo;
@property (nonatomic, readwrite, strong) PTYFontInfo *nonAsciiFontInfo;
@property (nonatomic, readwrite) CGSize asciiOffset;
@property (nonatomic, readwrite) CGSize glyphSize;
@property (nonatomic, readwrite) CGSize cellSize;
@property (nonatomic, readwrite) CGSize cellSizeWithoutSpacing;
@property (nonatomic, readwrite) CGFloat scale;
@property (nonatomic, readwrite) BOOL useBoldFont;
@property (nonatomic, readwrite) BOOL useItalicFont;
@property (nonatomic, readwrite) BOOL useNonAsciiFont;
@property (nonatomic, readwrite) BOOL asciiAntiAliased;
@property (nonatomic, readwrite) BOOL nonAsciiAntiAliased;
@property (nonatomic, readonly) CGFloat baselineOffset;

@end

@implementation iTermCharacterSourceDescriptor

+ (instancetype)characterSourceDescriptorWithAsciiFont:(PTYFontInfo *)asciiFontInfo
                                          nonAsciiFont:(PTYFontInfo *)nonAsciiFontInfo
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
    
    descriptor.asciiFontInfo = asciiFontInfo;
    descriptor.nonAsciiFontInfo = nonAsciiFontInfo;
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

- (NSDictionary *)dictionaryValue {
    return @{ @"asciiRegularFont": _asciiFontInfo.font ?: [NSNull null],
              @"asciiBoldFont": _asciiFontInfo.boldVersion.font ?: [NSNull null],
              @"asciiItalicFont": _asciiFontInfo.italicVersion.font ?: [NSNull null],
              @"asciiBoldItalicFont": _asciiFontInfo.boldItalicVersion.font ?: [NSNull null],
              @"nonAsciiRegularFont": _nonAsciiFontInfo.font ?: [NSNull null],
              @"nonAsciiBoldFont": _nonAsciiFontInfo.boldVersion.font ?: [NSNull null],
              @"nonAsciiItalicFont": _nonAsciiFontInfo.italicVersion.font ?: [NSNull null],
              @"nonAsciiBoldItalicFont": _nonAsciiFontInfo.boldItalicVersion.font ?: [NSNull null],
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
    return _asciiFontInfo.baselineOffset;
}

- (NSFont *)fontForASCII:(BOOL)isAscii
               attributes:(iTermCharacterSourceAttributes *)attributes
               renderBold:(BOOL *)renderBold
             renderItalic:(BOOL *)renderItalic {
    *renderBold = attributes.bold;
    *renderItalic = attributes.italic;
    return [PTYFontInfo fontForAsciiCharacter:isAscii
                                    asciiFont:_asciiFontInfo
                                 nonAsciiFont:_nonAsciiFontInfo
                                  useBoldFont:self.useBoldFont
                                useItalicFont:self.useItalicFont
                             usesNonAsciiFont:self.useNonAsciiFont
                                   renderBold:renderBold
                                 renderItalic:renderItalic].font;
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
    NSString *_string;
    iTermCharacterSourceDescriptor *_descriptor;
    iTermCharacterSourceAttributes *_attributes;
    BOOL _antialiased;
    BOOL _fakeBold;
    BOOL _fakeItalic;
    NSFont *_font;
    CGSize _size;
    BOOL _boxDrawing;
    BOOL _useNativePowerlineGlyphs;
    BOOL _postprocessed NS_AVAILABLE_MAC(10_14);
    
    CTLineRef _lineRefs[4];
    CGContextRef _context;
    NSMutableArray<NSMutableData *> *_datas;

    NSAttributedString *_attributedStrings[4];
    NSImage *_image;
    NSMutableData *_glyphsData;
    NSMutableData *_positionsBuffer;
    BOOL _haveDrawn;
    CGImageRef _imageRef;
    NSArray<NSNumber *> *_parts;
    int _radius;

    // If true then _isEmoji is valid.
    BOOL _haveTestedForEmoji;
    NSInteger _nextIterationToDrawBackgroundFor;
    NSInteger _numberOfIterationsNeeded;
    iTermBitmapData *_postprocessedData;
    BOOL _isAscii;
}

+ (NSRect)boundingRectForCharactersInRange:(NSRange)range
                             asciiFontInfo:(PTYFontInfo *)asciiFontInfo
                          nonAsciiFontInfo:(PTYFontInfo *)nonAsciiFontInfo
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
    if (!asciiFontInfo) {
        return NSMakeRect(0, 0, 1, 1);
    }
    CGFloat pointSize;
    if (useNonAsciiFont && nonAsciiFontInfo) {
        pointSize = MAX(asciiFontInfo.font.pointSize, nonAsciiFontInfo.font.pointSize);
    } else {
        pointSize = asciiFontInfo.font.pointSize;
    }
    NSArray *key = @[ NSStringFromRange(range),
                      asciiFontInfo.font.fontName ?: @"",
                      nonAsciiFontInfo.font.fontName ?: @"",
                      @(pointSize),
                      @(asciiFontInfo.baselineOffset),
                      @(scale),
                      @(useBoldFont),
                      @(useItalicFont),
                      @(useNonAsciiFont)];
    if (cache[key]) {
        return [cache[key] rectValue];
    }
    
    const CGSize bigSize = CGSizeMake(pointSize * 10,
                                      pointSize * 10);
    iTermCharacterSourceDescriptor *descriptor = [iTermCharacterSourceDescriptor characterSourceDescriptorWithAsciiFont:asciiFontInfo
                                                                                                           nonAsciiFont:nonAsciiFontInfo
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

- (instancetype)initWithCharacter:(NSString *)string
                       descriptor:(iTermCharacterSourceDescriptor *)descriptor
                       attributes:(iTermCharacterSourceAttributes *)attributes
                       boxDrawing:(BOOL)boxDrawing
                           radius:(int)radius
         useNativePowerlineGlyphs:(BOOL)useNativePowerlineGlyphs
                          context:(CGContextRef)context {
    assert(descriptor.glyphSize.width > 0);
    assert(descriptor.glyphSize.height > 0);
    assert(descriptor.scale > 0);

    if (string.length == 0) {
        return nil;
    }

    self = [super init];
    if (self) {
        _string = [string copy];
        _descriptor = descriptor;
        _isAscii = (string.length == 1 && [string characterAtIndex:0] < 128);
        _antialiased = _isAscii ? descriptor.asciiAntiAliased : descriptor.nonAsciiAntiAliased;
        _font = [descriptor fontForASCII:_isAscii attributes:attributes renderBold:&_fakeBold renderItalic:&_fakeItalic];
        ITAssertWithMessage(_font, @"Nil font for string=%@ attributes=%@", string, attributes);
        _attributes = attributes;
        _radius = radius;
        _size = CGSizeMake(descriptor.glyphSize.width * self.maxParts,
                           descriptor.glyphSize.height * self.maxParts);
        _boxDrawing = boxDrawing;
        _useNativePowerlineGlyphs = useNativePowerlineGlyphs;
        _context = context;
        CGContextRetain(context);

        for (int i = 0; i < 4; i++) {
            _attributedStrings[i] = [[NSAttributedString alloc] initWithString:string attributes:[self attributesForIteration:i]];
            _lineRefs[i] = CTLineCreateWithAttributedString((CFAttributedStringRef)_attributedStrings[i]);
        }
    }
    return self;
}

- (void)dealloc {
    CGContextRelease(_context);
    for (NSInteger i = 0; i < 4; i++) {
        if (_lineRefs[i]) {
            CFRelease(_lineRefs[i]);
        }
    }
    if (_imageRef) {
        CGImageRelease(_imageRef);
    }
}

- (int)maxParts {
    return _radius * 2 + 1;
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

#pragma mark - APIs

- (void)performPostProcessing {
    _postprocessedData = [iTermBitmapData dataOfLength:_size.width * 4 * _size.height];
    unsigned char *destination = _postprocessedData.mutableBytes;

    unsigned char *data[4];
    for (int i = 0; i < 4; i++) {
        data[i] = _datas[i].mutableBytes;
    }

    // i indexes into the array of pixels, always to the red value.
    for (int i = 0 ; i < _size.height * _size.width * 4; i += 4) {
        // j indexes a destination color component and a source bitmap.
        for (int j = 0; j < 4; j++) {
            destination[i + j] = data[j][i + 3];
        }
    }
    _postprocessed = YES;
    [_postprocessedData checkForOverrunWithInfo:[NSString stringWithFormat:@"Size is %@", NSStringFromSize(_size)]];
}

- (iTermCharacterBitmap *)bitmapForPart:(int)part {
    [self drawIfNeeded];
    const int radius = _radius;
    const int dx = iTermImagePartDX(part) + radius;
    const int dy = iTermImagePartDY(part) + radius;
    const size_t sourceRowSize = _size.width * 4;
    const size_t destRowSize = _descriptor.glyphSize.width * 4;
    const NSUInteger length = destRowSize * _descriptor.glyphSize.height;

    if (iTermTextIsMonochrome()) {
        if (!_postprocessed && !_isEmoji) {
            [self performPostProcessing];
        }
    }
    const unsigned char *bitmapBytes = _postprocessedData.bytes;
    if (!bitmapBytes) {
        bitmapBytes = _datas[0].bytes;
    }

    iTermCharacterBitmap *bitmap = [[iTermCharacterBitmap alloc] init];
    bitmap.data = [NSMutableData uninitializedDataWithLength:length];
    bitmap.size = _descriptor.glyphSize;

    BOOL saveBitmapsForDebugging = NO;
    if (saveBitmapsForDebugging) {
        NSImage *image = [NSImage imageWithRawData:[NSData dataWithBytes:bitmapBytes length:bitmap.data.length]
                                              size:_descriptor.glyphSize
                                     bitsPerSample:8
                                   samplesPerPixel:4
                                          hasAlpha:YES
                                    colorSpaceName:NSDeviceRGBColorSpace];
        [image saveAsPNGTo:[NSString stringWithFormat:@"/tmp/%@.%@.png", _string, @(part)]];

        NSData *bigData = [NSData dataWithBytes:bitmapBytes length:_size.width*_size.height*4];
        image = [NSImage imageWithRawData:bigData
                                     size:_size
                            bitsPerSample:8
                          samplesPerPixel:4
                                 hasAlpha:YES
                           colorSpaceName:NSDeviceRGBColorSpace];
        [image saveAsPNGTo:[NSString stringWithFormat:@"/tmp/big-%@.png", _string]];
    }


    char *dest = (char *)bitmap.data.mutableBytes;

    // Flip vertically and copy. The vertical flip is for historical reasons
    // (i.e., if I had more time I'd undo it but it's annoying because there
    // are assumptions about vertical flipping all over the fragment shader).
    size_t destOffset = (_descriptor.glyphSize.height - 1) * destRowSize;
    size_t sourceOffset = (dx * 4 * _descriptor.glyphSize.width) + (dy * _descriptor.glyphSize.height * sourceRowSize);
    for (int i = 0; i < _descriptor.glyphSize.height; i++) {
        memcpy(dest + destOffset, bitmapBytes + sourceOffset, destRowSize);
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
            CGRect partRect = CGRectMake(x * _descriptor.glyphSize.width,
                                         y * _descriptor.glyphSize.height,
                                         _descriptor.glyphSize.width,
                                         _descriptor.glyphSize.height);
            if (CGRectIntersectsRect(partRect, boundingBox)) {
                [result addObject:@(iTermImagePartFromDeltas(x - radius, y - radius))];
            }
        }
    }
    return [result copy];
}

- (void)drawIfNeeded {
    if (!_haveDrawn) {
        CGSize offset;
        if (_isAscii) {
            offset = _descriptor.asciiOffset;
        } else {
            offset = CGSizeZero;
        }
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

- (CGRect)frameFlipped:(BOOL)flipped {
    if (_string.length == 0) {
        return CGRectZero;
    }
    if (_boxDrawing) {
        NSRect rect;
        const CGFloat inset = _descriptor.scale;
        rect.origin = NSMakePoint(_descriptor.glyphSize.width * _radius - inset,
                                  _descriptor.glyphSize.height * _radius - inset);
        rect.size = NSMakeSize(_descriptor.cellSize.width * _descriptor.scale + inset * 2,
                               _descriptor.cellSize.height * _descriptor.scale + inset * 2);
        return rect;
    }

    CGContextRef cgContext = _context;
    CGRect frame = CTLineGetImageBounds(_lineRefs[0], cgContext);
    const int radius = _radius;
    frame.origin.y -= _descriptor.baselineOffset;
    frame.origin.x *= _descriptor.scale;
    frame.origin.y *= _descriptor.scale;
    frame.size.width *= _descriptor.scale;
    frame.size.height *= _descriptor.scale;

    if (_fakeItalic) {
        // Unfortunately it looks like CTLineGetImageBounds ignores the context's text matrix so we
        // have to guess what the frame's width would be when skewing it.
        const CGFloat heightAboveBaseline = NSMaxY(frame) + _descriptor.baselineOffset * _descriptor.scale;
        const CGFloat scaledSkew = iTermFakeItalicSkew * _descriptor.scale;
        const CGFloat rightExtension = heightAboveBaseline * scaledSkew;
        if (rightExtension > 0) {
            frame.size.width += rightExtension;
        }
    }
    if (_fakeBold) {
        frame.size.width += self.fakeBoldShift;
    }

    frame.origin.x += radius * _descriptor.glyphSize.width;
    frame.origin.y += radius * _descriptor.glyphSize.height;
    if (flipped) {
        frame.origin.y = _size.height - frame.origin.y - frame.size.height;
    }
    
    CGPoint min = CGPointMake(floor(CGRectGetMinX(frame)),
                              floor(CGRectGetMinY(frame)));
    CGPoint max = CGPointMake(ceil(CGRectGetMaxX(frame)),
                              ceil(CGRectGetMaxY(frame)));
    frame = CGRectMake(min.x, min.y, max.x - min.x, max.y - min.y);
    DLog(@"Bounding box for character '%@' in font %@ is %@ at scale %@", _string, _font, NSStringFromRect(frame), @(_descriptor.scale));

    return frame;
}

#pragma mark Drawing

- (void)drawWithOffset:(CGPoint)offset iteration:(NSInteger)iteration {
    CGAffineTransform textMatrix = CGContextGetTextMatrix(_context);
    CGContextSaveGState(_context);
    CFArrayRef runs = CTLineGetGlyphRuns(_lineRefs[iteration]);
    const CGFloat skew = _fakeItalic ? iTermFakeItalicSkew : 0;
    const CGFloat ty = offset.y - _descriptor.baselineOffset * _descriptor.scale;

    [self drawRuns:runs
          atOffset:CGPointMake(offset.x, ty)
              skew:skew
         iteration:iteration];
    _haveDrawn = YES;
    const NSUInteger length = CGBitmapContextGetBytesPerRow(_context) * CGBitmapContextGetHeight(_context);
    NSMutableData *data = [NSMutableData dataWithBytes:CGBitmapContextGetData(_context)
                                                length:length];
    [_datas addObject:data];
    CGContextRestoreGState(_context);
    CGContextSetTextMatrix(_context, textMatrix);
}

- (void)fillBackgroundForIteration:(NSInteger)iteration context:(CGContextRef)context {
    if (iTermTextIsMonochrome()) {
        CGContextSetRGBFillColor(context, 0, 0, 0, 0);
    } else {
        if (_isEmoji) {
            CGContextSetRGBFillColor(context, 1, 1, 1, 0);
        } else {
            CGContextSetRGBFillColor(context, 1, 1, 1, 1);
        }
    }
    CGRect rect = CGRectMake(0, 0, _size.width, _size.height);
    CGContextClearRect(context, rect);
    CGContextFillRect(context, rect);

#if ENABLE_DEBUG_CHARACTER_SOURCE_ALIGNMENT
    CGContextSetRGBStrokeColor(context, 1, 0, 0, 1);
    for (int x = 0; x < self.maxParts; x++) {
        for (int y = 0; y < self.maxParts; y++) {
            CGContextStrokeRect(context, CGRectMake(x * _descriptor.glyphSize.width,
                                                    y * _descriptor.glyphSize.height,
                                                    _descriptor.glyphSize.width,
                                                    _descriptor.glyphSize.height));
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

- (void)drawBackgroundIfNeededForIteration:(NSInteger)iteration
                                   context:(CGContextRef)context {
    if (iteration >= _nextIterationToDrawBackgroundFor) {
        _nextIterationToDrawBackgroundFor = iteration;
        [self fillBackgroundForIteration:iteration
                                 context:context];
    }
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

- (void)prepareToDrawRunAtIteration:(NSInteger)iteration
                             offset:(CGPoint)offset
                            runFont:(CTFontRef)runFont
                               skew:(CGFloat)skew
                        initialized:(BOOL)haveInitializedThisIteration {
    [self initializeStateIfNeededWithFont:runFont];

    CGContextRef context = _context;
    [self drawBackgroundIfNeededForIteration:iteration
                                     context:context];
    [self setTextColorForIteration:iteration
                           context:context];
    if (!haveInitializedThisIteration) {
        [self initializeIteration:iteration
                           offset:offset
                             skew:skew
                          context:context];
    }
}

- (void)drawBoxInContext:(CGContextRef)context offset:(CGPoint)offset iteration:(int)iteration {
    assert(context);
    [iTermBoxDrawingBezierCurveFactory drawCodeInCurrentContext:[_string characterAtIndex:0]
                                                       cellSize:NSMakeSize(_descriptor.cellSize.width * _descriptor.scale,
                                                                           _descriptor.cellSize.height * _descriptor.scale)
                                                           scale:_descriptor.scale
                                                          offset:offset
                                                          color:[self textColorForIteration:iteration]
                                                           useNativePowerlineGlyphs:_useNativePowerlineGlyphs];
}

- (void)drawBoxAtOffset:(CGPoint)offset iteration:(int)iteration {
    NSGraphicsContext *graphicsContext = [NSGraphicsContext graphicsContextWithCGContext:_context flipped:YES];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:graphicsContext];
    NSAffineTransform *transform = [NSAffineTransform transform];

    const CGFloat scaledCellHeight = _descriptor.cellSize.height * _descriptor.scale;
    const CGFloat scaledCellHeightWithoutSpacing = _descriptor.cellSizeWithoutSpacing.height * _descriptor.scale;
    const float verticalShift = round((scaledCellHeight - scaledCellHeightWithoutSpacing) / (2 * _descriptor.scale)) * _descriptor.scale;

    [transform translateXBy:offset.x yBy:offset.y + (_descriptor.baselineOffset + _descriptor.cellSize.height) * _descriptor.scale - verticalShift];
    [transform scaleXBy:1 yBy:-1];
    [transform concat];
    [self drawBoxInContext:_context offset:CGPointZero iteration:iteration];
    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawRuns:(CFArrayRef)runs
        atOffset:(CGPoint)offset
            skew:(CGFloat)skew
       iteration:(NSInteger)iteration {
    BOOL haveInitializedThisIteration = NO;
    for (CFIndex j = 0; j < CFArrayGetCount(runs); j++) {
        CTRunRef run = CFArrayGetValueAtIndex(runs, j);
        const size_t length = CTRunGetGlyphCount(run);
        const CGGlyph *buffer = [self glyphsInRun:run length:length];
        CGPoint *positions = [self positionsInRun:run length:length];
        CTFontRef runFont = CFDictionaryGetValue(CTRunGetAttributes(run), kCTFontAttributeName);

        [self prepareToDrawRunAtIteration:iteration offset:offset runFont:runFont skew:skew initialized:haveInitializedThisIteration];
        haveInitializedThisIteration = YES;
        CGContextRef context = _context;

        if (_boxDrawing) {
            [self drawBoxAtOffset:offset
                        iteration:iteration];
        } else if (_isEmoji) {
            [self drawEmojiWithFont:runFont
                             offset:offset
                             buffer:buffer
                          positions:positions
                             length:length
                          iteration:iteration
                            context:context];
        } else {
            CTFontDrawGlyphs(runFont, buffer, (NSPoint *)positions, length, context);

            if (_fakeBold) {
                [self initializeTextMatrixInContext:context
                                           withSkew:skew
                                             offset:CGPointMake(offset.x + self.fakeBoldShift * _descriptor.scale,
                                                                offset.y)];
                CTFontDrawGlyphs(runFont, buffer, (NSPoint *)positions, length, context);
            }

#if ENABLE_DEBUG_CHARACTER_SOURCE_ALIGNMENT
            CGContextSetRGBStrokeColor(_contexts[iteration], 0, 0, 1, 1);
            CGContextStrokeRect(_contexts[iteration], CGRectMake(offset.x + positions[0].x,
                                                                 offset.y + positions[0].y,
                                                                 _descriptor.glyphSize.width,
                                                                 _descriptor.glyphSize.height));

            CGContextSetRGBStrokeColor(_contexts[iteration], 1, 0, 1, 1);
            CGContextStrokeRect(_contexts[iteration], CGRectMake(offset.x,
                                                                 offset.y,
                                                                 _descriptor.glyphSize.width,
                                                                 _descriptor.glyphSize.height));
#endif
        }
    }
}

- (NSColor *)textColorForIteration:(NSInteger)iteration {
    if (iTermTextIsMonochrome()) {
        switch (iteration) {
            case 0:
                return [NSColor colorWithSRGBRed:0 green:0 blue:0 alpha:1];
            case 1:
                return [NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1];
            case 2:
                return [NSColor colorWithSRGBRed:0 green:1 blue:0 alpha:1];
            case 3:
                return [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:1];
        }
        ITAssertWithMessage(NO, @"bogus iteration %@", @(iteration));
    }
    return [NSColor blackColor];
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
        CGAffineTransform textMatrix = CGAffineTransformMake(_descriptor.scale,        0.0,
                                                             skew * _descriptor.scale, _descriptor.scale,
                                                             offset.x,                 offset.y);
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
    CGContextScaleCTM(context, _descriptor.scale, _descriptor.scale);
}

- (NSDictionary *)attributesForIteration:(NSInteger)iteration {
    static NSMutableParagraphStyle *paragraphStyle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.lineBreakMode = NSLineBreakByClipping;
        paragraphStyle.tabStops = @[];
        paragraphStyle.baseWritingDirection = NSWritingDirectionLeftToRight;
    });
    return @{ (NSString *)kCTLigatureAttributeName: @0,
              (NSString *)kCTForegroundColorAttributeName: (id)[self textColorForIteration:iteration],
              NSFontAttributeName: _font,
              NSParagraphStyleAttributeName: paragraphStyle };
}

@end
