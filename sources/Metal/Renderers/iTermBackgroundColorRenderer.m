#import "iTermBackgroundColorRenderer.h"

#import "iTermTextRenderer.h"

@interface iTermBackgroundColorRendererTransientState()
@property (nonatomic, readonly) NSInteger numberOfPIUs;
@end

@implementation iTermBackgroundColorRendererTransientState

- (NSUInteger)sizeOfNewPIUBuffer {
    return sizeof(iTermBackgroundColorPIU) * self.cellConfiguration.gridSize.width * self.cellConfiguration.gridSize.height;
}

- (void)setColorRLEs:(const iTermMetalBackgroundColorRLE *)rles
               count:(size_t)count
                 row:(int)row
               width:(int)width {
    vector_float2 cellSize = simd_make_float2(self.cellConfiguration.cellSize.width, self.cellConfiguration.cellSize.height);
    iTermBackgroundColorPIU *pius = (iTermBackgroundColorPIU *)self.pius.contents + sizeof(iTermBackgroundColorPIU) * _numberOfPIUs;
    const int height = self.cellConfiguration.gridSize.height;
    for (int i = 0; i < count; i++) {
        pius[i].color = rles[i].color;
        pius[i].runLength = rles[i].count;
        pius[i].offset = simd_make_float2(cellSize.x * (float)rles[i].origin,
                                          cellSize.y * (height - row - 1));
    }
    _numberOfPIUs += count;
}

@end

@implementation iTermBackgroundColorRenderer {
    iTermMetalCellRenderer *_cellRenderer;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:@"iTermBackgroundColorVertexShader"
                                                  fragmentFunctionName:@"iTermBackgroundColorFragmentShader"
                                                              blending:YES
                                                        piuElementSize:sizeof(iTermBackgroundColorPIU)
                                                   transientStateClass:[iTermBackgroundColorRendererTransientState class]];
    }
    return self;
}

- (void)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                      completion:(void (^)(__kindof iTermMetalRendererTransientState * _Nonnull))completion {
    [_cellRenderer createTransientStateForCellConfiguration:configuration
                                              commandBuffer:commandBuffer
                                                 completion:^(__kindof iTermMetalCellRendererTransientState * _Nonnull transientState) {
                                                     [self initializeTransientState:transientState];
                                                     completion(transientState);
                                                 }];
}

- (void)initializeTransientState:(iTermBackgroundColorRendererTransientState *)tState {
    tState.vertexBuffer = [_cellRenderer newQuadOfSize:tState.cellConfiguration.cellSize];

    // TODO: This is kinda big since it holds the worst case of every cell having a different
    // background color than its neighbors. See if it's a performance bottleneck and consider using
    // one draw call per line and a number of small PIU buffers.
    tState.pius = [_cellRenderer.device newBufferWithLength:tState.cellConfiguration.gridSize.width * tState.cellConfiguration.gridSize.height * sizeof(iTermBackgroundColorPIU)
                                                    options:MTLResourceStorageModeShared];
}


- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(nonnull __kindof iTermMetalRendererTransientState *)transientState {
    iTermBackgroundColorRendererTransientState *tState = transientState;
    [_cellRenderer drawWithTransientState:tState
                            renderEncoder:renderEncoder
                         numberOfVertices:6
                             numberOfPIUs:tState.numberOfPIUs
                            vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                             @(iTermVertexInputIndexPerInstanceUniforms): tState.pius,
                                             @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                          fragmentBuffers:@{}
                                 textures:@{} ];
}

@end
