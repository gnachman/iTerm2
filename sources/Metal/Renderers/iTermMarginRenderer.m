//
//  iTermMarginRenderer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/17.
//

#import "iTermMarginRenderer.h"

#import "iTermMetalBufferPool.h"
#import "iTermShaderTypes.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermMarginRendererTransientState
@end

@implementation iTermMarginRenderer {
    iTermMetalCellRenderer *_cellRenderer;
    iTermMetalBufferPool *_colorPool;
    iTermMetalBufferPool *_verticesPool;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:@"iTermMarginVertexShader"
                                                  fragmentFunctionName:@"iTermMarginFragmentShader"
                                                              blending:[[iTermMetalBlending alloc] init]
                                                        piuElementSize:0
                                                   transientStateClass:[iTermMarginRendererTransientState class]];
        _colorPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(vector_float4)];
        _verticesPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(vector_float2) * 6 * 4];
    }
    return self;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateMarginTS;
}

- (void)drawWithFrameData:(nonnull iTermMetalFrameData *)frameData
           transientState:(nonnull __kindof iTermMetalRendererTransientState *)transientState {
    iTermMarginRendererTransientState *tState = transientState;
    vector_float4 color = tState.color;
    id<MTLBuffer> colorBuffer = [_colorPool requestBufferFromContext:tState.poolContext
                                                           withBytes:&color
                                                      checkIfChanged:YES];
    [_cellRenderer drawWithTransientState:tState
                             renderEncoder:frameData.renderEncoder
                          numberOfVertices:6 * 4
                              numberOfPIUs:0
                             vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer }
                           fragmentBuffers:@{ @(iTermFragmentBufferIndexMarginColor): colorBuffer }
                                  textures:@{}];
}

- (BOOL)rendererDisabled {
    return NO;
}

- (__kindof iTermMetalRendererTransientState * _Nonnull)createTransientStateForCellConfiguration:(nonnull iTermCellRenderConfiguration *)configuration
                                   commandBuffer:(nonnull id<MTLCommandBuffer>)commandBuffer {
    __kindof iTermMetalRendererTransientState * _Nonnull transientState =
        [_cellRenderer createTransientStateForCellConfiguration:configuration
                                              commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (vector_float2 *)appendVerticesForQuad:(CGRect)quad vertices:(vector_float2 *)v {
    *(v++) = simd_make_float2(CGRectGetMaxX(quad), CGRectGetMinY(quad));
    *(v++) = simd_make_float2(CGRectGetMinX(quad), CGRectGetMinY(quad));
    *(v++) = simd_make_float2(CGRectGetMinX(quad), CGRectGetMaxY(quad));

    *(v++) = simd_make_float2(CGRectGetMaxX(quad), CGRectGetMinY(quad));
    *(v++) = simd_make_float2(CGRectGetMinX(quad), CGRectGetMaxY(quad));
    *(v++) = simd_make_float2(CGRectGetMaxX(quad), CGRectGetMaxY(quad));

    return v;
}

- (void)initializeTransientState:(iTermMarginRendererTransientState *)tState {
    CGSize size = CGSizeMake(tState.configuration.viewportSize.x,
                             tState.configuration.viewportSize.y);
    const NSEdgeInsets margins = tState.margins;
    vector_float2 vertices[6 * 4];
    vector_float2 *v = &vertices[0];
    // Top
    v = [self appendVerticesForQuad:CGRectMake(0,
                                               0,
                                               size.width,
                                               margins.top)
                           vertices:v];

    // Botom
    v = [self appendVerticesForQuad:CGRectMake(0,
                                               size.height - margins.bottom,
                                               size.width,
                                               margins.bottom)
                           vertices:v];

    const CGFloat innerHeight = size.height - margins.bottom - margins.top;

    // Left
    v = [self appendVerticesForQuad:CGRectMake(0,
                                               margins.top,
                                               margins.left,
                                               innerHeight)
                           vertices:v];

    // Right
    const CGFloat gridWidth = tState.cellConfiguration.gridSize.width * tState.cellConfiguration.cellSize.width;
    const CGFloat rightGutterWidth = tState.configuration.viewportSize.x - margins.left - margins.right - gridWidth;
    v = [self appendVerticesForQuad:CGRectMake(size.width - margins.right - rightGutterWidth,
                                               margins.top,
                                               margins.right + rightGutterWidth,
                                               innerHeight)
                           vertices:v];

    tState.vertexBuffer = [_verticesPool requestBufferFromContext:tState.poolContext
                                                        withBytes:vertices
                                                   checkIfChanged:YES];
}

@end

NS_ASSUME_NONNULL_END
