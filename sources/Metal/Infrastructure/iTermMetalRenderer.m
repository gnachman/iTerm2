#import "iTermMetalRenderer.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermMetalBufferPool.h"
#import "iTermMetalDebugInfo.h"
#import "iTermShaderTypes.h"
#import "iTermTexture.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import <simd/simd.h>

const NSInteger iTermMetalDriverMaximumNumberOfFramesInFlight = 3;

@implementation iTermMetalBlending

+ (instancetype)compositeSourceOver {
    iTermMetalBlending *blending = [[iTermMetalBlending alloc] init];
    // I tried to make this the same as NSCompositingOperationSourceOver. It's not quite right but I have
    // no idea why.
    blending.rgbBlendOperation = MTLBlendOperationAdd;
    blending.sourceRGBBlendFactor = MTLBlendFactorOne;  // because it's premultiplied
    blending.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    blending.alphaBlendOperation = MTLBlendOperationMax;
    blending.sourceAlphaBlendFactor = MTLBlendFactorOne;
    blending.destinationAlphaBlendFactor = MTLBlendFactorOne;

    return blending;
}

#if ENABLE_TRANSPARENT_METAL_WINDOWS

// See https://en.wikipedia.org/wiki/Alpha_compositing
+ (instancetype)premultipliedCompositing {
    iTermMetalBlending *blending = [[iTermMetalBlending alloc] init];
    blending.rgbBlendOperation = MTLBlendOperationAdd;
    blending.sourceRGBBlendFactor = MTLBlendFactorOne;
    blending.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    blending.alphaBlendOperation = MTLBlendOperationAdd;
    blending.sourceAlphaBlendFactor = MTLBlendFactorOne;
    blending.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    return blending;
}

#endif

- (instancetype)init {
    self = [super init];
    if (self) {
        _rgbBlendOperation = MTLBlendOperationAdd;
        _sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        _destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

        _alphaBlendOperation = MTLBlendOperationAdd;
        _sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        _destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    }
    return self;
}

@end

@implementation iTermRenderConfiguration

- (instancetype)initWithViewportSize:(vector_uint2)viewportSize
                               scale:(CGFloat)scale
                  hasBackgroundImage:(BOOL)hasBackgroundImage {
    self = [super init];
    if (self) {
        _viewportSize = viewportSize;
        _scale = scale;
        _hasBackgroundImage = hasBackgroundImage;
    }
    return self;
}

- (NSString *)debugDescription {
    return [NSString stringWithFormat:@"<%@: %p viewportSize=%@x%@ scale=%@>",
            NSStringFromClass([self class]),
            self,
            @(self.viewportSize.x),
            @(self.viewportSize.y),
            @(self.scale)];
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
        _poolContext = [[iTermMetalBufferPoolContext alloc] init];
        iTermPreciseTimerStats *stats = self.stats;
        for (int i = 0; i < self.numberOfStats; i++) {
            iTermPreciseTimerStatsInit(&stats[i], [self nameForStat:i].UTF8String);
        }
    }
    return self;
}

- (BOOL)skipRenderer {
    return NO;
}

- (void)measureTimeForStat:(int)index ofBlock:(void (^)(void))block {
    iTermPreciseTimerStats *stat = self.stats + index;
    iTermPreciseTimerStatsStartTimer(stat);
    block();
    iTermPreciseTimerStatsMeasureAndRecordTimer(stat);
}

- (nullable iTermPreciseTimerStats *)stats {
    return NULL;
}

- (int)numberOfStats {
    return 0;
}

- (NSString *)nameForStat:(int)i {
    [self doesNotRecognizeSelector:_cmd];
    return @"NA";
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [[_pipelineState debugDescription] writeToURL:[folder URLByAppendingPathComponent:@"PipelineState.txt"]
                                       atomically:NO
                                         encoding:NSUTF8StringEncoding
                                            error:NULL];
    [[_configuration debugDescription] writeToURL:[folder URLByAppendingPathComponent:@"Configuration.txt"]
                                       atomically:NO
                                         encoding:NSUTF8StringEncoding
                                            error:NULL];
    NSString *state = [NSString stringWithFormat:@"skip=%@", self.skipRenderer ? @"YES" : @"NO"];
    [state writeToURL:[folder URLByAppendingPathComponent:@"TransientState.txt"]
           atomically:NO
             encoding:NSUTF8StringEncoding
                error:NULL];
}

@end

@implementation iTermMetalRenderer {
    NSString *_vertexFunctionName;
    NSMutableDictionary<NSDictionary *, id<MTLRenderPipelineState>> *_pipelineStates;
    iTermMetalBlending *_blending;
    vector_uint2 _cachedViewportSize;
    id<MTLBuffer> _cachedViewportSizeBuffer;
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
                               blending:(iTermMetalBlending *)blending
                    transientStateClass:(Class)transientStateClass {
    self = [super init];
    if (self) {
        _device = device;
        _vertexFunctionName = [vertexFunctionName copy];
        _fragmentFunctionName = [fragmentFunctionName copy];
        _blending = blending;
        _transientStateClass = transientStateClass;
        _verticesPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermVertex) * 6];
        _pipelineStates = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSDictionary *)keyForPipelineState {
    // This must contain all inputs to picking the pipeline state. These can be changed at runtime.
    return @{ @"fragment function": _fragmentFunctionName ?: @"",
              @"vertex function": _vertexFunctionName ?: @"" };
}

- (id<MTLRenderPipelineState>)pipelineState {
    NSDictionary *key = [self keyForPipelineState];
    if (_pipelineStates[key] == nil) {
        static id<MTLLibrary> defaultLibrary;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            defaultLibrary = [self->_device newDefaultLibrary];
        });
        id <MTLFunction> vertexShader = [defaultLibrary newFunctionWithName:_vertexFunctionName];
        ITDebugAssert(vertexShader);
        id <MTLFunction> fragmentShader = [defaultLibrary newFunctionWithName:_fragmentFunctionName];
        ITDebugAssert(fragmentShader);
        _pipelineStates[key] = [self newPipelineWithBlending:_blending
                                              vertexFunction:vertexShader
                                            fragmentFunction:fragmentShader];
    }
    return _pipelineStates[key];
}

#pragma mark - iTermMetalDebugInfoFormatter

- (void)writeVertexBuffer:(id<MTLBuffer>)buffer index:(NSUInteger)index toFolder:(NSURL *)folder {
    NSString *name = [NSString stringWithFormat:@"vertexBuffer.%@.%@.bin", @(index), buffer.label];
    if (index == iTermVertexInputIndexVertices) {
        NSMutableString *s = [NSMutableString string];
        iTermVertex *v = (iTermVertex *)buffer.contents;
        for (int i = 0; i < buffer.length / sizeof(iTermVertex); i++) {
            [s appendFormat:@"position=(%@, %@) textureCoordinate=(%@, %@)\n",
             @(v[i].position.x),
             @(v[i].position.y),
             @(v[i].textureCoordinate.x),
             @(v[i].textureCoordinate.y)];
        }
        [s writeToURL:[folder URLByAppendingPathComponent:name] atomically:NO encoding:NSUTF8StringEncoding error:nil];
    } else {
        NSData *data = [NSData dataWithBytesNoCopy:buffer.contents
                                            length:buffer.length
                                      freeWhenDone:NO];
        [data writeToURL:[folder URLByAppendingPathComponent:name] atomically:NO];
    }

    if ([_formatterDelegate respondsToSelector:@selector(writeVertexBuffer:index:toFolder:)]) {
        [_formatterDelegate writeVertexBuffer:buffer index:index toFolder:folder];
    }
}

- (void)writeFragmentBuffer:(id<MTLBuffer>)buffer index:(NSUInteger)index toFolder:(NSURL *)folder {
    NSData *data = [NSData dataWithBytesNoCopy:buffer.contents
                                        length:buffer.length
                                  freeWhenDone:NO];
    NSString *name = [NSString stringWithFormat:@"fragmentBuffer.%@.%@.bin", @(index), buffer.label];
    [data writeToURL:[folder URLByAppendingPathComponent:name] atomically:NO];

    if ([_formatterDelegate respondsToSelector:@selector(writeFragmentBuffer:index:toFolder:)]) {
        [_formatterDelegate writeFragmentBuffer:buffer index:index toFolder:folder];
    }
}

- (void)writeFragmentTexture:(id<MTLTexture>)texture index:(NSUInteger)index toFolder:(NSURL *)folder {
    NSUInteger length = [iTermTexture rawDataSizeForTexture:texture];
    int samplesPerPixel = [iTermTexture samplesPerPixelForTexture:texture];
    NSMutableData *storage = [NSMutableData dataWithLength:length];
    [texture getBytes:storage.mutableBytes
          bytesPerRow:[iTermTexture bytesPerRowForForTexture:texture]
           fromRegion:MTLRegionMake2D(0, 0, texture.width, texture.height)
          mipmapLevel:0];
    NSImage *image = [NSImage imageWithRawData:storage
                                          size:NSMakeSize(texture.width, texture.height)
                                 bitsPerSample:8
                               samplesPerPixel:samplesPerPixel
                                      hasAlpha:samplesPerPixel == 4
                                colorSpaceName:NSDeviceRGBColorSpace];
    NSString *name = [NSString stringWithFormat:@"texture.%@.%@.png", @(index), texture.label];
    [image saveAsPNGTo:[folder URLByAppendingPathComponent:name].path];

    if ([_formatterDelegate respondsToSelector:@selector(writeFragmentTexture:index:toFolder:)]) {
        [_formatterDelegate writeFragmentTexture:texture index:index toFolder:folder];
    }
}

#pragma mark - Protocol Methods

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForConfiguration:(iTermRenderConfiguration *)configuration
                                                                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    iTermMetalRendererTransientState *tState = [[self.transientStateClass alloc] initWithConfiguration:configuration];
    tState.pipelineState = [self pipelineState];
    return tState;
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(NSDictionary *)transientState {
    [self doesNotRecognizeSelector:_cmd];
}

#pragma mark - Utilities for subclasses

- (id<MTLBuffer>)newQuadWithFrame:(CGRect)quad
                     textureFrame:(CGRect)textureFrame
                      poolContext:(iTermMetalBufferPoolContext *)poolContext {
    const iTermVertex vertices[] = {
        // Pixel Positions                              Texture Coordinates
        { { CGRectGetMaxX(quad), CGRectGetMinY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMinY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMinY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMaxY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },

        { { CGRectGetMaxX(quad), CGRectGetMinY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMinY(textureFrame) } },
        { { CGRectGetMinX(quad), CGRectGetMaxY(quad) }, { CGRectGetMinX(textureFrame), CGRectGetMaxY(textureFrame) } },
        { { CGRectGetMaxX(quad), CGRectGetMaxY(quad) }, { CGRectGetMaxX(textureFrame), CGRectGetMaxY(textureFrame) } },
    };
    return [_verticesPool requestBufferFromContext:poolContext
                                         withBytes:vertices
                                    checkIfChanged:YES];
}

- (id<MTLBuffer>)newQuadOfSize:(CGSize)size poolContext:(iTermMetalBufferPoolContext *)poolContext {
    const iTermVertex vertices[] = {
        // Pixel Positions             Texture Coordinates
        { { size.width,           0 }, { 1.f, 0.f } },
        { {          0,           0 }, { 0.f, 0.f } },
        { {          0, size.height }, { 0.f, 1.f } },

        { { size.width,           0 }, { 1.f, 0.f } },
        { {          0, size.height }, { 0.f, 1.f } },
        { { size.width, size.height }, { 1.f, 1.f } },
    };
    return [_verticesPool requestBufferFromContext:poolContext
                                         withBytes:vertices
                                    checkIfChanged:YES];
}

- (id<MTLBuffer>)newFlippedQuadOfSize:(CGSize)size poolContext:(iTermMetalBufferPoolContext *)poolContext {
    const iTermVertex vertices[] = {
        // Pixel Positions, Texture Coordinates
        { { size.width,           0 }, { 1.f, 1.f } },
        { {          0,           0 }, { 0.f, 1.f } },
        { {          0, size.height }, { 0.f, 0.f } },

        { { size.width,           0 }, { 1.f, 1.f } },
        { {          0, size.height }, { 0.f, 0.f } },
        { { size.width, size.height }, { 1.f, 0.f } },
    };
    return [_verticesPool requestBufferFromContext:poolContext
                                         withBytes:vertices
                                    checkIfChanged:YES];
}

- (id<MTLRenderPipelineState>)newPipelineWithBlending:(iTermMetalBlending *)blending
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
        renderbufferAttachment.rgbBlendOperation = blending.rgbBlendOperation;
        renderbufferAttachment.alphaBlendOperation = blending.alphaBlendOperation;

        renderbufferAttachment.sourceRGBBlendFactor = blending.sourceRGBBlendFactor;
        renderbufferAttachment.destinationRGBBlendFactor = blending.destinationRGBBlendFactor;

        renderbufferAttachment.sourceAlphaBlendFactor = blending.sourceAlphaBlendFactor;
        renderbufferAttachment.destinationAlphaBlendFactor = blending.destinationAlphaBlendFactor;
    }

    NSError *error = NULL;
    id<MTLRenderPipelineState> pipeline = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                                  error:&error];
    ITDebugAssert(pipeline);
    return pipeline;
}

- (nullable id<MTLTexture>)textureFromImage:(NSImage *)image context:(nullable iTermMetalBufferPoolContext *)context {
    return [self textureFromImage:image context:context pool:nil];
}

- (void)convertWidth:(NSUInteger)width
              height:(NSUInteger)height
             toWidth:(NSUInteger *)widthOut
              height:(NSUInteger *)heightOut
        notExceeding:(NSInteger)maxSize {
    if (height > width) {
        [self convertWidth:height height:width toWidth:heightOut height:widthOut notExceeding:maxSize];
        return;
    }
    // At this point, width >= height
    if (width > maxSize) {
        *widthOut = maxSize;
        const CGFloat aspectRatio = (CGFloat)height / (CGFloat)width;
        *heightOut = maxSize * aspectRatio;
    } else {
        *widthOut = width;
        *heightOut = height;
    }
}

- (nullable id<MTLTexture>)textureFromImage:(NSImage *)image context:(iTermMetalBufferPoolContext *)context pool:(iTermTexturePool *)pool {
    if (!image) {
        return nil;
    }
    NSRect imageRect = NSMakeRect(0, 0, image.size.width, image.size.height);
    CGImageRef imageRef = [image CGImageForProposedRect:&imageRect context:NULL hints:nil];

    // Create a suitable bitmap context for extracting the bits of the image
    NSUInteger width, height;
    [self convertWidth:CGImageGetWidth(imageRef)
                height:CGImageGetHeight(imageRef)
               toWidth:&width
                height:&height
          notExceeding:4096];
    if (width == 0 || height == 0) {
        return nil;
    }

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
    id<MTLTexture> texture = nil;
    if (pool) {
        texture = [pool requestTextureOfSize:simd_make_uint2(width, height)];
    }
    if (!texture) {
        texture = [_device newTextureWithDescriptor:textureDescriptor];
    }

    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    [texture replaceRegion:region mipmapLevel:0 withBytes:rawData bytesPerRow:bytesPerRow];

    [iTermTexture setBytesPerRow:bytesPerRow
                     rawDataSize:height * width * 4
                 samplesPerPixel:4
                      forTexture:texture];

    free(rawData);
    if (texture) {
        [context didAddTextureOfSize:texture.width * texture.height];
    }
    return texture;
}

- (id<MTLBuffer>)vertexBufferForViewportSize:(vector_uint2)viewportSize {
    if (!simd_equal(viewportSize, _cachedViewportSize)) {
        _cachedViewportSize = viewportSize;
        _cachedViewportSizeBuffer = [_device newBufferWithBytes:&viewportSize
                                                         length:sizeof(viewportSize)
                                                        options:MTLResourceStorageModeShared];
    }
    return _cachedViewportSizeBuffer;
}

- (void)drawWithTransientState:(iTermMetalRendererTransientState *)tState
                 renderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
              numberOfVertices:(NSInteger)numberOfVertices
                  numberOfPIUs:(NSInteger)numberOfPIUs
                 vertexBuffers:(NSDictionary<NSNumber *, id<MTLBuffer>> *)clientVertexBuffers
               fragmentBuffers:(NSDictionary<NSNumber *, id<MTLBuffer>> *)fragmentBuffers
                      textures:(NSDictionary<NSNumber *, id<MTLTexture>> *)textures {
    iTermMetalDebugDrawInfo *debugDrawInfo = [tState.debugInfo newDrawWithFormatter:self];
    debugDrawInfo.name = NSStringFromClass(tState.class);

    debugDrawInfo.fragmentFunctionName = self.fragmentFunctionName;
    debugDrawInfo.vertexFunctionName = self.vertexFunctionName;
    [renderEncoder setRenderPipelineState:tState.pipelineState];

    // Add viewport size to vertex buffers
    NSDictionary<NSNumber *, id<MTLBuffer>> *vertexBuffers;
    vertexBuffers =
        [clientVertexBuffers dictionaryBySettingObject:[self vertexBufferForViewportSize:tState.configuration.viewportSize]
                                                forKey:@(iTermVertexInputIndexViewportSize)];

    [vertexBuffers enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, id<MTLBuffer>  _Nonnull obj, BOOL * _Nonnull stop) {
        [debugDrawInfo setVertexBuffer:obj atIndex:key.unsignedIntegerValue];
        [renderEncoder setVertexBuffer:obj
                                offset:0
                               atIndex:[key unsignedIntegerValue]];
    }];

    [fragmentBuffers enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, id<MTLBuffer>  _Nonnull obj, BOOL * _Nonnull stop) {
        [debugDrawInfo setFragmentBuffer:obj atIndex:key.unsignedIntegerValue];
        [renderEncoder setFragmentBuffer:obj
                                  offset:0
                                 atIndex:[key unsignedIntegerValue]];
    }];

    [textures enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, id<MTLTexture>  _Nonnull obj, BOOL * _Nonnull stop) {
        [debugDrawInfo setFragmentTexture:obj atIndex:key.unsignedIntegerValue];
        [renderEncoder setFragmentTexture:obj atIndex:[key unsignedIntegerValue]];
    }];


    [debugDrawInfo drawWithVertexCount:numberOfVertices instanceCount:numberOfPIUs];
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
