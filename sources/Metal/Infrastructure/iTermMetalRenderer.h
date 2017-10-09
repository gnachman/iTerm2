#import <Foundation/Foundation.h>

#import "iTermShaderTypes.h"
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermMetalRendererTransientState;

@protocol iTermMetalRenderer<NSObject>

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(__kindof iTermMetalRendererTransientState *)transientState;

- (void)createTransientStateForViewportSize:(vector_uint2)viewportSize
                              commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                 completion:(void (^)(__kindof iTermMetalRendererTransientState *transientState))completion;

@end

@interface iTermMetalRendererTransientState : NSObject
@property (nonatomic) vector_uint2 viewportSize;
@property (nonatomic, strong) id<MTLBuffer> vertexBuffer;
@property (nonatomic, readonly, strong) id<MTLRenderPipelineState> pipelineState;
@end

@interface iTermMetalRenderer : NSObject<iTermMetalRenderer>

@property (nonatomic, readonly) id<MTLDevice> device;
@property (nonatomic, readonly) Class transientStateClass;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device;

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                     vertexFunctionName:(NSString *)vertexFunctionName
                   fragmentFunctionName:(NSString *)fragmentFunctionName
                               blending:(BOOL)blending
                    transientStateClass:(Class)transientStateClass;

- (instancetype)init NS_UNAVAILABLE;

#pragma mark - For subclasses

- (id<MTLBuffer>)newQuadOfSize:(CGSize)size;

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

@end

NS_ASSUME_NONNULL_END
