//
//  iTermCharacterSource+Private.h
//  iTerm2
//
//  Created by George Nachman on 2/26/25.
//

#import "iTermCharacterSource.h"

@interface iTermCharacterSource () {
@protected
    NSFont *_font;
    CGContextRef _context;
    BOOL _fakeBold;
    iTermCharacterSourceDescriptor *_descriptor;
    BOOL _debug;
    BOOL _isEmoji;
    int _radius;
    CGSize _size;
}

- (instancetype)initWithFont:(NSFont *)font
                    fakeBold:(BOOL)fakeBold
                  fakeItalic:(BOOL)fakeItalic
                 antialiased:(BOOL)antialiased
                  descriptor:(iTermCharacterSourceDescriptor *)descriptor
                  attributes:(iTermCharacterSourceAttributes *)attributes
                      radius:(int)radius
                     context:(CGContextRef)context;

- (void)prepareToDrawIteration:(NSInteger)iteration
                        offset:(CGPoint)offset
                       runFont:(CTFontRef)runFont
                          skew:(CGFloat)skew
                   initialized:(BOOL)haveInitializedThisIteration;

- (void)initializeTextMatrixInContext:(CGContextRef)cgContext
                             withSkew:(CGFloat)skew
                               offset:(CGPoint)offset;
- (void)initializeCTMWithFont:(CTFontRef)runFont
                       offset:(CGPoint)offset
                    iteration:(NSInteger)iteration
                      context:(CGContextRef)context;

- (CGFloat)fakeBoldShift;
- (NSRect)frameForBoundingRect:(NSRect)frame flipped:(BOOL)flipped;
- (NSColor *)textColorForIteration:(NSInteger)iteration;
- (void)drawEmojiWithFont:(CTFontRef)runFont
                   offset:(CGPoint)offset
                   buffer:(const CGGlyph *)buffer
                positions:(CGPoint *)positions
                   length:(size_t)length
                iteration:(NSInteger)iteration
                  context:(CGContextRef)context;

@end

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

