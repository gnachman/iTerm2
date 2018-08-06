#import "iTermBackgroundImageRenderer.h"

#import "ITAddressBookMgr.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermShaderTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBackgroundImageRendererTransientState ()
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic) iTermBackgroundImageMode mode;
@property (nonatomic) BOOL repeat;
@property (nonatomic) NSSize imageSize;
@end

@implementation iTermBackgroundImageRendererTransientState

- (BOOL)skipRenderer {
    return _texture == nil;
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];
    [[NSString stringWithFormat:@"mode=%@", @(_mode)] writeToURL:[folder URLByAppendingPathComponent:@"state.txt"]
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
    iTermBackgroundImageMode _mode;
    NSImage *_image;
    id<MTLTexture> _texture;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _metalRenderer = [[iTermMetalRenderer alloc] initWithDevice:device
                                                 vertexFunctionName:@"iTermBackgroundImageVertexShader"
                                               fragmentFunctionName:@"iTermBackgroundImageClampFragmentShader"
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

- (void)setImage:(NSImage *)image mode:(iTermBackgroundImageMode)mode context:(nullable iTermMetalBufferPoolContext *)context {
    if (image != _image) {
        _texture = image ? [_metalRenderer textureFromImage:image context:context] : nil;
    }
    _image = image;
    _mode = mode;
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
        _metalRenderer.fragmentFunctionName = tState.repeat ? @"iTermBackgroundImageWithAlphaRepeatFragmentShader" : @"iTermBackgroundImageWithAlphaClampFragmentShader";
        id<MTLBuffer> alphaBuffer = [self alphaBufferWithValue:alpha poolContext:tState.poolContext];
        fragmentBuffers = @{ @(iTermFragmentInputIndexAlpha): alphaBuffer };
    } else {
        _metalRenderer.fragmentFunctionName = tState.repeat ? @"iTermBackgroundImageRepeatFragmentShader" : @"iTermBackgroundImageClampFragmentShader";
        fragmentBuffers = @{};
    }
#else
    _metalRenderer.fragmentFunctionName = tState.repeat ? @"iTermBackgroundImageRepeatFragmentShader" : @"iTermBackgroundImageClampFragmentShader";
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
    tState.mode = _mode;
    tState.imageSize = _image.size;
    tState.repeat = (_mode == iTermBackgroundImageModeTile);
}

- (void)loadVertexBuffer:(iTermBackgroundImageRendererTransientState *)tState {
    const CGFloat scale = tState.configuration.scale;
    const CGSize nativeTextureSize = NSMakeSize(tState.imageSize.width * scale,
                                                tState.imageSize.height * scale);
    const CGSize viewportSize = CGSizeMake(tState.configuration.viewportSize.x,
                                           tState.configuration.viewportSize.y);
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

    const CGFloat imageAspectRatio = nativeTextureSize.width / nativeTextureSize.height;
    const CGFloat viewAspectRatio = viewportSize.width / viewportSize.height;
    
    // pixel coordinates
    const CGFloat viewHeight = viewportSize.height + topMargin + bottomMargin;
    const CGFloat viewWidth = viewportSize.width + leftMargin + rightMargin;
    const CGFloat minX = -leftMargin;
    const CGFloat minY = -topMargin;
    CGRect quadFrame = CGRectMake(minX,
                                  minY,
                                  viewWidth,
                                  viewHeight);
    
    // pixel coordinates
    CGRect textureFrame = CGRectMake(0, 0, nativeTextureSize.width, nativeTextureSize.height);
    switch (_mode) {
        case iTermBackgroundImageModeStretch:
            break;
            
        case iTermBackgroundImageModeTile:
            textureFrame = CGRectMake(0,
                                      0,
                                      viewportSize.width,
                                      viewportSize.height);
            break;
            
        case iTermBackgroundImageModeScaleAspectFit:
            if (imageAspectRatio > viewAspectRatio) {
                // Image is wide relative to view.
                // There will be letterboxes top and bottom.
                const CGFloat letterboxHeight = (viewHeight - viewWidth / imageAspectRatio) / 2.0;
                quadFrame = CGRectMake(minX,
                                       minY + letterboxHeight,
                                       viewWidth,
                                       viewHeight - letterboxHeight * 2);
            } else {
                // Image is tall relative to view.
                // There will be pillarboxes left and right.
                const CGFloat pillarboxWidth = (viewWidth - viewHeight * imageAspectRatio) / 2.0;
                quadFrame = CGRectMake(minX + pillarboxWidth,
                                       minY,
                                       viewWidth - pillarboxWidth * 2,
                                       viewHeight);
            }
            break;
            
        case iTermBackgroundImageModeScaleAspectFill:
            if (imageAspectRatio > viewAspectRatio) {
                // Image is wide relative to view.
                // Crop left and right.
                const CGFloat width = nativeTextureSize.height * viewAspectRatio;
                const CGFloat crop = (nativeTextureSize.width - width) / 2.0;
                textureFrame = CGRectMake(crop, 0, width, nativeTextureSize.height);
            } else {
                // Image is tall relative to view.
                // Crop top and bottom.
                const CGFloat height = nativeTextureSize.width / viewAspectRatio;
                const CGFloat crop = (nativeTextureSize.height - height) / 2.0;
                textureFrame = CGRectMake(0, crop, nativeTextureSize.width, height);
            }
            break;
    }

    // Convert textureFrame to normalized coordinates
    textureFrame.origin.x /= nativeTextureSize.width;
    textureFrame.size.width /= nativeTextureSize.width;
    textureFrame.origin.y /= nativeTextureSize.height;
    textureFrame.size.height /= nativeTextureSize.height;
    tState.vertexBuffer = [_metalRenderer newQuadWithFrame:quadFrame
                                              textureFrame:textureFrame
                                               poolContext:tState.poolContext];
}

@end

NS_ASSUME_NONNULL_END
