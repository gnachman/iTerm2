#import "iTermCursorGuideRenderer.h"

@interface iTermCursorGuideRendererTransientState : iTermMetalCellRendererTransientState
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic, strong) NSColor *color;
@property (nonatomic) int row;

- (nonnull NSData *)newCursorGuidePerInstanceUniforms;

@end

@implementation iTermCursorGuideRendererTransientState

- (nonnull NSData *)newCursorGuidePerInstanceUniforms {
    NSMutableData *data = [[NSMutableData alloc] initWithLength:sizeof(iTermCursorGuidePIU) * self.cellConfiguration.gridSize.width];
    iTermCursorGuidePIU *pius = (iTermCursorGuidePIU *)data.mutableBytes;
    for (size_t i = 0; i < self.cellConfiguration.gridSize.width; i++) {
        pius[i] = (iTermCursorGuidePIU) {
            .offset = {
                i * self.cellConfiguration.cellSize.width,
                (self.cellConfiguration.gridSize.height - _row - 1) * self.cellConfiguration.cellSize.height
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

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateCursorGuideTS;
}

- (__kindof iTermMetalRendererTransientState * _Nonnull)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    if (!_enabled) {
        return nil;
    }
    __kindof iTermMetalCellRendererTransientState * _Nonnull transientState =
        [_cellRenderer createTransientStateForCellConfiguration:configuration
                                                  commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermCursorGuideRendererTransientState *)tState {
    tState.color = _color;
    tState.row = _row;
    tState.vertexBuffer = [_cellRenderer newQuadOfSize:tState.cellConfiguration.cellSize
                                           poolContext:tState.poolContext];
    if (!CGSizeEqualToSize(tState.cellConfiguration.cellSize, _lastCellSize)) {
        _texture = [self newCursorGuideTextureWithTransientState:tState];
        _lastCellSize = tState.cellConfiguration.cellSize;
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
                             numberOfPIUs:tState.cellConfiguration.gridSize.width
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
    NSImage *image = [[NSImage alloc] initWithSize:tState.cellConfiguration.cellSize];

    [image lockFocus];
    {
        [tState.color set];
        NSRect rect = NSMakeRect(0,
                                 0,
                                 tState.cellConfiguration.cellSize.width,
                                 tState.cellConfiguration.cellSize.height);
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);

        rect.size.height = 1;
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);

        rect.origin.y += tState.cellConfiguration.cellSize.height - 1;
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
    }
    [image unlockFocus];

    return [_cellRenderer textureFromImage:image];
}

@end
