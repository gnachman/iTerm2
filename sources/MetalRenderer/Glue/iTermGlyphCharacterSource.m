//
//  iTermGlyphCharacterSource.m
//  iTerm2
//
//  Created by George Nachman on 2/26/25.
//

#import <Cocoa/Cocoa.h>

#import "iTermGlyphCharacterSource.h"
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

@implementation iTermGlyphCharacterSource {
    unsigned short _glyphNumber;
    NSPoint _position;
    iTermLineAttribute _lineAttribute;
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
        _lineAttribute = lineAttribute;
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
    if (_isEmoji) {
        [self drawEmojiWithFont:(__bridge CTFontRef)_font
                         offset:offset
                         buffer:&glyph
                      positions:&position
                         length:1
                      iteration:iteration
                        context:_context];
    } else {
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
}

- (NSString *)debugName {
    return [NSString stringWithFormat:@"glyph-%@", @(_glyphNumber)];
}

- (CGSize)desiredOffset {
    return CGSizeZero;
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

- (CGRect)frameFlipped:(BOOL)flipped {
    CGGlyph glyph = _glyphNumber;
    const CGRect bounds = CTFontGetBoundingRectsForGlyphs((__bridge CTFontRef)_font,
                                                          kCTFontOrientationDefault,
                                                          &glyph,
                                                          NULL,
                                                          1);
    const CGRect adjustedBounds = CGRectOffset(bounds, _position.x, _position.y);
    CGRect result = [self frameForBoundingRect:adjustedBounds flipped:flipped];
    if (iTermLineAttributeIsDoubleWidth(_lineAttribute)) {
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

@end

