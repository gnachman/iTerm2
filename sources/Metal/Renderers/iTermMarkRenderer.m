#import "iTermMarkRenderer.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermTextDrawingHelper.h"
#import "iTermTextureArray.h"
#import "iTermMetalCellRenderer.h"

@interface iTermMarkRendererTransientState()
@property (nonatomic, strong) iTermTextureArray *marksArrayTexture;
@property (nonatomic) CGSize markSize;
@property (nonatomic) CGPoint markOffset;
@property (nonatomic, copy) NSDictionary<NSNumber *, NSNumber *> *marks;
@end

@implementation iTermMarkRendererTransientState {
    NSMutableDictionary<NSNumber *, NSNumber *> *_marks;
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];
    [[NSString stringWithFormat:@"marks=%@", _marks] writeToURL:[folder URLByAppendingPathComponent:@"state.txt"]
                                                     atomically:NO
                                                       encoding:NSUTF8StringEncoding
                                                          error:NULL];
}

- (nonnull NSData *)newMarkPerInstanceUniforms {
    NSMutableData *data = [[NSMutableData alloc] initWithLength:sizeof(iTermMarkPIU) * _marks.count];
    iTermMarkPIU *pius = (iTermMarkPIU *)data.mutableBytes;
    __block size_t i = 0;
    [_marks enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull rowNumber, NSNumber * _Nonnull styleNumber, BOOL * _Nonnull stop) {
        MTLOrigin origin = [_marksArrayTexture offsetForIndex:styleNumber.integerValue];
        pius[i] = (iTermMarkPIU) {
            .offset = {
                0,
                (self.cellConfiguration.gridSize.height - rowNumber.intValue - 1) * self.cellConfiguration.cellSize.height + self.margins.top + self.cellConfiguration.cellSize.height - self.markSize.height - self.markOffset.y
            },
            .textureOffset = { origin.x, origin.y }
        };
        i++;
    }];
    return data;
}

- (void)setMarkStyle:(iTermMarkStyle)markStyle row:(int)row {
    if (!_marks) {
        _marks = [NSMutableDictionary dictionary];
    }
    if (markStyle == iTermMarkStyleNone) {
        [_marks removeObjectForKey:@(row)];
    } else {
        _marks[@(row)] = @(markStyle);
    }
}

@end

@implementation iTermMarkRenderer {
    iTermMetalCellRenderer *_cellRenderer;
    iTermTextureArray *_marksArrayTexture;
    CGSize _markSize;
    iTermMetalMixedSizeBufferPool *_piuPool;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:@"iTermMarkVertexShader"
                                                  fragmentFunctionName:@"iTermMarkFragmentShader"
                                                              blending:[iTermMetalBlending compositeSourceOver]
                                                        piuElementSize:sizeof(iTermMarkPIU)
                                                   transientStateClass:[iTermMarkRendererTransientState class]];
        _piuPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                capacity:iTermMetalDriverMaximumNumberOfFramesInFlight + 1
                                                                    name:@"mark PIU"];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateMarkTS;
}

- (__kindof iTermMetalRendererTransientState * _Nonnull)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    __kindof iTermMetalCellRendererTransientState * _Nonnull transientState =
        [_cellRenderer createTransientStateForCellConfiguration:configuration
                                              commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermMarkRendererTransientState *)tState {
    const CGFloat scale = tState.configuration.scale;

    CGRect leftMarignRect = CGRectMake(0,
                                       0,
                                       [iTermAdvancedSettingsModel terminalMargin] * scale,
                                       tState.cellConfiguration.cellSize.height);
    CGRect markRect = [iTermTextDrawingHelper frameForMarkContainedInRect:leftMarignRect
                                                                 cellSize:tState.cellConfiguration.cellSize
                                                   cellSizeWithoutSpacing:tState.cellConfiguration.cellSizeWithoutSpacing
                                                                    scale:scale];
    if (!CGSizeEqualToSize(markRect.size, _markSize)) {
        // Mark size has changed
        _markSize = markRect.size;
        _marksArrayTexture = [[iTermTextureArray alloc] initWithTextureWidth:_markSize.width
                                                               textureHeight:_markSize.height
                                                                 arrayLength:3
                                                                        bgra:NO
                                                                      device:_cellRenderer.device];

        NSColor *successColor = [iTermTextDrawingHelper successMarkColor];
        NSColor *otherColor = [iTermTextDrawingHelper otherMarkColor];
        NSColor *failureColor = [iTermTextDrawingHelper errorMarkColor];

        [_marksArrayTexture addSliceWithImage:[self newImageWithMarkOfColor:successColor size:_markSize]];
        [_marksArrayTexture addSliceWithImage:[self newImageWithMarkOfColor:failureColor size:_markSize]];
        [_marksArrayTexture addSliceWithImage:[self newImageWithMarkOfColor:otherColor size:_markSize]];
    }

    tState.markOffset = markRect.origin;
    tState.marksArrayTexture = _marksArrayTexture;
    tState.markSize = _markSize;
    tState.vertexBuffer = [_cellRenderer newQuadOfSize:_markSize poolContext:tState.poolContext];
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermMarkRendererTransientState *tState = transientState;
    if (tState.marks.count == 0) {
        return;
    }

    const CGFloat scale = tState.configuration.scale;
    const CGRect quad = CGRectMake(round(tState.markOffset.x / scale) * scale,
                                   0,
                                   tState.markSize.width,
                                   tState.markSize.height);
    const CGRect textureFrame = CGRectMake(0,
                                           0,
                                           tState.markSize.width,
                                           tState.markSize.height);
    const iTermVertex vertices[] = {
        // Pixel Positions                              Texture Coordinates
        { { CGRectGetMaxX(quad), CGRectGetMinY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMinY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMinY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMaxY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },

        { { CGRectGetMaxX(quad), CGRectGetMinY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMaxY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },
        { { CGRectGetMaxX(quad), CGRectGetMaxY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMaxY(textureFrame) } },
    };
    tState.vertexBuffer = [_cellRenderer.verticesPool requestBufferFromContext:tState.poolContext
                                                                      withBytes:vertices
                                                                 checkIfChanged:YES];

    NSData *data = [tState newMarkPerInstanceUniforms];
    tState.pius = [_piuPool requestBufferFromContext:tState.poolContext
                                                size:data.length];
    memcpy(tState.pius.contents, data.bytes, data.length);

    [_cellRenderer drawWithTransientState:tState
                            renderEncoder:renderEncoder
                         numberOfVertices:6
                             numberOfPIUs:tState.marks.count
                            vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                             @(iTermVertexInputIndexPerInstanceUniforms): tState.pius,
                                             @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                          fragmentBuffers:@{}
                                 textures:@{ @(iTermTextureIndexPrimary): tState.marksArrayTexture.texture } ];
}

#pragma mark - Private

- (NSImage *)newImageWithMarkOfColor:(NSColor *)color size:(CGSize)size {
    // Doing this hacky crap with NSBitmapImageRep is necessary to get it
    // pixel-perfect. If you lock an NSImage it'll create a rep that's larger by
    // the scale factor (of, uh, something).
    NSBitmapImageRep *offscreenRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                              pixelsWide:size.width
                                                                              pixelsHigh:size.height
                                                                           bitsPerSample:8
                                                                         samplesPerPixel:4
                                                                                hasAlpha:YES
                                                                                isPlanar:NO
                                                                          colorSpaceName:NSDeviceRGBColorSpace
                                                                            bitmapFormat:NSAlphaFirstBitmapFormat
                                                                             bytesPerRow:0
                                                                            bitsPerPixel:0];
    offscreenRep = [offscreenRep bitmapImageRepByRetaggingWithColorSpace:[NSColorSpace sRGBColorSpace]];

    NSGraphicsContext *g = [NSGraphicsContext graphicsContextWithBitmapImageRep:offscreenRep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:g];

    CGRect rect = CGRectMake(0, 0, size.width, size.height);

    NSPoint bottom = NSMakePoint(NSMinX(rect), NSMinY(rect));
    NSPoint right = NSMakePoint(NSMaxX(rect), NSMidY(rect));
    NSPoint top = NSMakePoint(NSMinX(rect), NSMaxY(rect));

    NSBezierPath *path;

    path = [NSBezierPath bezierPath];
    [color set];
    [path moveToPoint:top];
    [path lineToPoint:right];
    [path lineToPoint:bottom];
    [path lineToPoint:top];
    [path fill];

    [[NSColor blackColor] set];
    path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(bottom.x, bottom.y)];
    [path lineToPoint:NSMakePoint(right.x, right.y)];
    [path setLineWidth:1.0];
    [path stroke];

    [NSGraphicsContext restoreGraphicsState];

    NSImage *img = [[NSImage alloc] initWithSize:size];
    [img addRepresentation:offscreenRep];
    return img;
}

@end
