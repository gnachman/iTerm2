//
//  iTermCharacterSource.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/26/17.
//

#import <Cocoa/Cocoa.h>

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermBoxDrawingBezierCurveFactory.h"
#import "iTermCharacterBitmap.h"
#import "iTermCharacterParts.h"
#import "iTermCharacterSource.h"
#import "iTermData.h"
#import "iTermTextureArray.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
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
@property (nonatomic, readwrite, strong) iTermFontTable *fontTable;
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

@interface iTermRegularCharacterSource: iTermCharacterSource
@end

@interface iTermGlyphCharacterSource: iTermCharacterSource
@end

@implementation iTermCharacterSource {
@protected
    iTermCharacterSourceDescriptor *_descriptor;
    iTermCharacterSourceAttributes *_attributes;
    BOOL _antialiased;
    BOOL _fakeBold;
    BOOL _fakeItalic;
    NSFont *_font;

    // Large enough to hold glyphSize * maxParts in both horizontal and vertical direction.
    CGSize _size;
    BOOL _postprocessed NS_AVAILABLE_MAC(10_14);

    CGContextRef _context;
    // These have size _bytesPerRow * _numberOfRows.
    NSMutableArray<NSMutableData *> *_datas;

    NSImage *_image;
    BOOL _haveDrawn;
    NSArray<NSNumber *> *_parts;
    int _radius;

    // If true then _isEmoji is valid.
    BOOL _haveTestedForEmoji;
    NSInteger _nextIterationToDrawBackgroundFor;
    NSInteger _numberOfIterationsNeeded;
    iTermBitmapData *_postprocessedData;
    // These metrics are for _context.
    NSInteger _bytesPerRow;
    NSInteger _numberOfRows;

    BOOL _isEmoji;
    BOOL _debug;
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
                       context:(CGContextRef)context {
    return [[iTermGlyphCharacterSource alloc] initWithFontID:fontID
                                                    fakeBold:fakeBold
                                                  fakeItalic:fakeItalic
                                                 glyphNumber:glyphNumber
                                                    position:position
                                                  descriptor:descriptor
                                                  attributes:attributes
                                                      radius:radius
                                                     context:context];
}

- (instancetype)initWithCharacter:(NSString *)string
                       descriptor:(iTermCharacterSourceDescriptor *)descriptor
                       attributes:(iTermCharacterSourceAttributes *)attributes
                       boxDrawing:(BOOL)boxDrawing
                           radius:(int)radius
         useNativePowerlineGlyphs:(BOOL)useNativePowerlineGlyphs
                          context:(CGContextRef)context {
    return [[iTermRegularCharacterSource alloc] initWithCharacter:string
                                                       descriptor:descriptor
                                                       attributes:attributes
                                                       boxDrawing:boxDrawing
                                                           radius:radius
                                         useNativePowerlineGlyphs:useNativePowerlineGlyphs
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

- (void)drawWithOffset:(CGPoint)offset iteration:(NSInteger)iteration {
    CGAffineTransform textMatrix = CGContextGetTextMatrix(_context);
    CGContextSaveGState(_context);
    const CGFloat skew = _fakeItalic ? iTermFakeItalicSkew : 0;
    const CGFloat ty = offset.y - _descriptor.baselineOffset * _descriptor.scale;

    [self drawIteration:iteration
               atOffset:CGPointMake(offset.x, ty)
                   skew:skew];
    _haveDrawn = YES;
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
        CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, kUTTypePNG, 1, NULL);
        CGImageDestinationAddImage(destination, imageRef, nil);

        if (!CGImageDestinationFinalize(destination)) {
            NSLog(@"Failed to write image to /tmp/image.png");
        }

        // Clean up
        CFRelease(destination);
        CGImageRelease(imageRef);
    }
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

- (void)prepareToDrawIteration:(NSInteger)iteration
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
    DLog(@"%@ Bounding box for character '%@' in font %@ is %@ at scale %@",
         self, self.debugName, _font, NSStringFromRect(frame), @(_descriptor.scale));

    return frame;
}

@end

@implementation iTermGlyphCharacterSource {
    unsigned short _glyphNumber;
    NSPoint _position;
}

- (instancetype)initWithFontID:(unsigned int)fontID
                      fakeBold:(BOOL)fakeBold
                    fakeItalic:(BOOL)fakeItalic
                   glyphNumber:(unsigned short)glyphNumber
                      position:(NSPoint)position
                    descriptor:(iTermCharacterSourceDescriptor *)descriptor
                    attributes:(iTermCharacterSourceAttributes *)attributes
                        radius:(int)radius
                       context:(CGContextRef)context {
    NSFont *font = [NSFont it_fontWithMetalID:fontID];
    if (!font) {
        return nil;
    }
    self = [super initWithFont:font
                      fakeBold:fakeBold
                    fakeItalic:fakeItalic
                   antialiased:descriptor.nonAsciiAntiAliased
                    descriptor:descriptor
                    attributes:attributes
                        radius:radius
                       context:context];
    if (self) {
        _glyphNumber = glyphNumber;
        _position = position;
    }
    return self;
}

- (void)drawIteration:(NSInteger)iteration atOffset:(CGPoint)offset skew:(CGFloat)skew {
    [self prepareToDrawIteration:iteration
                          offset:offset
                         runFont:(__bridge CTFontRef)_font
                            skew:skew
                     initialized:NO];
    CGGlyph glyph = _glyphNumber;
    CGPoint position = _position;
    CTFontDrawGlyphs((__bridge CTFontRef)_font,
                     &glyph,
                     &position,
                     1,
                     _context);
    if (_fakeBold) {
        [self initializeTextMatrixInContext:_context
                                   withSkew:skew
                                     offset:CGPointMake(offset.x + self.fakeBoldShift * _descriptor.scale,
                                                        offset.y)];
        CTFontDrawGlyphs((__bridge CTFontRef)_font,
                         &glyph,
                         &position,
                         1,
                         _context);
    }
}

- (NSString *)debugName {
    return [NSString stringWithFormat:@"glyph-%@", @(_glyphNumber)];
}

- (CGSize)desiredOffset {
    return CGSizeZero;
}

- (CGRect)frameFlipped:(BOOL)flipped {
    CGGlyph glyph = _glyphNumber;
    const CGRect bounds = CTFontGetBoundingRectsForGlyphs((__bridge CTFontRef)_font,
                                                          kCTFontOrientationDefault,
                                                          &glyph,
                                                          NULL,
                                                          1);
    return [self frameForBoundingRect:bounds flipped:flipped];
}

@end

@implementation iTermRegularCharacterSource {
    NSString *_string;
    BOOL _boxDrawing;
    BOOL _useNativePowerlineGlyphs;

    CTLineRef _lineRefs[4];

    NSAttributedString *_attributedStrings[4];
    NSMutableData *_glyphsData;
    NSMutableData *_positionsBuffer;

    BOOL _isAscii;
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

    UTF32Char remapped = 0;
    BOOL fakeBold = attributes.bold;
    BOOL fakeItalic = attributes.italic;
    NSFont *font = [descriptor.fontTable fontForCharacter:[string longCharacterAtIndex:0]
                                              useBoldFont:descriptor.useBoldFont
                                            useItalicFont:descriptor.useItalicFont
                                               renderBold:&fakeBold
                                             renderItalic:&fakeItalic
                                                 remapped: &remapped].font;
    const BOOL isAscii = (string.length == 1 && [string characterAtIndex:0] < 128);

    self = [super initWithFont:font
                      fakeBold:fakeBold
                    fakeItalic:fakeItalic
                   antialiased:isAscii ? descriptor.asciiAntiAliased : descriptor.nonAsciiAntiAliased
                    descriptor:descriptor
                    attributes:attributes
                        radius:radius
                       context:context];
    // This is an appropriate place to set _debug to YES.
    if (self) {
        if (remapped) {
            string = [string stringByReplacingBaseCharacterWith:remapped];
        }

        _string = [string copy];
        _isAscii = isAscii;
        DLog(@"%p initialize with descriptor %@, isAscii=%@", self, descriptor, @(_isAscii));

        ITAssertWithMessage(descriptor.fontTable, @"Nil font table for string=%@ attributes=%@", string, attributes);
        _boxDrawing = boxDrawing;
        _useNativePowerlineGlyphs = useNativePowerlineGlyphs;

        for (int i = 0; i < 4; i++) {
            _attributedStrings[i] = [[NSAttributedString alloc] initWithString:string attributes:[self attributesForIteration:i]];
            DLog(@"Create lineref %@ with attributed string %@", @(i), _attributedStrings[i]);
            _lineRefs[i] = CTLineCreateWithAttributedString((CFAttributedStringRef)_attributedStrings[i]);
        }
    }
    return self;
}

- (void)dealloc {
    for (NSInteger i = 0; i < 4; i++) {
        if (_lineRefs[i]) {
            CFRelease(_lineRefs[i]);
        }
    }
}

#pragma mark - APIs

- (NSString *)debugName {
    return _string;
}

#pragma mark Lazy Computations

- (CGSize)desiredOffset {
    if (_isAscii) {
        return _descriptor.asciiOffset;
    } else {
        return CGSizeZero;
    }
}

- (CGRect)frameFlipped:(BOOL)flipped {
    if (_string.length == 0) {
        return CGRectZero;
    }
    if (_boxDrawing) {
        // yOffset should equal offset.y in drawWithOffset:iteration:
        const CGFloat yOffset = _descriptor.glyphSize.height * _radius;

        // ty should equal ty in drawWithOffset:iteration:
        const CGFloat ty = yOffset - _descriptor.baselineOffset * _descriptor.scale;

        // y should equal rect.origin.y in drawBoxAtOffset:iteration:
        const CGFloat y = ty + _descriptor.baselineOffset * _descriptor.scale - self.verticalShift;

        NSRect rect = NSMakeRect(_descriptor.glyphSize.width * _radius,
                                 y,
                                 _descriptor.cellSize.width * _descriptor.scale,
                                 _descriptor.cellSize.height * _descriptor.scale);
        if (_string.length > 0 &&
            _useNativePowerlineGlyphs &&
            [iTermBoxDrawingBezierCurveFactory isDoubleWidthPowerlineGlyph:[_string characterAtIndex:0]]) {
            rect.size.width *= 2;
        }
        if (flipped) {
            rect.origin.y = _size.height - rect.origin.y - rect.size.height;
        }
        return rect;
    }

    CGContextRef cgContext = _context;
    CGRect frame = CTLineGetImageBounds(_lineRefs[0], cgContext);
    return [self frameForBoundingRect:frame flipped:flipped];
}

#pragma mark Drawing

- (void)drawIteration:(NSInteger)iteration atOffset:(CGPoint)offset skew:(CGFloat)skew {
    CFArrayRef runs = CTLineGetGlyphRuns(_lineRefs[iteration]);

    [self drawRuns:runs
          atOffset:offset
              skew:skew
         iteration:iteration];
}

- (void)drawBoxInContext:(CGContextRef)context iteration:(int)iteration {
    assert(context);
    CGFloat systemScale = [NSImage systemScale];
    if (systemScale < 1) {
        systemScale = 1.0;
    }
    DLog(@"Draw box %@ at scale %@ with systemScale=%@ mainScreen=%@. descriptor=%@",
         _string, @(_descriptor.scale), @(systemScale), [[NSScreen mainScreen] it_uniqueName], _descriptor);
    [iTermBoxDrawingBezierCurveFactory drawCodeInCurrentContext:[_string characterAtIndex:0]
                                                       cellSize:NSMakeSize(_descriptor.cellSize.width * _descriptor.scale,
                                                                           _descriptor.cellSize.height * _descriptor.scale)
                                                           scale:_descriptor.scale
                                                       isPoints:NO
                                                          offset:CGPointZero
                                                          color:[[self textColorForIteration:iteration] CGColor]
                                                           useNativePowerlineGlyphs:_useNativePowerlineGlyphs];
}

// NOTE: This must match the logic in -[iTermTextRendererTransientState setGlyphKeysData:…] where
// verticalShift is computed.
- (CGFloat)verticalShift {
    const CGFloat cellHeight = (_descriptor.cellSize.height * _descriptor.scale);
    const CGFloat cellHeightWithoutSpacing = _descriptor.cellSizeWithoutSpacing.height * _descriptor.scale;
    const CGFloat scale = _descriptor.scale;

    return round((cellHeight - cellHeightWithoutSpacing) / (2 * scale)) * scale;
}

- (void)drawBoxAtOffset:(CGPoint)offset iteration:(int)iteration {
    NSGraphicsContext *graphicsContext = [NSGraphicsContext graphicsContextWithCGContext:_context flipped:YES];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:graphicsContext];
    NSAffineTransform *transform = [NSAffineTransform transform];

    NSRect rect = NSMakeRect(offset.x,
                             offset.y + _descriptor.baselineOffset * _descriptor.scale - self.verticalShift,
                             _descriptor.cellSize.width * _descriptor.scale,
                             _descriptor.cellSize.height * _descriptor.scale);
    if (_debug) {
        [[NSColor whiteColor] set];
        NSFrameRect(rect);
        NSBezierPath *diag = [NSBezierPath bezierPath];
        [diag moveToPoint:rect.origin];
        [diag lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
        [diag stroke];
    }

    [transform translateXBy:NSMinX(rect)
                        yBy:NSMaxY(rect)];
    [transform scaleXBy:1 yBy:-1];
    [transform concat];
    [self drawBoxInContext:_context iteration:iteration];

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
        DLog(@"%@ For run %@, run is %@ and runFont is %@", self, @(j), run, runFont);
        [self prepareToDrawIteration:iteration
                              offset:offset
                             runFont:runFont
                                skew:skew
                         initialized:haveInitializedThisIteration];
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
        }

#if ENABLE_DEBUG_CHARACTER_SOURCE_ALIGNMENT
            CGContextSetRGBStrokeColor(context, 0, 0, 1, 1);
            CGContextStrokeRect(context, CGRectMake(offset.x + positions[0].x,
                                                                 offset.y + positions[0].y,
                                                                 _descriptor.glyphSize.width,
                                                                 _descriptor.glyphSize.height));

            CGContextSetRGBStrokeColor(context, 1, 0, 1, 1);
            CGContextStrokeRect(context, CGRectMake(offset.x,
                                                                 offset.y,
                                                                 _descriptor.glyphSize.width,
                                                                 _descriptor.glyphSize.height));
#endif
    }
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
