#import "iTermCursorGuideRenderer.h"

@interface iTermCursorGuideRendererTransientState : iTermMetalCellRendererTransientState
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic, strong) NSColor *color;
@property (nonatomic) int row;

- (nonnull NSData *)newCursorGuidePerInstanceUniforms;

@end

@implementation iTermCursorGuideRendererTransientState

- (nonnull NSData *)newCursorGuidePerInstanceUniforms {
    NSMutableData *data = [[NSMutableData alloc] initWithLength:sizeof(iTermCursorGuidePIU) * self.gridSize.width];
    iTermCursorGuidePIU *pius = (iTermCursorGuidePIU *)data.mutableBytes;
    for (size_t i = 0; i < self.gridSize.width; i++) {
        pius[i] = (iTermCursorGuidePIU) {
            .offset = {
                i * self.cellSize.width,
                (self.gridSize.height - _row - 1) * self.cellSize.height
            },
        };
    }
    return data;
}

@end

@implementation iTermCursorGuideRenderer {
    iTermMetalCellRenderer *_cellRenderer;
    id<MTLTexture> _texture;
    NSColor *_color;
    int _row;
    CGSize _lastCellSize;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _color = [[NSColor blueColor] colorWithAlphaComponent:0.7];
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:@"iTermCursorGuideVertexShader"
                                                  fragmentFunctionName:@"iTermCursorGuideFragmentShader"
                                                              blending:YES
                                                        piuElementSize:sizeof(iTermCursorGuidePIU)
                                                   transientStateClass:[iTermCursorGuideRendererTransientState class]];
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

- (void)initializeTransientState:(iTermCursorGuideRendererTransientState *)tState {
    tState.color = _color;
    tState.row = _row;
    tState.vertexBuffer = [_cellRenderer newQuadOfSize:tState.cellSize];
    if (!CGSizeEqualToSize(tState.cellSize, _lastCellSize)) {
        _texture = [self newCursorGuideTextureWithTransientState:tState];
        _lastCellSize = tState.cellSize;
    }
    tState.texture = _texture;
    [self updatePIUsInState:tState];
}

- (void)setColor:(NSColor *)color {
    _color = color;
    _lastCellSize = CGSizeZero;
}

- (void)setRow:(int)row {
    _row = row;
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermCursorGuideRendererTransientState *tState = transientState;
    [_cellRenderer drawWithTransientState:tState
                            renderEncoder:renderEncoder
                         numberOfVertices:6
                             numberOfPIUs:tState.gridSize.width
                            vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                             @(iTermVertexInputIndexPerInstanceUniforms): tState.pius,
                                             @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                          fragmentBuffers:@{}
                                 textures:@{ @(iTermTextureIndexPrimary): tState.texture } ];
}

#pragma mark - Private

- (void)updatePIUsInState:(iTermCursorGuideRendererTransientState *)tState {
    NSData *data = [tState newCursorGuidePerInstanceUniforms];
    tState.pius = [_cellRenderer.device newBufferWithLength:data.length options:MTLResourceStorageModeShared];
    memcpy(tState.pius.contents, data.bytes, data.length);
}

- (id<MTLTexture>)newCursorGuideTextureWithTransientState:(iTermCursorGuideRendererTransientState *)tState {
    NSImage *image = [[NSImage alloc] initWithSize:tState.cellSize];

    [image lockFocus];
    {
        [tState.color set];
        NSRect rect = NSMakeRect(0,
                                 0,
                                 tState.cellSize.width,
                                 tState.cellSize.height);
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);

        rect.size.height = 1;
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);

        rect.origin.y += tState.cellSize.height - 1;
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
    }
    [image unlockFocus];

    return [_cellRenderer textureFromImage:image];
}

@end
