//
//  iTermCopyBackgroundRenderer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/4/17.
//

#import "iTermCopyBackgroundRenderer.h"


@implementation iTermCopyBackgroundRendererTransientState

- (BOOL)skipRenderer {
    return _sourceTexture == nil;
}

@end

@implementation iTermCopyBackgroundRenderer {
    iTermMetalRenderer *_metalRenderer;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _metalRenderer = [[iTermMetalRenderer alloc] initWithDevice:device
                                                 vertexFunctionName:@"iTermCopyBackgroundVertexShader"
                                               fragmentFunctionName:@"iTermCopyBackgroundFragmentShader"
                                                           blending:NO
                                                transientStateClass:[iTermCopyBackgroundRendererTransientState class]];
    }
    return self;
}

- (void)drawWithRenderEncoder:(nonnull id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(nonnull __kindof iTermMetalRendererTransientState *)transientState {
    iTermCopyBackgroundRendererTransientState *tState = transientState;
    [_metalRenderer drawWithTransientState:tState
                             renderEncoder:renderEncoder
                          numberOfVertices:6
                              numberOfPIUs:0
                             vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer }
                           fragmentBuffers:@{}
                                  textures:@{ @(iTermTextureIndexPrimary): tState.sourceTexture }];
}

- (void)createTransientStateForConfiguration:(iTermRenderConfiguration *)configuration
                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                  completion:(void (^)(__kindof iTermMetalRendererTransientState * _Nonnull))completion {
    [_metalRenderer createTransientStateForConfiguration:configuration
                                           commandBuffer:commandBuffer
                                              completion:^(__kindof iTermMetalRendererTransientState * _Nonnull transientState) {
                                                  [self initializeTransientState:transientState];
                                                  completion(transientState);
                                              }];
}

- (void)initializeTransientState:(iTermCopyBackgroundRendererTransientState *)tState {
    tState.vertexBuffer = [_metalRenderer newFlippedQuadOfSize:CGSizeMake(tState.configuration.viewportSize.x,
                                                                          tState.configuration.viewportSize.y)];
}

@end
