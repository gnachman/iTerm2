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

NS_ASSUME_NONNULL_BEGIN

extern const vector_float4 iTermIMEColor;

@class iTermCharacterBitmap;

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermTextRendererTransientState : iTermMetalCellRendererTransientState
@property (nonatomic, strong) NSMutableData *modelData;
@property (nonatomic, strong) id<MTLTexture> backgroundTexture;
@property (nonatomic) iTermMetalUnderlineDescriptor nonAsciiUnderlineDescriptor;
@property (nonatomic) vector_float4 defaultBackgroundColor;
@property (nonatomic, strong) id<MTLBuffer> colorsBuffer;  // iTermCellColors, to be populated by iTermColorComputer


- (void)setGlyphKeysData:(iTermData *)glyphKeysData
                   count:(int)count
                     row:(int)row
       markedRangeOnLine:(NSRange)markedRangeOnLine
                 context:(iTermMetalBufferPoolContext *)context
                creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(NS_NOESCAPE ^)(const iTermMetalGlyphKey *glyphKey, BOOL *emoji))creation;
- (void)willDraw;
- (void)didComplete;

@end

NS_ASSUME_NONNULL_END
