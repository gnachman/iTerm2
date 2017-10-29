#import "iTermBadgeRenderer.h"
#import "iTermMetalRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBadgeRendererTransientState : iTermMetalRendererTransientState
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic) CGSize size;
@end

@implementation iTermBadgeRendererTransientState

- (id<MTLBuffer>)newOffsetBufferWithDevice:(id<MTLDevice>)device {
    CGSize viewport = CGSizeMake(self.configuration.viewportSize.x, self.configuration.viewportSize.y);
    vector_float2 offset = {
        viewport.width - _size.width - 20,
        viewport.height - _size.height - 20
    };
    return [device newBufferWithBytes:&offset
                               length:sizeof(offset)
                              options:MTLResourceStorageModeShared];
}

@end

@implementation iTermBadgeRenderer {
    iTermMetalRenderer *_metalRenderer;
    id<MTLTexture> _texture;
    CGSize _size;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _metalRenderer = [[iTermMetalRenderer alloc] initWithDevice:device
                                                 vertexFunctionName:@"iTermBadgeVertexShader"
                                               fragmentFunctionName:@"iTermBadgeFragmentShader"
                                                           blending:YES
                                                transientStateClass:[iTermBadgeRendererTransientState class]];
        [self setBadgeImage:[NSImage imageNamed:@"badge"]];
    }
    return self;
}

- (void)setBadgeImage:(NSImage *)image {
    _size = image.size;
    _texture = [_metalRenderer textureFromImage:image];
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(nonnull __kindof iTermMetalRendererTransientState *)transientState {
    iTermBadgeRendererTransientState *tState = transientState;
    id<MTLBuffer> offsetBuffer = [tState newOffsetBufferWithDevice:_metalRenderer.device];
    [_metalRenderer drawWithTransientState:tState
                             renderEncoder:renderEncoder
                          numberOfVertices:6
                              numberOfPIUs:0
                             vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                              @(iTermVertexInputIndexOffset): offsetBuffer }
                           fragmentBuffers:@{}
                                  textures:@{ @(iTermTextureIndexPrimary): tState.texture }];
}

- (void)createTransientStateForConfiguration:(iTermRenderConfiguration *)configuration
                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                  completion:(void (^)(__kindof iTermMetalRendererTransientState * _Nonnull))completion {
    [_metalRenderer createTransientStateForConfiguration:configuration
                                           commandBuffer:commandBuffer
                                              completion:^(__kindof iTermMetalRendererTransientState * _Nonnull transientState) {
                                                  [self initializeTransientState:transientState];
                                                  completion(transientState);
                                              }];

}

- (void)initializeTransientState:(iTermBadgeRendererTransientState *)tState {
    tState.texture = _texture;
    tState.size = _size;
    tState.vertexBuffer = [_metalRenderer newQuadOfSize:_size];
}

@end

NS_ASSUME_NONNULL_END
