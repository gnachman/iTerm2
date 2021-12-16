#import "iTermBroadcastStripesRenderer.h"

#import "iTermMetalBufferPool.h"
#import "iTermSharedImageStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBroadcastStripesRendererTransientState : iTermMetalCellRendererTransientState
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic) CGSize size;
@end

@implementation iTermBroadcastStripesRendererTransientState

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];
    [[NSString stringWithFormat:@"size=%@", NSStringFromSize(self.size)] writeToURL:[folder URLByAppendingPathComponent:@"state.txt"]
                                                                         atomically:NO
                                                                           encoding:NSUTF8StringEncoding
                                                                              error:NULL];
}

@end

@implementation iTermBroadcastStripesRenderer {
    iTermMetalCellRenderer *_metalRenderer;
    id<MTLTexture> _texture;
    CGSize _size;
    iTermMetalBufferPool *_verticesPool;
    NSColorSpace *_colorSpace;
    NSImage *image;
    iTermImageWrapper *_imageWrapper;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _metalRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                     vertexFunctionName:@"iTermBroadcastStripesVertexShader"
                                                   fragmentFunctionName:@"iTermBroadcastStripesFragmentShader"
                                                               blending:[iTermMetalBlending atop]
                                                         piuElementSize:1
                                                    transientStateClass:[iTermBroadcastStripesRendererTransientState class]];
        NSImage *image = [[NSBundle bundleForClass:self.class] imageForResource:@"BackgroundStripes"];
        _imageWrapper = [iTermImageWrapper withImage:image];
        _size = image.size;
        _verticesPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermVertex) * 6];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateBroadcastStripesTS;
}

- (void)setColorSpace:(NSColorSpace *)colorSpace {
    if (colorSpace == _colorSpace) {
        return;
    }
    _colorSpace = colorSpace;
    _texture = [_metalRenderer textureFromImage:_imageWrapper
                                        context:nil
                                     colorSpace:colorSpace];
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermBroadcastStripesRendererTransientState *tState = transientState;
    [_metalRenderer drawWithTransientState:tState
                             renderEncoder:frameData.renderEncoder
                          numberOfVertices:6
                              numberOfPIUs:0
                             vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer }
                           fragmentBuffers:@{}
                                  textures:@{ @(iTermTextureIndexPrimary): tState.texture }];
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    if (!_enabled) {
        return nil;
    }
    __kindof iTermMetalRendererTransientState * _Nonnull transientState =
        [_metalRenderer createTransientStateForConfiguration:configuration
                                           commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermBroadcastStripesRendererTransientState *)tState {
    tState.texture = _texture;
    CGSize size = _size;
    size.width *= tState.configuration.scale;
    size.height *= tState.configuration.scale;
    tState.size = size;

    // The quad is exactly the area where text can appear, excluding margins.
    const vector_uint2 viewportSize = tState.configuration.viewportSizeExcludingLegacyScrollbars;
    const NSEdgeInsets margins = tState.margins;
    const float destRight = margins.left + tState.cellConfiguration.gridSize.width * tState.cellConfiguration.cellSize.width;
    const float destHeight = viewportSize.y - tState.configuration.extraMargins.top - tState.configuration.extraMargins.bottom;
    const float destBottom = tState.configuration.extraMargins.bottom;
    const float destTop = destBottom + destHeight;
    const float destLeft = margins.left;

    const float textureWidth = (destRight - destLeft) / size.width;
    const float textureHeight = destHeight / size.height;

    const iTermVertex vertices[] = {
        // Pixel Positions, Texture Coordinates
        { { destRight, destBottom },     { textureWidth, 0 } },
        { { destLeft,  destBottom },     { 0,            0 } },
        { { destLeft,  destTop    },     { 0,            textureHeight } },

        { { destRight, destBottom },     { textureWidth, 0 } },
        { { destLeft,  destTop    },     { 0,            textureHeight } },
        { { destRight, destTop    },     { textureWidth, textureHeight } },
    };
    tState.vertexBuffer = [_verticesPool requestBufferFromContext:tState.poolContext
                                                        withBytes:vertices
                                                   checkIfChanged:YES];
}

@end

NS_ASSUME_NONNULL_END

