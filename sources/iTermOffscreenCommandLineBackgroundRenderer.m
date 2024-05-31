//
//  iTermOffscreenCommandLineBackgroundRenderer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/14/23.
//

#import "iTermOffscreenCommandLineBackgroundRenderer.h"
#import "iTermPreferences.h"
#import "iTermTextDrawingHelper.h"

static const int iTermOffscreenCommandLineBackgroundRendererNumQuads = 3;

@interface iTermOffscreenCommandLineBackgroundRendererTransientState()
@property (nonatomic) vector_float4 outlineColor;
@property (nonatomic) vector_float4 backgroundColor;
@property (nonatomic) vector_float4 defaultBackgroundColor;
@property (nonatomic) CGFloat rowHeight;  // pixels
@end

@implementation iTermOffscreenCommandLineBackgroundRendererTransientState

- (void)setOutlineColor:(vector_float4)outlineColor
 defaultBackgroundColor:(vector_float4)defaultBackgroundColor
        backgroundColor:(vector_float4)backgroundColor
              rowHeight:(CGFloat)rowHeight {
    self.outlineColor = outlineColor;
    self.defaultBackgroundColor = defaultBackgroundColor;
    self.backgroundColor = backgroundColor;
    self.rowHeight = rowHeight;
}

// Value is in points
+ (CGFloat)heightForScale:(CGFloat)scale rowHeight:(CGFloat)rowHeight topExtraMargin:(CGFloat)topExtraMargin {
    const CGFloat padding = iTermOffscreenCommandLineVerticalPadding * scale;
    return (padding * 2 + rowHeight) / scale - 1 + topExtraMargin;
}

@end

// Matches function in iTermBackgroundColor.metal
vector_float4 iTermBlendColors(vector_float4 src, vector_float4 dst) {
    vector_float4 out;
    out.w = src.w + dst.w * (1 - src.w);
    if (out.w > 0) {
        out.xyz = (src.xyz * src.w + dst.xyz * dst.w * (1 - src.w)) / out.w;
    } else {
        out.xyz = 0;
    }
    return out;
}

vector_float4 iTermPremultiply(vector_float4 color) {
    vector_float4 result = color;
    result.xyz *= color.w;
    return result;
}

@implementation iTermOffscreenCommandLineBackgroundRenderer {
    iTermMetalRenderer *_solidColorRenderer;
    iTermMetalBufferPool *_colorsPool;
    iTermMetalBufferPool *_verticesPool;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _solidColorRenderer = [[iTermMetalRenderer alloc] initWithDevice:device
                                                      vertexFunctionName:@"iTermSolidColorVertexShader"
                                                    fragmentFunctionName:@"iTermSolidColorFragmentShader"
                                                                blending:[iTermMetalBlending compositeSourceOver]
                                                     transientStateClass:[iTermOffscreenCommandLineBackgroundRendererTransientState class]];
        _colorsPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(vector_float4) * iTermOffscreenCommandLineBackgroundRendererNumQuads];
        _verticesPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermVertex) * 6 * iTermOffscreenCommandLineBackgroundRendererNumQuads];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateOffscreenCommandLineTS;
}

- (id<MTLBuffer>)colorsBufferWithColors:(vector_float4 *)colorsPtr
                          poolContext:(iTermMetalBufferPoolContext *)poolContext {
    return [_colorsPool requestBufferFromContext:poolContext
                                      withBytes:colorsPtr
                                 checkIfChanged:YES];
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalRendererTransientState *)transientState {
    iTermOffscreenCommandLineBackgroundRendererTransientState *tState = transientState;
    const CGFloat viewportHeight = tState.configuration.viewportSize.y;
    const CGFloat viewportWidth = tState.configuration.viewportSize.x;
    const CGFloat scale = tState.configuration.scale;
    const CGFloat padding = iTermOffscreenCommandLineVerticalPadding * scale;

    // If you change this also update tState.height.
    const CGRect hullQuad = CGRectMake(0,
                                        viewportHeight - tState.rowHeight - padding * 2 + scale - tState.configuration.extraMargins.top,
                                        viewportWidth,
                                        padding * 2 + tState.rowHeight);
    const CGRect fieldQuad = CGRectMake(0,
                                        viewportHeight - tState.rowHeight - padding * 2 + scale - tState.configuration.extraMargins.top,
                                        viewportWidth,
                                        padding * 2 + tState.rowHeight - scale);
    const CGRect lowerLineQuad = CGRectMake(0,
                                            NSMinY(fieldQuad),
                                            viewportWidth,
                                            scale);

    const iTermVertex vertices[iTermOffscreenCommandLineBackgroundRendererNumQuads * 6] = {
        // Hull (default bg color)
        { { CGRectGetMaxX(hullQuad), CGRectGetMinY(hullQuad) }, { 1, 0 } },
        { { CGRectGetMinX(hullQuad), CGRectGetMinY(hullQuad) }, { 0, 0 } },
        { { CGRectGetMinX(hullQuad), CGRectGetMaxY(hullQuad) }, { 0, 1 } },

        { { CGRectGetMaxX(hullQuad), CGRectGetMinY(hullQuad) }, { 1, 0 } },
        { { CGRectGetMinX(hullQuad), CGRectGetMaxY(hullQuad) }, { 0, 1 } },
        { { CGRectGetMaxX(hullQuad), CGRectGetMaxY(hullQuad) }, { 1, 1 } },


        // Field (offscreen command line color)
        { { CGRectGetMaxX(fieldQuad), CGRectGetMinY(fieldQuad) }, { 1, 0 } },
        { { CGRectGetMinX(fieldQuad), CGRectGetMinY(fieldQuad) }, { 0, 0 } },
        { { CGRectGetMinX(fieldQuad), CGRectGetMaxY(fieldQuad) }, { 0, 1 } },

        { { CGRectGetMaxX(fieldQuad), CGRectGetMinY(fieldQuad) }, { 1, 0 } },
        { { CGRectGetMinX(fieldQuad), CGRectGetMaxY(fieldQuad) }, { 0, 1 } },
        { { CGRectGetMaxX(fieldQuad), CGRectGetMaxY(fieldQuad) }, { 1, 1 } },


        // Lower line
        { { CGRectGetMaxX(lowerLineQuad), CGRectGetMinY(lowerLineQuad) }, { 1, 0 } },
        { { CGRectGetMinX(lowerLineQuad), CGRectGetMinY(lowerLineQuad) }, { 0, 0 } },
        { { CGRectGetMinX(lowerLineQuad), CGRectGetMaxY(lowerLineQuad) }, { 0, 1 } },

        { { CGRectGetMaxX(lowerLineQuad), CGRectGetMinY(lowerLineQuad) }, { 1, 0 } },
        { { CGRectGetMinX(lowerLineQuad), CGRectGetMaxY(lowerLineQuad) }, { 0, 1 } },
        { { CGRectGetMaxX(lowerLineQuad), CGRectGetMaxY(lowerLineQuad) }, { 1, 1 } },
    };
    assert(sizeof(vertices) / sizeof(*vertices) == iTermOffscreenCommandLineBackgroundRendererNumQuads * 6);

    vector_float4 colors[iTermOffscreenCommandLineBackgroundRendererNumQuads] = {
        iTermPremultiply(iTermBlendColors(simd_make_float4(0, 0, 0, 0),
                                          tState.defaultBackgroundColor)),
        tState.backgroundColor,
        tState.outlineColor
    };
    assert(sizeof(colors) / sizeof(*colors) == iTermOffscreenCommandLineBackgroundRendererNumQuads);
    tState.vertexBuffer = [_verticesPool requestBufferFromContext:tState.poolContext
                                                        withBytes:vertices
                                                   checkIfChanged:YES];
    id<MTLBuffer> colorsBuffer = [self colorsBufferWithColors:colors poolContext:tState.poolContext];
    [_solidColorRenderer drawWithTransientState:tState
                                  renderEncoder:frameData.renderEncoder
                               numberOfVertices:sizeof(vertices) / sizeof(*vertices)
                                   numberOfPIUs:0
                                  vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                                   @(iTermVertexColorArray): colorsBuffer
                                                }
                                fragmentBuffers:@{}
                                       textures:@{}];
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForConfiguration:(nonnull iTermRenderConfiguration *)configuration
                                                                               commandBuffer:(nonnull id<MTLCommandBuffer>)commandBuffer {
    iTermOffscreenCommandLineBackgroundRendererTransientState * _Nonnull tState =
        [_solidColorRenderer createTransientStateForConfiguration:configuration
                                                    commandBuffer:commandBuffer];

    [self initializeTransientState:tState];

    return tState;
}

- (void)initializeTransientState:(iTermOffscreenCommandLineBackgroundRendererTransientState *)tState {
}

@end
