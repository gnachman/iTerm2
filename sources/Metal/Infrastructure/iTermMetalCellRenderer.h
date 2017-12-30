#import "iTermMetalRenderer.h"

#import "iTermMetalFrameData.h"
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat MARGIN_WIDTH;
extern const CGFloat TOP_MARGIN;
extern const CGFloat BOTTOM_MARGIN;

@class iTermMetalCellRendererTransientState;

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermCellRenderConfiguration : iTermRenderConfiguration
@property (nonatomic, readonly) CGSize cellSize;
@property (nonatomic, readonly) CGSize cellSizeWithoutSpacing;
@property (nonatomic, readonly) VT100GridSize gridSize;

// This determines how subpixel antialiasing is done. It's unfortunate that one
// renderer's needs affect the configuration for so many renderers. I need to
// find a better way to pass this info around. The problem is that it's needed
// early on--before the transient state is created--in order for the text
// renderer to be able to set its fragment function.
@property (nonatomic, readonly) BOOL usingIntermediatePass;

- (instancetype)initWithViewportSize:(vector_uint2)viewportSize scale:(CGFloat)scale NS_UNAVAILABLE;
- (instancetype)initWithViewportSize:(vector_uint2)viewportSize
                               scale:(CGFloat)scale
                            cellSize:(CGSize)cellSize
              cellSizeWithoutSpacing:(CGSize)cellSizeWithoutSpacing
                            gridSize:(VT100GridSize)gridSize
               usingIntermediatePass:(BOOL)usingIntermediatePass NS_DESIGNATED_INITIALIZER;

@end

NS_CLASS_AVAILABLE(10_11, NA)
@protocol iTermMetalCellRenderer<NSObject>
@property (nonatomic, readonly) BOOL rendererDisabled;

- (iTermMetalFrameDataStat)createTransientStateStat;
- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(__kindof iTermMetalCellRendererTransientState *)transientState;

- (__kindof iTermMetalRendererTransientState *)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                          commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

@end

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalCellRendererTransientState : iTermMetalRendererTransientState
@property (nonatomic, readonly) __kindof iTermCellRenderConfiguration *cellConfiguration;
@property (nonatomic, readonly) id<MTLBuffer> offsetBuffer;
@property (nonatomic, strong) id<MTLBuffer> pius;
@property (nonatomic, readonly) NSEdgeInsets margins;

- (instancetype)init NS_UNAVAILABLE;

- (void)setPIUValue:(void *)c coord:(VT100GridCoord)coord;
- (const void *)piuForCoord:(VT100GridCoord)coord;

@end

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalCellRenderer : iTermMetalRenderer

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_UNAVAILABLE;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                     vertexFunctionName:(NSString *)vertexFunctionName
                   fragmentFunctionName:(NSString *)fragmentFunctionName
                               blending:(nullable iTermMetalBlending *)blending
                    transientStateClass:(Class)transientStateClass NS_UNAVAILABLE;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                     vertexFunctionName:(NSString *)vertexFunctionName
                   fragmentFunctionName:(NSString *)fragmentFunctionName
                               blending:(nullable iTermMetalBlending *)blending
                         piuElementSize:(size_t)piuElementSize
                    transientStateClass:(Class)transientStateClass NS_DESIGNATED_INITIALIZER;

- (__kindof iTermMetalRendererTransientState *)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                          commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

@end

NS_ASSUME_NONNULL_END
