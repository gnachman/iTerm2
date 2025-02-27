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

