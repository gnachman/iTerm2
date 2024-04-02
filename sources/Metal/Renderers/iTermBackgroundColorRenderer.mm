#import "iTermBackgroundColorRenderer.h"

#import "FutureMethods.h"
#import "iTermPIUArray.h"
#import "iTermTextRenderer.h"

@interface iTermBackgroundColorRendererTransientState()
@end

@implementation iTermBackgroundColorRendererTransientState {
    iTerm2::PIUArray<iTermBackgroundColorPIU> _pius;
}

- (NSUInteger)sizeOfNewPIUBuffer {
    return sizeof(iTermBackgroundColorPIU) * self.cellConfiguration.gridSize.width * self.cellConfiguration.gridSize.height;
}

- (void)setColorRLEs:(const iTermMetalBackgroundColorRLE *)rles
               count:(size_t)count
                 row:(int)row
       repeatingRows:(int)repeatingRows {
    vector_float2 cellSize = simd_make_float2(self.cellConfiguration.cellSize.width, self.cellConfiguration.cellSize.height);
    const int height = self.cellConfiguration.gridSize.height;
    for (int i = 0; i < count; i++) {
        iTermBackgroundColorPIU &piu = *_pius.get_next();
        piu.color = rles[i].color;
        piu.runLength = rles[i].count;
        piu.numRows = repeatingRows;
        piu.offset = simd_make_float2(cellSize.x * (float)rles[i].origin,
                                      cellSize.y * (height - row - repeatingRows));
    }
}

- (void)enumerateSegments:(void (^NS_NOESCAPE)(const iTermBackgroundColorPIU *, size_t))block {
    const int n = _pius.get_number_of_segments();
    for (int segment = 0; segment < n; segment++) {
        const iTermBackgroundColorPIU *array = _pius.start_of_segment(segment);
        size_t size = _pius.size_of_segment(segment);
        block(array, size);
    }
}

@end

@interface iTermBackgroundColorRenderer() <iTermMetalDebugInfoFormatter>
@end

@implementation iTermBackgroundColorRenderer {
    iTermMetalCellRenderer *_blendingRenderer;
    iTermMetalCellRenderer *_nonblendingRenderer NS_AVAILABLE_MAC(10_14);
    iTermMetalBufferPool *_infoPool;
    iTermMetalBufferPool *_suppressedRegionVertexBufferPool;

#if ENABLE_TRANSPARENT_METAL_WINDOWS
    iTermMetalCellRenderer *_compositeOverRenderer NS_AVAILABLE_MAC(10_14);
#endif
    iTermMetalMixedSizeBufferPool *_piuPool;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _suppressedRegionVertexBufferPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermVertex) * 6];
#if ENABLE_TRANSPARENT_METAL_WINDOWS
        if (iTermTextIsMonochrome()) {
            _nonblendingRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                        vertexFunctionName:@"iTermBackgroundColorVertexShader"
                                                      fragmentFunctionName:@"iTermBackgroundColorFragmentShader"
                                                                  blending:nil
                                                            piuElementSize:sizeof(iTermBackgroundColorPIU)
                                                       transientStateClass:[iTermBackgroundColorRendererTransientState class]];
            _nonblendingRenderer.formatterDelegate = self;

            _compositeOverRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                        vertexFunctionName:@"iTermBackgroundColorVertexShader"
                                                      fragmentFunctionName:@"iTermBackgroundColorFragmentShader"
                                                                  blending:[iTermMetalBlending premultipliedCompositing]
                                                            piuElementSize:sizeof(iTermBackgroundColorPIU)
                                                       transientStateClass:[iTermBackgroundColorRendererTransientState class]];
            _compositeOverRenderer.formatterDelegate = self;
        }
#endif
        _blendingRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                        vertexFunctionName:@"iTermBackgroundColorVertexShader"
                                                      fragmentFunctionName:@"iTermBackgroundColorFragmentShader"
                                                                  blending:[[iTermMetalBlending alloc] init]
                                                            piuElementSize:sizeof(iTermBackgroundColorPIU)
                                                       transientStateClass:[iTermBackgroundColorRendererTransientState class]];
        _blendingRenderer.formatterDelegate = self;
        // TODO: The capacity here is a total guess. But this would be a lot of rows to have.
        _piuPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                capacity:512
                                                                    name:@"background color PIU"];
        _infoPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermMetalBackgroundColorInfo)];
    }
    return self;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateBackgroundColorTS;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalCellRenderer *)rendererForConfiguration:(iTermCellRenderConfiguration *)configuration {
#if ENABLE_TRANSPARENT_METAL_WINDOWS
    if (iTermTextIsMonochrome()) {
        if (configuration.hasBackgroundImage) {
            return _compositeOverRenderer;
        } else {
            return _nonblendingRenderer;
        }
    }
#endif
    return _blendingRenderer;
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    iTermMetalCellRenderer *renderer = [self rendererForConfiguration:configuration];
    __kindof iTermMetalCellRendererTransientState * _Nonnull transientState =
        [renderer createTransientStateForCellConfiguration:configuration
                                              commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermBackgroundColorRendererTransientState *)tState {
    tState.vertexBuffer = [[self rendererForConfiguration:tState.cellConfiguration] newQuadOfSize:tState.cellConfiguration.cellSize
                                                                                      poolContext:tState.poolContext];
    tState.vertexBuffer.label = @"Vertices";
}

- (id<MTLBuffer>)infoBufferForTransientState:(iTermBackgroundColorRendererTransientState *)tState {
    iTermMetalBackgroundColorInfo info;
    memset(&info, 0, sizeof(info));
    info.defaultBackgroundColor = tState.defaultBackgroundColor;
    id<MTLBuffer> buffer = [self->_infoPool requestBufferFromContext:tState.poolContext
                                                           withBytes:&info
                                                      checkIfChanged:YES];
    buffer.label = @"BG color info";
    return buffer;
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalRendererTransientState *)transientState {
    iTermBackgroundColorRendererTransientState *tState = transientState;
    id<MTLBuffer> infoBuffer = [self infoBufferForTransientState:tState];
    const NSUInteger suppressedPx = static_cast<NSUInteger>(tState.suppressedBottomHeight * tState.cellConfiguration.scale - tState.margins.top);
    [tState enumerateSegments:^(const iTermBackgroundColorPIU *pius, size_t numberOfInstances) {
        id<MTLBuffer> piuBuffer = [self->_piuPool requestBufferFromContext:tState.poolContext
                                                                      size:numberOfInstances * sizeof(*pius)
                                                                     bytes:pius];
        piuBuffer.label = @"PIUs";
        iTermMetalCellRenderer *cellRenderer = [self rendererForConfiguration:tState.cellConfiguration];

        if (tState.suppressedBottomHeight > 0) {
            // Don't do regular background drawing in the suppressed bottom.
            MTLScissorRect scissorRect = {
                .x = 0,
                .y = 0,
                .width = tState.cellConfiguration.viewportSize.x,
                .height = tState.cellConfiguration.viewportSize.y - suppressedPx
            };
            [frameData.renderEncoder setScissorRect:scissorRect];
        }
        [cellRenderer drawWithTransientState:tState
                               renderEncoder:frameData.renderEncoder
                            numberOfVertices:6
                                numberOfPIUs:numberOfInstances
                               vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                                @(iTermVertexInputIndexPerInstanceUniforms): piuBuffer,
                                                @(iTermVertexInputIndexOffset): tState.offsetBuffer,
                                                @(iTermVertexInputIndexDefaultBackgroundColorInfo): infoBuffer
                               }
                             fragmentBuffers:@{}
                                    textures:@{} ];
        if (tState.suppressedBottomHeight > 0) {
            // Restore the original scissor rect.
            MTLScissorRect scissorRect = {
                .x = 0,
                .y = 0,
                .width = tState.cellConfiguration.viewportSize.x,
                .height = tState.cellConfiguration.viewportSize.y
            };
            [frameData.renderEncoder setScissorRect:scissorRect];
        }
    }];
    if (tState.suppressedBottomHeight > 0) {
        // Fill in the suppressed region with default background color.
        // Note that we also draw the margins for simplicity.
        CGRect quad = CGRectMake(-tState.margins.left, 0, tState.cellConfiguration.viewportSize.x, suppressedPx);
        const CGRect textureFrame = CGRectMake(0, 0, 1, 1);
        const iTermVertex bottomRight = (iTermVertex) {
            .position = simd_make_float2(NSMaxX(quad), NSMinY(quad)),
            .textureCoordinate = simd_make_float2(NSMaxX(textureFrame),
                                                  NSMaxY(textureFrame))
        };
        const iTermVertex bottomLeft = (iTermVertex) {
            .position = simd_make_float2(NSMinX(quad), NSMinY(quad)),
            .textureCoordinate = simd_make_float2(NSMinX(textureFrame),
                                                  NSMaxY(textureFrame))
        };

        const iTermVertex topLeft = (iTermVertex) {
            .position = simd_make_float2(NSMinX(quad), NSMaxY(quad)),
            .textureCoordinate = simd_make_float2(NSMinX(textureFrame),
                                                  NSMinY(textureFrame))
        };

        const iTermVertex topRight = (iTermVertex) {
            .position = simd_make_float2(NSMaxX(quad), NSMaxY(quad)),
            .textureCoordinate = simd_make_float2(NSMaxX(textureFrame),
                                                  NSMinY(textureFrame))
        };

        iTermVertex vertices[] = {
            bottomRight, bottomLeft, topLeft,
            bottomRight, topLeft, topRight
        };
        id<MTLBuffer> vertexBuffer = [_suppressedRegionVertexBufferPool requestBufferFromContext:tState.poolContext
                                                                                      withBytes:vertices
                                                                                 checkIfChanged:YES];

        iTermBackgroundColorPIU piu = {
            .offset = simd_make_float2(0, 0),
            .runLength = 1,
            .numRows = 1,
            .color = tState.defaultBackgroundColor
        };
        piu.color.w = 0;
        id<MTLBuffer> piuBuffer = [self->_piuPool requestBufferFromContext:tState.poolContext
                                                                      size:sizeof(piu)
                                                                     bytes:&piu];
        piuBuffer.label = @"PIUs for suppressed region";

        iTermMetalCellRenderer *cellRenderer = [self rendererForConfiguration:tState.cellConfiguration];
        [cellRenderer drawWithTransientState:tState
                               renderEncoder:frameData.renderEncoder
                            numberOfVertices:6
                                numberOfPIUs:1
                               vertexBuffers:@{ @(iTermVertexInputIndexVertices): vertexBuffer,
                                                @(iTermVertexInputIndexPerInstanceUniforms): piuBuffer,
                                                @(iTermVertexInputIndexOffset): tState.offsetBuffer,
                                                @(iTermVertexInputIndexDefaultBackgroundColorInfo): infoBuffer
                               }
                             fragmentBuffers:@{}
                                    textures:@{} ];
    }
}

#pragma mark - iTermMetalDebugInfoFormatter

- (void)writeVertexBuffer:(id<MTLBuffer>)buffer index:(NSUInteger)index toFolder:(NSURL *)folder {
    if (index == iTermVertexInputIndexPerInstanceUniforms) {
        iTermBackgroundColorPIU *pius = (iTermBackgroundColorPIU *)buffer.contents;
        NSMutableString *s = [NSMutableString string];
        for (int i = 0; i < buffer.length / sizeof(*pius); i++) {
            [s appendFormat:@"offset=(%@, %@) runLength=%@ numRows=%@ color=(%@, %@, %@, %@)\n",
             @(pius[i].offset.x),
             @(pius[i].offset.y),
             @(pius[i].runLength),
             @(pius[i].numRows),
             @(pius[i].color.x),
             @(pius[i].color.y),
             @(pius[i].color.z),
             @(pius[i].color.w)];
        }
        NSURL *url = [folder URLByAppendingPathComponent:@"vertexBuffer.iTermVertexInputIndexPerInstanceUniforms.txt"];
        [s writeToURL:url atomically:NO encoding:NSUTF8StringEncoding error:nil];
    }
}

@end
