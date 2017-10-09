#import "iTermMetalRenderer.h"
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat MARGIN_WIDTH;
extern const CGFloat TOP_MARGIN;
extern const CGFloat BOTTOM_MARGIN;

@class iTermMetalCellRendererTransientState;

@protocol iTermMetalCellRenderer<NSObject>

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(__kindof iTermMetalCellRendererTransientState *)transientState;

- (void)createTransientStateForViewportSize:(vector_uint2)viewportSize
                                   cellSize:(CGSize)cellSize
                                   gridSize:(VT100GridSize)gridSize
                              commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                 completion:(void (^)(__kindof iTermMetalCellRendererTransientState *transientState))completion;

@end

@interface iTermMetalCellRendererTransientState : iTermMetalRendererTransientState
@property (nonatomic, readonly) VT100GridSize gridSize;
@property (nonatomic, readonly) CGSize cellSize;
@property (nonatomic, readonly) id<MTLBuffer> offsetBuffer;
@property (nonatomic, strong) id<MTLBuffer> pius;

- (void)setPIUValue:(void *)c coord:(VT100GridCoord)coord;
- (const void *)piuForCoord:(VT100GridCoord)coord;

@end

@interface iTermMetalCellRenderer : iTermMetalRenderer<iTermMetalCellRenderer>

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

- (void)createTransientStateForViewportSize:(vector_uint2)viewportSize
                              commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                 completion:(void (^)(__kindof iTermMetalRendererTransientState *transientState))completion NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
