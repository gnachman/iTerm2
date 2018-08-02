#import "iTermCursorRenderer.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermMetalBufferPool.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermCursorRenderer()
@property (nonatomic, readonly) iTermMetalCellRenderer *cellRenderer;
@end

@interface iTermFrameCursorRenderer()
@property (nonatomic, strong) id<MTLTexture> cachedTexture;
@property (nonatomic) CGSize cachedTextureSize;
@property (nonatomic) NSColor *cachedColor;
@end

@interface iTermCopyModeCursorRenderer()
@property (nonatomic, strong) id<MTLTexture> cachedTexture;
@property (nonatomic) CGSize cachedTextureSize;
@property (nonatomic) NSColor *cachedColor;
@end

@interface iTermCursorRendererTransientState()
@property (nonatomic, readonly) CGFloat cursorHeight;
@end

@implementation iTermCursorRendererTransientState

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];
    NSString *s = [NSString stringWithFormat:
                   @"color=%@\n"
                   @"coord=%@",
                   self.color,
                   VT100GridCoordDescription(_coord)];
    [s writeToURL:[folder URLByAppendingPathComponent:@"state.txt"]
       atomically:NO
         encoding:NSUTF8StringEncoding
            error:NULL];
}

- (CGFloat)cursorHeight {
    if ([iTermAdvancedSettingsModel fullHeightCursor]) {
        return MAX(self.cellConfiguration.cellSize.height, self.cellConfiguration.cellSizeWithoutSpacing.height);
    } else {
        return MIN(self.cellConfiguration.cellSize.height, self.cellConfiguration.cellSizeWithoutSpacing.height);
    }
}

@end

@interface iTermCopyModeCursorRendererTransientState()
@property (nullable, nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic, weak) iTermCopyModeCursorRenderer *renderer;
@property (nonatomic, readonly) CGSize size;
@end

@interface iTermFrameCursorRendererTransientState : iTermCursorRendererTransientState
@property (nonatomic, weak) iTermFrameCursorRenderer *renderer;
@property (nonatomic, strong) id<MTLTexture> texture;
@end

@implementation iTermCopyModeCursorRendererTransientState {
    NSColor *_color;
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];
    NSString *s = [NSString stringWithFormat:@"selecting=%@", _selecting ? @"YES" : @"NO"];
    [s writeToURL:[folder URLByAppendingPathComponent:@"CopyModeState.txt"]
       atomically:NO
         encoding:NSUTF8StringEncoding
            error:NULL];
}

- (CGSize)size {
    CGSize size = self.cellConfiguration.cellSize;
    size.width += 1;
    return size;
}

- (NSImage *)newImage {
    NSImage *image = [[NSImage alloc] initWithSize:self.size];

    [image lockFocus];
    const CGFloat heightFraction = 1 / 3.0;
    const CGFloat scale = self.cellConfiguration.scale;
    NSRect rect = NSMakeRect(scale / 2,
                             scale / 2,
                             self.cellConfiguration.cellSize.width,
                             self.cellConfiguration.cellSize.height - scale / 2);
    NSRect cursorRect = NSMakeRect(scale / 2,
                                   rect.size.height * (1 - heightFraction) + scale / 2,
                                   rect.size.width,
                                   self.cellConfiguration.cellSize.height * heightFraction - scale / 2);
    const CGFloat r = (self.selecting ? 2 : 1) * scale;

    NSBezierPath *path = [[NSBezierPath alloc] init];
    [path moveToPoint:NSMakePoint(NSMinX(cursorRect), NSMaxY(cursorRect))];
    [path lineToPoint:NSMakePoint(NSMidX(cursorRect) - r, NSMinY(cursorRect))];
    [path lineToPoint:NSMakePoint(NSMidX(cursorRect) - r, NSMinY(rect))];
    [path lineToPoint:NSMakePoint(NSMidX(cursorRect) + r, NSMinY(rect))];
    [path lineToPoint:NSMakePoint(NSMidX(cursorRect) + r, NSMinY(cursorRect))];
    [path lineToPoint:NSMakePoint(NSMaxX(cursorRect), NSMaxY(cursorRect))];
    [path lineToPoint:NSMakePoint(NSMinX(cursorRect), NSMaxY(cursorRect))];
    [_color set];
    [path fill];

    [[NSColor blackColor] set];
    [path setLineWidth:scale];
    [path stroke];
    [image unlockFocus];

    return image;
}

- (void)setSelecting:(BOOL)selecting {
    _selecting = selecting;
    _color = selecting ? [NSColor colorWithRed:0xc1 / 255.0 green:0xde / 255.0 blue:0xff / 255.0 alpha:1] : [NSColor whiteColor];
    _texture = nil;

    if (_renderer.cachedTexture == nil ||
        ![_color isEqual:_renderer.cachedColor] ||
        !CGSizeEqualToSize(_renderer.cachedTextureSize, self.cellConfiguration.cellSize)) {
        _renderer.cachedTexture = [_renderer.cellRenderer textureFromImage:[self newImage]
                                                                   context:self.poolContext];
        _renderer.cachedTextureSize = self.cellConfiguration.cellSize;
        _renderer.cachedColor = _color;
    }
    _texture = _renderer.cachedTexture;
}


@end

@implementation iTermFrameCursorRendererTransientState

- (NSImage *)newImage {
    NSImage *image = [[NSImage alloc] initWithSize:self.cellConfiguration.cellSize];

    [image lockFocus];
    NSRect rect = NSMakeRect(0,
                             0,
                             self.cellConfiguration.cellSize.width,
                             self.cellConfiguration.cellSize.height);
    rect = NSInsetRect(rect, self.cellConfiguration.scale / 2, self.cellConfiguration.scale / 2);
    NSBezierPath *path = [NSBezierPath bezierPathWithRect:rect];
    [path setLineWidth:self.cellConfiguration.scale];

    [[NSColor clearColor] setFill];
    [path fill];

    [self.color setStroke];
    [path stroke];

    [image unlockFocus];

    return image;
}

- (void)setColor:(NSColor *)color {
    [super setColor:color];
    if (_renderer.cachedTexture == nil ||
        ![color isEqual:_renderer.cachedColor] ||
        !CGSizeEqualToSize(_renderer.cachedTextureSize, self.cellConfiguration.cellSize)) {
        _renderer.cachedTexture = [_renderer.cellRenderer textureFromImage:[self newImage]
                                                                   context:self.poolContext];
        _renderer.cachedTextureSize = self.cellConfiguration.cellSize;
        _renderer.cachedColor = color;
    }
    _texture = _renderer.cachedTexture;
}

@end

@interface iTermUnderlineCursorRenderer : iTermCursorRenderer
@end

@interface iTermBarCursorRenderer : iTermCursorRenderer
@end

@interface iTermIMECursorRenderer : iTermBarCursorRenderer
@end

@interface iTermBlockCursorRenderer : iTermCursorRenderer
@end

@implementation iTermCursorRenderer {
@protected
    iTermMetalCellRenderer *_cellRenderer;
    iTermMetalBufferPool *_descriptionPool;
}

+ (instancetype)newUnderlineCursorRendererWithDevice:(id<MTLDevice>)device {
    return [[iTermUnderlineCursorRenderer alloc] initWithDevice:device];
}

+ (instancetype)newBarCursorRendererWithDevice:(id<MTLDevice>)device {
    return [[iTermBarCursorRenderer alloc] initWithDevice:device];
}

+ (instancetype)newIMECursorRendererWithDevice:(id<MTLDevice>)device {
    return [[iTermIMECursorRenderer alloc] initWithDevice:device];
}

+ (instancetype)newBlockCursorRendererWithDevice:(id<MTLDevice>)device {
    return [[iTermBlockCursorRenderer alloc] initWithDevice:device];
}

+ (instancetype)newCopyModeCursorRendererWithDevice:(id<MTLDevice>)device {
    return [[iTermCopyModeCursorRenderer alloc] initWithDevice:device
                                            vertexFunctionName:@"iTermTextureCursorVertexShader"
                                          fragmentFunctionName:@"iTermTextureCursorFragmentShader"];
}

+ (instancetype)newFrameCursorRendererWithDevice:(id<MTLDevice>)device {
    return [[iTermFrameCursorRenderer alloc] initWithDevice:device
                                         vertexFunctionName:@"iTermTextureCursorVertexShader"
                                       fragmentFunctionName:@"iTermTextureCursorFragmentShader"];
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
            vertexFunctionName:(NSString *)vertexFunctionName
          fragmentFunctionName:(NSString *)fragmentFunctionName {
    self = [super init];
    if (self) {
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:vertexFunctionName
                                                  fragmentFunctionName:fragmentFunctionName
                                                              blending:[[iTermMetalBlending alloc] init]
                                                        piuElementSize:0
                                                   transientStateClass:self.transientStateClass];
        _descriptionPool = [[iTermMetalBufferPool alloc] initWithDevice:device
                                                             bufferSize:sizeof(iTermCursorDescription)];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateCursorTS;
}

- (Class)transientStateClass {
    return [iTermCursorRendererTransientState class];
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    return [self initWithDevice:device
             vertexFunctionName:@"iTermCursorVertexShader"
           fragmentFunctionName:@"iTermCursorFragmentShader"];
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    __kindof iTermMetalRendererTransientState * _Nonnull transientState =
        [_cellRenderer createTransientStateForCellConfiguration:configuration
                                              commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermCursorRendererTransientState *)tState {
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalRendererTransientState *)transientState {
    iTermCursorRendererTransientState *tState = transientState;

    const CGFloat rowNumber = (tState.cellConfiguration.gridSize.height - tState.coord.y - 1);
    const CGSize cellSize = tState.cellConfiguration.cellSize;
    const CGSize cellSizeWithoutSpacing = tState.cellConfiguration.cellSizeWithoutSpacing;
    CGFloat y = rowNumber * cellSize.height;
    if (![iTermAdvancedSettingsModel fullHeightCursor]) {
        const CGFloat scale = tState.configuration.scale;
        y += cellSize.height - MAX(0, round(((cellSize.height - cellSizeWithoutSpacing.height) / 2) / scale) * scale) - tState.cursorHeight;
    }
    iTermCursorDescription description = {
        .origin = {
            tState.cellConfiguration.cellSize.width * tState.coord.x,
            y
        },
        .color = {
            tState.color.redComponent,
            tState.color.greenComponent,
            tState.color.blueComponent,
            1
        }
    };
    id<MTLBuffer> descriptionBuffer = [_descriptionPool requestBufferFromContext:tState.poolContext
                                                                       withBytes:&description
                                                                  checkIfChanged:YES];
    [_cellRenderer drawWithTransientState:tState
                            renderEncoder:frameData.renderEncoder
                         numberOfVertices:6
                             numberOfPIUs:0
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
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermCursorRendererTransientState *tState = transientState;
    int d = tState.doubleWidth ? 2 : 1;
    tState.vertexBuffer = [_cellRenderer newQuadOfSize:CGSizeMake(tState.cellConfiguration.cellSize.width * d,
                                                                  [iTermAdvancedSettingsModel underlineCursorHeight] * tState.cellConfiguration.scale)
                                           poolContext:tState.poolContext];
    [super drawWithFrameData:frameData transientState:transientState];
}

@end

@implementation iTermBarCursorRenderer

- (void)initializeTransientState:(iTermCursorRendererTransientState *)tState {
    [super initializeTransientState:tState];
    const CGFloat width = [iTermAdvancedSettingsModel verticalBarCursorWidth];
    tState.vertexBuffer =
        [_cellRenderer newQuadOfSize:CGSizeMake(tState.configuration.scale * width,
                                                tState.cellConfiguration.cellSize.height)
                         poolContext:tState.poolContext];
}

@end

@implementation iTermIMECursorRenderer
@end

@implementation iTermBlockCursorRenderer

- (void)initializeTransientState:(iTermCursorRendererTransientState *)tState {
    [super initializeTransientState:tState];
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermCursorRendererTransientState *tState = transientState;
    int d = tState.doubleWidth ? 2 : 1;
    const CGFloat width = MIN(tState.cellConfiguration.cellSize.width,
                              tState.cellConfiguration.cellSizeWithoutSpacing.width);
    tState.vertexBuffer = [_cellRenderer newQuadWithFrame:CGRectMake(0,
                                                                     0,
                                                                     width * d,
                                                                     tState.cursorHeight)
                                             textureFrame:CGRectMake(0, 0, 1, 1)
                                              poolContext:tState.poolContext];
    [super drawWithFrameData:frameData transientState:transientState];
}

@end

@implementation iTermFrameCursorRenderer {
    id<MTLTexture> _texture;
    CGSize _textureSize;
}

- (Class)transientStateClass {
    return [iTermFrameCursorRendererTransientState class];
}

- (void)initializeTransientState:(iTermFrameCursorRendererTransientState *)tState {
    [super initializeTransientState:tState];
    tState.renderer = self;
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermFrameCursorRendererTransientState *tState = transientState;
    int d = tState.doubleWidth ? 2 : 1;
    const CGFloat width = MIN(tState.cellConfiguration.cellSize.width,
                              tState.cellConfiguration.cellSizeWithoutSpacing.width);
    tState.vertexBuffer = [_cellRenderer newQuadWithFrame:CGRectMake(0,
                                                                     0,
                                                                     width * d,
                                                                     tState.cursorHeight)
                                             textureFrame:CGRectMake(0, 0, 1, 1)
                                              poolContext:tState.poolContext];
    iTermCursorDescription description = {
        .origin = {
            tState.cellConfiguration.cellSize.width * tState.coord.x,
            tState.cellConfiguration.cellSize.height * (tState.cellConfiguration.gridSize.height - tState.coord.y - 1),
        },
        .color = {
            tState.color.redComponent,
            tState.color.greenComponent,
            tState.color.blueComponent,
            1
        }
    };
    id<MTLBuffer> descriptionBuffer = [_descriptionPool requestBufferFromContext:tState.poolContext
                                                                       withBytes:&description
                                                                  checkIfChanged:YES];
    [_cellRenderer drawWithTransientState:tState
                            renderEncoder:frameData.renderEncoder
                         numberOfVertices:6
                             numberOfPIUs:tState.cellConfiguration.gridSize.width
                            vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                             @(iTermVertexInputIndexCursorDescription): descriptionBuffer,
                                             @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                          fragmentBuffers:@{}
                                 textures:@{ @(iTermTextureIndexPrimary): tState.texture } ];
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
    tState.renderer = self;
    tState.vertexBuffer = [_cellRenderer newQuadOfSize:CGSizeMake(tState.cellConfiguration.cellSize.width,
                                                                  tState.cellConfiguration.cellSize.height)
                                           poolContext:tState.poolContext];
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermCopyModeCursorRendererTransientState *tState = transientState;
    iTermCursorDescription description = {
        .origin = {
            tState.cellConfiguration.cellSize.width * tState.coord.x - tState.cellConfiguration.cellSize.width / 2,
            tState.cellConfiguration.cellSize.height * (tState.cellConfiguration.gridSize.height - tState.coord.y - 1),
        },
        .color = { 0, 0, 0, 0 }
    };
    // This cursor is a little larger than a cell.
    tState.vertexBuffer = [_cellRenderer newQuadOfSize:tState.size poolContext:tState.poolContext];
    id<MTLBuffer> descriptionBuffer = [_descriptionPool requestBufferFromContext:tState.poolContext
                                                                       withBytes:&description
                                                                  checkIfChanged:YES];
    [_cellRenderer drawWithTransientState:tState
                            renderEncoder:frameData.renderEncoder
                         numberOfVertices:6
                             numberOfPIUs:0
                            vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                             @(iTermVertexInputIndexCursorDescription): descriptionBuffer,
                                             @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                          fragmentBuffers:@{}
                                 textures:@{ @(iTermTextureIndexPrimary): tState.texture } ];
}

@end

NS_ASSUME_NONNULL_END
