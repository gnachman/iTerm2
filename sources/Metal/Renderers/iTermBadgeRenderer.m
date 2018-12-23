#import "iTermBadgeRenderer.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermMetalBufferPool.h"
#import "iTermMetalRenderer.h"
#import "iTermTextDrawingHelper.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBadgeRendererTransientState ()
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic) CGSize textureSizeInPoints;
@end

@implementation iTermBadgeRendererTransientState
@end

@implementation iTermBadgeRenderer {
    iTermMetalRenderer *_metalRenderer;
    id<MTLTexture> _texture;
    CGSize _size;
    NSImage *_previousImage;
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
    if (image == _previousImage) {
        return;
    }
    _previousImage = image;
    _size = image.size;
    _texture = [_metalRenderer textureFromImage:image context:context];
    _texture.label = @"Badge";
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalRendererTransientState *)transientState {
    iTermBadgeRendererTransientState *tState = transientState;
    const CGSize size = tState.destinationRect.size;
    const CGFloat scale = tState.configuration.scale;
    const CGFloat MARGIN_HEIGHT = [iTermAdvancedSettingsModel terminalVMargin] * scale;
    CGRect quad = CGRectMake(scale * tState.destinationRect.origin.x,
                             tState.configuration.viewportSize.y - scale * CGRectGetMaxY(tState.destinationRect) - MARGIN_HEIGHT,
                             scale * size.width,
                             scale * size.height);
    // The destinationRect is clipped to the visible area.
    const CGFloat textureHeight = tState.textureSizeInPoints.height * tState.configuration.scale;
    const CGFloat fractionVisible = quad.size.height / textureHeight;
    CGRect textureFrame = CGRectMake(0, 1 - fractionVisible, 1, fractionVisible);
    const iTermVertex vertices[] = {
        // Pixel Positions                              Texture Coordinates
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
                             renderEncoder:frameData.renderEncoder
                          numberOfVertices:6
                              numberOfPIUs:0
                             vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer }
                           fragmentBuffers:@{}
                                  textures:@{ @(iTermTextureIndexPrimary): tState.texture }];
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForConfiguration:(iTermRenderConfiguration *)configuration
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
    tState.textureSizeInPoints = _size;
}

@end

NS_ASSUME_NONNULL_END
