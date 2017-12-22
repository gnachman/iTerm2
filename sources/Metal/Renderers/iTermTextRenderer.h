#import "iTermASCIITexture.h"
#import "iTermMetalCellRenderer.h"
#import "iTermMetalGlyphKey.h"
#import "iTermTextRendererCommon.h"

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermTextRenderer : NSObject<iTermMetalCellRenderer>

- (instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)setASCIICellSize:(CGSize)cellSize
      creationIdentifier:(id)creationIdentifier
                creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(^)(char, iTermASCIITextureAttributes))creation;

@end

NS_ASSUME_NONNULL_END

