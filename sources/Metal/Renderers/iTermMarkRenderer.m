#import "iTermMarkRenderer.h"

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

- (void)initializeTransientState:(iTermMarkRendererTransientState *)tState {
    const CGFloat scale = tState.configuration.scale;

    CGRect leftMarginRect = CGRectMake(1,
                                       0,
                                       ([iTermPreferences intForKey:kPreferenceKeySideMargins] - 1) * scale,
                                       tState.cellConfiguration.cellSize.height);
    CGRect markRect = [iTermTextDrawingHelper frameForMarkContainedInRect:leftMarginRect
                                                                 cellSize:tState.cellConfiguration.cellSize
                                                   cellSizeWithoutSpacing:tState.cellConfiguration.cellSizeWithoutSpacing
                                                                    scale:scale];
    if (!CGSizeEqualToSize(markRect.size, _markSize) || ![NSObject object:tState.configuration.colorSpace isEqualToObject:_colorSpace]) {
        // Mark size or colorspace has changed
        _markSize = markRect.size;
        _colorSpace = tState.configuration.colorSpace;
        if (_markSize.width > 0 && _markSize.height > 0) {
            NSColor *successColor = [iTermTextDrawingHelper successMarkColor];
            NSColor *otherColor = [iTermTextDrawingHelper otherMarkColor];
            NSColor *failureColor = [iTermTextDrawingHelper errorMarkColor];
            NSImage *successImage = [self newImageWithMarkOfColor:successColor size:_markSize];
            NSImage *failureImage = [self newImageWithMarkOfColor:failureColor size:_markSize];
            NSImage *otherImage = [self newImageWithMarkOfColor:otherColor size:_markSize];

            _marksArrayTexture = [[iTermTextureArray alloc] initWithImages:@[successImage,
                                                                             failureImage,
                                                                             otherImage]
                                                                    device:_cellRenderer.device];
        }
    }

    tState.markOffset = markRect.origin;
    tState.marksArrayTexture = _marksArrayTexture;
    tState.markSize = _markSize;
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

- (NSImage *)newImageWithMarkOfColor:(NSColor *)color size:(CGSize)pixelSize {
    NSSize pointSize = pixelSize;
    const CGFloat scale = 2;
    pointSize.width /= scale;
    pointSize.height /= scale;

    return [iTermTextDrawingHelper newImageWithMarkOfColor:color size:pointSize];
}

@end
