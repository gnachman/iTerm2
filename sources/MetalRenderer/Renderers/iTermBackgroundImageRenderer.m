#import "iTermBackgroundImageRenderer.h"

#import "ITAddressBookMgr.h"
#import "DebugLogging.h"
#import "FutureMethods.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermBackgroundDrawingHelper.h"
#import "iTermPreferences.h"
#import "iTermShaderTypes.h"
#import "iTermSharedImageStore.h"
#import "NSFileManager+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

// Issue 12604/12791: FNV-1a-32 over the 24 uint32 words of the 6-vertex array.
// Must match the GPU-side implementation in iTermBackgroundImage.metal.
static inline uint32_t iTermBgImageVertexHash(const iTermVertex *vertices) {
    uint32_t hash = 2166136261u;
    for (int i = 0; i < 6; i++) {
        // Vector element addresses aren't taken in C/ObjC; copy through stack floats.
        const float px = vertices[i].position.x;
        const float py = vertices[i].position.y;
        const float tx = vertices[i].textureCoordinate.x;
        const float ty = vertices[i].textureCoordinate.y;
        uint32_t words[4];
        memcpy(&words[0], &px, sizeof(uint32_t));
        memcpy(&words[1], &py, sizeof(uint32_t));
        memcpy(&words[2], &tx, sizeof(uint32_t));
        memcpy(&words[3], &ty, sizeof(uint32_t));
        for (int j = 0; j < 4; j++) {
            hash ^= words[j];
            hash *= 16777619u;
        }
    }
    // Reserve 0 as a "skip check" sentinel; clip a legitimate-but-zero hash to 1.
    return hash == 0u ? 1u : hash;
}

@interface iTermBackgroundImageRendererTransientState ()
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic) iTermBackgroundImageMode mode;
@property (nonatomic) BOOL repeat;
@property (nonatomic) NSSize imageSize;
@property (nonatomic) CGFloat imageScale;
@property (nonatomic) CGRect frame;
@property (nonatomic) CGRect containerFrame;
@property (nonatomic) vector_float4 defaultBackgroundColor;
@property (nullable, nonatomic, strong) id<MTLBuffer> box1;
@property (nullable, nonatomic, strong) id<MTLBuffer> box2;
// Issue 12604/12791: GPU checksum witness
@property (nullable, nonatomic, strong) id<MTLBuffer> checksumReportBuffer;
@property (nonatomic) uint32_t expectedChecksum;
@property (nonatomic) vector_uint2 capturedViewportSize;
- (void)setCapturedVertices:(const iTermVertex *)vertices;
- (const iTermVertex *)capturedVertices;
- (void)setOwner:(iTermBackgroundImageRenderer *)owner;
@end

@interface iTermBackgroundImageRenderer (TransientStateReports)
- (void)reportChecksumFailureForTransientState:(iTermBackgroundImageRendererTransientState *)tState
                                         report:(uint32_t)report;
@end

@implementation iTermBackgroundImageRendererTransientState {
    iTermVertex _capturedVertices[6];
    __weak iTermBackgroundImageRenderer *_owner;
}

- (BOOL)skipRenderer {
    return _texture == nil;
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];
    [[NSString stringWithFormat:@"mode=%@", @(_mode)] writeToURL:[folder URLByAppendingPathComponent:@"state.txt"]
                                                      atomically:NO
                                                        encoding:NSUTF8StringEncoding
                                                           error:NULL];
}

- (void)setCapturedVertices:(const iTermVertex *)vertices {
    memcpy(_capturedVertices, vertices, sizeof(_capturedVertices));
}

- (const iTermVertex *)capturedVertices {
    return _capturedVertices;
}

- (void)setOwner:(iTermBackgroundImageRenderer *)owner {
    _owner = owner;
}

- (void)didComplete {
    if (!_checksumReportBuffer) {
        return;
    }
    uint32_t report = 0;
    memcpy(&report, _checksumReportBuffer.contents, sizeof(report));
    if (report == 0) {
        return;
    }
    [_owner reportChecksumFailureForTransientState:self report:report];
}

@end

@implementation iTermBackgroundImageRenderer {
    iTermMetalRenderer *_metalRenderer;
#if ENABLE_TRANSPARENT_METAL_WINDOWS
    iTermMetalBufferPool *_alphaPool;
#endif
    iTermMetalBufferPool *_colorPool;
    iTermMetalBufferPool *_solidColorPool;
    iTermMetalBufferPool *_box1Pool;
    iTermMetalBufferPool *_box2Pool;
    iTermBackgroundImageMode _mode;
    iTermImageWrapper *_image;
    id<MTLTexture> _texture;
    CGRect _frame;
    CGRect _containerFrame;
    vector_float4 _color;

    // Issue 12604: Diagnostic tracking
    iTermMetalBufferPool *_validationFlagPool;
    iTermVertex _previousVertices[6];
    BOOL _hasPreviousVertices;
    vector_uint2 _previousViewportSize;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _metalRenderer = [[iTermMetalRenderer alloc] initWithDevice:device
                                                 vertexFunctionName:@"iTermBackgroundImageVertexShader"
                                               fragmentFunctionName:@"iTermBackgroundImageClampFragmentShader"
                                                           blending:nil
                                                transientStateClass:[iTermBackgroundImageRendererTransientState class]];
#if ENABLE_TRANSPARENT_METAL_WINDOWS
        if (iTermTextIsMonochrome()) {
            _alphaPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(float)];
        }
#endif
        _box1Pool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermVertex) * 6];
        _box2Pool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermVertex) * 6];
        _colorPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(vector_float4)];
        _solidColorPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(vector_float4)];
        // Issue 12604: Validation flag buffer for shader-side validation
        _validationFlagPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(uint32_t)];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateBackgroundImageTS;
}

- (void)setImage:(iTermImageWrapper *)image
            mode:(iTermBackgroundImageMode)mode
           frame:(CGRect)frame
   containerRect:(CGRect)containerRect
           color:(vector_float4)defaultBackgroundColor
      colorSpace:(NSColorSpace *)colorSpace
         context:(nullable iTermMetalBufferPoolContext *)context {
    DLog(@"setImage:%@ mode:%@ frame:%@ containerRect:%@", 
         image.image, @(mode), NSStringFromRect(frame), NSStringFromRect(containerRect));
    if (image != _image) {
        DLog(@"Will create texture from image");
        _texture = image ? [_metalRenderer textureFromImage:image context:context colorSpace:colorSpace] : nil;
    }
    _frame = frame;
    _color = defaultBackgroundColor;
    _containerFrame = containerRect;
    _image = image;
    _mode = mode;
}

#if ENABLE_TRANSPARENT_METAL_WINDOWS
- (id<MTLBuffer>)alphaBufferWithValue:(float)value
                          poolContext:(iTermMetalBufferPoolContext *)poolContext {
    return [_alphaPool requestBufferFromContext:poolContext
                                      withBytes:&value
                                 checkIfChanged:YES];
    
}
#endif

- (id<MTLBuffer>)colorBufferWithColor:(vector_float4)color
                                alpha:(CGFloat)alpha
                          poolContext:(iTermMetalBufferPoolContext *)poolContext {
    vector_float4 premultiplied = color * alpha;
    premultiplied.w = alpha;
    iTermMetalBufferPool *pool = (alpha == 1) ? _solidColorPool : _colorPool;
    return [pool requestBufferFromContext:poolContext
                                withBytes:&premultiplied
                           checkIfChanged:YES];
}

- (id<MTLBuffer>)boxBufferWithRect:(CGRect)rect
                               box:(int)number
                       poolContext:(iTermMetalBufferPoolContext *)poolContext {
    iTermMetalBufferPool *pool = number == 1 ? _box1Pool : _box2Pool;
    const iTermVertex vertices[] = {
        // Pixel Positions       Texture Coordinates
        { { CGRectGetMaxX(rect), CGRectGetMinY(rect) }, { 0, 0 } },
        { { CGRectGetMinX(rect), CGRectGetMinY(rect) }, { 0, 0 } },
        { { CGRectGetMinX(rect), CGRectGetMaxY(rect) }, { 0, 0 } },
        
        { { CGRectGetMaxX(rect), CGRectGetMinY(rect) }, { 0, 0 } },
        { { CGRectGetMinX(rect), CGRectGetMaxY(rect) }, { 0, 0 } },
        { { CGRectGetMaxX(rect), CGRectGetMaxY(rect) }, { 0, 0 } },
    };
    return [pool requestBufferFromContext:poolContext
                                withBytes:vertices
                           checkIfChanged:YES];
}

- (id<MTLBuffer>)colorBufferForState:(iTermBackgroundImageRendererTransientState *)tState
                               alpha:(float)alpha {
    id<MTLBuffer> colorBuffer = [self colorBufferWithColor:tState.defaultBackgroundColor
                                                     alpha:alpha
                                               poolContext:tState.poolContext];
    return colorBuffer;
}

#pragma mark - Issue 12604: Vertex Validation

- (void)dumpDiagnostics:(const iTermVertex *)v
                 tState:(iTermBackgroundImageRendererTransientState *)tState
           viewportSize:(vector_uint2)viewportSize
                 reason:(NSString *)reason {
    NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *filename = [NSString stringWithFormat:@"bgimage-diag-%f.txt", [NSDate timeIntervalSinceReferenceDate]];
    NSString *path = [appSupport stringByAppendingPathComponent:filename];

    NSMutableString *dump = [NSMutableString string];
    [dump appendFormat:@"Timestamp: %@\n", [NSDate date]];
    [dump appendFormat:@"Reason: %@\n", reason];
    [dump appendFormat:@"Viewport: %u x %u\n", viewportSize.x, viewportSize.y];
    [dump appendFormat:@"Frame: %@\n", NSStringFromRect(tState.frame)];
    [dump appendFormat:@"ContainerFrame: %@\n", NSStringFromRect(tState.containerFrame)];
    [dump appendFormat:@"Mode: %d\n", (int)tState.mode];
    [dump appendFormat:@"ImageSize: %@\n", NSStringFromSize(tState.imageSize)];
    [dump appendFormat:@"ImageScale: %f\n", tState.imageScale];

    [dump appendString:@"\nCurrent Vertices:\n"];
    for (int i = 0; i < 6; i++) {
        [dump appendFormat:@"  v[%d]: pos=(%.2f, %.2f) tex=(%.6f, %.6f)\n",
         i, v[i].position.x, v[i].position.y,
         v[i].textureCoordinate.x, v[i].textureCoordinate.y];
    }

    if (_hasPreviousVertices) {
        [dump appendString:@"\nPrevious Vertices:\n"];
        for (int i = 0; i < 6; i++) {
            [dump appendFormat:@"  v[%d]: pos=(%.2f, %.2f) tex=(%.6f, %.6f)\n",
             i, _previousVertices[i].position.x, _previousVertices[i].position.y,
             _previousVertices[i].textureCoordinate.x, _previousVertices[i].textureCoordinate.y];
        }
        [dump appendFormat:@"\nPrevious Viewport: %u x %u\n", _previousViewportSize.x, _previousViewportSize.y];
    }

    NSError *error = nil;
    [dump writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        ELog(@"Failed to write diagnostic file: %@", error);
    }

    ITCriticalError(NO, @"Background image vertex validation failed: %@. Diagnostic written to %@", reason, path);
}

- (void)reportChecksumFailureForTransientState:(iTermBackgroundImageRendererTransientState *)tState
                                         report:(uint32_t)report {
    NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *filename = [NSString stringWithFormat:@"bgimage-diag-checksum-%f.txt",
                          [NSDate timeIntervalSinceReferenceDate]];
    NSString *path = [appSupport stringByAppendingPathComponent:filename];

    const iTermVertex *captured = tState.capturedVertices;
    const iTermVertex *currentBytes = (const iTermVertex *)tState.vertexBuffer.contents;

    NSMutableString *dump = [NSMutableString string];
    [dump appendFormat:@"Timestamp: %@\n", [NSDate date]];
    [dump appendFormat:@"Reason: GPU checksum mismatch (report bits=0x%x)\n", report];
    [dump appendFormat:@"Expected checksum (CPU, FNV-1a-32): 0x%08x\n", tState.expectedChecksum];
    [dump appendFormat:@"Re-hashed buffer contents now: 0x%08x\n",
        iTermBgImageVertexHash(currentBytes)];
    [dump appendFormat:@"Viewport: %u x %u\n",
        tState.capturedViewportSize.x, tState.capturedViewportSize.y];
    [dump appendFormat:@"Frame: %@\n", NSStringFromRect(tState.frame)];
    [dump appendFormat:@"ContainerFrame: %@\n", NSStringFromRect(tState.containerFrame)];
    [dump appendFormat:@"Mode: %d\n", (int)tState.mode];
    [dump appendFormat:@"ImageSize: %@\n", NSStringFromSize(tState.imageSize)];
    [dump appendFormat:@"ImageScale: %f\n", tState.imageScale];
    [dump appendFormat:@"VertexBuffer label: %@\n", tState.vertexBuffer.label];
    [dump appendFormat:@"VertexBuffer length: %lu\n", (unsigned long)tState.vertexBuffer.length];

    [dump appendString:@"\nCaptured Vertices (what the CPU wrote and hashed):\n"];
    for (int i = 0; i < 6; i++) {
        [dump appendFormat:@"  v[%d]: pos=(%.4f, %.4f) tex=(%.6f, %.6f)\n",
            i, captured[i].position.x, captured[i].position.y,
            captured[i].textureCoordinate.x, captured[i].textureCoordinate.y];
    }
    [dump appendString:@"\nBuffer Vertices Now (after GPU finished):\n"];
    for (int i = 0; i < 6; i++) {
        [dump appendFormat:@"  v[%d]: pos=(%.4f, %.4f) tex=(%.6f, %.6f)\n",
            i, currentBytes[i].position.x, currentBytes[i].position.y,
            currentBytes[i].textureCoordinate.x, currentBytes[i].textureCoordinate.y];
    }
    [dump appendString:@"\nByte diffs (captured vs now):\n"];
    const uint8_t *a = (const uint8_t *)captured;
    const uint8_t *b = (const uint8_t *)currentBytes;
    int diffCount = 0;
    for (size_t off = 0; off < sizeof(iTermVertex) * 6; off++) {
        if (a[off] != b[off]) {
            [dump appendFormat:@"  byte %zu: captured=0x%02x now=0x%02x\n", off, a[off], b[off]];
            diffCount++;
            if (diffCount > 32) {
                [dump appendString:@"  ... (truncated)\n"];
                break;
            }
        }
    }
    if (diffCount == 0) {
        [dump appendString:@"  (none - buffer bytes match CPU capture; corruption was transient)\n"];
    }

    NSError *error = nil;
    [dump writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        ELog(@"Failed to write checksum diagnostic: %@", error);
    }
    ITCriticalError(NO,
                    @"Background image GPU vertex checksum failed. Diagnostic written to %@",
                    path);
}

- (BOOL)validateVertexBuffer:(id<MTLBuffer>)buffer
                viewportSize:(vector_uint2)viewportSize
                      tState:(iTermBackgroundImageRendererTransientState *)tState {
    const iTermVertex *v = (const iTermVertex *)buffer.contents;

    // Check 1: Shared vertices must match (v[0]==v[3], v[2]==v[4])
    const float epsilon = 0.01;
    BOOL sharedVerticesMatch =
        (fabs(v[0].position.x - v[3].position.x) < epsilon &&
         fabs(v[0].position.y - v[3].position.y) < epsilon &&
         fabs(v[2].position.x - v[4].position.x) < epsilon &&
         fabs(v[2].position.y - v[4].position.y) < epsilon);

    // Check 2: No NaN values
    BOOL noNaN = YES;
    for (int i = 0; i < 6; i++) {
        if (isnan(v[i].position.x) || isnan(v[i].position.y) ||
            isnan(v[i].textureCoordinate.x) || isnan(v[i].textureCoordinate.y)) {
            noNaN = NO;
            break;
        }
    }

    // Check 3: Triangle areas non-zero (using cross product)
    // Triangle 1: v[0], v[1], v[2]
    float area1 = (v[1].position.x - v[0].position.x) * (v[2].position.y - v[0].position.y) -
                  (v[2].position.x - v[0].position.x) * (v[1].position.y - v[0].position.y);
    // Triangle 2: v[3], v[4], v[5]
    float area2 = (v[4].position.x - v[3].position.x) * (v[5].position.y - v[3].position.y) -
                  (v[5].position.x - v[3].position.x) * (v[4].position.y - v[3].position.y);
    BOOL nonDegenerateTriangles = (fabs(area1) > 1.0 && fabs(area2) > 1.0);

    // Check 4: Positions within reasonable bounds
    float maxBound = MAX(viewportSize.x, viewportSize.y) * 3;
    BOOL withinBounds = YES;
    for (int i = 0; i < 6; i++) {
        if (fabs(v[i].position.x) > maxBound || fabs(v[i].position.y) > maxBound) {
            withinBounds = NO;
            break;
        }
    }

    // Check 5: Frame-to-frame comparison for unexpected large changes
    BOOL frameToFrameOK = YES;
    if (_hasPreviousVertices && viewportSize.x == _previousViewportSize.x && viewportSize.y == _previousViewportSize.y) {
        // Same viewport size - vertices should be similar
        float maxDelta = MAX(viewportSize.x, viewportSize.y) * 0.5;
        for (int i = 0; i < 6; i++) {
            float dx = fabs(v[i].position.x - _previousVertices[i].position.x);
            float dy = fabs(v[i].position.y - _previousVertices[i].position.y);
            if (dx > maxDelta || dy > maxDelta) {
                frameToFrameOK = NO;
                DLog(@"Issue 12604: Large frame-to-frame vertex change detected at v[%d]: delta=(%.2f, %.2f)", i, dx, dy);
                break;
            }
        }
    }

    BOOL valid = sharedVerticesMatch && noNaN && nonDegenerateTriangles && withinBounds;

    if (!valid || !frameToFrameOK) {
        NSString *reason = [NSString stringWithFormat:@"sharedMatch=%d noNaN=%d nonDegenerate=%d bounds=%d frameOK=%d area1=%.2f area2=%.2f",
                            sharedVerticesMatch, noNaN, nonDegenerateTriangles, withinBounds, frameToFrameOK, area1, area2];
        [self dumpDiagnostics:v tState:tState viewportSize:viewportSize reason:reason];
    }

    return valid;
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalRendererTransientState *)transientState {
    iTermBackgroundImageRendererTransientState *tState = transientState;
    [self loadVertexBuffer:tState];

    // Issue 12604: Validate vertex buffer and create validation flag for shader
    vector_uint2 viewportSize = (vector_uint2){
        (uint32_t)tState.configuration.viewportSize.x,
        (uint32_t)tState.configuration.viewportSize.y
    };
    BOOL valid = [self validateVertexBuffer:tState.vertexBuffer
                               viewportSize:viewportSize
                                     tState:tState];
    uint32_t validationFlag = valid ? 0 : 1;
    id<MTLBuffer> validationBuffer = [_validationFlagPool requestBufferFromContext:tState.poolContext
                                                                          withBytes:&validationFlag
                                                                     checkIfChanged:NO];

    // Store current vertices for next frame comparison
    memcpy(_previousVertices, tState.vertexBuffer.contents, sizeof(iTermVertex) * 6);
    _hasPreviousVertices = YES;
    _previousViewportSize = viewportSize;

    // Issue 12604/12791: Compute an independent checksum witness for the vertex buffer.
    // The expected checksum rides through setVertexBytes (inline command-buffer payload,
    // no MTLBuffer involved) so a stomp on pool memory can't corrupt both witnesses
    // in lockstep. A fresh shared-storage MTLBuffer is the GPU's path to report a
    // mismatch back; allocated per-frame and read in didComplete.
    iTermVertex capturedVertices[6];
    memcpy(capturedVertices, tState.vertexBuffer.contents, sizeof(capturedVertices));
    const uint32_t expectedChecksum = iTermBgImageVertexHash(capturedVertices);
    tState.expectedChecksum = expectedChecksum;
    tState.capturedViewportSize = viewportSize;
    [tState setCapturedVertices:capturedVertices];
    [tState setOwner:self];

    const uint32_t zero = 0;
    id<MTLBuffer> checksumReportBuffer = [_metalRenderer.device newBufferWithBytes:&zero
                                                                            length:sizeof(zero)
                                                                           options:MTLResourceStorageModeShared];
    checksumReportBuffer.label = @"BG image checksum report";
    tState.checksumReportBuffer = checksumReportBuffer;

    NSDictionary *fragmentBuffers = nil;
#if ENABLE_TRANSPARENT_METAL_WINDOWS
    float alpha = tState.computedAlpha;

    // Alpha=1 here because an overall alpha is applied to the combination of underlayment and image.
    id<MTLBuffer> underlayColorBuffer = [self colorBufferForState:tState alpha:1];
    if (alpha < 1) {
        _metalRenderer.fragmentFunctionName = tState.repeat ? @"iTermBackgroundImageWithAlphaRepeatFragmentShader" : @"iTermBackgroundImageWithAlphaClampFragmentShader";
        id<MTLBuffer> alphaBuffer = [self alphaBufferWithValue:alpha poolContext:tState.poolContext];
        fragmentBuffers = @{ @(iTermFragmentInputIndexAlpha): alphaBuffer,
                             @(iTermFragmentInputIndexColor): underlayColorBuffer,
                             @(iTermFragmentBufferIndexBgImageChecksumReport): checksumReportBuffer,
        };
    } else {
        _metalRenderer.fragmentFunctionName = tState.repeat ? @"iTermBackgroundImageRepeatFragmentShader" : @"iTermBackgroundImageClampFragmentShader";
        fragmentBuffers = @{ @(iTermFragmentInputIndexColor): underlayColorBuffer,
                             @(iTermFragmentBufferIndexBgImageChecksumReport): checksumReportBuffer,
        };
    }
#else
    float alpha = 1;
    id<MTLBuffer> colorBuffer = [self colorBufferForState:tState alpha:alpha];
    _metalRenderer.fragmentFunctionName = tState.repeat ? @"iTermBackgroundImageRepeatFragmentShader" : @"iTermBackgroundImageClampFragmentShader";
    fragmentBuffers = @{ @(iTermFragmentBufferIndexBgImageChecksumReport): checksumReportBuffer };
#endif

    tState.pipelineState = _metalRenderer.pipelineState;

    // Issue 12604: Explicitly disable backface culling to guard against state leakage
    [frameData.renderEncoder setCullMode:MTLCullModeNone];

    // Issue 12604: Add memory barrier to ensure vertex buffer data is visible to GPU
    [frameData.renderEncoder memoryBarrierWithScope:MTLBarrierScopeBuffers
                                        afterStages:MTLRenderStageVertex
                                       beforeStages:MTLRenderStageVertex];

    // Issue 12604: Draw as two separate triangles instead of one 6-vertex draw.
    // This works around a suspected GPU driver bug where one triangle sometimes fails to render.
    NSDictionary *vertexBuffers = @{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                     @(iTermVertexInputIndexValidationFlag): validationBuffer };
    NSDictionary *textures = @{ @(iTermTextureIndexPrimary): tState.texture };

    // Issue 12604/12791: Bind the expected checksum via setVertexBytes so it travels
    // inline with the command buffer rather than as an MTLBuffer reference.
    [frameData.renderEncoder setVertexBytes:&expectedChecksum
                                     length:sizeof(expectedChecksum)
                                    atIndex:iTermVertexInputIndexBgImageChecksum];

    // Draw triangle 1 (vertices 0-2)
    [_metalRenderer drawWithTransientState:tState
                             renderEncoder:frameData.renderEncoder
                               vertexStart:0
                          numberOfVertices:3
                              numberOfPIUs:0
                             vertexBuffers:vertexBuffers
                           fragmentBuffers:fragmentBuffers
                                  textures:textures];

    // setVertexBytes binding persists, but rebind defensively for the second triangle
    // in case any other state-management code clears it.
    [frameData.renderEncoder setVertexBytes:&expectedChecksum
                                     length:sizeof(expectedChecksum)
                                    atIndex:iTermVertexInputIndexBgImageChecksum];

    // Draw triangle 2 (vertices 3-5)
    [_metalRenderer drawWithTransientState:tState
                             renderEncoder:frameData.renderEncoder
                               vertexStart:3
                          numberOfVertices:3
                              numberOfPIUs:0
                             vertexBuffers:vertexBuffers
                           fragmentBuffers:fragmentBuffers
                                  textures:textures];

    if (tState.box1) {
        assert(tState.box2);
        _metalRenderer.fragmentFunctionName = @"iTermBackgroundImageLetterboxFragmentShader";
        id<MTLBuffer> letterboxColorBuffer = [self colorBufferForState:tState alpha:alpha];
        tState.pipelineState = _metalRenderer.pipelineState;
        // Issue 12604/12791: Skip checksum check for letterbox boxes (sentinel=0).
        // Report buffer is reused so any GPU-side mismatch from those draws would
        // also surface, but with expected=0 the shader skips comparison.
        const uint32_t skipChecksum = 0;
        [frameData.renderEncoder setVertexBytes:&skipChecksum
                                         length:sizeof(skipChecksum)
                                        atIndex:iTermVertexInputIndexBgImageChecksum];
        [_metalRenderer drawWithTransientState:tState
                                 renderEncoder:frameData.renderEncoder
                              numberOfVertices:6
                                  numberOfPIUs:0
                                 vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.box1,
                                                  @(iTermVertexInputIndexValidationFlag): validationBuffer }
                               fragmentBuffers:@{ @(iTermFragmentInputIndexColor): letterboxColorBuffer,
                                                  @(iTermFragmentBufferIndexBgImageChecksumReport): checksumReportBuffer }
                                      textures:@{}];
        [frameData.renderEncoder setVertexBytes:&skipChecksum
                                         length:sizeof(skipChecksum)
                                        atIndex:iTermVertexInputIndexBgImageChecksum];
        [_metalRenderer drawWithTransientState:tState
                                 renderEncoder:frameData.renderEncoder
                              numberOfVertices:6
                                  numberOfPIUs:0
                                 vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.box2,
                                                  @(iTermVertexInputIndexValidationFlag): validationBuffer }
                               fragmentBuffers:@{ @(iTermFragmentInputIndexColor): letterboxColorBuffer,
                                                  @(iTermFragmentBufferIndexBgImageChecksumReport): checksumReportBuffer }
                                      textures:@{}];
    }
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForConfiguration:(iTermRenderConfiguration *)configuration
                                                                               commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    if (_image == nil) {
        return nil;
    }
    iTermBackgroundImageRendererTransientState * _Nonnull tState =
        [_metalRenderer createTransientStateForConfiguration:configuration
                                               commandBuffer:commandBuffer];

    [self initializeTransientState:tState];

    return tState;
}

- (void)initializeTransientState:(iTermBackgroundImageRendererTransientState *)tState {
    tState.texture = _texture;
    tState.mode = _mode;
    tState.imageSize = _image.image.size;
    tState.imageScale = [_image.image recommendedLayerContentsScale:tState.configuration.scale];
    tState.repeat = (_mode == iTermBackgroundImageModeTile);
    tState.frame = _frame;
    tState.defaultBackgroundColor = _color;
    tState.containerFrame = _containerFrame;
}

- (void)loadVertexBuffer:(iTermBackgroundImageRendererTransientState *)tState {
    const CGFloat scale = tState.configuration.scale;
    DLog(@"image size=%@ image scale=%@", NSStringFromSize(tState.imageSize), @(tState.imageScale));
    const CGSize nativeTextureSize = NSMakeSize(tState.texture.width,
                                                tState.texture.height);
    DLog(@"nativeTextureSize=%@", NSStringFromSize(nativeTextureSize));
    const CGSize viewportSize = CGSizeMake(tState.configuration.viewportSize.x,
                                           tState.configuration.viewportSize.y);
    DLog(@"viewport size=%@", NSStringFromSize(viewportSize));
    NSEdgeInsets insets;
    CGFloat vmargin;
    vmargin = 0;
    insets = NSEdgeInsetsZero;
    const CGFloat topMargin = insets.bottom + vmargin;
    const CGFloat bottomMargin = insets.top + vmargin;
    const CGFloat leftMargin = insets.left;
    const CGFloat rightMargin = insets.right;

    const CGFloat imageAspectRatio = nativeTextureSize.width / nativeTextureSize.height;
    DLog(@"image aspect ratio=%@", @(imageAspectRatio));

    // pixel coordinates
    const CGFloat viewHeight = viewportSize.height + topMargin + bottomMargin;
    const CGFloat viewWidth = viewportSize.width + leftMargin + rightMargin;
    const CGFloat minX = -leftMargin;
    const CGFloat minY = -topMargin;
    CGRect quadFrame = CGRectMake(minX,
                                  minY,
                                  viewWidth,
                                  viewHeight);
    
    // pixel coordinates
    CGRect textureFrame;
    const CGRect frame = tState.frame;
    DLog(@"tState.frame=%@", NSStringFromRect(frame));
    const CGRect containerRect = CGRectMake(tState.containerFrame.origin.x * scale,
                                            tState.containerFrame.origin.y * scale,
                                            tState.containerFrame.size.width * scale,
                                            tState.containerFrame.size.height * scale);
    const CGFloat containerHeight = viewHeight / frame.size.height;
    const CGFloat containerWidth = viewWidth / frame.size.width;
    const CGFloat containerAspectRatio = containerWidth / containerHeight;
    DLog(@"Container rect=%@, container aspect ratio=%@, mode=%@",
         NSStringFromRect(containerRect), @(containerAspectRatio), @(_mode));
    switch (_mode) {
        case iTermBackgroundImageModeStretch:
            textureFrame = CGRectMake(frame.origin.x * nativeTextureSize.width,
                                      frame.origin.y * nativeTextureSize.height,
                                      frame.size.width * nativeTextureSize.width,
                                      frame.size.height * nativeTextureSize.height);
            break;
            
        case iTermBackgroundImageModeTile:
            textureFrame = CGRectMake(frame.origin.x * containerRect.size.width,
                                      frame.origin.y * containerRect.size.height,
                                      viewportSize.width,
                                      viewportSize.height);
            break;
            
        case iTermBackgroundImageModeScaleAspectFit: {
            CGRect drawRect;
            const CGRect myFrameInContainer = CGRectMake(containerRect.origin.x + frame.origin.x * containerRect.size.width,
                                                         containerRect.origin.y + frame.origin.y * containerRect.size.height,
                                                         frame.size.width * containerRect.size.width,
                                                         frame.size.height * containerRect.size.height);
            NSRect box1 = NSZeroRect;
            NSRect box2 = NSZeroRect;
            textureFrame =
            [iTermBackgroundDrawingHelper scaleAspectFitSourceRectForForImageSize:nativeTextureSize
                                                                  destinationRect:containerRect
                                                                        dirtyRect:myFrameInContainer
                                                                         drawRect:&drawRect
                                                                         boxRect1:&box1
                                                                         boxRect2:&box2];

            // Convert frames into my coordinate system
            NSRect (^convertRect)(NSRect) = ^NSRect(NSRect drawRect) {
                return NSMakeRect(drawRect.origin.x - frame.origin.x * containerRect.size.width - containerRect.origin.x,
                                  drawRect.origin.y - frame.origin.y * containerRect.size.height - containerRect.origin.y,
                                  drawRect.size.width,
                                  drawRect.size.height);
            };
            quadFrame = convertRect(drawRect);
            tState.box1 = [self boxBufferWithRect:convertRect(box1) box:1 poolContext:tState.poolContext];
            tState.box2 = [self boxBufferWithRect:convertRect(box2) box:2 poolContext:tState.poolContext];
            break;
        }
            
        case iTermBackgroundImageModeScaleAspectFill: {
            CGRect globalTextureFrame;
            DLog(@"Image aspect ratio=%@, container aspect ratio=%@",
                 @(imageAspectRatio), @(containerAspectRatio));
            if (imageAspectRatio > containerAspectRatio) {
                DLog(@"Image is wide relative to view.");
                DLog(@"Crop left and right.");
                const CGFloat width = nativeTextureSize.height * containerAspectRatio;
                const CGFloat crop = (nativeTextureSize.width - width) / 2.0;
                globalTextureFrame = CGRectMake(crop, 0, width, nativeTextureSize.height);
            } else {
                DLog(@"Image is tall relative to view.");
                DLog(@"Crop top and bottom.");
                const CGFloat height = nativeTextureSize.width / containerAspectRatio;
                const CGFloat crop = (nativeTextureSize.height - height) / 2.0;
                globalTextureFrame = CGRectMake(0, crop, nativeTextureSize.width, height);
            }
            DLog(@"globalTextureFrame=%@", NSStringFromRect(globalTextureFrame));
            DLog(@"frame=%@", NSStringFromRect(frame));
            textureFrame = CGRectMake(frame.origin.x * globalTextureFrame.size.width + globalTextureFrame.origin.x,
                                      frame.origin.y * globalTextureFrame.size.height + globalTextureFrame.origin.y,
                                      frame.size.width * globalTextureFrame.size.width,
                                      frame.size.height * globalTextureFrame.size.height);
            DLog(@"textureFrame=%@", NSStringFromRect(textureFrame));
            break;
        }
    }

    // Convert textureFrame to normalized coordinates
    textureFrame.origin.x /= nativeTextureSize.width;
    textureFrame.size.width /= nativeTextureSize.width;
    textureFrame.origin.y /= nativeTextureSize.height;
    textureFrame.size.height /= nativeTextureSize.height;
    tState.vertexBuffer = [_metalRenderer newQuadWithFrame:quadFrame
                                              textureFrame:textureFrame
                                               poolContext:tState.poolContext];
}

@end

NS_ASSUME_NONNULL_END
