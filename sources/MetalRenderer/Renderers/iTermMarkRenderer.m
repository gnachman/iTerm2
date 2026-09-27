#import "iTermMarkRenderer.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermPreferences.h"
#import "iTermTextDrawingHelper.h"
#import "iTermTextureArray.h"
#import "iTermMetalCellRenderer.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"

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
        MTLOrigin origin = [self->_marksArrayTexture offsetForIndex:styleNumber.integerValue];
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
    NSColorSpace *_colorSpace;
    CGSize _markSize;
    CGPoint _markOffset;
    NSColor *_lastSuccessColor;
    NSColor *_lastOtherColor;
    NSColor *_lastFailureColor;
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

- (nullable  __kindof iTermMetalRendererTransientState *)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                                    commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    __kindof iTermMetalCellRendererTransientState * _Nonnull transientState =
        [_cellRenderer createTransientStateForCellConfiguration:configuration
                                              commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)updateForCellConfiguration:(iTermCellRenderConfiguration *)cellConfiguration
                      successColor:(NSColor *)successColor
                        otherColor:(NSColor *)otherColor
                      failureColor:(NSColor *)failureColor {
    const CGFloat scale = cellConfiguration.scale;
    CGRect leftMarginRect = CGRectMake(1,
                                       0,
                                       ([iTermPreferences sideMargins] - 1) * scale,
                                       cellConfiguration.cellSize.height);
    CGRect markRect = [iTermTextDrawingHelper frameForMarkContainedInRect:leftMarginRect
                                                                 cellSize:cellConfiguration.cellSize
                                                   cellSizeWithoutSpacing:cellConfiguration.cellSizeWithoutSpacing
                                                                    scale:scale];
    _markOffset = markRect.origin;
    const CGSize markSize = markRect.size;
    NSColorSpace *colorSpace = cellConfiguration.colorSpace;
    if (!CGSizeEqualToSize(markSize, _markSize) ||
        ![NSObject object:colorSpace isEqualToObject:_colorSpace] ||
        ![NSObject object:successColor isEqualToObject:_lastSuccessColor] ||
        ![NSObject object:otherColor isEqualToObject:_lastOtherColor] ||
        ![NSObject object:failureColor isEqualToObject:_lastFailureColor]) {
        DLog(@"Mark size, colorspace, or colors have changed");
        _markSize = markSize;
        _colorSpace = colorSpace;
        _lastSuccessColor = successColor;
        _lastOtherColor = otherColor;
        _lastFailureColor = failureColor;
        if (markSize.width > 0 && markSize.height > 0 && successColor && otherColor && failureColor) {
            DLog(@"Size is positive, make images of size %@", NSStringFromSize(markSize));
            NSImage *regularSuccessImage = [self newImageWithMarkOfColor:successColor size:markSize folded:NO];
            NSImage *regularFailureImage = [self newImageWithMarkOfColor:failureColor size:markSize folded:NO];
            NSImage *regularOtherImage = [self newImageWithMarkOfColor:otherColor size:markSize folded:NO];

            NSImage *foldedSuccessImage = [self newImageWithMarkOfColor:successColor size:markSize folded:YES];
            NSImage *foldedFailureImage = [self newImageWithMarkOfColor:failureColor size:markSize folded:YES];
            NSImage *foldedOtherImage = [self newImageWithMarkOfColor:otherColor size:markSize folded:YES];
            _marksArrayTexture = [[iTermTextureArray alloc] initWithImages:@[regularSuccessImage,
                                                                             regularFailureImage,
                                                                             regularOtherImage,
                                                                             foldedSuccessImage,
                                                                             foldedFailureImage,
                                                                             foldedOtherImage]
                                                                    device:_cellRenderer.device];
        } else {
            // Can't build an atlas for this size/colors. Clear the old texture so
            // _markSize and _marksArrayTexture never disagree; a later frame with a
            // valid size and non-nil colors will rebuild it. (drawWithFrameData:
            // draws nothing when the texture is nil.)
            _marksArrayTexture = nil;
        }
    }
}

- (void)initializeTransientState:(iTermMarkRendererTransientState *)tState {
    // The mark size, offset, and texture atlas were computed in
    // -updateForCellConfiguration:... during the driver's per-frame update phase
    // (before transient states are created), because the atlas depends on the
    // per-frame mark colors. Just hand that state to the transient state here.
    tState.markOffset = _markOffset;
    tState.markSize = _markSize;
    tState.marksArrayTexture = _marksArrayTexture;
    tState.vertexBuffer = [_cellRenderer newQuadOfSize:_markSize poolContext:tState.poolContext];
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermMarkRendererTransientState *tState = transientState;
    if (tState.marks.count == 0) {
        return;
    }
    if (tState.marksArrayTexture == nil) {
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
    DLog(@"Using texture frame of %@", NSStringFromRect(textureFrame));
    const iTermVertex vertices[] = {
        // Pixel Positions                              Texture Coordinates
        { { CGRectGetMaxX(quad), CGRectGetMinY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMaxY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMinY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMaxY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMinY(textureFrame) } },

        { { CGRectGetMaxX(quad), CGRectGetMinY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMaxY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMaxY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMinY(textureFrame) } },
        { { CGRectGetMaxX(quad), CGRectGetMaxY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
    };
    tState.vertexBuffer = [_cellRenderer.verticesPool requestBufferFromContext:tState.poolContext
                                                                      withBytes:vertices
                                                                 checkIfChanged:YES];

    NSData *data = [tState newMarkPerInstanceUniforms];
    tState.pius = [_piuPool requestBufferFromContext:tState.poolContext
                                                size:data.length];
    memcpy(tState.pius.contents, data.bytes, data.length);

    [_cellRenderer drawWithTransientState:tState
                            renderEncoder:frameData.renderEncoder
                         numberOfVertices:6
                             numberOfPIUs:tState.marks.count
                            vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                             @(iTermVertexInputIndexPerInstanceUniforms): tState.pius,
                                             @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                          fragmentBuffers:@{}
                                 textures:@{ @(iTermTextureIndexPrimary): tState.marksArrayTexture.texture } ];
}

#pragma mark - Private

- (NSImage *)newImageWithMarkOfColor:(NSColor *)color size:(CGSize)pixelSize folded:(BOOL)folded {
    return [iTermTextDrawingHelper newImageWithMarkOfColor:color
                                                 pixelSize:pixelSize
                                                    folded:folded];
}

@end
