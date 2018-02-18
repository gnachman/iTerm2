#import "iTermASCIITexture.h"
#import "iTermMetalCellRenderer.h"
#import "iTermMetalGlyphKey.h"
#import "iTermTextRendererCommon.h"

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermTextRenderer : NSObject<iTermMetalCellRenderer>

// Generic model used for blending in gpu
+ (NSData *)subpixelModelData;

- (instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

