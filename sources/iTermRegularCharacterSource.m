//
//  iTermRegularCharacterSource.m
//  iTerm2
//
//  Created by George Nachman on 2/26/25.
//

#import <Cocoa/Cocoa.h>

#import "iTermRegularCharacterSource.h"
#import "iTermCharacterSource+Private.h"

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

@implementation iTermRegularCharacterSource {
    NSString *_string;
    BOOL _boxDrawing;
    BOOL _useNativePowerlineGlyphs;
    iTermLineAttribute _lineAttribute;

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
                    lineAttribute:(iTermLineAttribute)lineAttribute
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
        _lineAttribute = lineAttribute;

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
    if (_isAscii && !iTermLineAttributeIsDoubleWidth(_lineAttribute)) {
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

        // y should equal boxY in drawBoxAtOffset:iteration:
        CGFloat y = ty + _descriptor.baselineOffset * _descriptor.scale - self.verticalShift;
        if (_lineAttribute == iTermLineAttributeDoubleHeightTop) {
            y += (_descriptor.cellSize.height + _descriptor.baselineOffset) * _descriptor.scale;
            y -= _descriptor.cellSize.height * _descriptor.scale;
        } else if (_lineAttribute == iTermLineAttributeDoubleHeightBottom) {
            y += _descriptor.baselineOffset * _descriptor.scale;
        }

        const CGFloat vScale = [self drawVScale];
        NSRect rect = NSMakeRect(_descriptor.glyphSize.width * _radius,
                                 y,
                                 _descriptor.cellSize.width * _descriptor.scale,
                                 _descriptor.cellSize.height * _descriptor.scale * vScale);
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

    // Temporarily remove any CTM scale so CTLineGetImageBounds returns
    // unscaled bounds. We apply hScale/vScale manually below because the
    // CTM is only set during drawing, not when newParts calls this.
    // TODO: Is this step actually needed?
    CGContextSaveGState(_context);
    CGContextConcatCTM(_context, CGAffineTransformInvert(CGContextGetCTM(_context)));
    CGRect frame = CTLineGetImageBounds(_lineRefs[0], _context);
    CGContextRestoreGState(_context);

    CGRect result = [self frameForBoundingRect:frame flipped:flipped];
    if (iTermLineAttributeIsDoubleWidth(_lineAttribute)) {
        // Expand around the unshifted text origin for the horizontal DWL
        // scaling and (for DECDHL) the vertical scaling.
        const CGFloat pivotX = _descriptor.glyphSize.width * _radius;
        const CGFloat tyUnflipped = _descriptor.glyphSize.height * _radius - _descriptor.baselineOffset * _descriptor.scale;
        const CGFloat pivotY = flipped ? (_size.height - tyUnflipped) : tyUnflipped;
        const CGFloat hScale = 2.0;
        const CGFloat vScale = (_lineAttribute == iTermLineAttributeDoubleHeightTop ||
                                _lineAttribute == iTermLineAttributeDoubleHeightBottom) ? 2.0 : 1.0;
        result = CGRectMake(pivotX + (result.origin.x - pivotX) * hScale,
                            pivotY + (result.origin.y - pivotY) * vScale,
                            result.size.width * hScale,
                            result.size.height * vScale);
        if (_lineAttribute == iTermLineAttributeDoubleHeightTop) {
            const CGFloat shift = (_descriptor.cellSize.height + _descriptor.baselineOffset) * _descriptor.scale;
            result.origin.y += flipped ? shift : -shift;
        } else if (_lineAttribute == iTermLineAttributeDoubleHeightBottom) {
            const CGFloat shift = _descriptor.baselineOffset * _descriptor.scale;
            result.origin.y += flipped ? shift : -shift;
        }
    }
    return result;
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
    const CGFloat vScale = [self drawVScale];
    [iTermBoxDrawingBezierCurveFactory drawCodeInCurrentContext:[_string longCharacterAtIndex:0]
                                                       cellSize:NSMakeSize(_descriptor.cellSize.width * _descriptor.scale,
                                                                           _descriptor.cellSize.height * _descriptor.scale * vScale)
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

    const CGFloat vScale = [self drawVScale];
    // For box drawing, position the rect at the cell boundary rather than
    // using the DECDHL text-offset. The offset already includes the DECDHL
    // ty shift meant for text rendering; undo it and use the raw cell origin.
    // The rect is drawn in a flipped context so the vertical direction is
    // reversed: shifting the rect DOWN in CG coords shows the TOP half.
    CGFloat boxY = offset.y + _descriptor.baselineOffset * _descriptor.scale - self.verticalShift;
    if (_lineAttribute == iTermLineAttributeDoubleHeightTop) {
        // Undo the top shift, then move down by one cell so the top half
        // of the 2x box lands in the clipped center row (flipped context).
        boxY += (_descriptor.cellSize.height + _descriptor.baselineOffset) * _descriptor.scale;
        boxY -= _descriptor.cellSize.height * _descriptor.scale;
    } else if (_lineAttribute == iTermLineAttributeDoubleHeightBottom) {
        // Undo the bottom shift.
        boxY += _descriptor.baselineOffset * _descriptor.scale;
    }
    NSRect rect = NSMakeRect(offset.x,
                             boxY,
                             _descriptor.cellSize.width * _descriptor.scale,
                             _descriptor.cellSize.height * _descriptor.scale * vScale);
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

- (iTermLineAttribute)lineAttribute {
    return _lineAttribute;
}

- (CGFloat)drawHScale {
    if (iTermLineAttributeIsDoubleWidth(_lineAttribute)) {
        return 2.0;
    }
    return 1.0;
}

- (CGFloat)drawVScale {
    if (_lineAttribute == iTermLineAttributeDoubleHeightTop ||
        _lineAttribute == iTermLineAttributeDoubleHeightBottom) {
        return 2.0;
    }
    return 1.0;
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
