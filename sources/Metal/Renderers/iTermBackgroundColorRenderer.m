#import "iTermBackgroundColorRenderer.h"

@implementation iTermBackgroundColorRendererTransientState

- (NSUInteger)sizeOfNewPIUBuffer {
    return sizeof(iTermBackgroundColorPIU) * self.gridSize.width * self.gridSize.height;
}

- (void)initializePIUBytes:(void *)bytes {
    NSInteger i = 0;
    vector_float2 cellSize = simd_make_float2(self.cellSize.width, self.cellSize.height);
    vector_float4 defaultColor = simd_make_float4(1, 0, 0, 1);
    iTermBackgroundColorPIU *pius = (iTermBackgroundColorPIU *)bytes;
    for (NSInteger y = 0; y < self.gridSize.height; y++) {
        const float rowOffset = (self.gridSize.height - y - 1);
        vector_float2 gridCoord = simd_make_float2(0, rowOffset);
        for (NSInteger x = 0; x < self.gridSize.width; x++) {
            gridCoord.x = x;
            pius[i].offset = gridCoord * cellSize;
            pius[i].color = defaultColor;
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

    tState.pius = [_cellRenderer.device newBufferWithLength:tState.sizeOfNewPIUBuffer
                                                    options:MTLResourceStorageModeShared];
    [tState initializePIUBytes:tState.pius.contents];
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
