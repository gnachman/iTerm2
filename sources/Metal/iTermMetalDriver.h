#import "VT100GridTypes.h"

#import "iTermASCIITexture.h"
#import "iTermCursor.h"
#import "iTermImageRenderer.h"
#import "iTermIndicatorRenderer.h"
#import "iTermMarkRenderer.h"
#import "iTermMetalDebugInfo.h"
#import "iTermMetalDriverDataSource.h"
#import "iTermMetalGlyphKey.h"
#import "iTermTextRenderer.h"
#import "iTermTextRendererTransientState.h"

#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

// Our platform independent render class
NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalDriver : NSObject<MTKViewDelegate>

@property (nullable, nonatomic, weak) id<iTermMetalDriverDataSource> dataSource;
@property (nonatomic, readonly) NSString *identifier;
@property (atomic) BOOL captureDebugInfoForNextFrame;

- (nullable instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView;
- (void)setCellSize:(CGSize)cellSize
cellSizeWithoutSpacing:(CGSize)cellSizeWithoutSpacing
           gridSize:(VT100GridSize)gridSize
              scale:(CGFloat)scale;

@end

NS_ASSUME_NONNULL_END
