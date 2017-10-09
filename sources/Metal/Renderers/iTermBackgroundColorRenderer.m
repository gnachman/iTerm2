#import "iTermBackgroundColorRenderer.h"

@implementation iTermBackgroundColorRendererTransientState

- (nonnull NSMutableData *)newPerInstanceUniformData  {
    NSMutableData *data = [[NSMutableData alloc] initWithLength:sizeof(iTermBackgroundColorPIU) * self.gridSize.width * self.gridSize.height];
    [self initializePIUData:data];
    return data;
}

- (void)initializePIUData:(NSMutableData *)data {
    void *bytes = data.mutableBytes;
    NSInteger i = 0;
    for (NSInteger y = 0; y < self.gridSize.height; y++) {
        for (NSInteger x = 0; x < self.gridSize.width; x++) {
            const iTermBackgroundColorPIU uniform = {
                .offset = {
                    x * self.cellSize.width,
                    (self.gridSize.height - y - 1) * self.cellSize.height
                },
                .color = (vector_float4){ 1, 0, 0, 1 }
            };
            memcpy(bytes + i * sizeof(uniform), &uniform, sizeof(uniform));
            i++;
        }
    }
}

- (void)setColorData:(NSData *)colorData
                 row:(int)row
               width:(int)width {
    iTermBackgroundColorPIU *pius = (iTermBackgroundColorPIU *)[self piuForCoord:VT100GridCoordMake(0, row)];
    const vector_float4 *colors = (const vector_float4 *)colorData.bytes;
    for (int x = 0; x < width; x++) {
        pius[x].color = colors[x];
    }
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

- (void)createTransientStateForViewportSize:(vector_uint2)viewportSize
                                   cellSize:(CGSize)cellSize
                                   gridSize:(VT100GridSize)gridSize
                              commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                 completion:(void (^)(__kindof iTermMetalCellRendererTransientState * _Nonnull))completion {
    [_cellRenderer createTransientStateForViewportSize:viewportSize
                                              cellSize:cellSize
                                              gridSize:gridSize
                                         commandBuffer:commandBuffer
                                            completion:^(__kindof iTermMetalCellRendererTransientState * _Nonnull transientState) {
                                                [self initializeTransientState:transientState];
                                                completion(transientState);
                                            }];
}

- (void)initializeTransientState:(iTermBackgroundColorRendererTransientState *)tState {
    tState.vertexBuffer = [_cellRenderer newQuadOfSize:tState.cellSize];

    NSMutableData *data = [tState newPerInstanceUniformData];
    tState.pius = [_cellRenderer.device newBufferWithLength:data.length
                                                    options:MTLResourceStorageModeShared];
    memcpy(tState.pius.contents, data.bytes, data.length);
}


- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(nonnull __kindof iTermMetalRendererTransientState *)transientState {
    iTermBackgroundColorRendererTransientState *tState = transientState;
    [_cellRenderer drawWithTransientState:tState
                            renderEncoder:renderEncoder
                         numberOfVertices:6
                             numberOfPIUs:tState.gridSize.width * tState.gridSize.height
                            vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                             @(iTermVertexInputIndexPerInstanceUniforms): tState.pius,
                                             @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                          fragmentBuffers:@{}
                                 textures:@{} ];
}

@end
