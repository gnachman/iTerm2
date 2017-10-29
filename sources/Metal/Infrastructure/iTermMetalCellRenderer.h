#import "iTermMetalRenderer.h"
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat MARGIN_WIDTH;
extern const CGFloat TOP_MARGIN;
extern const CGFloat BOTTOM_MARGIN;

@class iTermMetalCellRendererTransientState;

@interface iTermCellRenderConfiguration : iTermRenderConfiguration
@property (nonatomic, readonly) CGSize cellSize;
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
                            gridSize:(VT100GridSize)gridSize
               usingIntermediatePass:(BOOL)usingIntermediatePass NS_DESIGNATED_INITIALIZER;

@end

@protocol iTermMetalCellRenderer<NSObject>

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(__kindof iTermMetalCellRendererTransientState *)transientState;

- (void)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                      completion:(void (^)(__kindof iTermMetalRendererTransientState *transientState))completion;

@end

@interface iTermMetalCellRendererTransientState : iTermMetalRendererTransientState
@property (nonatomic, readonly) __kindof iTermCellRenderConfiguration *cellConfiguration;
@property (nonatomic, readonly) id<MTLBuffer> offsetBuffer;
@property (nonatomic, strong) id<MTLBuffer> pius;

- (void)setPIUValue:(void *)c coord:(VT100GridCoord)coord;
- (const void *)piuForCoord:(VT100GridCoord)coord;

@end

@interface iTermMetalCellRenderer : iTermMetalRenderer

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_UNAVAILABLE;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                     vertexFunctionName:(NSString *)vertexFunctionName
                   fragmentFunctionName:(NSString *)fragmentFunctionName
                               blending:(BOOL)blending
                    transientStateClass:(Class)transientStateClass NS_UNAVAILABLE;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                     vertexFunctionName:(NSString *)vertexFunctionName
                   fragmentFunctionName:(NSString *)fragmentFunctionName
                               blending:(BOOL)blending
                         piuElementSize:(size_t)piuElementSize
                    transientStateClass:(Class)transientStateClass NS_DESIGNATED_INITIALIZER;

- (void)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                      completion:(void (^)(__kindof iTermMetalRendererTransientState *transientState))completion;

- (void)createTransientStateForConfiguration:(iTermRenderConfiguration *)configuration
                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                  completion:(void (^)(__kindof iTermMetalRendererTransientState *transientState))completion NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
