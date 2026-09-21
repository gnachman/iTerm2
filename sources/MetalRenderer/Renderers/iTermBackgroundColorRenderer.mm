#import "iTermBackgroundColorRenderer.h"

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "NSFileManager+iTerm.h"
#import "iTermPIUArray.h"
#import "iTermTextRenderer.h"

#import <math.h>
#import <vector>

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

// Issue 12791: Area of a clip-space triangle that falls inside the visible region,
// expressed as a fraction of the viewport. The bg-color vertex shader divides pixel
// coordinates by the viewport size, and the render encoder's viewport rect maps clip
// x,y in [0,1] onto the drawable, so the visible region is the unit square. Clipping is
// Sutherland-Hodgman against the four half-planes; the result is the shoelace area of
// the clipped polygon. This is the number that makes a dropped triangle provable: if a
// triangle should cover a chunk of the screen and the rasterizer reported no fragments
// for it, it was discarded between the vertex stage and the rasterizer.
static double iTermBgColorVisibleAreaFraction(vector_float2 a, vector_float2 b, vector_float2 c) {
    if (!isfinite(a.x) || !isfinite(a.y) || !isfinite(b.x) || !isfinite(b.y) ||
        !isfinite(c.x) || !isfinite(c.y)) {
        return NAN;
    }
    std::vector<simd_double2> polygon = {
        simd_make_double2(a.x, a.y),
        simd_make_double2(b.x, b.y),
        simd_make_double2(c.x, c.y)
    };
    // edge 0..3: x>=0, x<=1, y>=0, y<=1.
    for (int edge = 0; edge < 4 && !polygon.empty(); edge++) {
        // Signed distance to the half-plane: positive is inside.
        const auto inside = [edge](simd_double2 p) -> double {
            switch (edge) {
                case 0: return p.x;
                case 1: return 1.0 - p.x;
                case 2: return p.y;
                default: return 1.0 - p.y;
            }
        };
        std::vector<simd_double2> output;
        for (size_t i = 0; i < polygon.size(); i++) {
            const simd_double2 current = polygon[i];
            const simd_double2 previous = polygon[(i + polygon.size() - 1) % polygon.size()];
            const double dCurrent = inside(current);
            const double dPrevious = inside(previous);
            if (dCurrent >= 0) {
                if (dPrevious < 0) {
                    const double t = dPrevious / (dPrevious - dCurrent);
                    output.push_back(previous + (current - previous) * t);
                }
                output.push_back(current);
            } else if (dPrevious >= 0) {
                const double t = dPrevious / (dPrevious - dCurrent);
                output.push_back(previous + (current - previous) * t);
            }
        }
        polygon = output;
    }
    if (polygon.size() < 3) {
        return 0;
    }
    double twiceArea = 0;
    for (size_t i = 0; i < polygon.size(); i++) {
        const simd_double2 p = polygon[i];
        const simd_double2 q = polygon[(i + 1) % polygon.size()];
        twiceArea += p.x * q.y - q.x * p.y;
    }
    return fabs(twiceArea) / 2.0;
}

@interface iTermBackgroundColorRendererTransientState()
// Issue 12791: GPU geometry checksum witness.
@property (nullable, nonatomic, strong) id<MTLBuffer> checksumReportBuffer;
@property (nonatomic) uint32_t expectedGeometryChecksum;
@property (nonatomic) vector_uint2 capturedViewportSize;
@property (nonatomic) iTermBackgroundColorRendererMode capturedMode;
@property (nullable, nonatomic, copy) NSString *cpuDegenerateReason;
// Issue 12791: per-triangle rasterizer coverage witness. coverageReportBuffer holds two
// atomic_uint sample counters (triangle 0, triangle 1) for the merged multi-row default-
// background quad; the bigQuad* fields record that quad's PIU for the diagnostic dump.
@property (nullable, nonatomic, strong) id<MTLBuffer> coverageReportBuffer;
@property (nonatomic) uint32_t bigQuadRunLength;
@property (nonatomic) uint32_t bigQuadNumRows;
@property (nonatomic) vector_float2 bigQuadOffset;
// Issue 12791: vertex-stage witness. vertexWitnessBuffer holds six
// iTermBgColorVertexWitnessSlot written by the vertex shader for the nominated quad;
// capturedRenderTargetSize is the size of the texture actually being rendered into, which
// is the number capturedViewportSize is supposed to agree with.
@property (nullable, nonatomic, strong) id<MTLBuffer> vertexWitnessBuffer;
@property (nonatomic) vector_uint2 capturedRenderTargetSize;
- (void)setOwner:(iTermBackgroundColorRenderer *)owner;
- (const iTermBgColorVertexWitnessSlot *)vertexWitnessSlots;  // 6 slots, or NULL
@end

@interface iTermBackgroundColorRenderer (TransientStateReports)
- (void)reportFailureForTransientState:(iTermBackgroundColorRendererTransientState *)tState
                                report:(uint32_t)report;
- (void)reportCoverageForTransientState:(iTermBackgroundColorRendererTransientState *)tState
                              triangle0:(uint32_t)triangle0
                              triangle1:(uint32_t)triangle1;
@end

@implementation iTermBackgroundColorRendererTransientState {
    iTerm2::PIUArray<iTermBackgroundColorPIU> _pius;
    __weak iTermBackgroundColorRenderer *_owner;
}

- (void)setOwner:(iTermBackgroundColorRenderer *)owner {
    _owner = owner;
}

// Issue 12791: the vertex shader's slots, valid once the command buffer has completed.
- (const iTermBgColorVertexWitnessSlot *)vertexWitnessSlots {
    if (!_vertexWitnessBuffer) {
        return NULL;
    }
    return (const iTermBgColorVertexWitnessSlot *)_vertexWitnessBuffer.contents;
}

// Issue 12791: Read back the GPU-written checksum report after the command buffer
// completes. Called from -[iTermMetalDriver complete:]. Also fires when the CPU-side
// check already found the buffer degenerate at submit (which the GPU checksum, reading
// the same stable bytes, would not flag).
- (void)didComplete {
    if (_checksumReportBuffer) {
        uint32_t report = 0;
        memcpy(&report, _checksumReportBuffer.contents, sizeof(report));
        if (report != 0 || _cpuDegenerateReason != nil) {
            [_owner reportFailureForTransientState:self report:report];
        }
    }
    // Issue 12791: read back the per-triangle coverage counters. The owner decides whether
    // the coverage is balanced (baseline) or severely asymmetric (dropped triangle).
    if (_coverageReportBuffer) {
        uint32_t coverage[2] = {0, 0};
        memcpy(coverage, _coverageReportBuffer.contents, sizeof(coverage));
        [_owner reportCoverageForTransientState:self triangle0:coverage[0] triangle1:coverage[1]];
    }
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
    iTermMetalCellRenderer *_nonblendingRenderer;
    iTermMetalBufferPool *_infoPool;
    iTermMetalBufferPool *_suppressedRegionVertexBufferPool;

#if ENABLE_TRANSPARENT_METAL_WINDOWS
    iTermMetalCellRenderer *_compositeOverRenderer;
#endif
    iTermMetalMixedSizeBufferPool *_piuPool;
    id<MTLDevice> _device;  // Issue 12791: for per-frame checksum report buffers
    BOOL _wroteCoverageBaseline;  // Issue 12791: one-shot balanced-coverage baseline dump
    int _coverageAsymmetricFilesWritten;  // Issue 12791: cap asymmetry dumps so a stuck artifact can't flood the folder
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

        // Issue 12791: two zeroed atomic_uint coverage counters (triangle 0, triangle 1).
        const uint32_t zero2[2] = {0, 0};
        id<MTLBuffer> coverageReportBuffer = [_device newBufferWithBytes:zero2
                                                                 length:sizeof(zero2)
                                                                options:MTLResourceStorageModeShared];
        coverageReportBuffer.label = @"BG color coverage report";
        tState.coverageReportBuffer = coverageReportBuffer;

        // Issue 12791: six zeroed vertex witness slots, written by the vertex stage.
        iTermBgColorVertexWitnessSlot zeroSlots[6];
        memset(zeroSlots, 0, sizeof(zeroSlots));
        id<MTLBuffer> vertexWitnessBuffer = [_device newBufferWithBytes:zeroSlots
                                                                 length:sizeof(zeroSlots)
                                                                options:MTLResourceStorageModeShared];
        vertexWitnessBuffer.label = @"BG color vertex witness";
        tState.vertexWitnessBuffer = vertexWitnessBuffer;

        tState.capturedViewportSize = (vector_uint2){
            (uint32_t)tState.configuration.viewportSize.x,
            (uint32_t)tState.configuration.viewportSize.y
        };
        // Issue 12791: the size of the texture we are really drawing into. If this differs
        // from capturedViewportSize then the shader is dividing by the wrong number and the
        // whole frame is scaled, which is the leading theory for the diagonal.
        id<MTLTexture> destination = frameData.renderPassDescriptor.colorAttachments[0].texture ?: frameData.destinationTexture;
        tState.capturedRenderTargetSize = (vector_uint2){
            (uint32_t)destination.width,
            (uint32_t)destination.height
        };
        tState.capturedMode = self.mode;
        [tState setOwner:self];

        const iTermVertex *geometry = (const iTermVertex *)tState.vertexBuffer.contents;
        const uint32_t vertexCount = (uint32_t)(tState.vertexBuffer.length / sizeof(iTermVertex));
        tState.expectedGeometryChecksum = iTermBgColorGeometryHash(geometry, vertexCount);
        tState.cpuDegenerateReason = iTermBgColorGeometryDegenerateReason(geometry, vertexCount);
    }
    id<MTLBuffer> checksumReportBuffer = tState.checksumReportBuffer;
    id<MTLBuffer> coverageReportBuffer = tState.coverageReportBuffer;
    id<MTLBuffer> vertexWitnessBuffer = tState.vertexWitnessBuffer;

    // Issue 12791: nominate the quad the vertex witness will describe: the largest merged
    // multi-row run in this draw, which is the one whose hypotenuse the diagonal follows.
    // This has to happen before any drawing so the nominated instance is the global
    // largest rather than whichever segment happened to come first.
    __block NSInteger witnessSegment = -1;
    __block uint32_t witnessInstance = iTermBgColorNoVertexWitnessInstance;
    __block uint32_t witnessArea = 0;
    __block uint32_t witnessRunLength = 0;
    __block uint32_t witnessNumRows = 0;
    __block vector_float2 witnessOffset = simd_make_float2(0, 0);
    __block NSInteger scanSegment = 0;
    const iTermBackgroundColorRendererMode mode = self.mode;
    [tState enumerateSegments:^(const iTermBackgroundColorPIU *pius, size_t numberOfInstances) {
        const NSInteger thisSegment = scanSegment++;
        for (size_t i = 0; i < numberOfInstances; i++) {
            if (pius[i].numRows <= 1) {
                continue;
            }
            // Never nominate an instance this pass is going to cancel: it would rasterize
            // nothing for a legitimate reason and read as a dropped triangle.
            if ((mode == iTermBackgroundColorRendererModeDefaultOnly && !pius[i].isDefault) ||
                (mode == iTermBackgroundColorRendererModeNondefaultOnly && pius[i].isDefault)) {
                continue;
            }
            const uint32_t area = (uint32_t)pius[i].runLength * (uint32_t)pius[i].numRows;
            if (area > witnessArea) {
                witnessArea = area;
                witnessSegment = thisSegment;
                witnessInstance = (uint32_t)i;
                witnessRunLength = pius[i].runLength;
                witnessNumRows = pius[i].numRows;
                witnessOffset = pius[i].offset;
            }
        }
    }];
    // The renderer can run twice per frame (default-only then nondefault-only) on one
    // transient state, so only let the bigger quad own the diagnostic's PIU fields.
    if (witnessArea > tState.bigQuadRunLength * tState.bigQuadNumRows) {
        tState.bigQuadRunLength = witnessRunLength;
        tState.bigQuadNumRows = witnessNumRows;
        tState.bigQuadOffset = witnessOffset;
    }

    // __block: the draw loop rewrites witnessInstance per segment.
    __block iTermBgColorChecksumParams params = {
        tState.expectedGeometryChecksum,
        (uint32_t)(tState.vertexBuffer.length / sizeof(iTermVertex)),
        iTermBgColorNoVertexWitnessInstance
    };

    const NSUInteger suppressedBottomPx = static_cast<NSUInteger>(tState.suppressedBottomHeight * tState.cellConfiguration.scale - tState.margins.top);
    __block NSInteger drawSegment = 0;
    [tState enumerateSegments:^(const iTermBackgroundColorPIU *pius, size_t numberOfInstances) {
        const NSInteger thisSegment = drawSegment++;
        if (numberOfInstances == 0) {
            return;
        }
        // Issue 12791: only the segment holding the nominated quad records vertices.
        params.witnessInstance = (thisSegment == witnessSegment) ? witnessInstance : iTermBgColorNoVertexWitnessInstance;
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
                                                @(iTermVertexInputIndexDefaultBackgroundColorInfo): infoBuffer,
                                                @(iTermVertexInputIndexBgColorVertexWitness): vertexWitnessBuffer
                               }
                             fragmentBuffers:@{ @(iTermFragmentBufferIndexBgColorChecksumReport): checksumReportBuffer,
                                                @(iTermFragmentBufferIndexBgColorCoverageReport): coverageReportBuffer }
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
        const iTermBgColorChecksumParams skipParams = { 0, 6, iTermBgColorNoVertexWitnessInstance };
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
                                                @(iTermVertexInputIndexDefaultBackgroundColorInfo): infoBuffer,
                                                @(iTermVertexInputIndexBgColorVertexWitness): vertexWitnessBuffer
                               }
                             fragmentBuffers:@{ @(iTermFragmentBufferIndexBgColorChecksumReport): checksumReportBuffer,
                                                @(iTermFragmentBufferIndexBgColorCoverageReport): coverageReportBuffer }
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

// Issue 12791: Per-triangle rasterizer coverage readout. triangle0/triangle1 are sparse
// fragment-sample counts (1 fragment in 256) for the two triangles of the merged multi-row
// default-background quad. Balanced counts mean both triangles rasterized; a near-zero
// count on one side while the other covered the screen means that triangle was dropped
// after the vertex stage - the failure the geometry checksum cannot see. We write a one-
// shot baseline (to confirm the witness is live and show normal numbers) and a file every
// time we see severe asymmetry (correlate its appearance with a diagonal sighting).
- (void)reportCoverageForTransientState:(iTermBackgroundColorRendererTransientState *)tState
                              triangle0:(uint32_t)triangle0
                              triangle1:(uint32_t)triangle1 {
    const uint32_t total = triangle0 + triangle1;
    if (total == 0) {
        // No merged multi-row quad was drawn this frame (e.g. a full screen of text).
        return;
    }
    const uint32_t lo = MIN(triangle0, triangle1);
    const uint32_t hi = MAX(triangle0, triangle1);
    // Severe asymmetry: one triangle rasterized almost nothing while the other covered a
    // meaningful area. hi>=64 filters out tiny quads where sampling noise dominates. This
    // is a weak signal on its own, because a triangle that legitimately lies off-screen
    // also rasterizes nothing.
    const BOOL asymmetric = (hi >= 64 && lo * 8 < hi);

    // The strong signal: the vertex stage placed a triangle over a meaningful part of the
    // screen and the rasterizer still produced (almost) nothing for it. That combination
    // can only mean the triangle was discarded after vertex shading, which is the failure
    // that makes half the window show the raw background image.
    const uint64_t viewportPixels =
        (uint64_t)tState.capturedViewportSize.x * (uint64_t)tState.capturedViewportSize.y;
    const uint32_t samples[2] = { triangle0, triangle1 };
    double expectedFraction[2] = { NAN, NAN };
    int droppedTriangle = -1;
    const iTermBgColorVertexWitnessSlot *slots = [tState vertexWitnessSlots];
    const BOOL haveVertexWitness = (slots != NULL && slots[0].written && slots[3].written);
    if (haveVertexWitness && viewportPixels > 0) {
        for (int t = 0; t < 2; t++) {
            expectedFraction[t] = iTermBgColorVisibleAreaFraction(slots[t * 3 + 0].clipSpacePosition,
                                                                  slots[t * 3 + 1].clipSpacePosition,
                                                                  slots[t * 3 + 2].clipSpacePosition);
            if (!(expectedFraction[t] > 0.01)) {
                // Legitimately off-screen or too small to judge.
                continue;
            }
            const double expectedPixels = expectedFraction[t] * (double)viewportPixels;
            const double measuredPixels = (double)samples[t] * 256.0;
            if (measuredPixels < expectedPixels * 0.1) {
                droppedTriangle = t;
            }
        }
    }
    const BOOL dropped = (droppedTriangle >= 0);
    const BOOL anomalous = (dropped || asymmetric);
    if (!anomalous && _wroteCoverageBaseline) {
        return;
    }
    // Cap anomaly dumps: a stuck artifact under rapid blend changes could otherwise write
    // a file every frame. 20 is plenty to characterize it. The baseline is separate.
    static const int kMaxAsymmetricFiles = 20;
    if (anomalous && _coverageAsymmetricFilesWritten >= kMaxAsymmetricFiles) {
        return;
    }

    NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *filename = [NSString stringWithFormat:@"bgcolor-diag-coverage-%f.txt",
                          [NSDate timeIntervalSinceReferenceDate]];
    NSString *path = [appSupport stringByAppendingPathComponent:filename];

    // Sampling is 1 fragment in 16x16=256, so multiply back to estimate covered pixels.
    const uint64_t estPixels0 = (uint64_t)triangle0 * 256;
    const uint64_t estPixels1 = (uint64_t)triangle1 * 256;

    NSString *verdict;
    if (dropped) {
        verdict = @"DROPPED - a triangle covered screen area but rasterized nothing";
    } else if (asymmetric) {
        verdict = @"ASYMMETRIC - one triangle rasterized almost nothing";
    } else {
        verdict = @"baseline (balanced coverage; witness is live)";
    }

    NSMutableString *dump = [NSMutableString string];
    [dump appendFormat:@"Timestamp: %@\n", [NSDate date]];
    [dump appendFormat:@"Verdict: %@\n", verdict];
    if (dropped) {
        [dump appendFormat:@"Dropped triangle: %d (vertices %@)\n",
            droppedTriangle, droppedTriangle == 0 ? @"0,1,2" : @"3,4,5"];
    } else if (asymmetric) {
        const int underCovered = (triangle0 < triangle1) ? 0 : 1;
        [dump appendFormat:@"Under-covered triangle: %d (vertices %@)\n",
            underCovered, underCovered == 0 ? @"0,1,2" : @"3,4,5"];
    }
    [dump appendFormat:@"Triangle 0 samples: %u (~%llu px)\n", triangle0, estPixels0];
    [dump appendFormat:@"Triangle 1 samples: %u (~%llu px)\n", triangle1, estPixels1];
    [dump appendFormat:@"Sampling: 1 fragment in 256 (16x16 grid)\n"];
    [dump appendFormat:@"Viewport (what the CPU configured): %u x %u\n",
        tState.capturedViewportSize.x, tState.capturedViewportSize.y];
    [dump appendFormat:@"Render target (what we draw into): %u x %u%@\n",
        tState.capturedRenderTargetSize.x, tState.capturedRenderTargetSize.y,
        (tState.capturedRenderTargetSize.x > 0 &&
         (tState.capturedRenderTargetSize.x != tState.capturedViewportSize.x ||
          tState.capturedRenderTargetSize.y != tState.capturedViewportSize.y)) ? @"  <-- MISMATCH" : @""];
    [dump appendFormat:@"CellSize: %.2f x %.2f\n",
        tState.cellConfiguration.cellSize.width, tState.cellConfiguration.cellSize.height];
    [dump appendFormat:@"GridSize: %d x %d\n",
        tState.cellConfiguration.gridSize.width, tState.cellConfiguration.gridSize.height];
    [dump appendFormat:@"Largest merged run: runLength=%u numRows=%u offset=(%.2f, %.2f)\n",
        tState.bigQuadRunLength, tState.bigQuadNumRows,
        tState.bigQuadOffset.x, tState.bigQuadOffset.y];
    [dump appendFormat:@"Renderer mode: %d\n", (int)tState.capturedMode];

    // Issue 12791: what the vertex stage actually computed. Vertex shading runs before
    // clipping, so these survive a triangle being discarded and say whether the inputs the
    // GPU read match the ones the CPU sent. Expected visible area is the share of the
    // viewport the triangle should have covered; compare it with the measured samples.
    if (!haveVertexWitness) {
        [dump appendString:@"\nVertex witness: not written (no merged multi-row run was nominated)\n"];
    } else {
        [dump appendString:@"\nVertex witness (what the GPU read and computed):\n"];
        for (int t = 0; t < 2; t++) {
            const double expectedPixels = expectedFraction[t] * (double)viewportPixels;
            [dump appendFormat:@"  Triangle %d expected visible area: %.4f of viewport (~%.0f px), measured ~%llu px\n",
                t, expectedFraction[t], expectedPixels, (uint64_t)samples[t] * 256];
        }
        for (int i = 0; i < 6; i++) {
            const iTermBgColorVertexWitnessSlot &slot = slots[i];
            [dump appendFormat:@"  v%d (tri %d): written=%u iid=%u vertex=(%.2f, %.2f) pixel=(%.2f, %.2f) clip=(%.5f, %.5f)\n",
                i, i / 3, slot.written, slot.instanceID,
                slot.vertexPosition.x, slot.vertexPosition.y,
                slot.pixelSpacePosition.x, slot.pixelSpacePosition.y,
                slot.clipSpacePosition.x, slot.clipSpacePosition.y];
        }
        [dump appendFormat:@"  GPU-side viewportSize: %.2f x %.2f%@\n",
            slots[0].viewportSize.x, slots[0].viewportSize.y,
            ((uint32_t)slots[0].viewportSize.x != tState.capturedViewportSize.x ||
             (uint32_t)slots[0].viewportSize.y != tState.capturedViewportSize.y) ? @"  <-- differs from the CPU's value" : @""];
        [dump appendFormat:@"  GPU-side runLength/numRows: %.0f x %.0f, instance offset: (%.2f, %.2f)\n",
            slots[0].runLengthNumRows.x, slots[0].runLengthNumRows.y,
            slots[0].instanceOffset.x, slots[0].instanceOffset.y];
    }

    NSError *error = nil;
    [dump writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        ELog(@"Failed to write bg-color coverage diagnostic: %@", error);
    }
    if (anomalous) {
        _coverageAsymmetricFilesWritten++;
        ITCriticalError(NO,
                        @"Background color quad triangle %@ (t0=%u t1=%u). Diagnostic written to %@",
                        dropped ? @"dropped" : @"under-covered",
                        triangle0, triangle1, path);
    } else {
        _wroteCoverageBaseline = YES;
        DLog(@"Issue 12791: bg-color coverage baseline written to %@ (t0=%u t1=%u)",
             path, triangle0, triangle1);
    }
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
