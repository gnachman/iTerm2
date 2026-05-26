#import "iTermBackgroundColorRenderer.h"

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "NSFileManager+iTerm.h"
#import "iTermPIUArray.h"
#import "iTermTextRenderer.h"

// Issue 12604/12791: FNV-1a-32 over the PIU array, hashed field-by-field to avoid
// struct padding. Must match the GPU-side implementation in iTermBackgroundColor.metal.
static inline uint32_t iTermBgColorPiuHash(const iTermBackgroundColorPIU *pius, uint32_t count) {
    uint32_t hash = 2166136261u;
    for (uint32_t i = 0; i < count; i++) {
        uint32_t words[9];
        const float ox = pius[i].offset.x;
        const float oy = pius[i].offset.y;
        const float cx = pius[i].color.x;
        const float cy = pius[i].color.y;
        const float cz = pius[i].color.z;
        const float cw = pius[i].color.w;
        memcpy(&words[0], &ox, sizeof(uint32_t));
        memcpy(&words[1], &oy, sizeof(uint32_t));
        words[2] = (uint32_t)pius[i].runLength;
        words[3] = (uint32_t)pius[i].numRows;
        memcpy(&words[4], &cx, sizeof(uint32_t));
        memcpy(&words[5], &cy, sizeof(uint32_t));
        memcpy(&words[6], &cz, sizeof(uint32_t));
        memcpy(&words[7], &cw, sizeof(uint32_t));
        words[8] = (uint32_t)pius[i].isDefault;
        for (int j = 0; j < 9; j++) {
            hash ^= words[j];
            hash *= 16777619u;
        }
    }
    // Reserve 0 as a "skip check" sentinel; clip a legitimate-but-zero hash to 1.
    return hash == 0u ? 1u : hash;
}

// Issue 12604/12791: One per PIU draw this frame, so didComplete can re-hash the buffer
// the GPU read and tell whether a reported mismatch was transient or persistent.
@interface iTermBgColorWitnessEntry : NSObject
@property (nonatomic, strong) id<MTLBuffer> piuBuffer;
@property (nonatomic) uint32_t expected;
@property (nonatomic) uint32_t count;
@end

@implementation iTermBgColorWitnessEntry
@end

@interface iTermBackgroundColorRendererTransientState()
// Issue 12604/12791: GPU checksum witness.
@property (nullable, nonatomic, strong) id<MTLBuffer> checksumReportBuffer;
@property (nonatomic, strong) NSMutableArray<iTermBgColorWitnessEntry *> *witnessEntries;
@property (nonatomic) vector_uint2 capturedViewportSize;
@property (nonatomic) iTermBackgroundColorRendererMode capturedMode;
- (void)setOwner:(iTermBackgroundColorRenderer *)owner;
@end

@interface iTermBackgroundColorRenderer (TransientStateReports)
- (void)reportChecksumFailureForTransientState:(iTermBackgroundColorRendererTransientState *)tState
                                         report:(uint32_t)report;
@end

@implementation iTermBackgroundColorRendererTransientState {
    iTerm2::PIUArray<iTermBackgroundColorPIU> _pius;
    __weak iTermBackgroundColorRenderer *_owner;
}

- (void)setOwner:(iTermBackgroundColorRenderer *)owner {
    _owner = owner;
}

// Issue 12604/12791: Read back the GPU-written checksum report after the command
// buffer completes. Called from -[iTermMetalDriver complete:].
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
    id<MTLDevice> _device;  // Issue 12604/12791: for per-frame checksum report buffers
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

    // Issue 12604/12791: Set up the PIU checksum witness. A shared-storage buffer is the
    // GPU's path to report a mismatch back; it's read in didComplete. We also remember each
    // PIU buffer + expected hash so didComplete can re-hash and tell whether a mismatch was
    // transient (race) or persistent. The bg-color renderer can be invoked more than once
    // per frame (e.g. default-only then nondefault-only around kitty images) on the same
    // transient state, so allocate lazily and accumulate witness entries across passes.
    if (!tState.checksumReportBuffer) {
        const uint32_t zero = 0;
        id<MTLBuffer> checksumReportBuffer = [_device newBufferWithBytes:&zero
                                                                 length:sizeof(zero)
                                                                options:MTLResourceStorageModeShared];
        checksumReportBuffer.label = @"BG color checksum report";
        tState.checksumReportBuffer = checksumReportBuffer;
        tState.witnessEntries = [NSMutableArray array];
        tState.capturedViewportSize = (vector_uint2){
            (uint32_t)tState.configuration.viewportSize.x,
            (uint32_t)tState.configuration.viewportSize.y
        };
        tState.capturedMode = self.mode;
        [tState setOwner:self];
    }
    id<MTLBuffer> checksumReportBuffer = tState.checksumReportBuffer;

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

        // Issue 12604/12791: Hash the PIU bytes the CPU just wrote and pass the expected
        // value inline via setVertexBytes so it bypasses the pooled PIU memory.
        const uint32_t expectedChecksum = iTermBgColorPiuHash((const iTermBackgroundColorPIU *)piuBuffer.contents,
                                                              (uint32_t)numberOfInstances);
        const iTermBgColorChecksumParams params = { expectedChecksum, (uint32_t)numberOfInstances };
        [frameData.renderEncoder setVertexBytes:&params
                                         length:sizeof(params)
                                        atIndex:iTermVertexInputIndexBgColorChecksum];

        iTermBgColorWitnessEntry *entry = [[iTermBgColorWitnessEntry alloc] init];
        entry.piuBuffer = piuBuffer;
        entry.expected = expectedChecksum;
        entry.count = (uint32_t)numberOfInstances;
        [tState.witnessEntries addObject:entry];

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

        // Issue 12604/12791: Skip the checksum check for the suppressed region (sentinel=0).
        // The report buffer is still bound because the fragment shader always declares it.
        const iTermBgColorChecksumParams skipParams = { 0, 1 };
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
                             fragmentBuffers:@{ @(iTermFragmentBufferIndexBgColorChecksumReport): tState.checksumReportBuffer }
                                    textures:@{} ];

        tState.suppressedTopHeight = savedTop;
        tState.suppressedBottomHeight = savedBottom;
    }
}

#pragma mark - Issue 12604/12791: Checksum witness reporting

- (void)reportChecksumFailureForTransientState:(iTermBackgroundColorRendererTransientState *)tState
                                         report:(uint32_t)report {
    NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *filename = [NSString stringWithFormat:@"bgcolor-diag-checksum-%f.txt",
                          [NSDate timeIntervalSinceReferenceDate]];
    NSString *path = [appSupport stringByAppendingPathComponent:filename];

    NSMutableString *dump = [NSMutableString string];
    [dump appendFormat:@"Timestamp: %@\n", [NSDate date]];
    [dump appendFormat:@"Reason: GPU PIU checksum mismatch (report bits=0x%x)\n", report];
    [dump appendFormat:@"Viewport: %u x %u\n", tState.capturedViewportSize.x, tState.capturedViewportSize.y];
    [dump appendFormat:@"Renderer mode: %d\n", (int)tState.capturedMode];
    const vector_float4 bg = tState.defaultBackgroundColor;
    [dump appendFormat:@"DefaultBackgroundColor: (%.4f, %.4f, %.4f, %.4f)\n", bg.x, bg.y, bg.z, bg.w];
    [dump appendFormat:@"Segments this frame: %lu\n", (unsigned long)tState.witnessEntries.count];

    NSInteger segmentIndex = 0;
    for (iTermBgColorWitnessEntry *entry in tState.witnessEntries) {
        const iTermBackgroundColorPIU *pius = (const iTermBackgroundColorPIU *)entry.piuBuffer.contents;
        const uint32_t rehashedNow = iTermBgColorPiuHash(pius, entry.count);
        const BOOL mismatch = (rehashedNow != entry.expected);
        [dump appendFormat:@"\nSegment %ld: instances=%u expected=0x%08x rehashedNow=0x%08x %@\n",
            (long)segmentIndex, entry.count, entry.expected, rehashedNow,
            mismatch ? @"<-- PERSISTENT MISMATCH (buffer differs now)"
                     : @"(buffer matches now; corruption was transient/in-flight)"];
        for (uint32_t i = 0; i < entry.count && i < 64; i++) {
            [dump appendFormat:@"  piu[%u]: offset=(%.2f, %.2f) runLength=%u numRows=%u color=(%.4f, %.4f, %.4f, %.4f) isDefault=%u\n",
                i, pius[i].offset.x, pius[i].offset.y,
                (unsigned)pius[i].runLength, (unsigned)pius[i].numRows,
                pius[i].color.x, pius[i].color.y, pius[i].color.z, pius[i].color.w,
                (unsigned)pius[i].isDefault];
        }
        if (entry.count > 64) {
            [dump appendString:@"  ... (truncated)\n"];
        }
        segmentIndex++;
    }

    NSError *error = nil;
    [dump writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        ELog(@"Failed to write bg-color checksum diagnostic: %@", error);
    }
    ITCriticalError(NO,
                    @"Background color GPU PIU checksum failed. Diagnostic written to %@",
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

