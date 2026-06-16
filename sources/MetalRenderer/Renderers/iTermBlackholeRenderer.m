#import "iTermBlackholeRenderer.h"
#import "iTermMetalBufferPool.h"
#import "iTermAdvancedSettingsModel.h"


@implementation iTermBlackholeRendererTransientState
@end

@implementation iTermBlackholeRenderer {
    id<MTLDevice> _device;
    id<MTLRenderPipelineState> _pipelineState;
    iTermMetalBufferPool *_pool;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _device = device;
        _pool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermBlackholeUniforms)];
        [self setupPipelineWithDevice:device];
    }
    return self;
}

- (void)setupPipelineWithDevice:(id<MTLDevice>)device {
    id<MTLLibrary> library = [device newDefaultLibrary];
    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"iTermBlackholeVertexShader"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"iTermBlackholeFragmentShader"];

    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.vertexFunction = vertexFunction;
    pipelineDescriptor.fragmentFunction = fragmentFunction;
    if ([iTermAdvancedSettingsModel hdrCursor]) {
        pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
    } else {
        pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    }
    pipelineDescriptor.colorAttachments[0].blendingEnabled = NO;

    NSError *error = nil;
    _pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    if (error) {
        NSLog(@"Error creating Blackhole pipeline state: %@", error);
    }
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatNA; // Stats are optional, NA is fine
}

- (BOOL)rendererDisabled {
    return NO;
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForConfiguration:(iTermRenderConfiguration *)configuration
                                                                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    iTermBlackholeRendererTransientState *tState = [[iTermBlackholeRendererTransientState alloc] initWithConfiguration:configuration];
    return tState;
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalRendererTransientState *)transientState {

    iTermBlackholeRendererTransientState *tState = transientState;
    if (!tState.sourceTexture || !_pipelineState) {
        return;
    }

    id<MTLRenderCommandEncoder> renderEncoder = frameData.renderEncoder;
    [renderEncoder setRenderPipelineState:_pipelineState];

    iTermBlackholeUniforms uniforms = tState.uniforms;
    id<MTLBuffer> uniformBuffer = [_pool requestBufferFromContext:tState.poolContext
                                                        withBytes:&uniforms
                                                   checkIfChanged:NO];

    [renderEncoder setFragmentTexture:tState.sourceTexture atIndex:0];
    [renderEncoder setFragmentBuffer:uniformBuffer offset:0 atIndex:0];

    // Draw full screen quad with 3 vertices
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];

    // Do not call endEncoding here, driver will handle it
}

@end
