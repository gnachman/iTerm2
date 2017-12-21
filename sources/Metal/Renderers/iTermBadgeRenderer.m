#import "iTermBadgeRenderer.h"

#import "iTermMetalBufferPool.h"
#import "iTermMetalRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBadgeRendererTransientState : iTermMetalRendererTransientState
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic) CGSize size;
@end

@implementation iTermBadgeRendererTransientState

- (id<MTLBuffer>)newOffsetBufferWithDevice:(id<MTLDevice>)device
                                      pool:(iTermMetalBufferPool *)pool {
    CGSize viewport = CGSizeMake(self.configuration.viewportSize.x, self.configuration.viewportSize.y);
    vector_float2 offset = {
        viewport.width - _size.width - 20,
        viewport.height - _size.height - 20
    };
    return [pool requestBufferFromContext:self.poolContext
                                withBytes:&offset
                           checkIfChanged:YES];
}

@end

@implementation iTermBadgeRenderer {
    iTermMetalRenderer *_metalRenderer;
    id<MTLTexture> _texture;
    CGSize _size;
    iTermMetalBufferPool *_offsetsPool;
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
        _offsetsPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(vector_float2) * 2];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateBadgeTS;
}

- (void)setBadgeImage:(NSImage *)image {
    _size = image.size;
    _texture = [_metalRenderer textureFromImage:image];
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(nonnull __kindof iTermMetalRendererTransientState *)transientState {
    iTermBadgeRendererTransientState *tState = transientState;
    id<MTLBuffer> offsetBuffer = [tState newOffsetBufferWithDevice:_metalRenderer.device
                                                              pool:_offsetsPool];
    [_metalRenderer drawWithTransientState:tState
                             renderEncoder:renderEncoder
                          numberOfVertices:6
                              numberOfPIUs:0
                             vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                              @(iTermVertexInputIndexOffset): offsetBuffer }
                           fragmentBuffers:@{}
                                  textures:@{ @(iTermTextureIndexPrimary): tState.texture }];
}

- (__kindof iTermMetalRendererTransientState * _Nonnull)createTransientStateForConfiguration:(iTermRenderConfiguration *)configuration
                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    if (CGSizeEqualToSize(CGSizeZero, _size)) {
        return nil;
    }

    __kindof iTermMetalRendererTransientState * _Nonnull transientState =
        [_metalRenderer createTransientStateForConfiguration:configuration
                                           commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermBadgeRendererTransientState *)tState {
    tState.texture = _texture;
    tState.size = _size;
    tState.vertexBuffer = [_metalRenderer newQuadOfSize:_size poolContext:tState.poolContext];
}

@end

NS_ASSUME_NONNULL_END
