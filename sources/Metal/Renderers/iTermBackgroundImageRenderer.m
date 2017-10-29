#import "iTermBackgroundImageRenderer.h"

#import "iTermShaderTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBackgroundImageRendererTransientState : iTermMetalRendererTransientState
@property (nonatomic, strong) id<MTLTexture> texture;
#warning TODO: Add support for blending and tiled modes
@property (nonatomic) CGFloat blending;
@property (nonatomic) BOOL tiled;
@end

@implementation iTermBackgroundImageRendererTransientState

- (BOOL)skipRenderer {
    return _texture == nil;
}

@end

@implementation iTermBackgroundImageRenderer {
    iTermMetalRenderer *_metalRenderer;

    // The texture is shared because it tends to get reused. The transient state holds a reference
    // to it, so when the image changes, this can be set to a new texture and it should just work.
    id<MTLTexture> _texture;

    CGFloat _blending;
    BOOL _tiled;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _metalRenderer = [[iTermMetalRenderer alloc] initWithDevice:device
                                                 vertexFunctionName:@"iTermBackgroundImageVertexShader"
                                               fragmentFunctionName:@"iTermBackgroundImageFragmentShader"
                                                           blending:NO
                                                transientStateClass:[iTermBackgroundImageRendererTransientState class]];
    }
    return self;
}

- (void)setImage:(NSImage *)image blending:(CGFloat)blending tiled:(BOOL)tiled {
    _texture = image ? [_metalRenderer textureFromImage:image] : nil;
    _blending = blending;
    _tiled = tiled;
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

- (void)initializeTransientState:(iTermBackgroundImageRendererTransientState *)tState {
    tState.texture = _texture;
    tState.blending = _blending;
    tState.tiled = _tiled;
    tState.vertexBuffer = [_metalRenderer newQuadOfSize:CGSizeMake(tState.configuration.viewportSize.x,
                                                                   tState.configuration.viewportSize.y)];
}

@end

NS_ASSUME_NONNULL_END
