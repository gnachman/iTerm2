#import "iTermBackgroundImageRenderer.h"

#import "ITAddressBookMgr.h"
#import "FutureMethods.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermBackgroundDrawingHelper.h"
#import "iTermPreferences.h"
#import "iTermShaderTypes.h"
#import "iTermSharedImageStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBackgroundImageRendererTransientState ()
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic) iTermBackgroundImageMode mode;
@property (nonatomic) BOOL repeat;
@property (nonatomic) NSSize imageSize;
@property (nonatomic) CGFloat imageScale;
@property (nonatomic) CGRect frame;
@property (nonatomic) CGRect containerFrame;
@property (nonatomic) vector_float4 defaultBackgroundColor;
@property (nullable, nonatomic, strong) id<MTLBuffer> box1;
@property (nullable, nonatomic, strong) id<MTLBuffer> box2;
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
    iTermMetalBufferPool *_colorPool;
    iTermMetalBufferPool *_solidColorPool;
    iTermMetalBufferPool *_box1Pool;
    iTermMetalBufferPool *_box2Pool;
    iTermBackgroundImageMode _mode;
    iTermImageWrapper *_image;
    id<MTLTexture> _texture;
    CGRect _frame;
    CGRect _containerFrame;
    vector_float4 _color;
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
        _box1Pool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermVertex) * 6];
        _box2Pool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermVertex) * 6];
        _colorPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(vector_float4)];
        _solidColorPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(vector_float4)];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateBackgroundImageTS;
}

- (void)setImage:(iTermImageWrapper *)image
            mode:(iTermBackgroundImageMode)mode
           frame:(CGRect)frame
   containerRect:(CGRect)containerRect
           color:(vector_float4)defaultBackgroundColor
      colorSpace:(NSColorSpace *)colorSpace
         context:(nullable iTermMetalBufferPoolContext *)context {
    if (image != _image) {
        _texture = image ? [_metalRenderer textureFromImage:image context:context colorSpace:colorSpace] : nil;
    }
    _frame = frame;
    _color = defaultBackgroundColor;
    _containerFrame = containerRect;
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

- (id<MTLBuffer>)colorBufferWithColor:(vector_float4)color
                                alpha:(CGFloat)alpha
                          poolContext:(iTermMetalBufferPoolContext *)poolContext {
    vector_float4 premultiplied = color * alpha;
    premultiplied.w = alpha;
    iTermMetalBufferPool *pool = (alpha == 1) ? _solidColorPool : _colorPool;
    return [pool requestBufferFromContext:poolContext
                                withBytes:&premultiplied
                           checkIfChanged:YES];
}

- (id<MTLBuffer>)boxBufferWithRect:(CGRect)rect
                               box:(int)number
                       poolContext:(iTermMetalBufferPoolContext *)poolContext {
    iTermMetalBufferPool *pool = number == 1 ? _box1Pool : _box2Pool;
    const iTermVertex vertices[] = {
        // Pixel Positions       Texture Coordinates
        { { CGRectGetMaxX(rect), CGRectGetMinY(rect) }, { 0, 0 } },
        { { CGRectGetMinX(rect), CGRectGetMinY(rect) }, { 0, 0 } },
        { { CGRectGetMinX(rect), CGRectGetMaxY(rect) }, { 0, 0 } },
        
        { { CGRectGetMaxX(rect), CGRectGetMinY(rect) }, { 0, 0 } },
        { { CGRectGetMinX(rect), CGRectGetMaxY(rect) }, { 0, 0 } },
        { { CGRectGetMaxX(rect), CGRectGetMaxY(rect) }, { 0, 0 } },
    };
    return [pool requestBufferFromContext:poolContext
                                withBytes:vertices
                           checkIfChanged:YES];
}

- (id<MTLBuffer>)colorBufferForState:(iTermBackgroundImageRendererTransientState *)tState
                               alpha:(float)alpha {
    id<MTLBuffer> colorBuffer = [self colorBufferWithColor:tState.defaultBackgroundColor
                                                     alpha:alpha
                                               poolContext:tState.poolContext];
    return colorBuffer;
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalRendererTransientState *)transientState {
    iTermBackgroundImageRendererTransientState *tState = transientState;
    [self loadVertexBuffer:tState];
    
    NSDictionary *fragmentBuffers = nil;
#if ENABLE_TRANSPARENT_METAL_WINDOWS
    float alpha = tState.computedAlpha;

    // Alpha=1 here because an overall alpha is applied to the combination of underlayment and image.
    id<MTLBuffer> underlayColorBuffer = [self colorBufferForState:tState alpha:1];
    if (alpha < 1) {
        _metalRenderer.fragmentFunctionName = tState.repeat ? @"iTermBackgroundImageWithAlphaRepeatFragmentShader" : @"iTermBackgroundImageWithAlphaClampFragmentShader";
        id<MTLBuffer> alphaBuffer = [self alphaBufferWithValue:alpha poolContext:tState.poolContext];
        fragmentBuffers = @{ @(iTermFragmentInputIndexAlpha): alphaBuffer,
                             @(iTermFragmentInputIndexColor): underlayColorBuffer
        };
    } else {
        _metalRenderer.fragmentFunctionName = tState.repeat ? @"iTermBackgroundImageRepeatFragmentShader" : @"iTermBackgroundImageClampFragmentShader";
        fragmentBuffers = @{ @(iTermFragmentInputIndexColor): underlayColorBuffer };
    }
#else
    float alpha = 1;
    id<MTLBuffer> colorBuffer = [self colorBufferForState:tState alpha:alpha];
    _metalRenderer.fragmentFunctionName = tState.repeat ? @"iTermBackgroundImageRepeatFragmentShader" : @"iTermBackgroundImageClampFragmentShader";
    fragmentBuffers = @{};
#endif
    
    tState.pipelineState = _metalRenderer.pipelineState;
    [_metalRenderer drawWithTransientState:tState
                             renderEncoder:frameData.renderEncoder
                          numberOfVertices:6
                              numberOfPIUs:0
                             vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer }
                           fragmentBuffers:fragmentBuffers
                                  textures:@{ @(iTermTextureIndexPrimary): tState.texture }];

    if (tState.box1) {
        assert(tState.box2);
        _metalRenderer.fragmentFunctionName = @"iTermBackgroundImageLetterboxFragmentShader";
        id<MTLBuffer> letterboxColorBuffer = [self colorBufferForState:tState alpha:alpha];
        tState.pipelineState = _metalRenderer.pipelineState;
        [_metalRenderer drawWithTransientState:tState
                                 renderEncoder:frameData.renderEncoder
                              numberOfVertices:6
                                  numberOfPIUs:0
                                 vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.box1 }
                               fragmentBuffers:@{ @(iTermFragmentInputIndexColor): letterboxColorBuffer }
                                      textures:@{}];
        [_metalRenderer drawWithTransientState:tState
                                 renderEncoder:frameData.renderEncoder
                              numberOfVertices:6
                                  numberOfPIUs:0
                                 vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.box2 }
                               fragmentBuffers:@{ @(iTermFragmentInputIndexColor): letterboxColorBuffer }
                                      textures:@{}];
    }
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
    tState.imageSize = _image.image.size;
    tState.imageScale = [_image.image recommendedLayerContentsScale:tState.configuration.scale];
    tState.repeat = (_mode == iTermBackgroundImageModeTile);
    tState.frame = _frame;
    tState.defaultBackgroundColor = _color;
    tState.containerFrame = _containerFrame;
}

- (void)loadVertexBuffer:(iTermBackgroundImageRendererTransientState *)tState {
    const CGFloat scale = tState.configuration.scale;
    const CGSize nativeTextureSize = NSMakeSize(tState.imageSize.width * tState.imageScale,
                                                tState.imageSize.height * tState.imageScale);
    const CGSize viewportSize = CGSizeMake(tState.configuration.viewportSize.x,
                                           tState.configuration.viewportSize.y);
    NSEdgeInsets insets;
    CGFloat vmargin;
    vmargin = 0;
    insets = NSEdgeInsetsZero;
    const CGFloat topMargin = insets.bottom + vmargin;
    const CGFloat bottomMargin = insets.top + vmargin;
    const CGFloat leftMargin = insets.left;
    const CGFloat rightMargin = insets.right;

    const CGFloat imageAspectRatio = nativeTextureSize.width / nativeTextureSize.height;
    
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
    CGRect textureFrame;
    const CGRect frame = tState.frame;
    const CGRect containerRect = CGRectMake(tState.containerFrame.origin.x * scale,
                                            tState.containerFrame.origin.y * scale,
                                            tState.containerFrame.size.width * scale,
                                            tState.containerFrame.size.height * scale);
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
            textureFrame = CGRectMake(frame.origin.x * containerRect.size.width,
                                      frame.origin.y * containerRect.size.height,
                                      viewportSize.width,
                                      viewportSize.height);
            break;
            
        case iTermBackgroundImageModeScaleAspectFit: {
            CGRect drawRect;
            const CGRect myFrameInContainer = CGRectMake(containerRect.origin.x + frame.origin.x * containerRect.size.width,
                                                         containerRect.origin.y + frame.origin.y * containerRect.size.height,
                                                         frame.size.width * containerRect.size.width,
                                                         frame.size.height * containerRect.size.height);
            NSRect box1 = NSZeroRect;
            NSRect box2 = NSZeroRect;
            textureFrame =
            [iTermBackgroundDrawingHelper scaleAspectFitSourceRectForForImageSize:nativeTextureSize
                                                                  destinationRect:containerRect
                                                                        dirtyRect:myFrameInContainer
                                                                         drawRect:&drawRect
                                                                         boxRect1:&box1
                                                                         boxRect2:&box2];

            // Convert frames into my coordinate system
            NSRect (^convertRect)(NSRect) = ^NSRect(NSRect drawRect) {
                return NSMakeRect(drawRect.origin.x - frame.origin.x * containerRect.size.width - containerRect.origin.x,
                                  drawRect.origin.y - frame.origin.y * containerRect.size.height - containerRect.origin.y,
                                  drawRect.size.width,
                                  drawRect.size.height);
            };
            quadFrame = convertRect(drawRect);
            tState.box1 = [self boxBufferWithRect:convertRect(box1) box:1 poolContext:tState.poolContext];
            tState.box2 = [self boxBufferWithRect:convertRect(box2) box:2 poolContext:tState.poolContext];
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
            textureFrame = CGRectMake(frame.origin.x * globalTextureFrame.size.width + globalTextureFrame.origin.x,
                                      frame.origin.y * globalTextureFrame.size.height + globalTextureFrame.origin.y,
                                      frame.size.width * globalTextureFrame.size.width,
                                      frame.size.height * globalTextureFrame.size.height);
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
