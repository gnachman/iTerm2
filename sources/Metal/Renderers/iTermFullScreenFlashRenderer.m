//
//  iTermFullScreenFlashRenderer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/30/17.
//

#import "iTermFullScreenFlashRenderer.h"

@implementation iTermFullScreenFlashRendererTransientState

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];
    NSString *s = [NSString stringWithFormat:
                   @"color=(%@, %@, %@, %@)",
                   @(self.color.x),
                   @(self.color.y),
                   @(self.color.z),
                   @(self.color.w)];
    [s writeToURL:[folder URLByAppendingPathComponent:@"state.txt"]
       atomically:NO
         encoding:NSUTF8StringEncoding
            error:NULL];
}

@end

@implementation iTermFullScreenFlashRenderer {
    iTermMetalRenderer *_metalRenderer;
    iTermMetalBufferPool *_colorBufferPool;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _metalRenderer = [[iTermMetalRenderer alloc] initWithDevice:device
                                                 vertexFunctionName:@"iTermFullScreenFlashVertexShader"
                                               fragmentFunctionName:@"iTermFullScreenFlashFragmentShader"
                                                           blending:[[iTermMetalBlending alloc] init]
                                                transientStateClass:[iTermFullScreenFlashRendererTransientState class]];
        _colorBufferPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(vector_float4)];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateFullScreenFlashTS;
}

- (void)drawWithRenderEncoder:(nonnull id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(nonnull __kindof iTermMetalRendererTransientState *)transientState {
    iTermFullScreenFlashRendererTransientState *tState = transientState;
    if (tState.color.w > 0) {
        CGSize size = CGSizeMake(transientState.configuration.viewportSize.x,
                                 transientState.configuration.viewportSize.y);
        id<MTLBuffer> vertexBuffer = [_metalRenderer newQuadOfSize:size poolContext:tState.poolContext];
        vector_float4 color = simd_make_float4(tState.color.x, tState.color.y, tState.color.z, tState.color.w);
        id<MTLBuffer> colorBuffer = [_colorBufferPool requestBufferFromContext:tState.poolContext
                                                                     withBytes:&color
                                                                checkIfChanged:YES];
        [_metalRenderer drawWithTransientState:tState
                                 renderEncoder:renderEncoder
                              numberOfVertices:6
                                  numberOfPIUs:0
                                 vertexBuffers:@{ @(iTermVertexInputIndexVertices): vertexBuffer }
                               fragmentBuffers:@{ @(iTermFragmentBufferIndexFullScreenFlashColor): colorBuffer }
                                      textures:@{}];
    }
}

- (nonnull __kindof iTermMetalRendererTransientState *)createTransientStateForConfiguration:(nonnull iTermRenderConfiguration *)configuration
                                                                              commandBuffer:(nonnull id<MTLCommandBuffer>)commandBuffer {
    __kindof iTermMetalRendererTransientState * _Nonnull transientState =
    [_metalRenderer createTransientStateForConfiguration:configuration
                                           commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermFullScreenFlashRendererTransientState *)tState {
}

@end
