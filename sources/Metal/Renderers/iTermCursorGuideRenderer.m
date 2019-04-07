#import "iTermCursorGuideRenderer.h"

@interface iTermCursorGuideRendererTransientState()
@property (nonatomic, strong) id<MTLTexture> horizontalTexture, verticalTexture;
@property (nonatomic) int row;
@property (nonatomic) int column;
@property (nonatomic) id<MTLBuffer> horizontalVertexBuffer, verticalVertexBuffer, upperVertexBuffer, lowerVertexBuffer;
@end

@implementation iTermCursorGuideRendererTransientState {
    int _row;
    int _column;
    id<MTLBuffer> _horizontalVertexBuffer, _verticalVertexBuffer;
    id<MTLBuffer> _upperVertexBuffer, _lowerVertexBuffer;
}

- (void)setCursorCoord:(VT100GridCoord)coord within:(VT100GridSize)bounds {
    _row = (0 <= coord.y && coord.y < bounds.height) ? coord.y : -1;
    _column = (0 <= coord.x && coord.x < bounds.width)  ? coord.x : -1;
}

- (void)initializeVerticesWithPool:(iTermMetalBufferPool *)verticesPool
                        horizontal:(BOOL)horizontal
                          vertical:(BOOL)vertical {
    CGSize cellSize = self.cellConfiguration.cellSize;
    VT100GridSize gridSize = self.cellConfiguration.gridSize;

    const CGRect textureFrame = CGRectMake(0, 0, 1, 1);

    CGFloat viewMinX = self.margins.left, viewMinY = self.margins.top;
    CGFloat viewMaxX = viewMinX + cellSize.width*gridSize.width, viewMaxY = viewMinY + cellSize.height*gridSize.height;

    CGFloat cursorMinX = self.margins.left + self.column * cellSize.width, cursorMinY = self.margins.top + (gridSize.height - self.row - 1) * cellSize.height;
    CGFloat cursorMaxX = cursorMinX + cellSize.width, cursorMaxY = cursorMinY + cellSize.height;

    if (horizontal) {
        const iTermVertex vertices[] = {
            // Pixel Positions                              Texture Coordinates
            { { viewMaxX, cursorMinY }, { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
            { { viewMinX, cursorMinY }, { CGRectGetMinX(textureFrame), CGRectGetMinY(textureFrame) } },
            { { viewMinX, cursorMaxY }, { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },

            { { viewMaxX, cursorMinY }, { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
            { { viewMinX, cursorMaxY }, { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },
            { { viewMaxX, cursorMaxY }, { CGRectGetMaxX(textureFrame), CGRectGetMaxY(textureFrame) } },
        };
        self.horizontalVertexBuffer = [verticesPool requestBufferFromContext:self.poolContext
                                                                   withBytes:vertices
                                                              checkIfChanged:YES];
    }

    if (horizontal && vertical) {
        const iTermVertex lowerVertices[] = {
            // Pixel Positions                              Texture Coordinates
            { { cursorMaxX, viewMinY },   { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
            { { cursorMinX, viewMinY },   { CGRectGetMinX(textureFrame), CGRectGetMinY(textureFrame) } },
            { { cursorMinX, cursorMinY }, { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },

            { { cursorMaxX, viewMinY },   { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
            { { cursorMinX, cursorMinY }, { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },
            { { cursorMaxX, cursorMinY }, { CGRectGetMaxX(textureFrame), CGRectGetMaxY(textureFrame) } },
        };
        self.lowerVertexBuffer = [verticesPool requestBufferFromContext:self.poolContext
                                                              withBytes:lowerVertices
                                                         checkIfChanged:YES];
        const iTermVertex upperVertices[] = {
            // Pixel Positions                              Texture Coordinates
            { { cursorMaxX, cursorMaxY }, { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
            { { cursorMinX, cursorMaxY }, { CGRectGetMinX(textureFrame), CGRectGetMinY(textureFrame) } },
            { { cursorMinX, viewMaxY },   { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },

            { { cursorMaxX, cursorMaxY }, { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
            { { cursorMinX, viewMaxY },   { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },
            { { cursorMaxX, viewMaxY },   { CGRectGetMaxX(textureFrame), CGRectGetMaxY(textureFrame) } },
        };
        self.upperVertexBuffer = [verticesPool requestBufferFromContext:self.poolContext
                                                              withBytes:upperVertices
                                                         checkIfChanged:YES];
    } else if (vertical) {
        const iTermVertex vertices[] = {
            // Pixel Positions                              Texture Coordinates
            { { cursorMaxX, viewMinY }, { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
            { { cursorMinX, viewMinY }, { CGRectGetMinX(textureFrame), CGRectGetMinY(textureFrame) } },
            { { cursorMinX, viewMaxY }, { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },

            { { cursorMaxX, viewMinY }, { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
            { { cursorMinX, viewMaxY }, { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },
            { { cursorMaxX, viewMaxY }, { CGRectGetMaxX(textureFrame), CGRectGetMaxY(textureFrame) } },
        };
        self.verticalVertexBuffer = [verticesPool requestBufferFromContext:self.poolContext
                                                                 withBytes:vertices
                                                            checkIfChanged:YES];
    }
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
    id<MTLTexture> _horizontalTexture, _verticalTexture;
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
    if (!_horizontalEnabled && !_verticalEnabled) {
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
        _horizontalTexture = [self newCursorGuideTextureWithTransientState:tState
                                                              isHorizontal:YES];
        _verticalTexture   = [self newCursorGuideTextureWithTransientState:tState
                                                              isHorizontal:NO];
        _lastCellSize = tState.cellConfiguration.cellSize;
    }
    tState.horizontalTexture = _horizontalTexture;
    tState.verticalTexture   = _verticalTexture;
}

- (void)setColor:(NSColor *)color {
    _color = color;

    // Invalidate cell size so the texture gets created again
    _lastCellSize = CGSizeZero;
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermCursorGuideRendererTransientState *tState = transientState;
    if (tState.row < 0 && tState.column < 0) {
        return;
    }

    if (tState.row >= 0 && tState.column >= 0 && self.horizontalEnabled && self.verticalEnabled) {
        [tState initializeVerticesWithPool:_cellRenderer.verticesPool horizontal:TRUE vertical:TRUE];
        [_cellRenderer drawWithTransientState:tState
                                renderEncoder:frameData.renderEncoder
                             numberOfVertices:6
                                 numberOfPIUs:0
                                vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.horizontalVertexBuffer }
                              fragmentBuffers:@{}
                                     textures:@{ @(iTermTextureIndexPrimary): tState.horizontalTexture } ];
        [_cellRenderer drawWithTransientState:tState
                                renderEncoder:frameData.renderEncoder
                             numberOfVertices:6
                                 numberOfPIUs:0
                                vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.upperVertexBuffer }
                              fragmentBuffers:@{}
                                     textures:@{ @(iTermTextureIndexPrimary): tState.verticalTexture } ];
        [_cellRenderer drawWithTransientState:tState
                                renderEncoder:frameData.renderEncoder
                             numberOfVertices:6
                                 numberOfPIUs:0
                                vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.lowerVertexBuffer }
                              fragmentBuffers:@{}
                                     textures:@{ @(iTermTextureIndexPrimary): tState.verticalTexture } ];
    } else if (tState.row >= 0 && self.horizontalEnabled) {
        [tState initializeVerticesWithPool:_cellRenderer.verticesPool horizontal:TRUE vertical:FALSE];
        [_cellRenderer drawWithTransientState:tState
                                renderEncoder:frameData.renderEncoder
                             numberOfVertices:6
                                 numberOfPIUs:0
                                vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.horizontalVertexBuffer }
                              fragmentBuffers:@{}
                                     textures:@{ @(iTermTextureIndexPrimary): tState.horizontalTexture } ];
    } else if (tState.column >= 0 && self.verticalEnabled) {
        [tState initializeVerticesWithPool:_cellRenderer.verticesPool horizontal:FALSE vertical:TRUE];
        [_cellRenderer drawWithTransientState:tState
                                renderEncoder:frameData.renderEncoder
                             numberOfVertices:6
                                 numberOfPIUs:0
                                vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.verticalVertexBuffer }
                              fragmentBuffers:@{}
                                     textures:@{ @(iTermTextureIndexPrimary): tState.verticalTexture } ];
    }
}

#pragma mark - Private

- (id<MTLTexture>)newCursorGuideTextureWithTransientState:(iTermCursorGuideRendererTransientState *)tState
                                             isHorizontal:(BOOL)isHorizontal {
    NSImage *image = [[NSImage alloc] initWithSize:tState.cellConfiguration.cellSize];
    [image lockFocus];
    {
        [_color set];
        NSRect rect = NSMakeRect(0,
                                 0,
                                 tState.cellConfiguration.cellSize.width,
                                 tState.cellConfiguration.cellSize.height);
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);

        if (isHorizontal) {
            rect.size.height = tState.cellConfiguration.scale;
            NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);

            rect.origin.y += tState.cellConfiguration.cellSize.height - tState.cellConfiguration.scale;
            NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
        } else {
            rect.size.width = tState.cellConfiguration.scale;
            NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);

            rect.origin.x += tState.cellConfiguration.cellSize.width - tState.cellConfiguration.scale;
            NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
        }
    }
    [image unlockFocus];

    return [_cellRenderer textureFromImage:image context:tState.poolContext];
}

@end
