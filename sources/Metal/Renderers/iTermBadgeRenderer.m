#import "iTermBadgeRenderer.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermMetalBufferPool.h"
#import "iTermMetalRenderer.h"
#import "iTermTextDrawingHelper.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBadgeRendererTransientState ()
@property (nonatomic, strong) id<MTLTexture> texture;
@end

@implementation iTermBadgeRendererTransientState
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
                                                           blending:[iTermMetalBlending compositeSourceOver]
                                                transientStateClass:[iTermBadgeRendererTransientState class]];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateBadgeTS;
}

- (BOOL)hasImage {
    return _texture != nil;
}

- (void)setBadgeImage:(NSImage *)image context:(nonnull iTermMetalBufferPoolContext *)context {
    _size = image.size;
    _texture = [_metalRenderer textureFromImage:image context:context];
    _texture.label = @"Badge";
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(nonnull __kindof iTermMetalRendererTransientState *)transientState {
    iTermBadgeRendererTransientState *tState = transientState;
    const CGSize size = tState.destinationRect.size;
    const CGFloat scale = tState.configuration.scale;
    CGRect textureFrame = CGRectMake(0, 0, 1, 1);
    const CGFloat MARGIN_HEIGHT = [iTermAdvancedSettingsModel terminalVMargin] * scale;

    CGRect quad = CGRectMake(scale * tState.destinationRect.origin.x,
                             tState.configuration.viewportSize.y - scale * CGRectGetMaxY(tState.destinationRect) - MARGIN_HEIGHT,
                             scale * size.width,
                             scale * size.height);
    const iTermVertex vertices[] = {
        // Pixel Positions             Texture Coordinates
        { { CGRectGetMaxX(quad), CGRectGetMinY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMinY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMinY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMaxY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },

        { { CGRectGetMaxX(quad), CGRectGetMinY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMaxY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },
        { { CGRectGetMaxX(quad), CGRectGetMaxY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMaxY(textureFrame) } },
    };
    tState.vertexBuffer = [_metalRenderer.verticesPool requestBufferFromContext:tState.poolContext
                                                                      withBytes:vertices
                                                                 checkIfChanged:YES];
    [_metalRenderer drawWithTransientState:tState
                             renderEncoder:renderEncoder
                          numberOfVertices:6
                              numberOfPIUs:0
                             vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer }
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
}

@end

NS_ASSUME_NONNULL_END
