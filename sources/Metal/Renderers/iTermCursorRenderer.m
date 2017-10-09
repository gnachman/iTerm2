#import "iTermCursorRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermCursorRendererTransientState : iTermMetalCellRendererTransientState
@property (nonatomic, strong) NSColor *color;
@property (nonatomic) VT100GridCoord coord;
@end

@implementation iTermCursorRendererTransientState
@end

@interface iTermCopyModeCursorRendererTransientState : iTermCursorRendererTransientState
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic) BOOL selecting;
@end

@implementation iTermCopyModeCursorRendererTransientState

- (NSImage *)newImage {
    NSImage *image = [[NSImage alloc] initWithSize:self.cellSize];

    [image lockFocus];
    const CGFloat heightFraction = 1 / 3.0;
    const CGFloat scale = 2;
    NSRect rect = NSMakeRect(scale / 2,
                             scale / 2,
                             self.cellSize.width,
                             self.cellSize.height - scale / 2);
    NSRect cursorRect = NSMakeRect(scale / 2,
                                   rect.size.height * (1 - heightFraction) + scale / 2,
                                   rect.size.width,
                                   self.cellSize.height * heightFraction - scale / 2);
    const CGFloat r = (self.selecting ? 2 : 1) * scale;

    NSBezierPath *path = [[NSBezierPath alloc] init];
    [path moveToPoint:NSMakePoint(NSMinX(cursorRect), NSMaxY(cursorRect))];
    [path lineToPoint:NSMakePoint(NSMidX(cursorRect) - r, NSMinY(cursorRect))];
    [path lineToPoint:NSMakePoint(NSMidX(cursorRect) - r, NSMinY(rect))];
    [path lineToPoint:NSMakePoint(NSMidX(cursorRect) + r, NSMinY(rect))];
    [path lineToPoint:NSMakePoint(NSMidX(cursorRect) + r, NSMinY(cursorRect))];
    [path lineToPoint:NSMakePoint(NSMaxX(cursorRect), NSMaxY(cursorRect))];
    [path lineToPoint:NSMakePoint(NSMinX(cursorRect), NSMaxY(cursorRect))];
    [self.color set];
    [path fill];

    [[NSColor blackColor] set];
    [path setLineWidth:scale];
    [path stroke];
    [image unlockFocus];

    return image;
}

@end

@interface iTermUnderlineCursorRenderer : iTermCursorRenderer
@end

@interface iTermBarCursorRenderer : iTermCursorRenderer
@end

@interface iTermBlockCursorRenderer : iTermCursorRenderer
@end

@implementation iTermCursorRenderer {
@protected
    iTermMetalCellRenderer *_cellRenderer;
    NSColor *_color;
    VT100GridCoord _coord;
}

+ (instancetype)newUnderlineCursorRendererWithDevice:(id<MTLDevice>)device {
    return [[iTermUnderlineCursorRenderer alloc] initWithDevice:device];
}

+ (instancetype)newBarCursorRendererWithDevice:(id<MTLDevice>)device {
    return [[iTermBarCursorRenderer alloc] initWithDevice:device];
}

+ (instancetype)newBlockCursorRendererWithDevice:(id<MTLDevice>)device {
    return [[iTermBlockCursorRenderer alloc] initWithDevice:device];
}

+ (instancetype)newCopyModeCursorRendererWithDevice:(id<MTLDevice>)device {
    return [[iTermCopyModeCursorRenderer alloc] initWithDevice:device
                                            vertexFunctionName:@"iTermTextureCursorVertexShader"
                                          fragmentFunctionName:@"iTermTextureCursorFragmentShader"];
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
            vertexFunctionName:(NSString *)vertexFunctionName
          fragmentFunctionName:(NSString *)fragmentFunctionName {
    self = [super init];
    if (self) {
        _color = [NSColor colorWithRed:1 green:1 blue:1 alpha:1];
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:vertexFunctionName
                                                  fragmentFunctionName:fragmentFunctionName
                                                              blending:YES
                                                        piuElementSize:0
                                                   transientStateClass:self.transientStateClass];
    }
    return self;
}

- (Class)transientStateClass {
    return [iTermCursorRendererTransientState class];
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    return [self initWithDevice:device
             vertexFunctionName:@"iTermCursorVertexShader"
           fragmentFunctionName:@"iTermCursorFragmentShader"];
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

- (void)initializeTransientState:(iTermCursorRendererTransientState *)tState {
    tState.color = _color;
    tState.coord = _coord;
}

- (void)setColor:(NSColor *)color {
    _color = color;
}

- (void)setCoord:(VT100GridCoord)coord {
    _coord = coord;
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(nonnull __kindof iTermMetalRendererTransientState *)transientState {
    iTermCursorRendererTransientState *tState = transientState;
    iTermCursorDescription description = {
        .origin = {
            tState.cellSize.width * tState.coord.x,
            tState.cellSize.height * (tState.gridSize.height - tState.coord.y - 1),
        },
        .color = {
            tState.color.redComponent,
            tState.color.greenComponent,
            tState.color.blueComponent,
            1
        }
    };
    id<MTLBuffer> descriptionBuffer = [_cellRenderer.device newBufferWithBytes:&description
                                                                        length:sizeof(description)
                                                                       options:MTLResourceStorageModeShared];
    [_cellRenderer drawWithTransientState:tState
                            renderEncoder:renderEncoder
                         numberOfVertices:6
                             numberOfPIUs:tState.gridSize.width
                            vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                             @(iTermVertexInputIndexCursorDescription): descriptionBuffer,
                                             @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                          fragmentBuffers:@{}
                                 textures:@{ } ];
}

@end

@implementation iTermUnderlineCursorRenderer

- (void)initializeTransientState:(iTermCursorRendererTransientState *)tState {
    [super initializeTransientState:tState];
    tState.vertexBuffer = [_cellRenderer newQuadOfSize:CGSizeMake(tState.cellSize.width, 2)];
}

@end

@implementation iTermBarCursorRenderer

- (void)initializeTransientState:(iTermCursorRendererTransientState *)tState {
    [super initializeTransientState:tState];
    tState.vertexBuffer = [_cellRenderer newQuadOfSize:CGSizeMake(2, tState.cellSize.height)];
}

@end

@implementation iTermBlockCursorRenderer

- (void)initializeTransientState:(iTermCursorRendererTransientState *)tState {
    [super initializeTransientState:tState];
    tState.vertexBuffer = [_cellRenderer newQuadOfSize:CGSizeMake(tState.cellSize.width, tState.cellSize.height)];
}

@end

@implementation iTermCopyModeCursorRenderer {
    id<MTLTexture> _texture;
    CGSize _textureSize;
}

- (Class)transientStateClass {
    return [iTermCopyModeCursorRendererTransientState class];
}

- (void)initializeTransientState:(iTermCopyModeCursorRendererTransientState *)tState {
    [super initializeTransientState:tState];
    tState.vertexBuffer = [_cellRenderer newQuadOfSize:CGSizeMake(tState.cellSize.width,
                                                                  tState.cellSize.height)];
    tState.selecting = _selecting;
    tState.color = _color;
    if (_texture == nil || !CGSizeEqualToSize(_textureSize, tState.cellSize)) {
        _texture = [_cellRenderer textureFromImage:[tState newImage]];
        _textureSize = tState.cellSize;
    }
    tState.texture = _texture;
}

- (void)setSelecting:(BOOL)selecting {
    if (selecting != _selecting) {
        _selecting = selecting;
        _color = selecting ? [NSColor colorWithRed:0xc1 / 255.0 green:0xde / 255.0 blue:0xff / 255.0 alpha:1] : [NSColor whiteColor];
        _texture = nil;
    }
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermCopyModeCursorRendererTransientState *tState = transientState;
    iTermCursorDescription description = {
        .origin = {
            tState.cellSize.width * tState.coord.x - tState.cellSize.width / 2,
            tState.cellSize.height * (tState.gridSize.height - tState.coord.y - 1),
        },
    };
    id<MTLBuffer> descriptionBuffer = [_cellRenderer.device newBufferWithBytes:&description
                                                                        length:sizeof(description)
                                                                       options:MTLResourceStorageModeShared];
    [_cellRenderer drawWithTransientState:tState
                            renderEncoder:renderEncoder
                         numberOfVertices:6
                             numberOfPIUs:tState.gridSize.width
                            vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                             @(iTermVertexInputIndexCursorDescription): descriptionBuffer,
                                             @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                          fragmentBuffers:@{}
                                 textures:@{ @(iTermTextureIndexPrimary): tState.texture } ];
}

@end

NS_ASSUME_NONNULL_END
