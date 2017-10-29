#import "iTermBroadcastStripesRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBroadcastStripesRendererTransientState : iTermMetalRendererTransientState
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic) CGSize size;
@end

@implementation iTermBroadcastStripesRendererTransientState
@end

@implementation iTermBroadcastStripesRenderer {
    iTermMetalRenderer *_metalRenderer;
    id<MTLTexture> _texture;
    CGSize _size;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _metalRenderer = [[iTermMetalRenderer alloc] initWithDevice:device
                                                 vertexFunctionName:@"iTermBroadcastStripesVertexShader"
                                               fragmentFunctionName:@"iTermBroadcastStripesFragmentShader"
                                                           blending:YES
                                                transientStateClass:[iTermBroadcastStripesRendererTransientState class]];
        NSImage *image = [NSImage imageNamed:@"BackgroundStripes"];
        _size = image.size;
        _texture = [_metalRenderer textureFromImage:image];
    }
    return self;
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(nonnull __kindof iTermMetalRendererTransientState *)transientState {
    iTermBroadcastStripesRendererTransientState *tState = transientState;
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

- (void)initializeTransientState:(iTermBroadcastStripesRendererTransientState *)tState {
    tState.texture = _texture;
    tState.size = _size;

    const vector_uint2 viewportSize = tState.configuration.viewportSize;
    const float maxX = viewportSize.x / _size.width;
    const float maxY = viewportSize.y / _size.height;
    const iTermVertex vertices[] = {
        // Pixel Positions, Texture Coordinates
        { { viewportSize.x, 0 },              { maxX, 0 } },
        { { 0,              0 },              { 0,    0 } },
        { { 0, viewportSize.y },              { 0,    maxY } },

        { { viewportSize.x, 0 },              { maxX, 0 } },
        { { 0,              viewportSize.y }, { 0,    maxY } },
        { { viewportSize.x, viewportSize.y }, { maxX, maxY } },
    };
    tState.vertexBuffer = [_metalRenderer.device newBufferWithBytes:vertices
                                                             length:sizeof(vertices)
                                                            options:MTLResourceStorageModeShared];
}

@end

NS_ASSUME_NONNULL_END

