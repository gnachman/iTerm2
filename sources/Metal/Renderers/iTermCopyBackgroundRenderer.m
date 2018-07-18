//
//  iTermCopyBackgroundRenderer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/4/17.
//

#import "iTermCopyBackgroundRenderer.h"
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

@implementation iTermCopyRendererTransientState

- (BOOL)skipRenderer {
    return _sourceTexture == nil;
}

@end

@implementation iTermCopyRenderer {
    iTermMetalRenderer *_metalRenderer;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _metalRenderer = [[iTermMetalRenderer alloc] initWithDevice:device
                                                 vertexFunctionName:@"iTermCopyBackgroundVertexShader"
                                               fragmentFunctionName:self.fragmentFunctionName
                                                           blending:nil
                                                transientStateClass:[self transientStateClass]];
    }
    return self;
}

- (NSString *)fragmentFunctionName {
    return @"iTermCopyBackgroundFragmentShader";
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateCopyBackgroundTS;
}

- (void)drawWithFrameData:(nonnull iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalRendererTransientState *)transientState {
    iTermCopyRendererTransientState *tState = transientState;
    [_metalRenderer drawWithTransientState:tState
                             renderEncoder:frameData.renderEncoder
                          numberOfVertices:6
                              numberOfPIUs:0
                             vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer }
                           fragmentBuffers:@{}
                                  textures:@{ @(iTermTextureIndexPrimary): tState.sourceTexture }];
}

- (BOOL)rendererDisabled {
    return NO;
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForConfiguration:(iTermRenderConfiguration *)configuration
                                                                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    if (!_enabled) {
        return nil;
    }
    __kindof iTermMetalRendererTransientState * _Nonnull transientState =
        [_metalRenderer createTransientStateForConfiguration:configuration
                                               commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermCopyRendererTransientState *)tState {
    tState.vertexBuffer = [_metalRenderer newFlippedQuadOfSize:CGSizeMake(tState.configuration.viewportSize.x,
                                                                          tState.configuration.viewportSize.y)
                                                   poolContext:tState.poolContext];
}

- (Class)transientStateClass {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

@end

@implementation iTermCopyBackgroundRendererTransientState
@end

@implementation iTermCopyBackgroundRenderer

- (Class)transientStateClass {
    return [iTermCopyBackgroundRendererTransientState class];
}

@end

@implementation iTermCopyOffscreenRendererTransientState
@end

@implementation iTermCopyOffscreenRenderer

- (Class)transientStateClass {
    return [iTermCopyOffscreenRendererTransientState class];
}

@end

#if ENABLE_USE_TEMPORARY_TEXTURE
@implementation iTermCopyToDrawableRendererTransientState
@end

@implementation iTermCopyToDrawableRenderer

- (Class)transientStateClass {
    return [iTermCopyToDrawableRendererTransientState class];
}

@end
#endif

@implementation iTermPremultiplyAlphaRendererTransientState
@end

@implementation iTermPremultiplyAlphaRenderer {
    MPSImageConversion *_conversion;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super initWithDevice:device];
    if (self) {
        _conversion = [[MPSImageConversion alloc] initWithDevice:device
                                                        srcAlpha:MPSAlphaTypeNonPremultiplied
                                                       destAlpha:MPSAlphaTypePremultiplied
                                                 backgroundColor:nil
                                                  conversionInfo:nil];
    }
    return self;
}

- (Class)transientStateClass {
    return [iTermPremultiplyAlphaRendererTransientState class];
}

- (NSString *)fragmentFunctionName {
    return @"iTermPremultiplyAlphaFragmentShader";
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForConfiguration:(iTermRenderConfiguration *)configuration
                                                                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    iTermPremultiplyAlphaRendererTransientState *tState = [super createTransientStateForConfiguration:configuration
                                                                                        commandBuffer:commandBuffer];
    if (!tState) {
        return nil;
    }
    tState.commandBuffer = commandBuffer;
    return tState;
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData transientState:(__kindof iTermMetalRendererTransientState *)transientState {
    iTermPremultiplyAlphaRendererTransientState *tState = transientState;
    [_conversion encodeToCommandBuffer:tState.commandBuffer
                         sourceTexture:tState.sourceTexture
                    destinationTexture:tState.destinationTexture];
}

@end
