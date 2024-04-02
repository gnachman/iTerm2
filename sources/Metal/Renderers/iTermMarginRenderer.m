//
//  iTermMarginRenderer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/17.
//

#import "iTermMarginRenderer.h"

#import "FutureMethods.h"
#import "iTermMetalBufferPool.h"
#import "iTermShaderTypes.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermMarginRendererTransientState
@end

@implementation iTermMarginRenderer {
    iTermMetalCellRenderer *_blendingRenderer;
#if ENABLE_TRANSPARENT_METAL_WINDOWS
    iTermMetalCellRenderer *_nonblendingRenderer NS_AVAILABLE_MAC(10_14);
    iTermMetalCellRenderer *_compositeOverRenderer NS_AVAILABLE_MAC(10_14);
#endif
    iTermMetalBufferPool *_colorPool;
    iTermMetalBufferPool *_verticesPool;
    iTermMetalBufferPool *_deselectedVerticesPool;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
#if ENABLE_TRANSPARENT_METAL_WINDOWS
        if (iTermTextIsMonochrome()) {
            _nonblendingRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                               vertexFunctionName:@"iTermMarginVertexShader"
                                                             fragmentFunctionName:@"iTermMarginFragmentShader"
                                                                         blending:nil
                                                                   piuElementSize:0
                                                              transientStateClass:[iTermMarginRendererTransientState class]];
            _compositeOverRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                                 vertexFunctionName:@"iTermMarginVertexShader"
                                                               fragmentFunctionName:@"iTermMarginFragmentShader"
                                                                           blending:[iTermMetalBlending premultipliedCompositing]
                                                                     piuElementSize:0
                                                                transientStateClass:[iTermMarginRendererTransientState class]];
        }
#endif
        _blendingRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                        vertexFunctionName:@"iTermMarginVertexShader"
                                                      fragmentFunctionName:@"iTermMarginFragmentShader"
                                                                  blending:[[iTermMetalBlending alloc] init]
                                                            piuElementSize:0
                                                       transientStateClass:[iTermMarginRendererTransientState class]];
        _colorPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(vector_float4)];
        _verticesPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(vector_float2) * 6 * 6];
        _deselectedVerticesPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(vector_float2) * 6 * 8];
    }
    return self;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateMarginTS;
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

- (void)drawWithFrameData:(nonnull iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalRendererTransientState *)transientState {
    iTermMarginRendererTransientState *tState = transientState;
    if (tState.hasSelectedRegion) {
        [self drawWithSelectedRegionHavingFrameData:frameData tState:tState];
    } else {
        [self drawRegularHavingFrameData:frameData tState:tState];
    }
}

- (void)drawRegularHavingFrameData:(nonnull iTermMetalFrameData *)frameData
                            tState:(nonnull iTermMarginRendererTransientState *)tState {
    [self initializeRegularVertexBuffer:tState];
    vector_float4 regularColor = tState.regularColor;
    if (iTermTextIsMonochrome()) {
        regularColor.x *= regularColor.w;
        regularColor.y *= regularColor.w;
        regularColor.z *= regularColor.w;
    }
    id<MTLBuffer> colorBuffer = [_colorPool requestBufferFromContext:tState.poolContext
                                                           withBytes:&regularColor
                                                      checkIfChanged:YES];
    iTermMetalCellRenderer *cellRenderer = [self rendererForConfiguration:tState.cellConfiguration];
    [cellRenderer drawWithTransientState:tState
                           renderEncoder:frameData.renderEncoder
                        numberOfVertices:6 * 4
                            numberOfPIUs:0
                           vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer }
                         fragmentBuffers:@{ @(iTermFragmentBufferIndexMarginColor): colorBuffer }
                                textures:@{}];
}

// Matches function in iTermBackgroundColor.metal
static vector_float4 iTermBlendColors(vector_float4 src, vector_float4 dst) {
    vector_float4 out;
    out.w = src.w + dst.w * (1 - src.w);
    if (out.w > 0) {
        out.xyz = (src.xyz * src.w + dst.xyz * dst.w * (1 - src.w)) / out.w;
    } else {
        out.xyz = 0;
    }
    return out;
}

- (void)drawWithSelectedRegionHavingFrameData:(nonnull iTermMetalFrameData *)frameData
                                       tState:(nonnull iTermMarginRendererTransientState *)tState {
    // Do up to 8 separate draws
    iTermMetalCellRenderer *cellRenderer = [self rendererForConfiguration:tState.cellConfiguration];

    int n = [self initializeDeselected:NO vertexBuffer:tState];
    [self drawWithRenderEncoder:frameData.renderEncoder
                          color:tState.regularColor
                    poolContext:tState.poolContext
                   cellRenderer:cellRenderer
                   vertexBuffer:tState.vertexBuffer
                       numQuads:n
                 transientState:tState];

    const NSUInteger suppressedPx = tState.suppressedBottomHeight * tState.cellConfiguration.scale;
    if (tState.suppressedBottomHeight > 0) {
        // Avoid drawing margin in suppressed region. Background color renderer will handle it for us.
        MTLScissorRect scissorRect = {
            .x = 0,
            .y = 0,
            .width = tState.cellConfiguration.viewportSize.x,
            .height = tState.cellConfiguration.viewportSize.y - suppressedPx
        };
        [frameData.renderEncoder setScissorRect:scissorRect];
    }

    n = [self initializeDeselected:YES vertexBuffer:tState];
    const vector_float4 blendedColor = iTermBlendColors(tState.deselectedColor, tState.regularColor);
    [self drawWithRenderEncoder:frameData.renderEncoder
                          color:blendedColor
                    poolContext:tState.poolContext
                   cellRenderer:cellRenderer
                   vertexBuffer:tState.vertexBuffer
                       numQuads:n
                 transientState:tState];
    if (tState.suppressedBottomHeight > 0) {
        MTLScissorRect scissorRect = {
            .x = 0,
            .y = 0,
            .width = tState.cellConfiguration.viewportSize.x,
            .height = tState.cellConfiguration.viewportSize.y
        };
        [frameData.renderEncoder setScissorRect:scissorRect];
    }
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
                        color:(vector_float4)nonPremultipliedColor
                  poolContext:(iTermMetalBufferPoolContext *)poolContext
                 cellRenderer:(iTermMetalCellRenderer *)cellRenderer
                 vertexBuffer:(id<MTLBuffer>)vertexBuffer
                     numQuads:(int)numQuads
               transientState:(iTermMetalRendererTransientState *)transientState {
    if (numQuads == 0) {
        return;
    }
    vector_float4 color = nonPremultipliedColor;
    if (iTermTextIsMonochrome()) {
        color.x *= color.w;
        color.y *= color.w;
        color.z *= color.w;
    }
    id<MTLBuffer> colorBuffer = [_colorPool requestBufferFromContext:poolContext
                                                           withBytes:&color
                                                      checkIfChanged:YES];

    [cellRenderer drawWithTransientState:transientState
                           renderEncoder:renderEncoder
                        numberOfVertices:6 * numQuads
                            numberOfPIUs:0
                           vertexBuffers:@{ @(iTermVertexInputIndexVertices): vertexBuffer }
                         fragmentBuffers:@{ @(iTermFragmentBufferIndexMarginColor): colorBuffer }
                                textures:@{}];
}

- (BOOL)rendererDisabled {
    return NO;
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForCellConfiguration:(nonnull iTermCellRenderConfiguration *)configuration
                                                                          commandBuffer:(nonnull id<MTLCommandBuffer>)commandBuffer {
    iTermMetalCellRenderer *renderer = [self rendererForConfiguration:configuration];
    __kindof iTermMetalRendererTransientState * _Nonnull transientState =
        [renderer createTransientStateForCellConfiguration:configuration
                                             commandBuffer:commandBuffer];
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

- (void)initializeRegularVertexBuffer:(iTermMarginRendererTransientState *)tState {
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

    // Bottom
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
    [self appendVerticesForQuad:CGRectMake(size.width - margins.right - rightGutterWidth,
                                           margins.top,
                                           margins.right + rightGutterWidth,
                                           innerHeight)
                       vertices:v];

    tState.vertexBuffer = [_verticesPool requestBufferFromContext:tState.poolContext
                                                        withBytes:vertices
                                                   checkIfChanged:YES];
}

- (int)initializeDeselected:(BOOL)deselected vertexBuffer:(iTermMarginRendererTransientState *)tState {
    CGSize size = CGSizeMake(tState.configuration.viewportSize.x,
                             tState.configuration.viewportSize.y);
    const NSEdgeInsets margins = tState.margins;
    vector_float2 vertices[6 * 8];
    vector_float2 *v = &vertices[0];
    const VT100GridRange visibleRange = VT100GridRangeMake(0, MAX(0, tState.cellConfiguration.gridSize.height));
    const VT100GridRange selectedRange = VT100GridRangeMake(tState.selectedCommandRect.origin.y,
                                                            tState.selectedCommandRect.size.height);

    int count = 0;

    // Top
    const BOOL topDeselected = tState.selectedCommandRect.origin.y > 0;
    if (deselected == topDeselected) {
        v = [self appendVerticesForQuad:CGRectMake(0,
                                                   size.height - margins.bottom,
                                                   size.width,
                                                   margins.bottom)
                               vertices:v];
        count += 1;
    }

    // Bottom
    const BOOL bottomDeselected = (!VT100GridRangeContains(selectedRange,
                                                           tState.cellConfiguration.gridSize.height) &&
                                   !tState.forceRegularBottomMargin);
    if (deselected == bottomDeselected) {
        v = [self appendVerticesForQuad:CGRectMake(0,
                                                   0,
                                                   size.width,
                                                   margins.top)
                               vertices:v];
        count += 1;
    }

    const CGFloat gridWidth = tState.cellConfiguration.gridSize.width * tState.cellConfiguration.cellSize.width;
    const CGFloat rightGutterWidth = tState.configuration.viewportSize.x - margins.left - margins.right - gridWidth;

    // Left/Right bottom deselected
    CGFloat y = margins.top;
    CGFloat h = 0;

    int lines = tState.cellConfiguration.gridSize.height - (tState.selectedCommandRect.origin.y + tState.selectedCommandRect.size.height);
    h = MAX(0, lines) * tState.cellConfiguration.cellSize.height;

    if (h > 0 && deselected) {
        v = [self appendVerticesForQuad:CGRectMake(0,
                                                   y,
                                                   margins.left,
                                                   h)
                               vertices:v];
        v = [self appendVerticesForQuad:CGRectMake(size.width - margins.right - rightGutterWidth,
                                                   y,
                                                   margins.right + rightGutterWidth,
                                                   h)
                           vertices:v];
        count += 2;
    }
    y += h;

    // Left/Right selected
    const VT100GridRange visibleSelectedRange = VT100GridRangeIntersection(visibleRange, selectedRange);
    h = visibleSelectedRange.length * tState.cellConfiguration.cellSize.height;
    if (h > 0 && !deselected) {
        v = [self appendVerticesForQuad:CGRectMake(0,
                                                   y,
                                                   margins.left,
                                                   h)
                               vertices:v];
        v = [self appendVerticesForQuad:CGRectMake(size.width - margins.right - rightGutterWidth,
                                                   y,
                                                   margins.right + rightGutterWidth,
                                                   h)
                               vertices:v];
        count += 2;
    }
    y += h;

    // Left/Right top deselected
    lines = tState.selectedCommandRect.origin.y;
    h = MAX(0, lines * tState.cellConfiguration.cellSize.height);
    if (h > 0 && deselected) {
        v = [self appendVerticesForQuad:CGRectMake(0,
                                                   y,
                                                   margins.left,
                                                   h)
                               vertices:v];
        v = [self appendVerticesForQuad:CGRectMake(size.width - margins.right - rightGutterWidth,
                                                   y,
                                                   margins.right + rightGutterWidth,
                                                   h)
                               vertices:v];
        count += 2;
    }
    y += h;

    tState.vertexBuffer = [_verticesPool requestBufferFromContext:tState.poolContext
                                                        withBytes:vertices
                                                   checkIfChanged:YES];
    return count;
}

@end

NS_ASSUME_NONNULL_END
