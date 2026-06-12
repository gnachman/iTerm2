#import "iTermUnderlineSpanTestHelper.h"
#import "iTermTextRendererTransientState.h"

@implementation iTermUnderlineSpanTestHelper {
    iTermTextRendererTransientState *_state;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        iTermCellRenderConfiguration *config =
            [[iTermCellRenderConfiguration alloc] initWithViewportSize:(vector_uint2){800, 600}
                                                  legacyScrollbarWidth:0
                                                                 scale:2.0
                                                    hasBackgroundImage:NO
                                                          extraMargins:NSEdgeInsetsZero
                          maximumExtendedDynamicRangeColorComponentValue:1.0
                                                            colorSpace:[NSColorSpace sRGBColorSpace]
                                                      rightExtraPixels:0
                                                panelReservationPixels:0
                                                              cellSize:CGSizeMake(10, 20)
                                                             glyphSize:CGSizeMake(10, 20)
                                                cellSizeWithoutSpacing:CGSizeMake(10, 20)
                                                              gridSize:VT100GridSizeMake(80, 24)
                                                 usingIntermediatePass:NO];
        _state = [[iTermTextRendererTransientState alloc] initWithConfiguration:config];
    }
    return self;
}

- (void)setAsciiUnderlineDescriptor:(iTermMetalUnderlineDescriptor)asciiUnderlineDescriptor {
    _state.asciiUnderlineDescriptor = asciiUnderlineDescriptor;
}

- (iTermMetalUnderlineDescriptor)asciiUnderlineDescriptor {
    return _state.asciiUnderlineDescriptor;
}

- (void)setNonAsciiUnderlineDescriptor:(iTermMetalUnderlineDescriptor)nonAsciiUnderlineDescriptor {
    _state.nonAsciiUnderlineDescriptor = nonAsciiUnderlineDescriptor;
}

- (iTermMetalUnderlineDescriptor)nonAsciiUnderlineDescriptor {
    return _state.nonAsciiUnderlineDescriptor;
}

- (void)computeSpansFromAttributes:(const iTermMetalGlyphAttributes *)attributes
                             count:(int)count
                               row:(int)row
                 markedRangeOnLine:(NSRange)markedRangeOnLine
                              line:(const screen_char_t *)line
                        lineLength:(int)lineLength
                        inverseLUT:(const int *)inverseLUT
                    inverseLUTLen:(int)inverseLUTLen
                    underlineSpans:(NSMutableData *)underlineSpans
                strikethroughSpans:(NSMutableData *)strikethroughSpans {
    [_state computeUnderlineSpansFromAttributes:attributes
                                          count:count
                                            row:row
                              markedRangeOnLine:markedRangeOnLine
                                           line:line
                                     lineLength:lineLength
                                     inverseLUT:inverseLUT
                                 inverseLUTLen:inverseLUTLen
                                lineAttribute:iTermLineAttributeSingleWidth
                                 underlineSpans:underlineSpans
                             strikethroughSpans:strikethroughSpans];
}

@end
