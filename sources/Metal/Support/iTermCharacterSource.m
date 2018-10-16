//
//  iTermCharacterSource.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/26/17.
//

#import <Cocoa/Cocoa.h>

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "iTermCharacterBitmap.h"
#import "iTermCharacterParts.h"
#import "iTermCharacterSource.h"
#import "iTermData.h"
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

@interface iTermBitmapContextPool : NSObject
+ (instancetype)sharedInstance;
- (CGContextRef)allocateBitmapContextOfSize:(CGSize)size;
- (void)deallocateBitmapContext:(CGContextRef)context;
@end

@implementation iTermBitmapContextPool {
    CGSize _size;
    NSMutableArray *_array;
}

+ (instancetype)sharedInstance {
    NSMutableDictionary *threadDict = [[NSThread currentThread] threadDictionary];
    NSString *key = @"iTermBitmapContextPool";
    id instance = threadDict[key];
    if (instance) {
        return instance;
    }

    instance = [[self alloc] init];
    ITAssertWithMessage(instance, @"-[iTermBitmapContextPool init] returned nil");
    threadDict[key] = instance;
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _array = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [self releaseAllContexts];
}

- (void)releaseAllContexts {
    [_array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        CGContextRef context = (__bridge CGContextRef)(obj);
        CGContextRelease(context);
    }];
    [_array removeAllObjects];
}

+ (CGColorSpaceRef)colorSpace {
    static dispatch_once_t onceToken;
    static CGColorSpaceRef colorSpace;
    dispatch_once(&onceToken, ^{
        colorSpace = CGColorSpaceCreateDeviceRGB();
        ITAssertWithMessage(colorSpace, @"Colorspace is %@", colorSpace);
    });
    return colorSpace;
}

- (CGContextRef)allocateBitmapContextOfSize:(CGSize)size {
    CGContextRef context = [self internalAllocateBitmapContextOfSize:size];
    ITAssertWithMessage(context, @"nil context with size %@", NSStringFromSize(size));
    CGContextSaveGState(context);
    return context;
}

- (void)deallocateBitmapContext:(CGContextRef)context {
    CGSize size = CGSizeMake(CGBitmapContextGetWidth(context),
                             CGBitmapContextGetHeight(context));
    if (!CGSizeEqualToSize(size, _size)) {
        CGContextRelease(context);
        return;
    }
    
    CGContextRestoreGState(context);
    [_array addObject:(__bridge id _Nonnull)(context)];
}

- (CGContextRef)internalAllocateBitmapContextOfSize:(CGSize)size {
    if (!CGSizeEqualToSize(size, _size)) {
        [self releaseAllContexts];
        _size = size;
    }
    if (_array.count) {
        CGContextRef first = (__bridge CGContextRef)(_array.firstObject);
        [_array removeObjectAtIndex:0];
        ITAssertWithMessage(first, @"first array element is nil. Array length is now %@", @(_array.count));
        return first;
    }
    ITAssertWithMessage(size.width > 0, @"size is %@", NSStringFromSize(size));
    ITAssertWithMessage(size.width * 4 > 0, @"size is %@", NSStringFromSize(size));
    ITAssertWithMessage(size.height > 0, @"size is %@", NSStringFromSize(size));
    CGContextRef context = CGBitmapContextCreate(NULL,
                                                 size.width,
                                                 size.height,
                                                 8,
                                                 size.width * 4,
                                                 [iTermBitmapContextPool colorSpace],
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    ITAssertWithMessage(context, @"nil CGContextRef. size is %@. colorspace is %@", NSStringFromSize(size), [iTermBitmapContextPool colorSpace]);
    return context;
}
@end

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
    CTLineRef _lineRefs[4];
    CGContextRef _contexts[4];

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
}

+ (CGContextRef)newBitmapContextOfSize:(CGSize)size {
    iTermBitmapContextPool *pool = [iTermBitmapContextPool sharedInstance];
    assert(pool);
    return [pool allocateBitmapContextOfSize:size];
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
    assert(font);
    assert(size.width > 0);
    assert(size.height > 0);
    assert(scale > 0);

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

        for (int i = 0; i < 4; i++) {
            _attributedStrings[i] = [[NSAttributedString alloc] initWithString:string attributes:[self attributesForIteration:i]];
            _lineRefs[i] = CTLineCreateWithAttributedString((CFAttributedStringRef)_attributedStrings[i]);
        }
        _antialiased = antialiased;
    }
    return self;
}

- (void)dealloc {
    for (NSInteger i = 0; i < _numberOfIterationsNeeded; i++) {
        CGContextRef context = [self contextForIteration:i];
        if (context) {
            [[iTermBitmapContextPool sharedInstance] deallocateBitmapContext:context];
            _contexts[i] = NULL;
        }
    }
    for (NSInteger i = 0; i < 4; i++) {
        if (_lineRefs[i]) {
            CFRelease(_lineRefs[i]);
        }
    }
    if (_imageRef) {
        CGImageRelease(_imageRef);
    }
}

- (CGContextRef)contextForIteration:(NSInteger)iteration {
    ITAssertWithMessage(iteration >= 0 && iteration < 4, @"requested iteration %@ out of %@", @(iteration), @(_numberOfIterationsNeeded));
    ITAssertWithMessage(iteration < _numberOfIterationsNeeded, @"requested iteration %@ out of %@", @(iteration), @(_numberOfIterationsNeeded));
    CGContextRef context = _contexts[iteration];
    ITAssertWithMessage(context, @"nil context for iteration %@/%@", @(iteration), @(_numberOfIterationsNeeded));
    return context;
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
        CGContextRef context = [self contextForIteration:i];
        data[i] = (unsigned char *)CGBitmapContextGetData(context);

        // Sanity checks to ensure we don't traipse off the end of the allocated region.
        const size_t bytesPerRow = CGBitmapContextGetBytesPerRow(context);
        ITAssertWithMessage(bytesPerRow >= _size.width * 4, @"bytesPerRow is %@ too big for size %@", @(bytesPerRow), NSStringFromSize(_size));
        const size_t height = CGBitmapContextGetHeight(context);
        ITAssertWithMessage(height >= _size.height, @"bitmap height is %@ for context %@, too big for size %@", @(height), context, NSStringFromSize(_size));
    }

    // i indexes into the array of pixels, always to the red value.
    for (int i = 0 ; i < _size.height * _size.width * 4; i += 4) {
        // j indexes a destination color component and a source bitmap.
        for (int j = 0; j < 4; j++) {
            destination[i + j] = data[j][i + 3];
        }
    }
    _postprocessed = YES;
}

- (iTermCharacterBitmap *)bitmapForPart:(int)part {
    [self drawIfNeeded];
    const int radius = _radius;
    const int dx = iTermImagePartDX(part) + radius;
    const int dy = iTermImagePartDY(part) + radius;
    const size_t sourceRowSize = _size.width * 4;
    const size_t destRowSize = _partSize.width * 4;
    const NSUInteger length = destRowSize * _partSize.height;

    if (iTermTextIsMonochrome()) {
        if (!_postprocessed && !_isEmoji) {
            [self performPostProcessing];
        }
    }
    const unsigned char *bitmapBytes = _postprocessedData.bytes;
    if (!bitmapBytes) {
        bitmapBytes = (const unsigned char *)CGBitmapContextGetData([self contextForIteration:0]);
    }

#if ENABLE_DEBUG_CHARACTER_SOURCE_ALIGNMENT
    if (saveBitmapsForDebugging) {
        NSImage *image = [NSImage imageWithRawData:[NSData dataWithBytes:bitmapBytes length:bitmap.data.length]
                                              size:_partSize
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
#endif

    iTermCharacterBitmap *bitmap = [[iTermCharacterBitmap alloc] init];
    bitmap.data = [NSMutableData uninitializedDataWithLength:length];
    bitmap.size = _partSize;

    char *dest = (char *)bitmap.data.mutableBytes;

    // Flip vertically and copy. The vertical flip is for historical reasons
    // (i.e., if I had more time I'd undo it but it's annoying because there
    // are assumptions about vertical flipping all over the fragment shader).
    size_t destOffset = (_partSize.height - 1) * destRowSize;
    size_t sourceOffset = (dx * 4 * _partSize.width) + (dy * _partSize.height * sourceRowSize);
    for (int i = 0; i < _partSize.height; i++) {
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

- (void)drawIfNeeded {
    if (!_haveDrawn) {
        NSInteger iteration = 0;
        do {
            const int radius = _radius;
            // This has the side-effect of setting _numberOfIterationsNeeded
            [self drawWithOffset:CGPointMake(_partSize.width * radius,
                                             _partSize.height * radius)
                       iteration:iteration];
            iteration += 1;
        } while (iteration < _numberOfIterationsNeeded);
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

    CGRect frame = CTLineGetImageBounds(_lineRefs[0], cgContext);
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

- (void)drawWithOffset:(CGPoint)offset iteration:(NSInteger)iteration {
    CFArrayRef runs = CTLineGetGlyphRuns(_lineRefs[iteration]);
    const CGFloat skew = _fakeItalic ? iTermFakeItalicSkew : 0;
    const CGFloat ty = offset.y - _baselineOffset * _scale;

    [self drawRuns:runs
          atOffset:CGPointMake(offset.x, ty)
              skew:skew
         iteration:iteration];
    _haveDrawn = YES;
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
            CGContextStrokeRect(context, CGRectMake(x * _partSize.width,
                                                    y * _partSize.height,
                                                    _partSize.width, _partSize.height));
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
    for (int i = 0; i < _numberOfIterationsNeeded; i++) {
        ITAssertWithMessage(_contexts[i] == NULL, @"context %@/%@ leaking", @(i), @(_numberOfIterationsNeeded));
        _contexts[i] = [iTermCharacterSource newBitmapContextOfSize:_size];
        ITAssertWithMessage(_contexts[i], @"context %@/%@ is null for size %@", @(i), @(_numberOfIterationsNeeded), NSStringFromSize(_size));
    }
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

    BOOL shouldSmooth = _useThinStrokes;
    int style = -1;
    if (iTermTextIsMonochrome()) {
        if (_useThinStrokes) {
            shouldSmooth = NO;
        } else {
            shouldSmooth = YES;
        }
    } else {
        // User enabled subpixel AA
        shouldSmooth = YES;
    }
    if (shouldSmooth) {
        if (_useThinStrokes) {
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

    [self initializeTextMatrixInContext:context
                               withSkew:skew
                                 offset:offset];
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

        [self initializeStateIfNeededWithFont:runFont];
        CGContextRef context = [self contextForIteration:iteration];
        [self drawBackgroundIfNeededForIteration:iteration
                                         context:context];
        [self setTextColorForIteration:iteration
                               context:context];
        if (!haveInitializedThisIteration) {
            [self initializeIteration:iteration
                               offset:offset
                                 skew:skew
                              context:context];
            haveInitializedThisIteration = YES;
        }

        if (_isEmoji) {
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
                                             offset:CGPointMake(offset.x + self.fakeBoldShift * _scale,
                                                                offset.y)];
                CTFontDrawGlyphs(runFont, buffer, (NSPoint *)positions, length, context);
            }

#if ENABLE_DEBUG_CHARACTER_SOURCE_ALIGNMENT
            CGContextSetRGBStrokeColor(_contexts[iteration], 0, 0, 1, 1);
            CGContextStrokeRect(_contexts[iteration], CGRectMake(offset.x + positions[0].x,
                                                                   offset.y + positions[0].y,
                                                                   _partSize.width, _partSize.height));

            CGContextSetRGBStrokeColor(_contexts[iteration], 1, 0, 1, 1);
            CGContextStrokeRect(_contexts[iteration], CGRectMake(offset.x,
                                                                   offset.y,
                                                                   _partSize.width, _partSize.height));
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
    CGContextSaveGState(context);
    // You have to use the CTM with emoji. CGContextSetTextMatrix doesn't work.
    [self initializeCTMWithFont:runFont offset:offset iteration:iteration context:context];

    CTFontDrawGlyphs(runFont, buffer, (NSPoint *)positions, length, context);

    CGContextRestoreGState(context);
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
    CGContextScaleCTM(context, _scale, _scale);
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
