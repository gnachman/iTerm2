#import "iTermBackgroundColorRenderer.h"

#import "iTermPIUArray.h"
#import "iTermTextRenderer.h"

@interface iTermBackgroundColorRendererTransientState()
@property (nonatomic, readonly) iTermBackgroundColorConfiguration backgroundColorConfiguration;
@end

@implementation iTermBackgroundColorRendererTransientState

- (iTermBackgroundColorConfiguration)backgroundColorConfiguration {
    iTermBackgroundColorConfiguration backgroundColorConfiguration = {
        .cellSize = simd_make_float2(self.cellConfiguration.cellSize.width,
                                     self.cellConfiguration.cellSize.height),
        .gridSize = simd_make_uint2(self.cellConfiguration.gridSize.width,
                                    self.cellConfiguration.gridSize.height)
    };
    return backgroundColorConfiguration;
}

@end

@interface iTermBackgroundColorRenderer() <iTermMetalDebugInfoFormatter>
@end

@implementation iTermBackgroundColorRenderer {
    iTermMetalCellRenderer *_cellRenderer;
    iTermMetalBufferPool *_configPool;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:@"iTermBackgroundColorVertexShader"
                                                  fragmentFunctionName:@"iTermBackgroundColorFragmentShader"
                                                              blending:[[iTermMetalBlending alloc] init]
                                                        piuElementSize:1
                                                   transientStateClass:[iTermBackgroundColorRendererTransientState class]];
        _cellRenderer.formatterDelegate = self;
        _configPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermBackgroundColorConfiguration)];
    }
    return self;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateBackgroundColorTS;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (__kindof iTermMetalRendererTransientState * _Nonnull)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    __kindof iTermMetalCellRendererTransientState * _Nonnull transientState =
        [_cellRenderer createTransientStateForCellConfiguration:configuration
                                              commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermBackgroundColorRendererTransientState *)tState {
    tState.vertexBuffer = [_cellRenderer newQuadOfSize:tState.cellConfiguration.cellSize
                                           poolContext:tState.poolContext];
    tState.vertexBuffer.label = @"Vertices";
}


- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(nonnull __kindof iTermMetalRendererTransientState *)transientState {
    iTermBackgroundColorRendererTransientState *tState = transientState;
    iTermBackgroundColorConfiguration config = tState.backgroundColorConfiguration;
    id<MTLBuffer> configBuffer = [_configPool requestBufferFromContext:tState.poolContext
                                                             withBytes:&config
                                                        checkIfChanged:YES];
    [_cellRenderer drawWithTransientState:tState
                            renderEncoder:renderEncoder
                         numberOfVertices:6
                             numberOfPIUs:config.gridSize.x * config.gridSize.y
                            vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                             @(iTermVertexInputBackgroundColorConfiguration): configBuffer,
                                             @(iTermVertexInputIndexOffset): tState.offsetBuffer,
                                             @(iTermVertexInputCellColors): tState.colorsBuffer
                                             }
                          fragmentBuffers:@{}
                                 textures:@{} ];
}

#pragma mark - iTermMetalDebugInfoFormatter

- (void)writeVertexBuffer:(id<MTLBuffer>)buffer index:(NSUInteger)index toFolder:(NSURL *)folder {
    if (index == iTermVertexInputBackgroundColorConfiguration) {
        iTermBackgroundColorConfiguration *config = (iTermBackgroundColorConfiguration *)buffer.contents;
        NSMutableString *s = [NSMutableString stringWithFormat:@"cellSize=%@x%@\ngridSize=%@x%@",
                              @(config->cellSize.x),
                              @(config->cellSize.y),
                              @(config->gridSize.x),
                              @(config->gridSize.y)];
        NSURL *url = [folder URLByAppendingPathComponent:@"vertexBuffer.iTermVertexInputIndexPerInstanceUniforms.txt"];
        [s writeToURL:url atomically:NO encoding:NSUTF8StringEncoding error:nil];
    }
}

@end
