#import "iTermMetalRenderer.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermShaderTypes.h"

@implementation iTermRenderConfiguration

- (instancetype)initWithViewportSize:(vector_uint2)viewportSize scale:(CGFloat)scale {
    self = [super init];
    if (self) {
        _viewportSize = viewportSize;
        _scale = scale;
    }
    return self;
}

@end

@interface iTermMetalRendererTransientState()
@property (nonatomic, readwrite) CGFloat scale;
@end

@implementation iTermMetalRendererTransientState

- (instancetype)initWithConfiguration:(iTermRenderConfiguration *)configuration {
    self = [super init];
    if (self) {
        _configuration = configuration;
    }
    return self;
}

- (BOOL)skipRenderer {
    return NO;
}

@end

@implementation iTermMetalRenderer {
    BOOL _blending;
    NSString *_vertexFunctionName;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _device = device;
    }
    return self;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                     vertexFunctionName:(NSString *)vertexFunctionName
                   fragmentFunctionName:(NSString *)fragmentFunctionName
                               blending:(BOOL)blending
                    transientStateClass:(Class)transientStateClass {
    self = [super init];
    if (self) {
        _device = device;
        _vertexFunctionName = [vertexFunctionName copy];
        _fragmentFunctionName = [fragmentFunctionName copy];
        _blending = blending;
        _transientStateClass = transientStateClass;
    }
    return self;
}

- (id<MTLRenderPipelineState>)newPipelineState {
    static id<MTLLibrary> defaultLibrary;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaultLibrary = [_device newDefaultLibrary];
    });
    id <MTLFunction> vertexShader = [defaultLibrary newFunctionWithName:_vertexFunctionName];
    ITDebugAssert(vertexShader);
    id <MTLFunction> fragmentShader = [defaultLibrary newFunctionWithName:_fragmentFunctionName];
    ITDebugAssert(fragmentShader);
    return [self newPipelineWithBlending:_blending
                          vertexFunction:vertexShader
                        fragmentFunction:fragmentShader];
}

#pragma mark - Protocol Methods

- (void)createTransientStateForConfiguration:(iTermRenderConfiguration *)configuration
                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                  completion:(void (^)(__kindof iTermMetalRendererTransientState * _Nonnull))completion {
    iTermMetalRendererTransientState *tState = [[self.transientStateClass alloc] initWithConfiguration:configuration];
    tState.pipelineState = [self newPipelineState];
    completion(tState);
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(NSDictionary *)transientState {
    [self doesNotRecognizeSelector:_cmd];
}

#pragma mark - Utilities for subclasses

- (id<MTLBuffer>)newQuadOfSize:(CGSize)size {
    const iTermVertex vertices[] = {
        // Pixel Positions, Texture Coordinates
        { { size.width, 0 }, { 1.f, 0.f } },
        { { 0, 0 }, { 0.f, 0.f } },
        { { 0, size.height }, { 0.f, 1.f } },

        { { size.width, 0 }, { 1.f, 0.f } },
        { { 0, size.height }, { 0.f, 1.f } },
        { { size.width, size.height }, { 1.f, 1.f } },
    };
    return [_device newBufferWithBytes:vertices length:sizeof(vertices) options:MTLResourceStorageModeShared];
}

- (id<MTLBuffer>)newFlippedQuadOfSize:(CGSize)size {
    const iTermVertex vertices[] = {
        // Pixel Positions, Texture Coordinates
        { { size.width,           0 }, { 1.f, 1.f } },
        { {          0,           0 }, { 0.f, 1.f } },
        { {          0, size.height }, { 0.f, 0.f } },

        { { size.width,           0 }, { 1.f, 1.f } },
        { {          0, size.height }, { 0.f, 0.f } },
        { { size.width, size.height }, { 1.f, 0.f } },
    };
    return [_device newBufferWithBytes:vertices length:sizeof(vertices) options:MTLResourceStorageModeShared];
}

- (id<MTLRenderPipelineState>)newPipelineWithBlending:(BOOL)blending
                                       vertexFunction:(id<MTLFunction>)vertexFunction
                                     fragmentFunction:(id<MTLFunction>)fragmentFunction {
    // Set up a descriptor for creating a pipeline state object
    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.label = [NSString stringWithFormat:@"Pipeline for %@", NSStringFromClass([self class])];
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    if (blending) {
        MTLRenderPipelineColorAttachmentDescriptor *renderbufferAttachment = pipelineStateDescriptor.colorAttachments[0];
        renderbufferAttachment.blendingEnabled = YES;
        renderbufferAttachment.rgbBlendOperation = MTLBlendOperationAdd;
        renderbufferAttachment.alphaBlendOperation = MTLBlendOperationAdd;

        renderbufferAttachment.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        renderbufferAttachment.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

        renderbufferAttachment.sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        renderbufferAttachment.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    }

    NSError *error = NULL;
    id<MTLRenderPipelineState> pipeline = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                                  error:&error];
    ITDebugAssert(pipeline);
    return pipeline;
}

- (id<MTLTexture>)textureFromImage:(NSImage *)image {
    if (!image)
        return nil;

    NSRect imageRect = NSMakeRect(0, 0, image.size.width, image.size.height);
    CGImageRef imageRef = [image CGImageForProposedRect:&imageRect context:NULL hints:nil];

    // Create a suitable bitmap context for extracting the bits of the image
    NSUInteger width = CGImageGetWidth(imageRef);
    NSUInteger height = CGImageGetHeight(imageRef);

    if (width == 0 || height == 0)
        return nil;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    uint8_t *rawData = (uint8_t *)calloc(height * width * 4, sizeof(uint8_t));
    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * width;
    NSUInteger bitsPerComponent = 8;
    CGContextRef bitmapContext = CGBitmapContextCreate(rawData, width, height,
                                                       bitsPerComponent, bytesPerRow, colorSpace,
                                                       kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);

    // Flip the context so the positive Y axis points down
    CGContextTranslateCTM(bitmapContext, 0, height);
    CGContextScaleCTM(bitmapContext, 1, -1);

    CGContextDrawImage(bitmapContext, CGRectMake(0, 0, width, height), imageRef);
    CGContextRelease(bitmapContext);

    MTLTextureDescriptor *textureDescriptor =
    [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                       width:width
                                                      height:height
                                                   mipmapped:NO];
    id<MTLTexture> texture = [_device newTextureWithDescriptor:textureDescriptor];

    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    [texture replaceRegion:region mipmapLevel:0 withBytes:rawData bytesPerRow:bytesPerRow];

    free(rawData);

    return texture;
}

- (void)drawWithTransientState:(iTermMetalRendererTransientState *)tState
                 renderEncoder:(id <MTLRenderCommandEncoder>)renderEncoder
              numberOfVertices:(NSInteger)numberOfVertices
                  numberOfPIUs:(NSInteger)numberOfPIUs
                 vertexBuffers:(NSDictionary<NSNumber *, id<MTLBuffer>> *)vertexBuffers
               fragmentBuffers:(NSDictionary<NSNumber *, id<MTLBuffer>> *)fragmentBuffers
                      textures:(NSDictionary<NSNumber *, id<MTLTexture>> *)textures {
    [renderEncoder setRenderPipelineState:tState.pipelineState];

    [vertexBuffers enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, id<MTLBuffer>  _Nonnull obj, BOOL * _Nonnull stop) {
        [renderEncoder setVertexBuffer:obj
                                offset:0
                               atIndex:[key unsignedIntegerValue]];
    }];

    [fragmentBuffers enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, id<MTLBuffer>  _Nonnull obj, BOOL * _Nonnull stop) {
        [renderEncoder setFragmentBuffer:obj
                                  offset:0
                                 atIndex:[key unsignedIntegerValue]];
    }];

    const vector_uint2 viewportSize = tState.configuration.viewportSize;
    [renderEncoder setVertexBytes:&viewportSize
                           length:sizeof(viewportSize)
                          atIndex:iTermVertexInputIndexViewportSize];

    [textures enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, id<MTLTexture>  _Nonnull obj, BOOL * _Nonnull stop) {
        [renderEncoder setFragmentTexture:obj atIndex:[key unsignedIntegerValue]];
    }];


    if (numberOfPIUs > 0) {
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:numberOfVertices
                        instanceCount:numberOfPIUs];
    } else {
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:numberOfVertices];
    }
}

@end
