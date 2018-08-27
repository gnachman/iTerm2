#import "iTermBroadcastStripesRenderer.h"

#import "iTermMetalBufferPool.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBroadcastStripesRendererTransientState : iTermMetalRendererTransientState
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
    iTermMetalRenderer *_metalRenderer;
    id<MTLTexture> _texture;
    CGSize _size;
    iTermMetalBufferPool *_verticesPool;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _metalRenderer = [[iTermMetalRenderer alloc] initWithDevice:device
                                                 vertexFunctionName:@"iTermBroadcastStripesVertexShader"
                                               fragmentFunctionName:@"iTermBroadcastStripesFragmentShader"
                                                           blending:[iTermMetalBlending compositeSourceOver]
                                                transientStateClass:[iTermBroadcastStripesRendererTransientState class]];
        NSImage *image = [[NSBundle bundleForClass:self.class] imageForResource:@"BackgroundStripes"];
        _size = image.size;
        _texture = [_metalRenderer textureFromImage:image context:nil];
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

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalRendererTransientState *)transientState {
    iTermBroadcastStripesRendererTransientState *tState = transientState;
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

    const vector_uint2 viewportSize = tState.configuration.viewportSize;
    const float maxX = viewportSize.x / size.width;
    const float maxY = viewportSize.y / size.height;
    const iTermVertex vertices[] = {
        // Pixel Positions, Texture Coordinates
        { { viewportSize.x, 0 },              { maxX, 0 } },
        { { 0,              0 },              { 0,    0 } },
        { { 0, viewportSize.y },              { 0,    maxY } },

        { { viewportSize.x, 0 },              { maxX, 0 } },
        { { 0,              viewportSize.y }, { 0,    maxY } },
        { { viewportSize.x, viewportSize.y }, { maxX, maxY } },
    };
    tState.vertexBuffer = [_verticesPool requestBufferFromContext:tState.poolContext
                                                        withBytes:vertices
                                                   checkIfChanged:YES];
}

@end

NS_ASSUME_NONNULL_END

