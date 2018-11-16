@import simd;
@import MetalKit;

#import "iTermMetalDriver.h"

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermASCIITexture.h"
#import "iTermBackgroundImageRenderer.h"
#import "iTermBackgroundColorRenderer.h"
#import "iTermBadgeRenderer.h"
#import "iTermBroadcastStripesRenderer.h"
#import "iTermCopyBackgroundRenderer.h"
#import "iTermCursorGuideRenderer.h"
#import "iTermCursorRenderer.h"
#import "iTermFullScreenFlashRenderer.h"
#import "iTermHighlightRowRenderer.h"
#import "iTermHistogram.h"
#import "iTermImageRenderer.h"
#import "iTermIndicatorRenderer.h"
#import "iTermMarginRenderer.h"
#import "iTermMetalDebugInfo.h"
#import "iTermMetalFrameData.h"
#import "iTermMarkRenderer.h"
#import "iTermMetalRowData.h"
#import "iTermPreciseTimer.h"
#import "iTermPreferences.h"
#import "iTermTextRendererTransientState.h"
#import "iTermTexture.h"
#import "iTermTimestampsRenderer.h"
#import "iTermShaderTypes.h"
#import "iTermTextRenderer.h"
#import "iTermTextureArray.h"
#import "MovingAverage.h"
#import "NSArray+iTerm.h"
#import "NSMutableData+iTerm.h"
#import <stdatomic.h>

@interface iTermMetalDriverAsyncContext : NSObject
@property (nonatomic, strong) dispatch_group_t group;
@property (nonatomic) BOOL aborted;
@property (nonatomic) int count;
@end

@implementation iTermMetalDriverAsyncContext
@end


@implementation iTermMetalCursorInfo
@end

@implementation iTermMetalIMEInfo

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p cursor=%@ range=%@>",
            NSStringFromClass(self.class),
            self,
            VT100GridCoordDescription(_cursorCoord),
            VT100GridCoordRangeDescription(_markedRange)];
}

- (void)setRangeStart:(VT100GridCoord)start {
    _markedRange.start = start;
}

- (void)setRangeEnd:(VT100GridCoord)end {
    _markedRange.end = end;
}

@end

typedef struct {
    // The current size of our view so we can use this in our render pipeline
    vector_uint2 viewportSize;
    CGSize cellSize;
    CGSize cellSizeWithoutSpacing;
    int rows;
    int columns;
    CGFloat scale;
    CGSize glyphSize;
    CGSize asciiOffset;
    CGContextRef context;
} iTermMetalDriverMainThreadState;

@interface iTermMetalDriver()
// This indicates if a draw call was made while busy. When we stop being busy
// and this is set, then we must schedule another draw.
@property (atomic) BOOL needsDraw;
@property (atomic) BOOL waitingOnSynchronousDraw;
@property (nonatomic, readonly) iTermMetalDriverMainThreadState *mainThreadState;
@end

@implementation iTermMetalDriver {
    iTermMarginRenderer *_marginRenderer;
    iTermBackgroundImageRenderer *_backgroundImageRenderer;
    iTermBackgroundColorRenderer *_backgroundColorRenderer;
    iTermTextRenderer *_textRenderer;
    iTermMarkRenderer *_markRenderer;
    iTermBadgeRenderer *_badgeRenderer;
    iTermFullScreenFlashRenderer *_flashRenderer;
    iTermTimestampsRenderer *_timestampsRenderer;
    iTermIndicatorRenderer *_indicatorRenderer;
    iTermBroadcastStripesRenderer *_broadcastStripesRenderer;
    iTermCursorGuideRenderer *_cursorGuideRenderer;
    iTermHighlightRowRenderer *_highlightRowRenderer;
    iTermCursorRenderer *_underlineCursorRenderer;
    iTermCursorRenderer *_barCursorRenderer;
    iTermCursorRenderer *_imeCursorRenderer;
    iTermCursorRenderer *_blockCursorRenderer;
    iTermCursorRenderer *_frameCursorRenderer;
    iTermCopyModeCursorRenderer *_copyModeCursorRenderer;
    iTermCopyBackgroundRenderer *_copyBackgroundRenderer;
    iTermCursorRenderer *_keyCursorRenderer;
    iTermImageRenderer *_imageRenderer;
#if ENABLE_USE_TEMPORARY_TEXTURE
    iTermCopyToDrawableRenderer *_copyToDrawableRenderer;
#endif

    // This one is special because it's debug only
    iTermCopyOffscreenRenderer *_copyOffscreenRenderer;
    iTermTexturePool *_fullSizeTexturePool;


    // The command Queue from which we'll obtain command buffers
    id<MTLCommandQueue> _commandQueue;
    iTermMetalDriverMainThreadState _mainThreadState;

#if ENABLE_PRIVATE_QUEUE
    dispatch_queue_t _queue;
#endif
    iTermPreciseTimerStats _stats[iTermMetalFrameDataStatCount];
    NSArray<iTermHistogram *> *_statHistograms;
    int _dropped;
    int _total;

    // @synchronized(self)
    NSMutableArray *_currentFrames;
    NSTimeInterval _startTime;
    MovingAverage *_fpsMovingAverage;
    NSTimeInterval _lastFrameTime;
    NSTimeInterval _lastFrameStartTime;
    iTermHistogram *_startToStartHistogram;
    iTermHistogram *_inFlightHistogram;
    MovingAverage *_currentDrawableTime;
    NSInteger _maxFramesInFlight;

    // For client-driven calls through drawAsynchronouslyInView, this will
    // be nonnil and holds the state needed by those calls. Will bet set to nil if the frame will
    // be drawn by reallyDrawInMTKView:.
    iTermMetalDriverAsyncContext *_context;
}

- (nullable instancetype)initWithDevice:(nonnull id<MTLDevice>)device {
    self = [super init];
    if (self) {
        static int gNextIdentifier;
        _identifier = [NSString stringWithFormat:@"[driver %d]", gNextIdentifier++];
        _startToStartHistogram = [[iTermHistogram alloc] init];
        _inFlightHistogram = [[iTermHistogram alloc] init];
        _startTime = [NSDate timeIntervalSinceReferenceDate];
        _fullSizeTexturePool = [[iTermTexturePool alloc] init];
        
        _marginRenderer = [[iTermMarginRenderer alloc] initWithDevice:device];
        _backgroundImageRenderer = [[iTermBackgroundImageRenderer alloc] initWithDevice:device];
        _textRenderer = [[iTermTextRenderer alloc] initWithDevice:device];
        _backgroundColorRenderer = [[iTermBackgroundColorRenderer alloc] initWithDevice:device];
        _markRenderer = [[iTermMarkRenderer alloc] initWithDevice:device];
        _badgeRenderer = [[iTermBadgeRenderer alloc] initWithDevice:device];
        _flashRenderer = [[iTermFullScreenFlashRenderer alloc] initWithDevice:device];
        _timestampsRenderer = [[iTermTimestampsRenderer alloc] initWithDevice:device];
        _indicatorRenderer = [[iTermIndicatorRenderer alloc] initWithDevice:device];
        _broadcastStripesRenderer = [[iTermBroadcastStripesRenderer alloc] initWithDevice:device];
        _cursorGuideRenderer = [[iTermCursorGuideRenderer alloc] initWithDevice:device];
        _highlightRowRenderer = [[iTermHighlightRowRenderer alloc] initWithDevice:device];
        _imageRenderer = [[iTermImageRenderer alloc] initWithDevice:device];
        _underlineCursorRenderer = [iTermCursorRenderer newUnderlineCursorRendererWithDevice:device];
        _barCursorRenderer = [iTermCursorRenderer newBarCursorRendererWithDevice:device];
        _imeCursorRenderer = [iTermCursorRenderer newIMECursorRendererWithDevice:device];
        _blockCursorRenderer = [iTermCursorRenderer newBlockCursorRendererWithDevice:device];
        _frameCursorRenderer = [iTermCursorRenderer newFrameCursorRendererWithDevice:device];
        _copyModeCursorRenderer = [iTermCursorRenderer newCopyModeCursorRendererWithDevice:device];
        _keyCursorRenderer = [iTermCursorRenderer newKeyCursorRendererWithDevice:device];
        _copyBackgroundRenderer = [[iTermCopyBackgroundRenderer alloc] initWithDevice:device];
#if ENABLE_USE_TEMPORARY_TEXTURE
        if (iTermTextIsMonochrome()) {} else {
            _copyToDrawableRenderer = [[iTermCopyToDrawableRenderer alloc] initWithDevice:device];
        }
#endif

        _commandQueue = [device newCommandQueue];
#if ENABLE_PRIVATE_QUEUE
        _queue = dispatch_queue_create("com.iterm2.metalDriver", NULL);
#endif
        _currentFrames = [NSMutableArray array];
        _currentDrawableTime = [[MovingAverage alloc] init];
        _currentDrawableTime.alpha = 0.75;

        _fpsMovingAverage = [[MovingAverage alloc] init];
        _fpsMovingAverage.alpha = 0.75;
        iTermMetalFrameDataStatsBundleInitialize(_stats);
        _statHistograms = [[NSArray sequenceWithRange:NSMakeRange(0, iTermMetalFrameDataStatCount)] mapWithBlock:^id(NSNumber *anObject) {
            return [[iTermHistogram alloc] init];
        }];

        _maxFramesInFlight = iTermMetalDriverMaximumNumberOfFramesInFlight;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
    }

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    // This reference to _mainThreadState is *possibly* unsafe! dealloc gets called off the main
    // queue. But there should not be any remaining references to mainThreadState once you get to
    // dealloc.
    CGContextRef context = _mainThreadState.context;
    dispatch_async(dispatch_get_main_queue(), ^{
        CGContextRelease(context);
    });
}

- (iTermMetalDriverMainThreadState *)mainThreadState {
    assert([NSThread isMainThread]);
    return &_mainThreadState;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
#if ENABLE_PRIVATE_QUEUE
    dispatch_async(_queue, ^{
        iTermMetalFrameDataStatsBundleInitialize(self->_stats);
        [self->_statHistograms enumerateObjectsUsingBlock:^(iTermHistogram * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [obj clear];
        }];
    });
#else
    iTermMetalFrameDataStatsBundleInitialize(_stats);
#endif
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p identifier=%@>", NSStringFromClass([self class]), self, _identifier];
}

#pragma mark - APIs

- (void)setCellSize:(CGSize)cellSize
cellSizeWithoutSpacing:(CGSize)cellSizeWithoutSpacing
          glyphSize:(CGSize)glyphSize
           gridSize:(VT100GridSize)gridSize
        asciiOffset:(CGSize)asciiOffset
              scale:(CGFloat)scale
            context:(CGContextRef)context {
    scale = MAX(1, scale);
    cellSize.width *= scale;
    cellSize.height *= scale;

    glyphSize.width *= scale;
    glyphSize.height *= scale;
    
    cellSizeWithoutSpacing.width *= scale;
    cellSizeWithoutSpacing.height *= scale;

    if (scale == 0) {
        DLog(@"Warning: scale is 0");
    }
    DLog(@"Cell size is now %@x%@, grid size is now %@x%@", @(cellSize.width), @(cellSize.height), @(gridSize.width), @(gridSize.height));
    if (self.mainThreadState->context) {
        CGContextRelease(self.mainThreadState->context);
        self.mainThreadState->context = NULL;
    }
    CGContextRetain(context);
    self.mainThreadState->cellSize = cellSize;
    self.mainThreadState->cellSizeWithoutSpacing = cellSizeWithoutSpacing;
    self.mainThreadState->rows = MAX(1, gridSize.height);
    self.mainThreadState->columns = MAX(1, gridSize.width);
    self.mainThreadState->scale = scale;
    self.mainThreadState->glyphSize = glyphSize;
    self.mainThreadState->asciiOffset = asciiOffset;
    self.mainThreadState->context = context;
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
    self.mainThreadState->viewportSize.x = size.width;
    self.mainThreadState->viewportSize.y = size.height;
}

// Called whenever the view needs to render a frame
- (void)drawInMTKView:(nonnull MTKView *)view {
    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    const NSTimeInterval dt = now - _lastFrameStartTime;
    _lastFrameStartTime = now;

    iTermMetalDriverAsyncContext *context = _context;
    BOOL ok = [self reallyDrawInMTKView:view startToStartTime:dt];
    context.aborted = !ok;
    if (_context && context) {
        // Explicit draw call (drawSynchronously or drawAsynchronously) that failed.
        dispatch_group_leave(context.group);
        _context = nil;
    }

    if (!context && !ok) {
        // Was a system-initiated draw that failed. Try again later.
        [view setNeedsDisplay:YES];
    }

    iTermPreciseTimerSaveLog([NSString stringWithFormat:@"%@: Dropped frames", _identifier],
                             [NSString stringWithFormat:@"%0.1f%%\n", 100.0 * ((double)_dropped / (double)_total)]);
    if (_total % 10 == 1) {
        iTermPreciseTimerSaveLog([NSString stringWithFormat:@"%@: Start-to-Start Time (ms)", _identifier],
                                 [_startToStartHistogram stringValue]);
        iTermPreciseTimerSaveLog([NSString stringWithFormat:@"%@: Frames In Flight at Start", _identifier],
                                 [_inFlightHistogram stringValue]);
    }
}

- (int)maximumNumberOfFramesInFlight {
    if (![iTermAdvancedSettingsModel throttleMetalConcurrentFrames]) {
        return iTermMetalDriverMaximumNumberOfFramesInFlight;
    }

    const CGFloat slowEnoughToDowngradeThreshold = 0.002;
    const CGFloat fastEnoughToUpgradeThreshold = 0.0005;
    if (_currentDrawableTime.numberOfMeasurements > 5 &&
        _maxFramesInFlight > 1 &&
        _currentDrawableTime.value > slowEnoughToDowngradeThreshold) {
        DLog(@"Moving average of currentDrawable latency of %0.2fms with %@ measurements with mff of %@ is too high. Decrease mff to %@",
             _currentDrawableTime.value * 1000,
             @(_currentDrawableTime.numberOfMeasurements),
             @(_maxFramesInFlight),
             @(_maxFramesInFlight - 1));
        _maxFramesInFlight -= 1;
        [_currentDrawableTime reset];
    } else if (_currentDrawableTime.numberOfMeasurements > 10 &&
               _maxFramesInFlight < iTermMetalDriverMaximumNumberOfFramesInFlight &&
               _currentDrawableTime.value < fastEnoughToUpgradeThreshold) {
        DLog(@"Moving average of currentDrawable latency of %0.2fms with %@ measurements with mff of %@ is low. Increase mff to %@",
              _currentDrawableTime.value * 1000,
              @(_currentDrawableTime.numberOfMeasurements),
              @(_maxFramesInFlight),
              @(_maxFramesInFlight + 1));
        _maxFramesInFlight += 1;
        [_currentDrawableTime reset];
    }
    return _maxFramesInFlight;
}

- (iTermMetalDriverAsyncContext *)newContextForDrawInView:(MTKView *)view count:(int)count {
    iTermMetalDriverAsyncContext *context = [[iTermMetalDriverAsyncContext alloc] init];
    _context = context;
    context.count = count;
    context.group = dispatch_group_create();
    dispatch_group_enter(context.group);
    [view draw];

    return context;
}

- (void)drawAsynchronouslyInView:(MTKView *)view completion:(void (^)(BOOL))completion {
    static _Atomic int count;
    int thisCount = atomic_fetch_add_explicit(&count, 1, memory_order_relaxed);
    DLog(@"Start asynchronous draw of %@ count=%d", view, thisCount);
    iTermMetalDriverAsyncContext *context = [self newContextForDrawInView:view count:count];
    dispatch_group_notify(context.group, dispatch_get_main_queue(), ^{
        DLog(@"Asynchronous draw of %@ completed count=%d", view, thisCount);
        completion(!context.aborted);
    });
}

- (BOOL)reallyDrawInMTKView:(nonnull MTKView *)view startToStartTime:(NSTimeInterval)startToStartTime {
    @synchronized (self) {
        [_inFlightHistogram addValue:_currentFrames.count];
    }
    if (self.mainThreadState->rows == 0 || self.mainThreadState->columns == 0) {
        DLog(@"  abort: uninitialized");
        [self scheduleDrawIfNeededInView:view];
        return NO;
    }

#if ENABLE_FLAKY_METAL
#warning DO NOT SUBMIT - FLAKY MODE ENABLED
    if (arc4random_uniform(3) == 0) {
        return NO;
    }
#endif
    
    _total++;
    if (_total % 60 == 0) {
        @synchronized (self) {
            DLog(@"fps=%f (%d in flight)", (_total - _dropped) / ([NSDate timeIntervalSinceReferenceDate] - _startTime), (int)_currentFrames.count);
            DLog(@"%@", _currentFrames);
        }
    }

    if (view.bounds.size.width == 0 || view.bounds.size.height == 0) {
        DLog(@"  abort: 0x0 view");
        return NO;
    }

    iTermMetalFrameData *frameData = [self newFrameDataForView:view];
    DLog(@"allocated metal frame %@", frameData);
    if (VT100GridSizeEquals(frameData.gridSize, VT100GridSizeMake(0, 0))) {
        DLog(@"  abort: 0x0 grid");
        return NO;
    }

    @synchronized(self) {
        const NSInteger framesInFlight = _currentFrames.count;
        const BOOL shouldDrop = (framesInFlight >= [self maximumNumberOfFramesInFlight]);
        if (shouldDrop) {
            DLog(@"  abort: busy (dropped %@%%, number in flight: %d)", @((_dropped * 100)/_total), (int)framesInFlight);
            DLog(@"  current frames:\n%@", _currentFrames);
            _dropped++;
            self.needsDraw = YES;
            return NO;
        }
    }

    if (self.captureDebugInfoForNextFrame) {
        frameData.debugInfo = [[iTermMetalDebugInfo alloc] init];
        self.captureDebugInfoForNextFrame = NO;
    }
    if (_total > 1) {
        [_startToStartHistogram addValue:startToStartTime * 1000];
    }
#if ENABLE_PRIVATE_QUEUE
    [self acquireScarceResources:frameData view:view];
    if (!frameData.deferCurrentDrawable) {
        if (frameData.destinationTexture == nil || frameData.renderPassDescriptor == nil) {
            DLog(@"  abort: failed to get drawable or RPD");
            self.needsDraw = YES;
            return NO;
        }
    }
#endif

    @synchronized(self) {
        [_currentFrames addObject:frameData];
    }

    frameData.group = _context.group;
    if (frameData.group) {
        DLog(@"Frame %@ has a group. The context's count is %d", frameData, _context.count);
    }
    _context = nil;

    void (^block)(void) = ^{
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (self->_lastFrameTime) {
            [self->_fpsMovingAverage addValue:now - self->_lastFrameTime];
        }
        self->_lastFrameTime = now;

        [self performPrivateQueueSetupForFrameData:frameData view:view];
    };
#if ENABLE_PRIVATE_QUEUE
    [frameData dispatchToPrivateQueue:_queue forPreparation:block];
#else
    block();
#endif

    return YES;
}

#pragma mark - Draw Helpers

// Called on the main queue
- (iTermMetalFrameData *)newFrameDataForView:(MTKView *)view {
    iTermMetalFrameData *frameData = [[iTermMetalFrameData alloc] initWithView:view
                                                           fullSizeTexturePool:_fullSizeTexturePool];

    [frameData measureTimeForStat:iTermMetalFrameDataStatMtExtractFromApp ofBlock:^{
        frameData.viewportSize = self.mainThreadState->viewportSize;
        frameData.asciiOffset = self.mainThreadState->asciiOffset;

        // This is the slow part
        frameData.perFrameState = [self->_dataSource metalDriverWillBeginDrawingFrame];

        frameData.rows = [NSMutableArray array];
        frameData.gridSize = frameData.perFrameState.gridSize;

        CGSize (^rescale)(CGSize) = ^CGSize(CGSize size) {
            return CGSizeMake(size.width * self.mainThreadState->scale, size.height * self.mainThreadState->scale);
        };
        frameData.cellSize = rescale(frameData.perFrameState.cellSize);
        frameData.cellSizeWithoutSpacing = rescale(frameData.perFrameState.cellSizeWithoutSpacing);
        frameData.glyphSize = self.mainThreadState->glyphSize;
        
        frameData.scale = self.mainThreadState->scale;
        frameData.hasBackgroundImage = frameData.perFrameState.hasBackgroundImage;
    }];
    return frameData;
}

#pragma mark - Private Queue Orchestration

// Runs in private queue
- (void)performPrivateQueueSetupForFrameData:(iTermMetalFrameData *)frameData
                                        view:(nonnull MTKView *)view {
    DLog(@"Begin private queue setup for frame %@", frameData);
    if ([iTermAdvancedSettingsModel showMetalFPSmeter]) {
        [frameData.perFrameState setDebugString:[self fpsMeterStringForFrameNumber:frameData.frameNumber]];
    }

    // Get glyph keys, attributes, background colors, etc. from datasource.
    [frameData measureTimeForStat:iTermMetalFrameDataStatPqBuildRowData ofBlock:^{
        [self addRowDataToFrameData:frameData];
    }];
    for (iTermMetalRowData *rowData in frameData.rows) {
        [rowData.lineData checkForOverrun];
    }

    // If we're rendering to an intermediate texture because there's something complicated
    // behind text and we need to use the fancy subpixel antialiasing algorithm, create it now.
    // This has to be done before updates so the copyBackgroundRenderer's `enabled` flag can be
    // set properly.
    if ([self shouldCreateIntermediateRenderPassDescriptor:frameData]) {
        [frameData createIntermediateRenderPassDescriptor];
    }
#if ENABLE_USE_TEMPORARY_TEXTURE
    if (iTermTextIsMonochrome()) {} else {
        [frameData createTemporaryRenderPassDescriptor];
    }
#endif

    // Set properties of the renderers for values that tend not to change very often and which
    // are used to create transient states. This must happen before creating transient states
    // since renderers use this info to decide if they should return a nil transient state.
    [frameData measureTimeForStat:iTermMetalFrameDataStatPqUpdateRenderers ofBlock:^{
        [self updateRenderersForNewFrameData:frameData];
    }];
    for (iTermMetalRowData *rowData in frameData.rows) {
        [rowData.lineData checkForOverrun];
    }

    // Create each renderer's transient state, which its per-frame object.
    __block id<MTLCommandBuffer> commandBuffer;
    [frameData measureTimeForStat:iTermMetalFrameDataStatPqCreateTransientStates ofBlock:^{
        commandBuffer = [self->_commandQueue commandBuffer];
        frameData.commandBuffer = commandBuffer;
        [self createTransientStatesWithFrameData:frameData view:view commandBuffer:commandBuffer];
    }];
    for (iTermMetalRowData *rowData in frameData.rows) {
        [rowData.lineData checkForOverrun];
    }

    // Copy state from frame data to transient states
    [frameData measureTimeForStat:iTermMetalFrameDataStatPqPopulateTransientStates ofBlock:^{
        [self populateTransientStatesWithFrameData:frameData range:NSMakeRange(0, frameData.rows.count)];
    }];

#if !ENABLE_PRIVATE_QUEUE
    [self acquireScarceResources:frameData view:view];
    if (!frameData.deferCurrentDrawable) {
        if (frameData.destinationTexture == nil || frameData.renderPassDescriptor == nil) {
            DLog(@"  abort: failed to get drawable or RPD");
            self.needsDraw = YES;
            [self complete:frameData];
            return;
        }
    }
#endif

    [frameData enqueueDrawCallsWithBlock:^{
        [self enqueueDrawCallsForFrameData:frameData
                             commandBuffer:commandBuffer];
    }];
    for (iTermMetalRowData *rowData in frameData.rows) {
        [rowData.lineData checkForOverrun];
    }
}

- (void)addRowDataToFrameData:(iTermMetalFrameData *)frameData {
    NSUInteger sketch = 0;
    for (int y = 0; y < frameData.gridSize.height; y++) {
        const int columns = frameData.gridSize.width;
        iTermMetalRowData *rowData = [[iTermMetalRowData alloc] init];
        [frameData.rows addObject:rowData];
        rowData.y = y;
        rowData.keysData = [iTermGlyphKeyData dataOfLength:sizeof(iTermMetalGlyphKey) * columns];
        rowData.attributesData = [iTermAttributesData dataOfLength:sizeof(iTermMetalGlyphAttributes) * columns];
        rowData.backgroundColorRLEData = [iTermBackgroundColorRLEsData dataOfLength:sizeof(iTermMetalBackgroundColorRLE) * columns];
        rowData.lineData = [frameData.perFrameState lineForRow:y];
        iTermMetalGlyphKey *glyphKeys = (iTermMetalGlyphKey *)rowData.keysData.mutableBytes;
        int drawableGlyphs = 0;
        int rles = 0;
        iTermMarkStyle markStyle;
        NSDate *date;
        [frameData.perFrameState metalGetGlyphKeys:glyphKeys
                                        attributes:rowData.attributesData.mutableBytes
                                         imageRuns:rowData.imageRuns
                                        background:rowData.backgroundColorRLEData.mutableBytes
                                          rleCount:&rles
                                         markStyle:&markStyle
                                               row:y
                                             width:columns
                                    drawableGlyphs:&drawableGlyphs
                                              date:&date
                                            sketch:&sketch];
        rowData.backgroundColorRLEData.length = rles * sizeof(iTermMetalBackgroundColorRLE);
        rowData.date = date;
        rowData.numberOfBackgroundRLEs = rles;
        rowData.numberOfDrawableGlyphs = drawableGlyphs;
        ITConservativeBetaAssert(drawableGlyphs <= rowData.keysData.length / sizeof(iTermMetalGlyphKey),
                                 @"Have %@ drawable glyphs with %@ glyph keys",
                                 @(drawableGlyphs),
                                 @(rowData.keysData.length / sizeof(iTermMetalGlyphKey)));
        rowData.markStyle = markStyle;
        [rowData.keysData checkForOverrun];
        [rowData.attributesData checkForOverrun];
        [rowData.backgroundColorRLEData checkForOverrun];
        [frameData.debugInfo addRowData:rowData];
        [rowData.lineData checkForOverrun];
    }

    // On average, this will be true if there are more than 16 unique color combinations.
    // See tests/sketch_monte_carlo.py
    frameData.hasManyColorCombos = (__builtin_popcountll(sketch) > 14);
}

- (BOOL)shouldCreateIntermediateRenderPassDescriptor:(iTermMetalFrameData *)frameData {
    if (iTermTextIsMonochrome()) {
        return NO;
    }
    if (!_backgroundImageRenderer.rendererDisabled && [frameData.perFrameState metalBackgroundImageGetMode:NULL]) {
        return YES;
    }
    if (!_badgeRenderer.rendererDisabled && [frameData.perFrameState badgeImage]) {
        return YES;
    }
    if (!_broadcastStripesRenderer.rendererDisabled && frameData.perFrameState.showBroadcastStripes) {
        return YES;
    }
    if (!_cursorGuideRenderer.rendererDisabled && frameData.perFrameState.cursorGuideEnabled) {
        return YES;
    }

#if ENABLE_PRETTY_ASCII_OVERLAP
    return YES;
#endif
    
    return NO;
}

- (void)updateRenderersForNewFrameData:(iTermMetalFrameData *)frameData {
    [self updateTextRendererForFrameData:frameData];
    [self updateBackgroundImageRendererForFrameData:frameData];
    [self updateCopyBackgroundRendererForFrameData:frameData];
    [self updateBadgeRendererForFrameData:frameData];
    [self updateBroadcastStripesRendererForFrameData:frameData];
    [self updateCursorGuideRendererForFrameData:frameData];
    [self updateIndicatorRendererForFrameData:frameData];
    [self updateTimestampsRendererForFrameData:frameData];

    [self.cellRenderers enumerateObjectsUsingBlock:^(id<iTermMetalCellRenderer>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (!obj.rendererDisabled) {
            [frameData.debugInfo addCellRenderer:obj];
        }
    }];
}

- (void)createTransientStatesWithFrameData:(iTermMetalFrameData *)frameData
                                      view:(nonnull MTKView *)view
                             commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    iTermCellRenderConfiguration *cellConfiguration = frameData.cellConfiguration;

    [commandBuffer enqueue];
    commandBuffer.label = @"Draw Terminal";
    for (id<iTermMetalRenderer> renderer in self.nonCellRenderers) {
        if (renderer.rendererDisabled) {
            continue;
        }
        [frameData measureTimeForStat:renderer.createTransientStateStat ofBlock:^{
            __kindof iTermMetalRendererTransientState * _Nonnull tState =
            [renderer createTransientStateForConfiguration:cellConfiguration
                                             commandBuffer:commandBuffer];
            if (tState) {
                [frameData setTransientState:tState forRenderer:renderer];
                [frameData.debugInfo addTransientState:tState];
                tState.debugInfo = frameData.debugInfo;
            }
        }];
    };

    for (id<iTermMetalCellRenderer> renderer in self.cellRenderers) {
        if (renderer.rendererDisabled) {
            continue;
        }
        [frameData measureTimeForStat:renderer.createTransientStateStat ofBlock:^{
            __kindof iTermMetalCellRendererTransientState *tState =
                [renderer createTransientStateForCellConfiguration:cellConfiguration
                                                     commandBuffer:commandBuffer];
            if (tState) {
                [frameData setTransientState:tState forRenderer:renderer];
                [frameData.debugInfo addTransientState:tState];
            }
        }];
    };
}

// Called when all renderers have transient state
- (void)populateTransientStatesWithFrameData:(iTermMetalFrameData *)frameData
                                       range:(NSRange)range {
    [self populateMarginRendererTransientStateWithFrameData:frameData];
    [self populateCopyBackgroundRendererTransientStateWithFrameData:frameData];
    [self populateCursorRendererTransientStateWithFrameData:frameData];
    [self populateTextAndBackgroundRenderersTransientStateWithFrameData:frameData];
    [self populateBadgeRendererTransientStateWithFrameData:frameData];
    [self populateMarkRendererTransientStateWithFrameData:frameData];
    [self populateCursorGuideRendererTransientStateWithFrameData:frameData];
    [self populateHighlightRowRendererTransientStateWithFrameData:frameData];
    [self populateTimestampsRendererTransientStateWithFrameData:frameData];
    [self populateFlashRendererTransientStateWithFrameData:frameData];
    [self populateImageRendererTransientStateWithFrameData:frameData];
    [self populateBackgroundImageRendererTransientStateWithFrameData:frameData];
}

- (id<MTLTexture>)destinationTextureForFrameData:(iTermMetalFrameData *)frameData {
    if (frameData.debugInfo) {
        // Render to offscreen first
        MTLTextureDescriptor *textureDescriptor =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                               width:frameData.destinationDrawable.texture.width
                                                              height:frameData.destinationDrawable.texture.height
                                                           mipmapped:NO];
        id<MTLTexture> texture = [frameData.device newTextureWithDescriptor:textureDescriptor];
        texture.label = @"Offscreen destination";
        [iTermTexture setBytesPerRow:frameData.destinationDrawable.texture.width * 4
                         rawDataSize:frameData.destinationDrawable.texture.width * frameData.destinationDrawable.texture.height * 4
                     samplesPerPixel:4
                          forTexture:texture];
        return texture;
    } else {
        // Render directly to drawable
        id<MTLTexture> texture = frameData.destinationDrawable.texture;
        texture.label = @"Drawable destination";
        return texture;
    }
}

// Main thread
- (void)acquireScarceResources:(iTermMetalFrameData *)frameData view:(MTKView *)view {
    if (frameData.debugInfo) {
        [frameData measureTimeForStat:iTermMetalFrameDataStatMtGetRenderPassDescriptor ofBlock:^{
            frameData.renderPassDescriptor = [frameData newRenderPassDescriptorWithLabel:@"Offscreen debug texture"
                                                                                    fast:NO];
            frameData.debugRealRenderPassDescriptor = view.currentRenderPassDescriptor;
        }];
        [frameData measureTimeForStat:iTermMetalFrameDataStatMtGetCurrentDrawable ofBlock:^{
            frameData.destinationDrawable = view.currentDrawable;
            frameData.destinationTexture = frameData.renderPassDescriptor.colorAttachments[0].texture;
        }];

    } else {
#if ENABLE_DEFER_CURRENT_DRAWABLE
        const BOOL synchronousDraw = (_context.group != nil);
        frameData.deferCurrentDrawable = ([iTermPreferences boolForKey:kPreferenceKeyMetalMaximizeThroughput] &&
                                          !synchronousDraw);
#else
        frameData.deferCurrentDrawable = NO;
#endif
        if (!frameData.deferCurrentDrawable) {
            NSTimeInterval duration = [frameData measureTimeForStat:iTermMetalFrameDataStatMtGetCurrentDrawable ofBlock:^{
                frameData.destinationDrawable = view.currentDrawable;
                frameData.destinationTexture = [self destinationTextureForFrameData:frameData];
            }];
            [_currentDrawableTime addValue:duration];
            if (frameData.destinationDrawable == nil) {
                DLog(@"YIKES! Failed to get a drawable. %@/%@", self, frameData);
                return;
            }
        }

        [frameData measureTimeForStat:iTermMetalFrameDataStatMtGetRenderPassDescriptor ofBlock:^{
            if (frameData.deferCurrentDrawable) {
                frameData.renderPassDescriptor = [frameData newRenderPassDescriptorWithLabel:@"RPD for deferred draw" fast:YES];
            } else {
                frameData.renderPassDescriptor = view.currentRenderPassDescriptor;
            }
        }];
        if (frameData.renderPassDescriptor == nil) {
            DLog(@"YIKES! Failed to get an RPD. %@/%@", self, frameData);
            return;
        }
    }
}

- (void)enqueueDrawCallsForFrameData:(iTermMetalFrameData *)frameData
                       commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    DLog(@"  enqueueDrawCallsForFrameData %@", frameData);

    NSString *firstLabel;
    if (frameData.intermediateRenderPassDescriptor) {
        firstLabel = @"Draw content behind text";
    } else {
        firstLabel = @"Draw bg and text";
    }
    [self updateRenderEncoderForCurrentPass:frameData
                                      label:firstLabel];

    [self drawContentBehindTextWithFrameData:frameData];

    // If we're using an intermediate render pass, copy from it to the view for final steps.
    if (frameData.intermediateRenderPassDescriptor) {
        frameData.currentPass = frameData.currentPass + 1;
        [self updateRenderEncoderForCurrentPass:frameData label:@"Copy bg and render text"];
        [self drawRenderer:_copyBackgroundRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueCopyBackground];
    }

    [self drawCellRenderer:_textRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawText];

    [self drawCellRenderer:_imageRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawImage];

    [self drawCursorAfterTextWithFrameData:frameData];

    [self drawCellRenderer:_markRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawMarks];

    [self drawRenderer:_indicatorRenderer
             frameData:frameData
                  stat:iTermMetalFrameDataStatPqEnqueueDrawIndicators];

    [self drawCellRenderer:_timestampsRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawTimestamps];

    [self drawRenderer:_flashRenderer
             frameData:frameData
                  stat:iTermMetalFrameDataStatPqEnqueueDrawFullScreenFlash];

    [self drawCellRenderer:_highlightRowRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawHighlightRow];

    [self finishDrawingWithCommandBuffer:commandBuffer
                               frameData:frameData];
}

#pragma mark - Update Renderers

- (void)updateTextRendererForFrameData:(iTermMetalFrameData *)frameData {
    if (_textRenderer.rendererDisabled) {
        return;
    }
    __weak __typeof(self) weakSelf = self;
    CGSize cellSize = frameData.cellSize;
    CGSize glyphSize = frameData.glyphSize;
    CGFloat scale = frameData.scale;
    __weak iTermMetalFrameData *weakFrameData = frameData;
    [_textRenderer setASCIICellSize:cellSize
                             offset:frameData.asciiOffset
                         descriptor:[frameData.perFrameState characterSourceDescriptorForASCIIWithGlyphSize:glyphSize
                                                                                                asciiOffset:frameData.asciiOffset]
                 creationIdentifier:[frameData.perFrameState metalASCIICreationIdentifierWithOffset:frameData.asciiOffset]
                           creation:^NSDictionary<NSNumber *, iTermCharacterBitmap *> *(char c, iTermASCIITextureAttributes attributes) {
                               __typeof(self) strongSelf = weakSelf;
                               iTermMetalFrameData *strongFrameData = weakFrameData;
                               if (strongSelf && strongFrameData) {
                                   return [strongSelf dictionaryForCharacter:c
                                                              withAttributes:attributes
                                                                   frameData:strongFrameData
                                                                   glyphSize:glyphSize
                                                                       scale:scale];
                               } else {
                                   return nil;
                               }
                           }];
}

- (NSDictionary<NSNumber *, iTermCharacterBitmap *> *)dictionaryForCharacter:(char)c
                                                              withAttributes:(iTermASCIITextureAttributes)attributes
                                                                   frameData:(iTermMetalFrameData *)frameData
                                                                   glyphSize:(CGSize)glyphSize
                                                                       scale:(CGFloat)scale {
    static const int typefaceMask = ((1 << iTermMetalGlyphKeyTypefaceNumberOfBitsNeeded) - 1);
    iTermMetalGlyphKey glyphKey = {
        .code = c,
        .isComplex = NO,
        .boxDrawing = NO,
        .thinStrokes = !!(attributes & iTermASCIITextureAttributesThinStrokes),
        .drawable = YES,
        .typeface = (attributes & typefaceMask),
    };
    BOOL emoji = NO;
    return [frameData.perFrameState metalImagesForGlyphKey:&glyphKey
                                               asciiOffset:frameData.asciiOffset
                                                      size:glyphSize
                                                     scale:scale
                                                     emoji:&emoji];
}

- (void)updateBackgroundImageRendererForFrameData:(iTermMetalFrameData *)frameData {
    if (_backgroundImageRenderer.rendererDisabled) {
        return;
    }
    iTermBackgroundImageMode mode;
    NSImage *backgroundImage = [frameData.perFrameState metalBackgroundImageGetMode:&mode];
    [_backgroundImageRenderer setImage:backgroundImage
                                  mode:mode
                                 frame:frameData.perFrameState.relativeFrame
                         containerSize:frameData.perFrameState.containerSize
                                 color:frameData.perFrameState.defaultBackgroundColor
                               context:frameData.framePoolContext];
}

- (void)updateCopyBackgroundRendererForFrameData:(iTermMetalFrameData *)frameData {
    if (_copyBackgroundRenderer.rendererDisabled) {
        return;
    }
    _copyBackgroundRenderer.enabled = (frameData.intermediateRenderPassDescriptor != nil);
#if ENABLE_USE_TEMPORARY_TEXTURE
    if (iTermTextIsMonochrome()) {} else {
        _copyToDrawableRenderer.enabled = YES;
    }
#endif
}

- (void)updateBadgeRendererForFrameData:(iTermMetalFrameData *)frameData {
    if (_badgeRenderer.rendererDisabled) {
        return;
    }
    [_badgeRenderer setBadgeImage:frameData.perFrameState.badgeImage context:frameData.framePoolContext];
}

- (void)updateIndicatorRendererForFrameData:(iTermMetalFrameData *)frameData {
    if (_indicatorRenderer.rendererDisabled) {
        return;
    }
    const CGFloat scale = frameData.scale;
    NSRect frame = NSMakeRect(0,
                              0,
                              frameData.viewportSize.x / scale,
                              frameData.viewportSize.y / scale);
    [_indicatorRenderer reset];
    [frameData.perFrameState enumerateIndicatorsInFrame:frame block:^(iTermIndicatorDescriptor * _Nonnull indicator) {
        [self->_indicatorRenderer addIndicator:indicator context:frameData.framePoolContext];
    }];
}

- (void)updateBroadcastStripesRendererForFrameData:(iTermMetalFrameData *)frameData {
    if (_broadcastStripesRenderer.rendererDisabled) {
        return;
    }
    _broadcastStripesRenderer.enabled = frameData.perFrameState.showBroadcastStripes;
}

- (void)updateCursorGuideRendererForFrameData:(iTermMetalFrameData *)frameData {
    if (_cursorGuideRenderer.rendererDisabled) {
        return;
    }
    [_cursorGuideRenderer setColor:frameData.perFrameState.cursorGuideColor];
    _cursorGuideRenderer.enabled = frameData.perFrameState.cursorGuideEnabled;
}

- (void)updateTimestampsRendererForFrameData:(iTermMetalFrameData *)frameData {
    if (_timestampsRenderer.rendererDisabled) {
        return;
    }
    _timestampsRenderer.enabled = frameData.perFrameState.timestampsEnabled;
}

#pragma mark - Populate Transient States

- (void)populateCopyBackgroundRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData NS_DEPRECATED_MAC(10_12, 10_14) {
    if (_copyBackgroundRenderer.rendererDisabled) {
        return;
    }
    // Copy state
    iTermCopyBackgroundRendererTransientState *copyState = [frameData transientStateForRenderer:_copyBackgroundRenderer];
    copyState.sourceTexture = frameData.intermediateRenderPassDescriptor.colorAttachments[0].texture;

#if ENABLE_USE_TEMPORARY_TEXTURE
    iTermCopyToDrawableRendererTransientState *dState = [frameData transientStateForRenderer:_copyToDrawableRenderer];
    dState.sourceTexture = frameData.temporaryRenderPassDescriptor.colorAttachments[0].texture;
#endif
}

- (void)populateCursorRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    if (_underlineCursorRenderer.rendererDisabled &&
        _barCursorRenderer.rendererDisabled &&
        _blockCursorRenderer.rendererDisabled &&
        _imeCursorRenderer.rendererDisabled) {
        return;
    }

    // Update glyph attributes for block cursor if needed.
    iTermMetalCursorInfo *cursorInfo = [frameData.perFrameState metalDriverCursorInfo];
    if (!cursorInfo.frameOnly &&
        cursorInfo.cursorVisible &&
        cursorInfo.shouldDrawText &&
        cursorInfo.coord.y >= 0 &&
        cursorInfo.coord.y < frameData.gridSize.height &&
        cursorInfo.coord.x < frameData.gridSize.width) {
        iTermMetalRowData *rowWithCursor = frameData.rows[cursorInfo.coord.y];
        iTermMetalGlyphAttributes *glyphAttributes = (iTermMetalGlyphAttributes *)rowWithCursor.attributesData.mutableBytes;
        glyphAttributes[cursorInfo.coord.x].foregroundColor = cursorInfo.textColor;
        glyphAttributes[cursorInfo.coord.x].backgroundColor = simd_make_float4(cursorInfo.cursorColor.redComponent,
                                                                               cursorInfo.cursorColor.greenComponent,
                                                                               cursorInfo.cursorColor.blueComponent,
                                                                               1);
        [rowWithCursor.attributesData checkForOverrun];
    }

    if (cursorInfo.copyMode) {
        iTermCopyModeCursorRendererTransientState *tState = [frameData transientStateForRenderer:_copyModeCursorRenderer];
        tState.selecting = cursorInfo.copyModeCursorSelecting;
        tState.coord = cursorInfo.copyModeCursorCoord;
    }
    if (cursorInfo.cursorVisible && cursorInfo.password) {
        iTermCursorRendererTransientState *tState = [frameData transientStateForRenderer:_keyCursorRenderer];
        tState.coord = cursorInfo.coord;
    } else if (cursorInfo.cursorVisible) {
        switch (cursorInfo.type) {
            case CURSOR_UNDERLINE: {
                iTermCursorRendererTransientState *tState = [frameData transientStateForRenderer:_underlineCursorRenderer];
                tState.coord = cursorInfo.coord;
                tState.color = cursorInfo.cursorColor;
                tState.doubleWidth = cursorInfo.doubleWidth;
                break;
            }
            case CURSOR_BOX: {
                iTermCursorRendererTransientState *tState = [frameData transientStateForRenderer:_blockCursorRenderer];
                tState.coord = cursorInfo.coord;
                tState.color = cursorInfo.cursorColor;
                tState.doubleWidth = cursorInfo.doubleWidth;

                tState = [frameData transientStateForRenderer:_frameCursorRenderer];
                tState.coord = cursorInfo.coord;
                tState.color = cursorInfo.cursorColor;
                tState.doubleWidth = cursorInfo.doubleWidth;
                break;
            }
            case CURSOR_VERTICAL: {
                iTermCursorRendererTransientState *tState = [frameData transientStateForRenderer:_barCursorRenderer];
                tState.coord = cursorInfo.coord;
                tState.color = cursorInfo.cursorColor;
                break;
            }
            case CURSOR_DEFAULT:
                break;
        }
    }

    iTermMetalIMEInfo *imeInfo = frameData.perFrameState.imeInfo;
    if (imeInfo) {
        iTermCursorRendererTransientState *tState = [frameData transientStateForRenderer:_imeCursorRenderer];
        tState.coord = imeInfo.cursorCoord;
        tState.color = [NSColor colorWithSRGBRed:iTermIMEColor.x
                                           green:iTermIMEColor.y
                                            blue:iTermIMEColor.z
                                           alpha:iTermIMEColor.w];
    }
}

- (void)populateBadgeRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    if (_badgeRenderer.rendererDisabled) {
        return;
    }
    iTermBadgeRendererTransientState *tState = [frameData transientStateForRenderer:_badgeRenderer];
    tState.sourceRect = frameData.perFrameState.badgeSourceRect;
    tState.destinationRect = frameData.perFrameState.badgeDestinationRect;
}

- (void)populateTextAndBackgroundRenderersTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    if (_textRenderer.rendererDisabled && _backgroundColorRenderer.rendererDisabled) {
        return;
    }

    // Update the text renderer's transient state with current glyphs and colors.
    CGFloat scale = frameData.scale;
    iTermTextRendererTransientState *textState = [frameData transientStateForRenderer:_textRenderer];

    // Set the background texture if one is available.
    textState.backgroundTexture = frameData.intermediateRenderPassDescriptor.colorAttachments[0].texture;
    textState.disableIndividualColorModels = frameData.hasManyColorCombos;

    // Configure underlines
    iTermMetalUnderlineDescriptor asciiUnderlineDescriptor;
    iTermMetalUnderlineDescriptor nonAsciiUnderlineDescriptor;
    [frameData.perFrameState metalGetUnderlineDescriptorsForASCII:&asciiUnderlineDescriptor
                                                         nonASCII:&nonAsciiUnderlineDescriptor];
    textState.asciiUnderlineDescriptor = asciiUnderlineDescriptor;
    textState.nonAsciiUnderlineDescriptor = nonAsciiUnderlineDescriptor;
    textState.defaultBackgroundColor = frameData.perFrameState.defaultBackgroundColor;

    CGSize glyphSize = textState.cellConfiguration.glyphSize;
    iTermBackgroundColorRendererTransientState *backgroundState = [frameData transientStateForRenderer:_backgroundColorRenderer];

    iTermMetalIMEInfo *imeInfo = frameData.perFrameState.imeInfo;

    [frameData.rows enumerateObjectsUsingBlock:^(iTermMetalRowData * _Nonnull rowData, NSUInteger idx, BOOL * _Nonnull stop) {
        NSRange markedRangeOnLine = NSMakeRange(NSNotFound, 0);
        if (imeInfo &&
            rowData.y >= imeInfo.markedRange.start.y &&
            rowData.y <= imeInfo.markedRange.end.y) {
            // This line contains at least part of the marked range
            if (rowData.y == imeInfo.markedRange.start.y) {
                // Marked range starts on this line
                if (rowData.y == imeInfo.markedRange.end.y) {
                    // Marked range starts and ends on this line.
                    markedRangeOnLine = NSMakeRange(imeInfo.markedRange.start.x,
                                                    imeInfo.markedRange.end.x - imeInfo.markedRange.start.x);
                } else {
                    // Marked line begins on this line and ends later
                    markedRangeOnLine = NSMakeRange(imeInfo.markedRange.start.x,
                                                    frameData.gridSize.width - imeInfo.markedRange.start.x);
                }
            } else {
                // Marked range started on a prior line
                if (rowData.y == imeInfo.markedRange.end.y) {
                    // Marked range ends on this line
                    markedRangeOnLine = NSMakeRange(0, imeInfo.markedRange.end.x);
                } else {
                    // Marked range ends on a later line
                    markedRangeOnLine = NSMakeRange(0, frameData.gridSize.width);
                }
            }
        }

        iTermMetalGlyphKey *glyphKeys = (iTermMetalGlyphKey *)rowData.keysData.mutableBytes;

        if (!self->_textRenderer.rendererDisabled) {
            ITConservativeBetaAssert(rowData.numberOfDrawableGlyphs * sizeof(iTermMetalGlyphKey) <= rowData.keysData.length,
                                     @"Need %@ bytes of glyph keys but have %@",
                                     @(rowData.numberOfDrawableGlyphs * sizeof(iTermMetalGlyphKey)),
                                     @(rowData.keysData.length));
            [textState setGlyphKeysData:rowData.keysData
                                  count:rowData.numberOfDrawableGlyphs
                         attributesData:rowData.attributesData
                                    row:rowData.y
                 backgroundColorRLEData:rowData.backgroundColorRLEData
                      markedRangeOnLine:markedRangeOnLine
                                context:textState.poolContext
                               creation:^NSDictionary<NSNumber *, iTermCharacterBitmap *> * _Nonnull(int x, BOOL *emoji) {
                                   return [frameData.perFrameState metalImagesForGlyphKey:&glyphKeys[x]
                                                                              asciiOffset:frameData.asciiOffset
                                                                                     size:glyphSize
                                                                                    scale:scale
                                                                                    emoji:emoji];
                               }];
        }
        [rowData.keysData checkForOverrun];
    }];
    if (!_backgroundColorRenderer.rendererDisabled) {
        BOOL (^comparator)(iTermMetalRowData *obj1, iTermMetalRowData *obj2) = ^BOOL(iTermMetalRowData *obj1, iTermMetalRowData *obj2) {
            const NSUInteger count = obj1.numberOfBackgroundRLEs;
            if (count != obj2.numberOfBackgroundRLEs) {
                return NO;
            }
            const iTermMetalBackgroundColorRLE *array1 = (const iTermMetalBackgroundColorRLE *)obj1.backgroundColorRLEData.mutableBytes;
            const iTermMetalBackgroundColorRLE *array2 = (const iTermMetalBackgroundColorRLE *)obj2.backgroundColorRLEData.mutableBytes;
            for (int i = 0; i < count; i++) {
                if (array1[i].color.x != array2[i].color.x ||
                    array1[i].color.y != array2[i].color.y ||
                    array1[i].color.z != array2[i].color.z ||
                    array1[i].count != array2[i].count) {
                    return NO;
                }
            }
            return YES;
        };
        [frameData.rows enumerateCoalescedObjectsWithComparator:comparator block:^(iTermMetalRowData *rowData, NSUInteger count) {
            [backgroundState setColorRLEs:(const iTermMetalBackgroundColorRLE *)rowData.backgroundColorRLEData.mutableBytes
                                    count:rowData.numberOfBackgroundRLEs
                                      row:rowData.y
                            repeatingRows:count];
        }];
    }

    // Tell the text state that it's done getting row data.
    if (!_textRenderer.rendererDisabled) {
        [textState willDraw];
    }
}

- (NSString *)fpsMeterStringForFrameNumber:(int)frameNumber {
    const double period = [_fpsMovingAverage value];
    double fps = 1.0 / period;
    if (period < 0.001) {
        fps = 0;
    }
    return [NSString stringWithFormat:@" [Frame %d: %d fps] ", frameNumber, (int)round(fps)];
}

- (void)populateMarkRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    iTermMarkRendererTransientState *tState = [frameData transientStateForRenderer:_markRenderer];
    [frameData.rows enumerateObjectsUsingBlock:^(iTermMetalRowData * _Nonnull rowData, NSUInteger idx, BOOL * _Nonnull stop) {
        [tState setMarkStyle:rowData.markStyle row:idx];
    }];
}

- (void)populateHighlightRowRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    iTermHighlightRowRendererTransientState *tState = [frameData transientStateForRenderer:_highlightRowRenderer];
    [frameData.perFrameState metalEnumerateHighlightedRows:^(vector_float3 color, NSTimeInterval age, int row) {
        const CGFloat opacity = MAX(0, 0.75 - age);
        [tState setOpacity:opacity color:color row:row];
    }];
}

- (void)populateCursorGuideRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    iTermCursorGuideRendererTransientState *tState = [frameData transientStateForRenderer:_cursorGuideRenderer];
    iTermMetalCursorInfo *cursorInfo = frameData.perFrameState.metalDriverCursorInfo;
    if (cursorInfo.coord.y >= 0 &&
        cursorInfo.coord.y < frameData.gridSize.height) {
        [tState setRow:frameData.perFrameState.metalDriverCursorInfo.coord.y];
    } else {
        [tState setRow:-1];
    }
}

- (void)populateTimestampsRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    iTermTimestampsRendererTransientState *tState = [frameData transientStateForRenderer:_timestampsRenderer];
    if (frameData.perFrameState.timestampsEnabled) {
        tState.backgroundColor = frameData.perFrameState.timestampsBackgroundColor;
        tState.textColor = frameData.perFrameState.timestampsTextColor;

        tState.timestamps = [frameData.rows mapWithBlock:^id(iTermMetalRowData *row) {
            return row.date;
        }];
    }
}

- (void)populateFlashRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    iTermFullScreenFlashRendererTransientState *tState = [frameData transientStateForRenderer:_flashRenderer];
    tState.color = frameData.perFrameState.fullScreenFlashColor;
}

- (void)populateMarginRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    iTermMarginRendererTransientState *tState = [frameData transientStateForRenderer:_marginRenderer];
    vector_float4 color = frameData.perFrameState.processedDefaultBackgroundColor;
    [tState setColor:color];
}

- (void)populateImageRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    iTermImageRendererTransientState *tState = [frameData transientStateForRenderer:_imageRenderer];
    tState.firstVisibleAbsoluteLineNumber = frameData.perFrameState.firstVisibleAbsoluteLineNumber;
    [frameData.rows enumerateObjectsUsingBlock:^(iTermMetalRowData * _Nonnull row, NSUInteger idx, BOOL * _Nonnull stop) {
        [row.imageRuns enumerateObjectsUsingBlock:^(iTermMetalImageRun * _Nonnull imageRun, NSUInteger idx, BOOL * _Nonnull stop) {
            [tState addRun:imageRun];
        }];
    }];
}

- (void)populateBackgroundImageRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    iTermBackgroundImageRendererTransientState *tState =
        [frameData transientStateForRenderer:_backgroundImageRenderer];
    tState.transparencyAlpha = frameData.perFrameState.transparencyAlpha;
    tState.edgeInsets = frameData.perFrameState.edgeInsets;
}

#pragma mark - Draw

- (id<MTLBuffer>)bufferWithContentsOfDestinationTextureInFrameData:(iTermMetalFrameData *)frameData
                                                             label:(NSString *)label {
    // Blit to shared buffer so CPU can see it
    id<MTLBlitCommandEncoder> blitter = [frameData.commandBuffer blitCommandEncoder];
    blitter.label = [NSString stringWithFormat:@"Get debug pixels for %@", label];
    NSUInteger bytesPerRow = frameData.destinationTexture.width * 4;
    NSUInteger length = bytesPerRow * frameData.destinationTexture.height;
    id<MTLBuffer> buffer = [frameData.device newBufferWithLength:length options:MTLResourceStorageModeShared];
    [blitter copyFromTexture:frameData.destinationTexture
                 sourceSlice:0
                 sourceLevel:0
                sourceOrigin:MTLOriginMake(0, 0, 0)
                  sourceSize:MTLSizeMake(frameData.destinationTexture.width, frameData.destinationTexture.height, 1)
                    toBuffer:buffer
           destinationOffset:0
      destinationBytesPerRow:bytesPerRow
    destinationBytesPerImage:length];
    [blitter endEncoding];

    return buffer;
}

- (void)copyToDrawableFromTexture:(id<MTLTexture>)sourceTexture
         withRenderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor
                            label:(NSString *)label
                        frameData:(iTermMetalFrameData *)frameData {
    // Copy from texture to drawable
    [frameData updateRenderEncoderWithRenderPassDescriptor:renderPassDescriptor
                                                      stat:iTermMetalFrameDataStatNA
                                                     label:label];
    if (!_copyOffscreenRenderer) {
        _copyOffscreenRenderer = [[iTermCopyOffscreenRenderer alloc] initWithDevice:frameData.device];
        _copyOffscreenRenderer.enabled = YES;
    }

    iTermCopyOffscreenRendererTransientState *tState =
        [_copyOffscreenRenderer createTransientStateForConfiguration:frameData.cellConfiguration
                                                       commandBuffer:frameData.commandBuffer];
    tState.sourceTexture = sourceTexture;
    tState.debugInfo = frameData.debugInfo;
    [_copyOffscreenRenderer drawWithFrameData:frameData transientState:tState];
    [frameData.renderEncoder endEncoding];
}

// frameData's renderEncoder must have just had -endEncoding called on it at this point.
// It will be left in the same state.
- (void)copyOffscreenTextureToDrawableInFrameData:(iTermMetalFrameData *)frameData {
    [self copyToDrawableFromTexture:frameData.destinationTexture
           withRenderPassDescriptor:frameData.debugRealRenderPassDescriptor
                              label:@"copy offscreen to drawable"
                          frameData:frameData];
}

- (void)drawRenderer:(id<iTermMetalRenderer>)renderer
           frameData:(iTermMetalFrameData *)frameData
                stat:(iTermMetalFrameDataStat)stat {
    if (renderer.rendererDisabled) {
        return;
    }

    const NSUInteger before = frameData.debugInfo.numberOfRecordedDraws;
    [frameData measureTimeForStat:stat ofBlock:^{
        iTermMetalRendererTransientState *state = [frameData transientStateForRenderer:renderer];
        state.sequenceNumber = frameData.numberOfRenderersDrawn;
        frameData.numberOfRenderersDrawn = frameData.numberOfRenderersDrawn + 1;

        // NOTE: State may be nil if we determined it should be skipped early on.
        if (state != nil && !state.skipRenderer) {
            [renderer drawWithFrameData:frameData transientState:state];
        }
    }];

    const NSUInteger numberOfDraws = frameData.debugInfo.numberOfRecordedDraws - before;

    if (numberOfDraws) {
        iTermMetalRendererTransientState *state = [frameData transientStateForRenderer:renderer];
        [self saveRenderOutputForDebuggingIfNeeded:frameData tState:state];
    }
}

- (void)drawCellRenderer:(id<iTermMetalCellRenderer>)renderer
               frameData:(iTermMetalFrameData *)frameData
                    stat:(iTermMetalFrameDataStat)stat {
    if (renderer.rendererDisabled) {
        return;
    }

    const NSUInteger before = frameData.debugInfo.numberOfRecordedDraws;
    [frameData measureTimeForStat:stat ofBlock:^{
        iTermMetalCellRendererTransientState *state = [frameData transientStateForRenderer:renderer];
        state.sequenceNumber = frameData.numberOfRenderersDrawn;
        frameData.numberOfRenderersDrawn = frameData.numberOfRenderersDrawn + 1;
        if (state != nil && !state.skipRenderer) {
            [renderer drawWithFrameData:frameData transientState:state];
        }
    }];

    const NSUInteger numberOfDraws = frameData.debugInfo.numberOfRecordedDraws - before;
    if (numberOfDraws) {
        iTermMetalCellRendererTransientState *state = [frameData transientStateForRenderer:renderer];
        [self saveRenderOutputForDebuggingIfNeeded:frameData tState:state];
    }
}

- (void)saveRenderOutputForDebuggingIfNeeded:(iTermMetalFrameData *)frameData
                                      tState:(iTermMetalRendererTransientState *)state {
    if (frameData.debugInfo && frameData.debugRealRenderPassDescriptor) {
        [frameData.renderEncoder endEncoding];

        id<MTLBuffer> pixelBuffer = [self bufferWithContentsOfDestinationTextureInFrameData:frameData
                                                                                      label:NSStringFromClass([state class])];
        iTermMetalDebugInfo *debugInfo = frameData.debugInfo;
        CGSize size = CGSizeMake(frameData.viewportSize.x, frameData.viewportSize.y);
        [frameData.commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull commandBuffer) {
            void (^block)(void) = ^{
                NSMutableData *data = [NSMutableData dataWithBytes:pixelBuffer.contents length:pixelBuffer.length];
                [self convertBGRAToRGBA:data];
                [debugInfo addRenderOutputData:data size:size transientState:state];
            };
#if ENABLE_PRIVATE_QUEUE
            dispatch_async(self->_queue, block);
#else
            dispatch_async(dispatch_get_main_queue(), block);
#endif
        }];

        [self updateRenderEncoderForCurrentPass:frameData
                                          label:@"Save output for debugging"];
    }
}

- (void)updateRenderEncoderForCurrentPass:(iTermMetalFrameData *)frameData
                                    label:(NSString *)label {
    const int pass = frameData.currentPass;

    BOOL useTemporaryTexture;
    if (iTermTextIsMonochrome()) {
        useTemporaryTexture = NO;
    } else {
#if ENABLE_USE_TEMPORARY_TEXTURE
        useTemporaryTexture = YES;
#else
        useTemporaryTexture = NO;
#endif
    }
    
    NSArray<MTLRenderPassDescriptor *> *descriptors;
    iTermMetalFrameDataStat stats[3] = {
        iTermMetalFrameDataStatPqEnqueueDrawCreateFirstRenderEncoder,
        iTermMetalFrameDataStatPqEnqueueDrawCreateSecondRenderEncoder,
        iTermMetalFrameDataStatPqEnqueueDrawCreateThirdRenderEncoder,
    };
    if (useTemporaryTexture) {
        assert(pass >= 0 && pass <= 2);

        descriptors =
            @[ frameData.intermediateRenderPassDescriptor ?: frameData.temporaryRenderPassDescriptor,
               frameData.temporaryRenderPassDescriptor,
               frameData.renderPassDescriptor ];
    } else {
        // No temporary texture
        assert(pass >= 0 && pass <= 1);
        descriptors =
        @[ frameData.intermediateRenderPassDescriptor ?: frameData.renderPassDescriptor,
           frameData.renderPassDescriptor,
           frameData.renderPassDescriptor ];
    }

    [frameData updateRenderEncoderWithRenderPassDescriptor:descriptors[pass]
                                                      stat:stats[pass]
                                                     label:label];
    frameData.destinationTexture = [descriptors[pass].colorAttachments[0] texture];
}

- (void)drawCursorBeforeTextWithFrameData:(iTermMetalFrameData *)frameData {
    iTermMetalCursorInfo *cursorInfo = [frameData.perFrameState metalDriverCursorInfo];

    if (!cursorInfo.copyMode && !cursorInfo.password && cursorInfo.cursorVisible) {
        switch (cursorInfo.type) {
            case CURSOR_UNDERLINE:
                if (frameData.intermediateRenderPassDescriptor) {
                    [self drawCellRenderer:_underlineCursorRenderer
                                 frameData:frameData
                                      stat:iTermMetalFrameDataStatPqEnqueueDrawCursor];
                }
                break;
            case CURSOR_BOX:
                if (!cursorInfo.frameOnly) {
                    [self drawCellRenderer:_blockCursorRenderer
                                 frameData:frameData
                                      stat:iTermMetalFrameDataStatPqEnqueueDrawCursor];
                }
                break;
            case CURSOR_VERTICAL:
                if (frameData.intermediateRenderPassDescriptor) {
                    [self drawCellRenderer:_barCursorRenderer
                                 frameData:frameData
                                      stat:iTermMetalFrameDataStatPqEnqueueDrawCursor];
                }
                break;
            case CURSOR_DEFAULT:
                break;
        }
    }
}

- (void)drawCursorAfterTextWithFrameData:(iTermMetalFrameData *)frameData {
    iTermMetalCursorInfo *cursorInfo = [frameData.perFrameState metalDriverCursorInfo];

    if (cursorInfo.copyMode) {
        [self drawCellRenderer:_copyModeCursorRenderer
                     frameData:frameData
                          stat:iTermMetalFrameDataStatPqEnqueueDrawCursor];
    }
    if (cursorInfo.cursorVisible) {
        if (cursorInfo.password) {
            [self drawCellRenderer:_keyCursorRenderer
                         frameData:frameData
                              stat:iTermMetalFrameDataStatPqEnqueueDrawCursor];
        } else {
            switch (cursorInfo.type) {
                case CURSOR_UNDERLINE:
                    if (!frameData.intermediateRenderPassDescriptor) {
                        [self drawCellRenderer:_underlineCursorRenderer
                                     frameData:frameData
                                          stat:iTermMetalFrameDataStatPqEnqueueDrawCursor];
                    }
                    break;
                case CURSOR_BOX:
                    if (cursorInfo.frameOnly) {
                        [self drawCellRenderer:_frameCursorRenderer
                                     frameData:frameData
                                          stat:iTermMetalFrameDataStatPqEnqueueDrawCursor];
                    }
                    break;
                case CURSOR_VERTICAL:
                    if (!frameData.intermediateRenderPassDescriptor) {
                        [self drawCellRenderer:_barCursorRenderer
                                     frameData:frameData
                                          stat:iTermMetalFrameDataStatPqEnqueueDrawCursor];
                    }
                    break;
                case CURSOR_DEFAULT:
                    break;
            }
        }
    }
    if (frameData.perFrameState.imeInfo) {
        [self drawCellRenderer:_imeCursorRenderer
                     frameData:frameData
                          stat:iTermMetalFrameDataStatPqEnqueueDrawCursor];
    }
}

- (void)drawContentBehindTextWithFrameData:(iTermMetalFrameData *)frameData {
    [self drawRenderer:_backgroundImageRenderer
             frameData:frameData
                  stat:iTermMetalFrameDataStatPqEnqueueDrawBackgroundImage];

    [self drawCellRenderer:_marginRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawMargin];

     [self drawCellRenderer:_backgroundColorRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawBackgroundColor];

    [self drawRenderer:_badgeRenderer
             frameData:frameData
                  stat:iTermMetalFrameDataStatPqEnqueueBadge];

    [self drawRenderer:_broadcastStripesRenderer
             frameData:frameData
                  stat:iTermMetalFrameDataStatPqEnqueueBroadcastStripes];

    [self drawCellRenderer:_cursorGuideRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawCursorGuide];

    [self drawCursorBeforeTextWithFrameData:frameData];

    if (frameData.intermediateRenderPassDescriptor) {
        [frameData measureTimeForStat:iTermMetalFrameDataStatPqEnqueueDrawEndEncodingToIntermediateTexture ofBlock:^{
            [frameData.renderEncoder endEncoding];
        }];
    }
}

// This is horribly slow but it's only for debug capturing a frame.
- (void)convertBGRAToRGBA:(NSMutableData *)data {
    NSUInteger length = data.length;
    unsigned char *bytes = (unsigned char *)data.mutableBytes;
    for (NSUInteger i = 0; i < length; i += 4) {
        const unsigned char b = bytes[i];
        const unsigned char r = bytes[i + 2];
        bytes[i] = r;
        bytes[i + 2] = b;
    }
}

- (BOOL)deferredRequestCurrentDrawableWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                              frameData:(iTermMetalFrameData *)frameData {
    __block BOOL shouldCopyToDrawable = NO;
    [frameData measureTimeForStat:iTermMetalFrameDataStatPqBlockOnSynchronousGetDrawable ofBlock:^{
        // Get a drawable and then copy to it.
        if (!self.waitingOnSynchronousDraw) {
            dispatch_semaphore_t sema = dispatch_semaphore_create(0);
            __block BOOL timedOut = NO;
            __block id<CAMetalDrawable> drawable = nil;
            __block id<MTLTexture> texture = nil;
            __block MTLRenderPassDescriptor *renderPassDescriptor = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                dispatch_semaphore_signal(sema);
                @synchronized(self) {
                    if (timedOut) {
                        DLog(@"** TIMED OUT %@ **", frameData);
                        return;
                    }
                    [frameData measureTimeForStat:iTermMetalFrameDataStatMtGetCurrentDrawable ofBlock:^{
                        drawable = frameData.view.currentDrawable;
                        DLog(@"%p DEFERRED PATH: got drawable %@ for frame %@", self, drawable, @(frameData.frameNumber));
                        texture = drawable.texture;
                        renderPassDescriptor = frameData.view.currentRenderPassDescriptor;
                    }];
                }
            });
            // TODO: This could avoid false positives by polling every millisecond to see if
            // waitingOnSynchronousDraw has become true.
            const BOOL semaphoreTimeout =
            (dispatch_semaphore_wait(sema,
                                     dispatch_time(DISPATCH_TIME_NOW,
                                                   (int64_t)(0.1 * NSEC_PER_SEC))) != 0);
            @synchronized(self) {
                if (semaphoreTimeout) {
                    // This is usually because the main thread is wedged
                    // waiting for a synchronous draw.
                    DLog(@"** SEMAPHORE EXPIRED %@ **", frameData);
                    timedOut = YES;
                }
                frameData.destinationDrawable = drawable;
                frameData.destinationTexture = texture;
                frameData.destinationTexture.label = @"Drawable destination";
                frameData.renderPassDescriptor = renderPassDescriptor;
            }
        }
        if (frameData.destinationTexture == nil) {
            DLog(@"  abort: failed to get drawable or RPD %@", frameData);
            self.needsDraw = YES;
            [frameData.renderEncoder endEncoding];
            [commandBuffer commit];
            [self didComplete:NO withFrameData:frameData];
        } else {
            DLog(@"Continuing on %@", frameData);
            shouldCopyToDrawable = YES;
        }
    }];
    return shouldCopyToDrawable;
}

- (void)finishDrawingWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                             frameData:(iTermMetalFrameData *)frameData {
#if ENABLE_USE_TEMPORARY_TEXTURE
    BOOL shouldCopyToDrawable = YES;
#else
    BOOL shouldCopyToDrawable = NO;
#endif

    if (@available(macOS 10.14, *)) {
        if (iTermTextIsMonochromeOnMojave()) {
            shouldCopyToDrawable = NO;
        }
    }
    
#if ENABLE_DEFER_CURRENT_DRAWABLE
    if (frameData.deferCurrentDrawable) {
        if ([self deferredRequestCurrentDrawableWithCommandBuffer:commandBuffer frameData:frameData]) {
            shouldCopyToDrawable = YES;
        }
        if (frameData.destinationTexture == nil) {
            DLog(@"nil texture %@", frameData);
            return;
        }
    }
#endif

    if (shouldCopyToDrawable) {
        // Copy to the drawable
        frameData.currentPass = 2;
        [frameData.renderEncoder endEncoding];

        [self updateRenderEncoderForCurrentPass:frameData label:@"Copy to drawable"];
        [self drawRenderer:_copyToDrawableRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueCopyToDrawable];
    }
    [frameData measureTimeForStat:iTermMetalFrameDataStatPqEnqueueDrawEndEncodingToDrawable ofBlock:^{
        [frameData.renderEncoder endEncoding];
    }];

    if (frameData.debugInfo) {
        [self copyOffscreenTextureToDrawableInFrameData:frameData];
    }
    [frameData measureTimeForStat:iTermMetalFrameDataStatPqEnqueueDrawPresentAndCommit ofBlock:^{
#if !ENABLE_SYNCHRONOUS_PRESENTATION
        if (frameData.destinationDrawable) {
            [commandBuffer presentDrawable:frameData.destinationDrawable];
        }
#endif

        iTermPreciseTimerStatsStartTimer(&frameData.stats[iTermMetalFrameDataStatGpuScheduleWait]);

        iTermPreciseTimerStats *scheduleWaitStat = &frameData.stats[iTermMetalFrameDataStatGpuScheduleWait];
        iTermHistogram *scheduleWaitHist = frameData.statHistograms[iTermMetalFrameDataStatGpuScheduleWait];
        void (^scheduledBlock)(void) = [^{
            const double duration = iTermPreciseTimerStatsMeasureAndRecordTimer(scheduleWaitStat);
            [scheduleWaitHist addValue:duration * 1000];
            DLog(@"did schedule %@", frameData);
            [frameData class];  // force a reference to frameData to be kept
        } copy];
        [commandBuffer addScheduledHandler:^(id<MTLCommandBuffer> _Nonnull commandBuffer) {
            dispatch_async(self->_queue, scheduledBlock);
        }];

        __block BOOL completed = NO;
        void (^completedBlock)(void) = [^{
            completed = [self didComplete:completed withFrameData:frameData];
        } copy];

        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull buffer) {
#if ENABLE_PRIVATE_QUEUE
            [frameData dispatchToQueue:self->_queue forCompletion:completedBlock];
#else
            [frameData dispatchToQueue:dispatch_get_main_queue() forCompletion:block];
#endif
        }];

        [commandBuffer commit];
#if ENABLE_SYNCHRONOUS_PRESENTATION
        if (frameData.destinationDrawable) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [commandBuffer waitUntilScheduled];
                [frameData.destinationDrawable present];
            });
        }
#endif
    }];
}

- (BOOL)didComplete:(BOOL)completed withFrameData:(iTermMetalFrameData *)frameData {
    DLog(@"did complete (completed=%@) %@", @(completed), frameData);
    if (!completed) {
        if (frameData.debugInfo) {
            NSData *archive = [frameData.debugInfo newArchive];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.dataSource metalDriverDidProduceDebugInfo:archive];
            });
        }

        completed = YES;
        [self complete:frameData];
        [self scheduleDrawIfNeededInView:frameData.view];

        __weak __typeof(self) weakSelf = self;
        [weakSelf dispatchAsyncToMainQueue:^{
            if (!self->_imageRenderer.rendererDisabled) {
                iTermImageRendererTransientState *tState = [frameData transientStateForRenderer:self->_imageRenderer];
                [weakSelf.dataSource metalDidFindImages:tState.foundImageUniqueIdentifiers
                                          missingImages:tState.missingImageUniqueIdentifiers
                                          animatedLines:tState.animatedLines];
            }
            [weakSelf.dataSource metalDriverDidDrawFrame:frameData.perFrameState];
        }];
    }
    return completed;
}

#pragma mark - Drawing Helpers

- (void)complete:(iTermMetalFrameData *)frameData {
    DLog(@"  in complete: for %@", frameData);

    if (!_textRenderer.rendererDisabled) {
        // Unlock indices and free up the stage texture.
        iTermTextRendererTransientState *textState = [frameData transientStateForRenderer:_textRenderer];
        [textState didComplete];
    }

    DLog(@"  Recording final stats");
    [frameData didCompleteWithAggregateStats:_stats
                                  histograms:_statHistograms
                                       owner:_identifier];

    @synchronized(self) {
        frameData.status = @"retired";
        [_currentFrames removeObject:frameData];
    }
    [self dispatchAsyncToPrivateQueue:^{
        [self scheduleDrawIfNeededInView:frameData.view];
    }];

    if (frameData.group) {
        DLog(@"finished draw with group of frame %@", frameData);
        dispatch_group_leave(frameData.group);
    }
}

#pragma mark - Miscellaneous Utility Methods

- (NSArray<id<iTermMetalCellRenderer>> *)cellRenderers {
    return @[ _marginRenderer,
              _textRenderer,
              _backgroundColorRenderer,
              _markRenderer,
              _cursorGuideRenderer,
              _highlightRowRenderer,
              _imageRenderer,
              _underlineCursorRenderer,
              _barCursorRenderer,
              _imeCursorRenderer,
              _blockCursorRenderer,
              _frameCursorRenderer,
              _copyModeCursorRenderer,
              _keyCursorRenderer,
              _timestampsRenderer ];
}

- (NSArray<id<iTermMetalRenderer>> *)nonCellRenderers {
    NSArray *shared = @[ _backgroundImageRenderer,
                         _badgeRenderer,
                         _broadcastStripesRenderer,
                         _copyBackgroundRenderer,
                         _indicatorRenderer,
                         _flashRenderer ];

    BOOL useTemporaryTexture;
    if (iTermTextIsMonochrome()) {
        useTemporaryTexture = NO;
    } else {
#if ENABLE_USE_TEMPORARY_TEXTURE
        useTemporaryTexture = YES;
#else
        useTemporaryTexture = NO;
#endif
    }
    
    if (useTemporaryTexture) {
        return [shared arrayByAddingObject:_copyToDrawableRenderer];
    } else {
        return shared;
    }
}

- (void)scheduleDrawIfNeededInView:(MTKView *)view {
    if (self.needsDraw) {
        void (^block)(void) = ^{
            if (self.needsDraw) {
                self.needsDraw = NO;
                [view setNeedsDisplay:YES];
            }
        };
#if ENABLE_PRIVATE_QUEUE
        dispatch_async(dispatch_get_main_queue(), block);
#else
        block();
#endif
    }
}

- (void)dispatchAsyncToPrivateQueue:(void (^)(void))block {
#if ENABLE_PRIVATE_QUEUE
    dispatch_async(_queue, block);
#else
    block();
#endif
}

- (void)dispatchAsyncToMainQueue:(void (^)(void))block {
#if ENABLE_PRIVATE_QUEUE
    dispatch_async(dispatch_get_main_queue(), block);
#else
    block();
#endif
}

@end
