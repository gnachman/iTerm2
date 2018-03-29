//
//  iTermCornerCutoutRenderer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/29/18.
//

#import "iTermCornerCutoutRenderer.h"

static const CGFloat iTermCornerCutoutTextureSizeInPoints = 5;  // It is a square

@implementation iTermCornerCutoutRendererTransientState

- (id<MTLBuffer>)leftVertexBufferForRenderer:(iTermMetalRenderer *)renderer {
    const CGFloat scale = self.configuration.scale;
    return [renderer newQuadWithFrame:CGRectMake(0,
                                                 0,
                                                 iTermCornerCutoutTextureSizeInPoints * scale,
                                                 iTermCornerCutoutTextureSizeInPoints * scale)
                         textureFrame:CGRectMake(0, 0, 1, 1)
                          poolContext:self.poolContext];
}

- (id<MTLBuffer>)rightVertexBufferForRenderer:(iTermMetalRenderer *)renderer {
    const CGFloat scale = self.configuration.scale;
    const CGFloat width = self.configuration.viewportSize.x;
    return [renderer newQuadWithFrame:CGRectMake(width - iTermCornerCutoutTextureSizeInPoints * scale,
                                                 0,
                                                 iTermCornerCutoutTextureSizeInPoints * scale,
                                                 iTermCornerCutoutTextureSizeInPoints * scale)
                         textureFrame:CGRectMake(0, 0, 1, 1)
                          poolContext:self.poolContext];
}

@end

@implementation iTermCornerCutoutRenderer {
    iTermMetalRenderer *_metalRenderer;
    id<MTLTexture> _leftTexture;
    id<MTLTexture> _rightTexture;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        iTermMetalBlending *blending = [[iTermMetalBlending alloc] init];
        blending.rgbBlendOperation = MTLBlendOperationAdd;
        blending.alphaBlendOperation = MTLBlendOperationMin;

        blending.sourceRGBBlendFactor = MTLBlendFactorZero;
        blending.sourceAlphaBlendFactor = MTLBlendFactorOne;

        blending.destinationRGBBlendFactor = MTLBlendFactorOne;
        blending.destinationAlphaBlendFactor = MTLBlendFactorZero;

        _metalRenderer = [[iTermMetalRenderer alloc] initWithDevice:device
                                                 vertexFunctionName:@"iTermCornerCutoutVertexShader"
                                               fragmentFunctionName:@"iTermCornerCutoutFragmentShader"
                                                           blending:blending
                                                transientStateClass:[iTermCornerCutoutRendererTransientState class]];
        _leftTexture = [_metalRenderer textureFromImage:[NSImage imageNamed:@"LeftCornerMask"]
                                                context:nil];
        assert(_leftTexture);
        _rightTexture = [_metalRenderer textureFromImage:[NSImage imageNamed:@"RightCornerMask"]
                                                 context:nil];
        assert(_rightTexture);
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (nonnull __kindof iTermMetalRendererTransientState *)createTransientStateForConfiguration:(nonnull iTermRenderConfiguration *)configuration
                                                                              commandBuffer:(nonnull id<MTLCommandBuffer>)commandBuffer {
    __kindof iTermMetalRendererTransientState * _Nonnull transientState =
    [_metalRenderer createTransientStateForConfiguration:configuration
                                           commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermCornerCutoutRendererTransientState *)tState {
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateIndicatorsTS;
}

- (void)drawWithRenderEncoder:(nonnull id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(nonnull __kindof iTermMetalRendererTransientState *)transientState {
    iTermCornerCutoutRendererTransientState *tState = transientState;

    if (tState.drawLeft) {
        [self drawTransientState:tState
                   renderEncoder:renderEncoder
                    vertexBuffer:[tState leftVertexBufferForRenderer:_metalRenderer]
                         texture:_leftTexture];
    }
    if (tState.drawRight) {
        [self drawTransientState:tState
                   renderEncoder:renderEncoder
                    vertexBuffer:[tState rightVertexBufferForRenderer:_metalRenderer]
                         texture:_rightTexture];
    }
}

- (void)drawTransientState:(iTermCornerCutoutRendererTransientState *)tState
             renderEncoder:(nonnull id<MTLRenderCommandEncoder>)renderEncoder
              vertexBuffer:(id<MTLBuffer>)vertexBuffer
                   texture:(id<MTLTexture>)texture {
    [_metalRenderer drawWithTransientState:tState
                             renderEncoder:renderEncoder
                          numberOfVertices:6
                              numberOfPIUs:0
                             vertexBuffers:@{ @(iTermVertexInputIndexVertices): vertexBuffer }
                           fragmentBuffers:@{}
                                  textures:@{ @(iTermTextureIndexPrimary): texture }];
}

@end
