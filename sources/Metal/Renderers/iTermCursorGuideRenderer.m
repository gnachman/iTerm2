#import "iTermCursorGuideRenderer.h"

@interface iTermCursorGuideRendererTransientState()
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic) int row;
@end

@implementation iTermCursorGuideRendererTransientState {
    int _row;
}

- (void)setRow:(int)row {
    _row = row;
}

- (void)initializeVerticesWithPool:(iTermMetalBufferPool *)verticesPool {
    CGSize cellSize = self.cellConfiguration.cellSize;
    VT100GridSize gridSize = self.cellConfiguration.gridSize;

    const CGRect quad = CGRectMake(self.margins.left,
                                   self.margins.top + (gridSize.height - self.row - 1) * cellSize.height,
                                   cellSize.width * gridSize.width,
                                   cellSize.height);
    const CGRect textureFrame = CGRectMake(0, 0, 1, 1);
    const iTermVertex vertices[] = {
        // Pixel Positions                              Texture Coordinates
        { { CGRectGetMaxX(quad), CGRectGetMinY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMinY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMinY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMaxY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },

        { { CGRectGetMaxX(quad), CGRectGetMinY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMaxY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },
        { { CGRectGetMaxX(quad), CGRectGetMaxY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMaxY(textureFrame) } },
    };
    self.vertexBuffer = [verticesPool requestBufferFromContext:self.poolContext
                                                     withBytes:vertices
                                                checkIfChanged:YES];
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];
    [[NSString stringWithFormat:@"row=%@", @(_row)] writeToURL:[folder URLByAppendingPathComponent:@"state.txt"]
                                                    atomically:NO
                                                      encoding:NSUTF8StringEncoding
                                                         error:NULL];
}

@end

@implementation iTermCursorGuideRenderer {
    iTermMetalCellRenderer *_cellRenderer;
    id<MTLTexture> _texture;
    NSColor *_color;
    CGSize _lastCellSize;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _color = [[NSColor blueColor] colorWithAlphaComponent:0.7];
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:@"iTermCursorGuideVertexShader"
                                                  fragmentFunctionName:@"iTermCursorGuideFragmentShader"
                                                              blending:[iTermMetalBlending compositeSourceOver]
                                                        piuElementSize:0
                                                   transientStateClass:[iTermCursorGuideRendererTransientState class]];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateCursorGuideTS;
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
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
    if (!CGSizeEqualToSize(tState.cellConfiguration.cellSize, _lastCellSize)) {
        _texture = [self newCursorGuideTextureWithTransientState:tState];
        _lastCellSize = tState.cellConfiguration.cellSize;
    }
    tState.texture = _texture;
}

- (void)setColor:(NSColor *)color {
    _color = color;

    // Invalidate cell size so the texture gets created again
    _lastCellSize = CGSizeZero;
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermCursorGuideRendererTransientState *tState = transientState;
    if (tState.row < 0) {
        // Cursor is offscreen. We set it to -1 to signal this.
        return;
    }

    [tState initializeVerticesWithPool:_cellRenderer.verticesPool];
    [_cellRenderer drawWithTransientState:tState
                            renderEncoder:frameData.renderEncoder
                         numberOfVertices:6
                             numberOfPIUs:0
                            vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer }
                          fragmentBuffers:@{}
                                 textures:@{ @(iTermTextureIndexPrimary): tState.texture } ];
}

#pragma mark - Private

- (id<MTLTexture>)newCursorGuideTextureWithTransientState:(iTermCursorGuideRendererTransientState *)tState {
    NSImage *image = [[NSImage alloc] initWithSize:tState.cellConfiguration.cellSize];

    [image lockFocus];
    {
        [_color set];
        NSRect rect = NSMakeRect(0,
                                 0,
                                 tState.cellConfiguration.cellSize.width,
                                 tState.cellConfiguration.cellSize.height);
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);

        rect.size.height = tState.cellConfiguration.scale;
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);

        rect.origin.y += tState.cellConfiguration.cellSize.height - tState.cellConfiguration.scale;
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
    }
    [image unlockFocus];

    return [_cellRenderer textureFromImage:image context:tState.poolContext];
}

@end
