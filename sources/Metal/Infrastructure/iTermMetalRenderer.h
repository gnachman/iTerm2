#import <Foundation/Foundation.h>

#import "iTermShaderTypes.h"
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermMetalRendererTransientState;

@interface iTermRenderConfiguration : NSObject
@property (nonatomic, readonly) vector_uint2 viewportSize;
@property (nonatomic, readonly) CGFloat scale;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithViewportSize:(vector_uint2)viewportSize
                               scale:(CGFloat)scale NS_DESIGNATED_INITIALIZER;
@end

@protocol iTermMetalRenderer<NSObject>

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(__kindof iTermMetalRendererTransientState *)transientState;

- (void)createTransientStateForConfiguration:(iTermRenderConfiguration *)configuration
                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                  completion:(void (^)(__kindof iTermMetalRendererTransientState *transientState))completion;

@end

@interface iTermMetalRendererTransientState : NSObject
@property (nonatomic, strong, readonly) __kindof iTermRenderConfiguration *configuration;
@property (nonatomic, strong) id<MTLBuffer> vertexBuffer;
@property (nonatomic, readonly, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, readonly) BOOL skipRenderer;

- (instancetype)initWithConfiguration:(__kindof iTermRenderConfiguration *)configuration;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface iTermMetalRenderer : NSObject

@property (nonatomic, readonly) id<MTLDevice> device;
@property (nonatomic, readonly) Class transientStateClass;
@property (nonatomic, copy) NSString *fragmentFunctionName;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                     vertexFunctionName:(NSString *)vertexFunctionName
                   fragmentFunctionName:(NSString *)fragmentFunctionName
                               blending:(BOOL)blending
                    transientStateClass:(Class)transientStateClass;

- (instancetype)init NS_UNAVAILABLE;

#pragma mark - For subclasses

- (id<MTLBuffer>)newQuadOfSize:(CGSize)size;

// Things in Metal are randomly upside down for no good reason. So make it easy to flip them back.
- (id<MTLBuffer>)newFlippedQuadOfSize:(CGSize)size;

- (void)drawWithTransientState:(iTermMetalRendererTransientState *)tState
                 renderEncoder:(id <MTLRenderCommandEncoder>)renderEncoder
              numberOfVertices:(NSInteger)numberOfVertices
                  numberOfPIUs:(NSInteger)numberOfPIUs
                 vertexBuffers:(NSDictionary<NSNumber *, id<MTLBuffer>> *)vertexBuffers
               fragmentBuffers:(NSDictionary<NSNumber *, id<MTLBuffer>> *)fragmentBuffers
                      textures:(NSDictionary<NSNumber *, id<MTLTexture>> *)textures;

- (id<MTLTexture>)textureFromImage:(NSImage *)image;

- (id<MTLRenderPipelineState>)newPipelineWithBlending:(BOOL)blending
                                       vertexFunction:(id<MTLFunction>)vertexFunction
                                     fragmentFunction:(id<MTLFunction>)fragmentFunction;

- (void)createTransientStateForConfiguration:(iTermRenderConfiguration *)configuration
                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                  completion:(void (^)(__kindof iTermMetalRendererTransientState *transientState))completion;

@end

NS_ASSUME_NONNULL_END
