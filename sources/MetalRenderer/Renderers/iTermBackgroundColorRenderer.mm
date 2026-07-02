#import "iTermBackgroundColorRenderer.h"

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "NSFileManager+iTerm.h"
#import "iTermPIUArray.h"
#import "iTermTextRenderer.h"

#import <math.h>

// Issue 12791: Bit ORed into the shared report buffer when the GPU-side geometry witness
// fails. Kept in sync with iTermBgColorReportWitnessFailed in iTermBackgroundColor.metal.
enum {
    iTermBgColorReportWitnessFailed = 0x1,
};

// Issue 12791: FNV-1a-32 over the vertex array, hashed float-by-float to avoid struct
// padding. Witnesses the geometry buffer (iTermVertexInputIndexVertices) - the only
// per-vertex-varying input, and therefore the only thing that can make one triangle of
// the merged default-background quad render differently from the other. Must match the
// GPU-side implementation in iTermBackgroundColor.metal.
static inline uint32_t iTermBgColorGeometryHash(const iTermVertex *vertices, uint32_t count) {
    uint32_t hash = 2166136261u;
    for (uint32_t i = 0; i < count; i++) {
        float words[4] = {
            vertices[i].position.x,
            vertices[i].position.y,
            vertices[i].textureCoordinate.x,
            vertices[i].textureCoordinate.y
        };
        for (int j = 0; j < 4; j++) {
            uint32_t bits;
            memcpy(&bits, &words[j], sizeof(bits));
            hash ^= bits;
            hash *= 16777619u;
        }
    }
    // Reserve 0 as a "skip check" sentinel; clip a legitimate-but-zero hash to 1.
    return hash == 0u ? 1u : hash;
}

// Issue 12791: CPU-side geometry sanity check. Catches a buffer that is already bad at
// submit time (persistent corruption), including the failure the GPU checksum cannot
// distinguish on its own: a stable zero-area triangle (two coincident vertices) that
// hashes consistently but rasterizes to nothing. Returns a human-readable reason or nil.
static NSString *iTermBgColorGeometryDegenerateReason(const iTermVertex *v, uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        const float comps[4] = { v[i].position.x, v[i].position.y,
                                 v[i].textureCoordinate.x, v[i].textureCoordinate.y };
        for (int j = 0; j < 4; j++) {
            if (!isfinite(comps[j])) {
                return [NSString stringWithFormat:@"vertex %u component %d is non-finite (%g)",
                        i, j, comps[j]];
            }
        }
    }
    // Each 6-vertex quad is two triangles: v[0..2] and v[3..5]. Flag a near-zero-area
    // triangle, which would leave a triangular wedge of bare image with no overlay.
    for (uint32_t t = 0; t + 2 < count; t += 3) {
        const vector_float2 a = v[t].position;
        const vector_float2 b = v[t + 1].position;
        const vector_float2 c = v[t + 2].position;
        const float area2 = fabsf((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y));
        if (area2 < 0.01f) {
            return [NSString stringWithFormat:@"triangle %u has near-zero area (2*area=%g)",
                    t / 3, area2];
        }
    }
    return nil;
}

@interface iTermBackgroundColorRendererTransientState()
// Issue 12791: GPU geometry checksum witness.
@property (nullable, nonatomic, strong) id<MTLBuffer> checksumReportBuffer;
@property (nonatomic) uint32_t expectedGeometryChecksum;
@property (nonatomic) vector_uint2 capturedViewportSize;
@property (nonatomic) iTermBackgroundColorRendererMode capturedMode;
@property (nullable, nonatomic, copy) NSString *cpuDegenerateReason;
- (void)setOwner:(iTermBackgroundColorRenderer *)owner;
@end

@interface iTermBackgroundColorRenderer (TransientStateReports)
- (void)reportFailureForTransientState:(iTermBackgroundColorRendererTransientState *)tState
                                report:(uint32_t)report;
@end

@implementation iTermBackgroundColorRendererTransientState {
    iTerm2::PIUArray<iTermBackgroundColorPIU> _pius;
    __weak iTermBackgroundColorRenderer *_owner;
}

- (void)setOwner:(iTermBackgroundColorRenderer *)owner {
    _owner = owner;
}

// Issue 12791: Read back the GPU-written checksum report after the command buffer
// completes. Called from -[iTermMetalDriver complete:]. Also fires when the CPU-side
// check already found the buffer degenerate at submit (which the GPU checksum, reading
// the same stable bytes, would not flag).
- (void)didComplete {
    if (!_checksumReportBuffer) {
        return;
    }
    uint32_t report = 0;
    memcpy(&report, _checksumReportBuffer.contents, sizeof(report));
    if (report == 0 && _cpuDegenerateReason == nil) {
        return;
    }
    [_owner reportFailureForTransientState:self report:report];
}

- (NSUInteger)sizeOfNewPIUBuffer {
    return sizeof(iTermBackgroundColorPIU) * self.cellConfiguration.gridSize.width * self.cellConfiguration.gridSize.height;
}

- (void)setColorRLEs:(const iTermMetalBackgroundColorRLE *)rles
               count:(size_t)count
                 row:(int)row
       repeatingRows:(int)repeatingRows
           omitClear:(BOOL)omitClear {
    vector_float2 cellSize = simd_make_float2(self.cellConfiguration.cellSize.width, self.cellConfiguration.cellSize.height);
    const int height = self.cellConfiguration.gridSize.height;
    for (int i = 0; i < count; i++) {
        if (omitClear && rles[i].color.w == 0) {
            continue;
        }
        iTermBackgroundColorPIU &piu = *_pius.get_next();
        piu.color = rles[i].color;
        piu.runLength = rles[i].count;
        piu.numRows = repeatingRows;
        piu.offset = simd_make_float2(cellSize.x * (float)rles[i].origin,
                                      _verticalOffset + cellSize.y * (height - row - repeatingRows));
        piu.isDefault = rles[i].isDefault;
    }
}

- (void)enumerateSegments:(void (^NS_NOESCAPE)(const iTermBackgroundColorPIU *, size_t))block {
    const int n = _pius.get_number_of_segments();
    for (int segment = 0; segment < n; segment++) {
        if (_pius.size_of_segment(segment) == 0) {
            continue;
        }
        const iTermBackgroundColorPIU *array = _pius.start_of_segment(segment);
        size_t size = _pius.size_of_segment(segment);
        block(array, size);
    }
}

@end

@interface iTermBackgroundColorRenderer() <iTermMetalDebugInfoFormatter>
@end

@implementation iTermBackgroundColorRenderer {
    iTermMetalCellRenderer *_blendingRenderer;
    iTermMetalCellRenderer *_nonblendingRenderer NS_AVAILABLE_MAC(10_14);
    iTermMetalBufferPool *_infoPool;
    iTermMetalBufferPool *_suppressedRegionVertexBufferPool;

#if ENABLE_TRANSPARENT_METAL_WINDOWS
    iTermMetalCellRenderer *_compositeOverRenderer NS_AVAILABLE_MAC(10_14);
#endif
    iTermMetalMixedSizeBufferPool *_piuPool;
    id<MTLDevice> _device;  // Issue 12791: for per-frame checksum report buffers
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _device = device;
        _suppressedRegionVertexBufferPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermVertex) * 6];
#if ENABLE_TRANSPARENT_METAL_WINDOWS
        if (iTermTextIsMonochrome()) {
            _nonblendingRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                        vertexFunctionName:@"iTermBackgroundColorVertexShader"
                                                      fragmentFunctionName:@"iTermBackgroundColorFragmentShader"
                                                                  blending:nil
                                                            piuElementSize:sizeof(iTermBackgroundColorPIU)
                                                       transientStateClass:[iTermBackgroundColorRendererTransientState class]];
            _nonblendingRenderer.formatterDelegate = self;

            _compositeOverRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                        vertexFunctionName:@"iTermBackgroundColorVertexShader"
                                                      fragmentFunctionName:@"iTermBackgroundColorFragmentShader"
                                                                  blending:[iTermMetalBlending premultipliedCompositing]
                                                            piuElementSize:sizeof(iTermBackgroundColorPIU)
                                                       transientStateClass:[iTermBackgroundColorRendererTransientState class]];
            _compositeOverRenderer.formatterDelegate = self;
        }
#endif
        _blendingRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                        vertexFunctionName:@"iTermBackgroundColorVertexShader"
                                                      fragmentFunctionName:@"iTermBackgroundColorFragmentShader"
                                                                  blending:[[iTermMetalBlending alloc] init]
                                                            piuElementSize:sizeof(iTermBackgroundColorPIU)
                                                       transientStateClass:[iTermBackgroundColorRendererTransientState class]];
        _blendingRenderer.formatterDelegate = self;
        // TODO: The capacity here is a total guess. But this would be a lot of rows to have.
        _piuPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                capacity:512
                                                                    name:@"background color PIU"];
        _infoPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermMetalBackgroundColorInfo)];
    }
    return self;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateBackgroundColorTS;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalCellRenderer *)rendererForConfiguration:(iTermCellRenderConfiguration *)configuration {
#if ENABLE_TRANSPARENT_METAL_WINDOWS
    if (iTermTextIsMonochrome()) {
        if (configuration.hasBackgroundImage) {
            return _compositeOverRenderer;
        } else {
            return _nonblendingRenderer;
        }
    }
#endif
    return _blendingRenderer;
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                                                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    iTermMetalCellRenderer *renderer = [self rendererForConfiguration:configuration];
    __kindof iTermMetalCellRendererTransientState * _Nonnull transientState =
        [renderer createTransientStateForCellConfiguration:configuration
                                              commandBuffer:commandBuffer];
    [self initializeTransientState:transientState];
    return transientState;
}

- (void)initializeTransientState:(iTermBackgroundColorRendererTransientState *)tState {
    tState.vertexBuffer = [[self rendererForConfiguration:tState.cellConfiguration] newQuadOfSize:tState.cellConfiguration.cellSize
                                                                                      poolContext:tState.poolContext];
    tState.vertexBuffer.label = @"Vertices";
}

- (id<MTLBuffer>)infoBufferForTransientState:(iTermBackgroundColorRendererTransientState *)tState {
    iTermMetalBackgroundColorInfo info;
    memset(&info, 0, sizeof(info));
    info.defaultBackgroundColor = tState.defaultBackgroundColor;
    info.mode = self.mode;
    id<MTLBuffer> buffer = [self->_infoPool requestBufferFromContext:tState.poolContext
                                                           withBytes:&info
                                                      checkIfChanged:YES];
    buffer.label = @"BG color info";
    return buffer;
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalRendererTransientState *)transientState {
    iTermBackgroundColorRendererTransientState *tState = transientState;
    id<MTLBuffer> infoBuffer = [self infoBufferForTransientState:tState];

    // Issue 12791: Set up the geometry checksum witness. All non-suppressed draws share
    // tState.vertexBuffer (a pooled unit quad), so hash it once. A shared-storage buffer
    // carries any mismatch back to the CPU; it's read in didComplete. We also run a
    // CPU-side sanity check on the exact bytes the GPU will read. The bg-color renderer
    // can be invoked more than once per frame (default-only then nondefault-only) on the
    // same transient state, so set this up lazily.
    if (!tState.checksumReportBuffer) {
        const uint32_t zero = 0;
        id<MTLBuffer> checksumReportBuffer = [_device newBufferWithBytes:&zero
                                                                 length:sizeof(zero)
                                                                options:MTLResourceStorageModeShared];
        checksumReportBuffer.label = @"BG color checksum report";
        tState.checksumReportBuffer = checksumReportBuffer;
        tState.capturedViewportSize = (vector_uint2){
            (uint32_t)tState.configuration.viewportSize.x,
            (uint32_t)tState.configuration.viewportSize.y
        };
        tState.capturedMode = self.mode;
        [tState setOwner:self];

        const iTermVertex *geometry = (const iTermVertex *)tState.vertexBuffer.contents;
        const uint32_t vertexCount = (uint32_t)(tState.vertexBuffer.length / sizeof(iTermVertex));
        tState.expectedGeometryChecksum = iTermBgColorGeometryHash(geometry, vertexCount);
        tState.cpuDegenerateReason = iTermBgColorGeometryDegenerateReason(geometry, vertexCount);
    }
    id<MTLBuffer> checksumReportBuffer = tState.checksumReportBuffer;
    const iTermBgColorChecksumParams params = {
        tState.expectedGeometryChecksum,
        (uint32_t)(tState.vertexBuffer.length / sizeof(iTermVertex))
    };

    const NSUInteger suppressedBottomPx = static_cast<NSUInteger>(tState.suppressedBottomHeight * tState.cellConfiguration.scale - tState.margins.top);
    [tState enumerateSegments:^(const iTermBackgroundColorPIU *pius, size_t numberOfInstances) {
        if (numberOfInstances == 0) {
            return;
        }
        id<MTLBuffer> piuBuffer = [self->_piuPool requestBufferFromContext:tState.poolContext
                                                                      size:numberOfInstances * sizeof(*pius)
                                                                     bytes:pius];
        piuBuffer.label = @"PIUs";
        iTermMetalCellRenderer *cellRenderer = [self rendererForConfiguration:tState.cellConfiguration];

        // Issue 12791: The expected geometry hash rides inline via setVertexBytes so it
        // bypasses the pooled vertex memory and can't be corrupted in lockstep with it.
        [frameData.renderEncoder setVertexBytes:&params
                                         length:sizeof(params)
                                        atIndex:iTermVertexInputIndexBgColorChecksum];

        [cellRenderer drawWithTransientState:tState
                               renderEncoder:frameData.renderEncoder
                            numberOfVertices:6
                                numberOfPIUs:numberOfInstances
                               vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                                @(iTermVertexInputIndexPerInstanceUniforms): piuBuffer,
                                                @(iTermVertexInputIndexOffset): tState.offsetBuffer,
                                                @(iTermVertexInputIndexDefaultBackgroundColorInfo): infoBuffer
                               }
                             fragmentBuffers:@{ @(iTermFragmentBufferIndexBgColorChecksumReport): checksumReportBuffer }
                                    textures:@{} ];
    }];
    if (tState.suppressedBottomHeight > 0) {
        // Fill in the suppressed region with default background color.
        // Note that we also draw the margins for simplicity.
        CGRect quad = CGRectMake(0,
                                 0,
                                 tState.cellConfiguration.cellSize.width * tState.cellConfiguration.gridSize.width,
                                 suppressedBottomPx);
        const CGRect textureFrame = CGRectMake(0, 0, 1, 1);
        const iTermVertex bottomRight = (iTermVertex) {
            .position = simd_make_float2(NSMaxX(quad), NSMinY(quad)),
            .textureCoordinate = simd_make_float2(NSMaxX(textureFrame),
                                                  NSMaxY(textureFrame))
        };
        const iTermVertex bottomLeft = (iTermVertex) {
            .position = simd_make_float2(NSMinX(quad), NSMinY(quad)),
            .textureCoordinate = simd_make_float2(NSMinX(textureFrame),
                                                  NSMaxY(textureFrame))
        };

        const iTermVertex topLeft = (iTermVertex) {
            .position = simd_make_float2(NSMinX(quad), NSMaxY(quad)),
            .textureCoordinate = simd_make_float2(NSMinX(textureFrame),
                                                  NSMinY(textureFrame))
        };

        const iTermVertex topRight = (iTermVertex) {
            .position = simd_make_float2(NSMaxX(quad), NSMaxY(quad)),
            .textureCoordinate = simd_make_float2(NSMaxX(textureFrame),
                                                  NSMinY(textureFrame))
        };

        iTermVertex vertices[] = {
            bottomRight, bottomLeft, topLeft,
            bottomRight, topLeft, topRight
        };
        id<MTLBuffer> vertexBuffer = [_suppressedRegionVertexBufferPool requestBufferFromContext:tState.poolContext
                                                                                      withBytes:vertices
                                                                                 checkIfChanged:YES];

        iTermBackgroundColorPIU piu = {
            .offset = simd_make_float2(0, 0),
            .runLength = 1,
            .numRows = 1,
            .color = tState.defaultBackgroundColor,
            .isDefault = 1
        };
        piu.color.w = 0;
        id<MTLBuffer> piuBuffer = [self->_piuPool requestBufferFromContext:tState.poolContext
                                                                      size:sizeof(piu)
                                                                     bytes:&piu];
        piuBuffer.label = @"PIUs for suppressed region";

        iTermMetalCellRenderer *cellRenderer = [self rendererForConfiguration:tState.cellConfiguration];

        const CGFloat savedTop = tState.suppressedTopHeight;
        const CGFloat savedBottom = tState.suppressedBottomHeight;
        tState.suppressedTopHeight = 0;
        tState.suppressedBottomHeight = 0;

        // Issue 12791: Skip the checksum check for the suppressed region (sentinel=0). Its
        // geometry is built fresh here, not from the pooled unit quad under suspicion. The
        // report buffer stays bound because the shaders always declare it.
        const iTermBgColorChecksumParams skipParams = { 0, 6 };
        [frameData.renderEncoder setVertexBytes:&skipParams
                                         length:sizeof(skipParams)
                                        atIndex:iTermVertexInputIndexBgColorChecksum];

        [cellRenderer drawWithTransientState:tState
                               renderEncoder:frameData.renderEncoder
                            numberOfVertices:6
                                numberOfPIUs:1
                               vertexBuffers:@{ @(iTermVertexInputIndexVertices): vertexBuffer,
                                                @(iTermVertexInputIndexPerInstanceUniforms): piuBuffer,
                                                @(iTermVertexInputIndexOffset): tState.offsetBuffer,
                                                @(iTermVertexInputIndexDefaultBackgroundColorInfo): infoBuffer
                               }
                             fragmentBuffers:@{ @(iTermFragmentBufferIndexBgColorChecksumReport): checksumReportBuffer }
                                    textures:@{} ];

        tState.suppressedTopHeight = savedTop;
        tState.suppressedBottomHeight = savedBottom;
    }
}

#pragma mark - Issue 12791: Geometry checksum witness reporting

- (void)reportFailureForTransientState:(iTermBackgroundColorRendererTransientState *)tState
                                report:(uint32_t)report {
    NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *filename = [NSString stringWithFormat:@"bgcolor-diag-checksum-%f.txt",
                          [NSDate timeIntervalSinceReferenceDate]];
    NSString *path = [appSupport stringByAppendingPathComponent:filename];

    const iTermVertex *geometry = (const iTermVertex *)tState.vertexBuffer.contents;
    const uint32_t vertexCount = (uint32_t)(tState.vertexBuffer.length / sizeof(iTermVertex));
    const uint32_t rehashedNow = iTermBgColorGeometryHash(geometry, vertexCount);
    const BOOL persistent = (rehashedNow != tState.expectedGeometryChecksum);
    NSString *degenerateNow = iTermBgColorGeometryDegenerateReason(geometry, vertexCount);

    NSMutableString *dump = [NSMutableString string];
    [dump appendFormat:@"Timestamp: %@\n", [NSDate date]];
    [dump appendFormat:@"GPU report bits: 0x%x%@\n", report,
        (report & iTermBgColorReportWitnessFailed) ? @" [GPU geometry witness failed]" : @""];
    [dump appendFormat:@"CPU degeneracy at submit: %@\n", tState.cpuDegenerateReason ?: @"(none)"];
    [dump appendFormat:@"CPU degeneracy now: %@\n", degenerateNow ?: @"(none)"];
    [dump appendFormat:@"Expected geometry hash: 0x%08x\n", tState.expectedGeometryChecksum];
    [dump appendFormat:@"Geometry hash now: 0x%08x %@\n", rehashedNow,
        persistent ? @"<-- PERSISTENT (buffer differs now)"
                   : @"(buffer matches now; corruption was transient/in-flight)"];
    [dump appendFormat:@"Viewport: %u x %u\n", tState.capturedViewportSize.x, tState.capturedViewportSize.y];
    [dump appendFormat:@"Renderer mode: %d\n", (int)tState.capturedMode];
    const vector_float4 bg = tState.defaultBackgroundColor;
    [dump appendFormat:@"DefaultBackgroundColor: (%.4f, %.4f, %.4f, %.4f)\n", bg.x, bg.y, bg.z, bg.w];
    [dump appendFormat:@"CellSize: %.2f x %.2f\n",
        tState.cellConfiguration.cellSize.width, tState.cellConfiguration.cellSize.height];
    [dump appendString:@"\nUnit quad vertices (as read back now):\n"];
    for (uint32_t i = 0; i < vertexCount; i++) {
        [dump appendFormat:@"  v[%u]: position=(%.4f, %.4f) textureCoordinate=(%.4f, %.4f)\n",
            i, geometry[i].position.x, geometry[i].position.y,
            geometry[i].textureCoordinate.x, geometry[i].textureCoordinate.y];
    }

    NSError *error = nil;
    [dump writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        ELog(@"Failed to write bg-color checksum diagnostic: %@", error);
    }
    ITCriticalError(NO,
                    @"Background color GPU geometry checksum failed. Diagnostic written to %@",
                    path);
}

#pragma mark - iTermMetalDebugInfoFormatter

- (void)writeVertexBuffer:(id<MTLBuffer>)buffer index:(NSUInteger)index toFolder:(NSURL *)folder {
    if (index == iTermVertexInputIndexPerInstanceUniforms) {
        iTermBackgroundColorPIU *pius = (iTermBackgroundColorPIU *)buffer.contents;
        NSMutableString *s = [NSMutableString string];
        for (int i = 0; i < buffer.length / sizeof(*pius); i++) {
            [s appendFormat:@"offset=(%@, %@) runLength=%@ numRows=%@ color=(%@, %@, %@, %@)\n",
             @(pius[i].offset.x),
             @(pius[i].offset.y),
             @(pius[i].runLength),
             @(pius[i].numRows),
             @(pius[i].color.x),
             @(pius[i].color.y),
             @(pius[i].color.z),
             @(pius[i].color.w)];
        }
        NSURL *url = [folder URLByAppendingPathComponent:@"vertexBuffer.iTermVertexInputIndexPerInstanceUniforms.txt"];
        [s writeToURL:url atomically:NO encoding:NSUTF8StringEncoding error:nil];
    }
}

@end

@implementation iTermOffscreenCommandLineBackgroundColorRenderer
@end
