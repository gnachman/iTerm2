//
//  iTermTextRendererTransientState.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/17.
//

#import "iTermMetalCellRenderer.h"
#import "iTermMetalGlyphKey.h"
#import "iTermMetalRowData.h"
#import "iTermTextRendererCommon.h"
#import "ScreenChar.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermCharacterBitmap;

@interface iTermTextRendererTransientState : iTermMetalCellRendererTransientState
@property (nonatomic, strong) NSMutableData *modelData;
@property (nonatomic, strong) id<MTLTexture> backgroundTexture;
@property (nonatomic) iTermMetalUnderlineDescriptor asciiUnderlineDescriptor;
@property (nonatomic) iTermMetalUnderlineDescriptor nonAsciiUnderlineDescriptor;
@property (nonatomic) iTermMetalUnderlineDescriptor strikethroughUnderlineDescriptor;
@property (nonatomic) CGFloat verticalOffset;

// When YES, underline styles in PIUs are forced to None (for multi-pass underline rendering).
@property (nonatomic) BOOL suppressUnderlines;

// Text under a filled box cursor. When cursorTextInfo.enabled is set, glyphs in
// the columns the cursor covers are given those columns' normal colors (see
// -setCursorRow:...) and the fragment shader draws the pixels inside the
// cursor box, cursorTextInfo.rect, in cursorTextInfo.color. That way a glyph
// that extends past its cell, like a ligature whose glyph sits in the cursor
// cell but draws over the previous cell, only takes the cursor color inside
// the cursor. Must be set before rows are added. Issue 13203.
@property (nonatomic) iTermTextCursorInfo cursorTextInfo;

// `count` contiguous visual columns starting at `firstColumn` on `row` are
// covered by the box cursor. `colors` gives their normal text colors. `count`
// is clamped to iTermBoxCursorMaxColumns.
- (void)setCursorRow:(int)row
         firstColumn:(int)firstColumn
               count:(int)count
    normalTextColors:(const vector_float4 *)colors;

// Compute underline/strikethrough spans from the attributes array and append to the given data objects.
// inverseLUT maps visual column -> logical index (from BidiDisplayInfoObjc.inverseLUT).
// Used to determine ASCII vs non-ASCII per column for descriptor color selection.
- (void)computeUnderlineSpansFromAttributes:(const iTermMetalGlyphAttributes *)attributes
                                      count:(int)count
                                        row:(int)row
                          markedRangeOnLine:(NSRange)markedRangeOnLine
                                       line:(const screen_char_t *)line
                                 lineLength:(int)lineLength
                                 inverseLUT:(const int * _Nullable)inverseLUT
                             inverseLUTLen:(int)inverseLUTLen
                              lineAttribute:(iTermLineAttribute)lineAttribute
                             underlineSpans:(NSMutableData *)underlineSpans
                         strikethroughSpans:(NSMutableData *)strikethroughSpans;

- (void)setGlyphKeysData:(iTermGlyphKeyData*)glyphKeysData
           glyphKeyCount:(NSUInteger)glyphKeyCount
                   count:(int)count
          attributesData:(iTermAttributesData *)attributesData
                     row:(int)row
  backgroundColorRLEData:(iTermData *)backgroundColorData  // array of iTermMetalBackgroundColorRLE background colors.
       markedRangeOnLine:(NSRange)markedRangeOnLine
                 context:(iTermMetalBufferPoolContext *)context
                creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(NS_NOESCAPE ^)(int x, BOOL *emoji))creation;
- (void)willDraw;
- (void)didComplete;
- (void)expireNonASCIIGlyphs;

@end

NS_ASSUME_NONNULL_END
