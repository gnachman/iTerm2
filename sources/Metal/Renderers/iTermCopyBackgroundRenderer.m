//
//  iTermCopyBackgroundRenderer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/4/17.
//

#import "iTermCopyBackgroundRenderer.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermShaderTypes.h"


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

- (void)validateVertexBuffer:(id<MTLBuffer>)buffer expectedSize:(CGSize)size {
    if (!buffer) {
        ITCriticalError(NO, @"CopyToDrawable: Vertex buffer is nil");
        return;
    }

    const iTermVertex *vertices = (const iTermVertex *)buffer.contents;
    const CGFloat w = size.width;
    const CGFloat h = size.height;

    // Expected positions for flipped quad (6 vertices forming 2 triangles)
    const struct { CGFloat x, y; } expected[6] = {
        { w, 0 }, { 0, 0 }, { 0, h },  // Triangle 1
        { w, 0 }, { 0, h }, { w, h },  // Triangle 2
    };

    for (int i = 0; i < 6; i++) {
        const CGFloat vx = vertices[i].position.x;
        const CGFloat vy = vertices[i].position.y;
        const CGFloat epsilon = 0.01;

        if (fabs(vx - expected[i].x) > epsilon || fabs(vy - expected[i].y) > epsilon) {
            ITCriticalError(NO,
                @"CopyToDrawable vertex %d mismatch: got (%.1f,%.1f) expected (%.1f,%.1f). "
                @"Size=(%.0f,%.0f). All vertices: "
                @"[(%.1f,%.1f),(%.1f,%.1f),(%.1f,%.1f),(%.1f,%.1f),(%.1f,%.1f),(%.1f,%.1f)]",
                i, vx, vy, expected[i].x, expected[i].y, w, h,
                vertices[0].position.x, vertices[0].position.y,
                vertices[1].position.x, vertices[1].position.y,
                vertices[2].position.x, vertices[2].position.y,
                vertices[3].position.x, vertices[3].position.y,
                vertices[4].position.x, vertices[4].position.y,
                vertices[5].position.x, vertices[5].position.y);
            return;
        }
    }
}

- (void)drawWithFrameData:(nonnull iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalRendererTransientState *)transientState {
    iTermCopyRendererTransientState *tState = transientState;

    if ([iTermAdvancedSettingsModel metalValidateVertexBuffers]) {
        [self validateVertexBuffer:tState.vertexBuffer
                      expectedSize:CGSizeMake(tState.configuration.viewportSize.x,
                                              tState.configuration.viewportSize.y)];
    }

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

@implementation iTermCopyToDrawableRendererTransientState
@end

@implementation iTermCopyToDrawableRenderer

- (Class)transientStateClass {
    return [iTermCopyToDrawableRendererTransientState class];
}

@end
