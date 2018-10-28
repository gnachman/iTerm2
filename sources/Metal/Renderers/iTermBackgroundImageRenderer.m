#import "iTermBackgroundImageRenderer.h"

#import "ITAddressBookMgr.h"
#import "FutureMethods.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermShaderTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBackgroundImageRendererTransientState ()
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic) iTermBackgroundImageMode mode;
@property (nonatomic) BOOL repeat;
@property (nonatomic) NSSize imageSize;
@property (nonatomic) CGRect frame;
@property (nonatomic) CGSize containerSize;
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
    CGRect _frame;
    CGSize _containerSize;
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
        if (iTermTextIsMonochrome()) {
            _alphaPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(float)];
        }
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

- (void)setImage:(NSImage *)image
            mode:(iTermBackgroundImageMode)mode
           frame:(CGRect)frame
   containerSize:(CGSize)containerSize
         context:(nullable iTermMetalBufferPoolContext *)context {
    if (image != _image) {
        _texture = image ? [_metalRenderer textureFromImage:image context:context] : nil;
    }
    _frame = frame;
    _containerSize = containerSize;
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
    tState.frame = _frame;
    tState.containerSize = _containerSize;
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
        insets = NSEdgeInsetsZero;
    } else {
        vmargin = [iTermAdvancedSettingsModel terminalVMargin] * scale;
        insets = tState.edgeInsets;
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
    const CGRect frame = tState.frame;
    const CGSize containerSize = CGSizeMake(tState.containerSize.width * scale,
                                            tState.containerSize.height * scale);
    const CGFloat containerHeight = viewHeight / frame.size.height;
    const CGFloat containerWidth = viewWidth / frame.size.width;
    const CGFloat containerAspectRatio = containerWidth / containerHeight;

    switch (_mode) {
        case iTermBackgroundImageModeStretch:
            textureFrame = CGRectMake(frame.origin.x * nativeTextureSize.width,
                                      frame.origin.y * nativeTextureSize.height,
                                      frame.size.width * nativeTextureSize.width,
                                      frame.size.height * nativeTextureSize.height);
            break;
            
        case iTermBackgroundImageModeTile:
            textureFrame = CGRectMake(frame.origin.x * containerSize.width,
                                      frame.origin.y * containerSize.height,
                                      viewportSize.width,
                                      viewportSize.height);
            break;
            
        case iTermBackgroundImageModeScaleAspectFit: {
            const CGRect myFrameInContainer = CGRectMake(frame.origin.x * containerSize.width,
                                                         frame.origin.y * containerSize.height,
                                                         frame.size.width * containerSize.width,
                                                         frame.size.height * containerSize.height);
            CGRect globalQuadFrame;
            CGFloat globalLetterboxHeight = 0;
            CGFloat globalPillarboxWidth = 0;
            if (imageAspectRatio > containerAspectRatio) {
                // Image is wide relative to view.
                // There will be letterboxes top and bottom.
                globalLetterboxHeight = (containerHeight - containerWidth / imageAspectRatio) / 2.0;
                globalQuadFrame = CGRectMake(minX,
                                             minY + globalLetterboxHeight,
                                             containerWidth,
                                             containerHeight - globalLetterboxHeight * 2);
            } else {
                // Image is tall relative to view.
                // There will be pillarboxes left and right.
                globalPillarboxWidth = (containerWidth - containerHeight * imageAspectRatio) / 2.0;
                globalQuadFrame = CGRectMake(minX + globalPillarboxWidth,
                                             minY,
                                             containerWidth - globalPillarboxWidth * 2,
                                             containerHeight);
            }
            quadFrame = CGRectIntersection(myFrameInContainer, globalQuadFrame);
            quadFrame.origin.x -= myFrameInContainer.origin.x;
            quadFrame.origin.y -= myFrameInContainer.origin.y;

            // Constructs a rect giving what the texture frame *would* be if it extended corner to corner. That means
            // if there are letterboxes/pillarboxes then the origin will have a negative x or y value and a width or
            // height more than 1. If there is no letterbox/pillarbox the rect will be (0,0,1,1).
            const CGRect relativeGlobalTextureFrame =
                CGRectMake(-globalPillarboxWidth / globalQuadFrame.size.width,
                           -globalLetterboxHeight / globalQuadFrame.size.height,
                           containerWidth / globalQuadFrame.size.width,
                           containerHeight / globalQuadFrame.size.height);
            
            // Converts the relativeGlobalTextureFrame to pixel space where the origin (0,0) is the origin of where
            // the top-left pixel of the quad that's actually drawn will be.
            const CGRect globalTextureFrameInQuadSpace =
                CGRectMake(relativeGlobalTextureFrame.origin.x * containerWidth,
                           relativeGlobalTextureFrame.origin.y * containerHeight,
                           relativeGlobalTextureFrame.size.width * containerWidth,
                           relativeGlobalTextureFrame.size.height * containerHeight);
            
            // This gives the pixel-space texture coordinates that will be in this view
            const CGRect myTextureFrame = CGRectIntersection(globalTextureFrameInQuadSpace, myFrameInContainer);
            
            // Convert from pixel space to texture space.
            textureFrame = CGRectMake(myTextureFrame.origin.x / containerWidth * nativeTextureSize.width,
                                      myTextureFrame.origin.y / containerHeight * nativeTextureSize.height,
                                      myTextureFrame.size.width / containerWidth * nativeTextureSize.width,
                                      myTextureFrame.size.height / containerHeight * nativeTextureSize.height);
            break;
        }
            
        case iTermBackgroundImageModeScaleAspectFill: {
            CGRect globalTextureFrame;
            if (imageAspectRatio > containerAspectRatio) {
                // Image is wide relative to view.
                // Crop left and right.
                const CGFloat width = nativeTextureSize.height * containerAspectRatio;
                const CGFloat crop = (nativeTextureSize.width - width) / 2.0;
                globalTextureFrame = CGRectMake(crop, 0, width, nativeTextureSize.height);
            } else {
                // Image is tall relative to view.
                // Crop top and bottom.
                const CGFloat height = nativeTextureSize.width / containerAspectRatio;
                const CGFloat crop = (nativeTextureSize.height - height) / 2.0;
                globalTextureFrame = CGRectMake(0, crop, nativeTextureSize.width, height);
            }
            const CGRect myFrameInContainer = CGRectMake(frame.origin.x * containerSize.width,
                                                         frame.origin.y * containerSize.height,
                                                         frame.size.width * containerSize.width,
                                                         frame.size.height * containerSize.height);
            const CGRect relativeGlobalTextureFrame =
                CGRectMake(globalTextureFrame.origin.x / nativeTextureSize.width,
                           globalTextureFrame.origin.y / nativeTextureSize.height,
                           globalTextureFrame.size.width / nativeTextureSize.width,
                           globalTextureFrame.size.height / nativeTextureSize.height);
            const CGRect globalTextureFrameInQuadSpace =
                CGRectMake(relativeGlobalTextureFrame.origin.x * containerWidth,
                           relativeGlobalTextureFrame.origin.y * containerHeight,
                           relativeGlobalTextureFrame.size.width * containerWidth,
                           relativeGlobalTextureFrame.size.height * containerHeight);
            // This gives the pixel-space texture coordinates that will be in this view
            const CGRect myTextureFrame = CGRectIntersection(globalTextureFrameInQuadSpace, myFrameInContainer);
            // Convert from pixel space to texture space.
            textureFrame = CGRectMake(myTextureFrame.origin.x / containerWidth * nativeTextureSize.width,
                                      myTextureFrame.origin.y / containerHeight * nativeTextureSize.height,
                                      myTextureFrame.size.width / containerWidth * nativeTextureSize.width,
                                      myTextureFrame.size.height / containerHeight * nativeTextureSize.height);
            break;
        }
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
