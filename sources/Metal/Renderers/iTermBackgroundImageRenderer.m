#import "iTermBackgroundImageRenderer.h"

#import "iTermShaderTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBackgroundImageRendererTransientState : iTermMetalRendererTransientState
@property (nonatomic, strong) id<MTLTexture> texture;
@end

@implementation iTermBackgroundImageRendererTransientState
@end

@implementation iTermBackgroundImageRenderer {
    iTermMetalRenderer *_metalRenderer;

    // The texture is shared because it tends to get reused. The transient state holds a reference
    // to it, so when the image changes, this can be set to a new texture and it should just work.
    id<MTLTexture> _texture;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _metalRenderer = [[iTermMetalRenderer alloc] initWithDevice:device
                                                 vertexFunctionName:@"iTermBackgroundImageVertexShader"
                                               fragmentFunctionName:@"iTermBackgroundImageFragmentShader"
                                                           blending:NO
                                                transientStateClass:[iTermBackgroundImageRendererTransientState class]];
        NSImage *image = [NSImage imageNamed:@"background"];
        _texture = [_metalRenderer textureFromImage:image];
    }
    return self;
}

- (void)drawWithRenderEncoder:(nonnull id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(nonnull __kindof iTermMetalRendererTransientState *)transientState {
    iTermBackgroundImageRendererTransientState *tState = transientState;
    [_metalRenderer drawWithTransientState:tState
                             renderEncoder:renderEncoder
                          numberOfVertices:6
                              numberOfPIUs:0
                             vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer }
                           fragmentBuffers:@{}
                                  textures:@{ @(iTermTextureIndexPrimary): tState.texture }];
}

- (void)createTransientStateForViewportSize:(vector_uint2)viewportSize
                              commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                 completion:(void (^)(__kindof iTermMetalRendererTransientState * _Nonnull))completion {
    [_metalRenderer createTransientStateForViewportSize:viewportSize
                                          commandBuffer:commandBuffer
                                             completion:^(__kindof iTermMetalRendererTransientState * _Nonnull transientState) {
                                                 [self initializeTransientState:transientState];
                                                 completion(transientState);
                                             }];
}

- (void)initializeTransientState:(iTermBackgroundImageRendererTransientState *)tState {
    tState.texture = _texture;
    tState.vertexBuffer = [_metalRenderer newQuadOfSize:CGSizeMake(tState.viewportSize.x,
                                                                   tState.viewportSize.y)];
}

@end

NS_ASSUME_NONNULL_END
