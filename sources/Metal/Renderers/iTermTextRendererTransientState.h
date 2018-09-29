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
@property (nonatomic) iTermMetalUnderlineDescriptor asciiUnderlineDescriptor;
@property (nonatomic) iTermMetalUnderlineDescriptor nonAsciiUnderlineDescriptor;
@property (nonatomic) vector_float4 defaultBackgroundColor;
@property (nonatomic) BOOL disableIndividualColorModels NS_DEPRECATED_MAC(10_12, 10_14);

- (void)setGlyphKeysData:(iTermGlyphKeyData*)glyphKeysData
                   count:(int)count
          attributesData:(iTermAttributesData *)attributesData
                     row:(int)row
  backgroundColorRLEData:(iTermData *)backgroundColorData  // array of iTermMetalBackgroundColorRLE background colors.
       markedRangeOnLine:(NSRange)markedRangeOnLine
                 context:(iTermMetalBufferPoolContext *)context
                creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(NS_NOESCAPE ^)(int x, BOOL *emoji))creation;
- (void)willDraw;
- (void)didComplete;

@end

NS_ASSUME_NONNULL_END
