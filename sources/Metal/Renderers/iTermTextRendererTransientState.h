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

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermTextRendererTransientState : iTermMetalCellRendererTransientState
@property (nonatomic, strong) NSMutableData *modelData;
@property (nonatomic, strong) id<MTLTexture> backgroundTexture;
@property (nonatomic) iTermMetalUnderlineDescriptor asciiUnderlineDescriptor;
@property (nonatomic) iTermMetalUnderlineDescriptor nonAsciiUnderlineDescriptor;
@property (nonatomic) iTermMetalUnderlineDescriptor strikethroughUnderlineDescriptor;
@property (nonatomic) CGFloat verticalOffset;

// When YES, underline styles in PIUs are forced to None (for multi-pass underline rendering).
@property (nonatomic) BOOL suppressUnderlines;

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
