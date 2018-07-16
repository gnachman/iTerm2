#import "iTermBackgroundImageRenderer.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermShaderTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBackgroundImageRendererTransientState ()
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic) BOOL tiled;
@property (nonatomic) NSSize imageSize;
@end

@implementation iTermBackgroundImageRendererTransientState

- (BOOL)skipRenderer {
    return _texture == nil;
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];
    [[NSString stringWithFormat:@"tiled=%@", _tiled ? @"YES" : @"NO"] writeToURL:[folder URLByAppendingPathComponent:@"state.txt"]
                                                                      atomically:NO
                                                                        encoding:NSUTF8StringEncoding
                                                                           error:NULL];
}

@end

@implementation iTermBackgroundImageRenderer {
    iTermMetalRenderer *_metalRenderer;
#if ENABLE_TRANSPARENT_METAL_WINDOWS
    iTermMetalBufferPool *_alphaPool;
#endif
    BOOL _tiled;
    NSImage *_image;
    id<MTLTexture> _texture;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _metalRenderer = [[iTermMetalRenderer alloc] initWithDevice:device
                                                 vertexFunctionName:@"iTermBackgroundImageVertexShader"
                                               fragmentFunctionName:@"iTermBackgroundImageFragmentShader"
                                                           blending:nil
                                                transientStateClass:[iTermBackgroundImageRendererTransientState class]];
#if ENABLE_TRANSPARENT_METAL_WINDOWS
        _alphaPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(float)];
#endif
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateBackgroundImageTS;
}

- (void)setImage:(NSImage *)image tiled:(BOOL)tiled context:(nullable iTermMetalBufferPoolContext *)context {
    if (image != _image) {
        _texture = image ? [_metalRenderer textureFromImage:image context:context] : nil;
    }
    _image = image;
    _tiled = tiled;
}

#if ENABLE_TRANSPARENT_METAL_WINDOWS
- (id<MTLBuffer>)alphaBufferWithValue:(float)value
                          poolContext:(iTermMetalBufferPoolContext *)poolContext {
    return [_alphaPool requestBufferFromContext:poolContext
                                      withBytes:&value
                                 checkIfChanged:YES];
    
}
#endif

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalRendererTransientState *)transientState {
    iTermBackgroundImageRendererTransientState *tState = transientState;
    [self loadVertexBuffer:tState];
    
    NSDictionary *fragmentBuffers = nil;
#if ENABLE_TRANSPARENT_METAL_WINDOWS
    float alpha = tState.transparencyAlpha;
    if (alpha < 1) {
        _metalRenderer.fragmentFunctionName = @"iTermBackgroundImageWithAlphaFragmentShader";
        id<MTLBuffer> alphaBuffer = [self alphaBufferWithValue:alpha poolContext:tState.poolContext];
        fragmentBuffers = @{ @(iTermFragmentInputIndexAlpha): alphaBuffer };
    } else {
        _metalRenderer.fragmentFunctionName = @"iTermBackgroundImageFragmentShader";
        fragmentBuffers = @{};
    }
#else
    _metalRenderer.fragmentFunctionName = @"iTermBackgroundImageFragmentShader";
    fragmentBuffers = @{};
#endif
    
    tState.pipelineState = [_metalRenderer pipelineState];

    [_metalRenderer drawWithTransientState:tState
                             renderEncoder:frameData.renderEncoder
                          numberOfVertices:6
                              numberOfPIUs:0
                             vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer }
                           fragmentBuffers:fragmentBuffers
                                  textures:@{ @(iTermTextureIndexPrimary): tState.texture }];
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForConfiguration:(iTermRenderConfiguration *)configuration
                                                                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    if (_image == nil) {
        return nil;
    }
    iTermBackgroundImageRendererTransientState * _Nonnull tState =
        [_metalRenderer createTransientStateForConfiguration:configuration
                                               commandBuffer:commandBuffer];

    [self initializeTransientState:tState];

    return tState;
}

- (void)initializeTransientState:(iTermBackgroundImageRendererTransientState *)tState {
    tState.texture = _texture;
    tState.tiled = _tiled;
    tState.imageSize = _image.size;
}

- (void)loadVertexBuffer:(iTermBackgroundImageRendererTransientState *)tState {
    const CGFloat scale = tState.configuration.scale;
    const CGSize nativeTextureSize = NSMakeSize(tState.imageSize.width * scale,
                                                tState.imageSize.height * scale);
    const CGSize size = CGSizeMake(tState.configuration.viewportSize.x,
                                   tState.configuration.viewportSize.y);
    CGSize textureSize;
    if (_tiled) {
        textureSize = CGSizeMake(size.width / nativeTextureSize.width,
                                 size.height / nativeTextureSize.height);
    } else {
        textureSize = CGSizeMake(1, 1);
    }
    NSEdgeInsets insets = tState.edgeInsets;
    CGFloat vmargin;
    if (@available(macOS 10.14, *)) {
        vmargin = 0;
    } else {
        vmargin = [iTermAdvancedSettingsModel terminalVMargin] * scale;
    }
    const CGFloat topMargin = insets.bottom + vmargin;
    const CGFloat bottomMargin = insets.top + vmargin;
    const CGFloat leftMargin = insets.left;
    const CGFloat rightMargin = insets.right;
    tState.vertexBuffer = [_metalRenderer newQuadWithFrame:CGRectMake(-leftMargin,
                                                                      -topMargin,
                                                                      size.width + leftMargin + rightMargin,
                                                                      size.height + topMargin + bottomMargin)
                                              textureFrame:CGRectMake(0,
                                                                      0,
                                                                      textureSize.width,
                                                                      textureSize.height)
                                               poolContext:tState.poolContext];
}

@end

NS_ASSUME_NONNULL_END
