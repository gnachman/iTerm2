@import simd;
@import MetalKit;

#import "iTermMetalDriver.h"

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermASCIITexture.h"
#import "iTermAlphaBlendingHelper.h"
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
#import "iTermLineStyleMarkRenderer.h"
#import "iTermMarginRenderer.h"
#import "iTermMetalDebugInfo.h"
#import "iTermMetalFrameData.h"
#import "iTermMarkRenderer.h"
#import "iTermMetalRowData.h"
#import "iTermOffscreenCommandLineBackgroundRenderer.h"
#import "iTermPreciseTimer.h"
#import "iTermPreferences.h"
#import "iTermTextDrawingHelper.h"
#import "iTermTextRendererTransientState.h"
#import "iTermTexture.h"
#import "iTermTimestampsRenderer.h"
#import "iTermShaderTypes.h"
#import "iTermTextRenderer.h"
#import "iTermTextureArray.h"
#import "MovingAverage.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSMutableData+iTerm.h"
#import "PTYTextView.h"
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
#if ENABLE_UNFAMILIAR_TEXTURE_WORKAROUND
    NSInteger unfamiliarTextureCount;
#endif
    CGFloat maximumExtendedDynamicRangeColorComponentValue NS_AVAILABLE_MAC(10_15);
    CGFloat legacyScrollbarWidth;
} iTermMetalDriverMainThreadState;

@interface iTermMetalDriver()

// When less than infinity, we need to trigger our own redraw. This could be because we failed to
// get a frame or there are too many concurrent draws. When the current attempt at drawing finishes
// a call to setNeedsDisplay: will be made after this duration. It is reset to INFINITY when a draw
// is not needed.
@property (atomic) NSTimeInterval needsDrawAfterDuration;
@property (atomic) BOOL waitingOnSynchronousDraw;
@property (nonatomic, readonly) iTermMetalDriverMainThreadState *mainThreadState;
@end

@implementation iTermMetalDriver {
    iTermMarginRenderer *_marginRenderer;
    iTermBackgroundImageRenderer *_backgroundImageRenderer;
    iTermBackgroundColorRenderer *_backgroundColorRenderer;
    iTermOffscreenCommandLineBackgroundRenderer *_offscreenCommandLineBackgroundRenderer;
    iTermTextRenderer *_textRenderer;
    iTermOffscreenCommandLineTextRenderer *_offscreenCommandLineTextRenderer;
    iTermMarkRenderer *_arrowStyleMarkRenderer;
    iTermLineStyleMarkRenderer *_lineStyleMarkRenderer;
    iTermBadgeRenderer *_badgeRenderer;
    iTermFullScreenFlashRenderer *_flashRenderer;
    iTermTimestampsRenderer *_timestampsRenderer;
    iTermIndicatorRenderer *_indicatorRenderer;
    iTermBroadcastStripesRenderer *_broadcastStripesRenderer;
    iTermCursorGuideRenderer *_cursorGuideRenderer;
    iTermHighlightRowRenderer *_highlightRowRenderer;
    iTermCursorRenderer *_horizontalShadowCursorRenderer;
    iTermCursorRenderer *_verticalShadowCursorRenderer;
    iTermCursorRenderer *_underlineCursorRenderer;
    iTermCursorRenderer *_barCursorRenderer;
    iTermCursorRenderer *_imeCursorRenderer;
    iTermCursorRenderer *_blockCursorRenderer;
    iTermCursorRenderer *_frameCursorRenderer;
    iTermCopyModeCursorRenderer *_copyModeCursorRenderer;
    iTermCopyBackgroundRenderer *_copyBackgroundRenderer;
    iTermCursorRenderer *_keyCursorRenderer;
    iTermImageRenderer *_imageRenderer;
    iTermCopyToDrawableRenderer *_copyToDrawableRenderer;
    iTermBlockRenderer *_blockRenderer;
    iTermTerminalButtonRenderer *_terminalButtonRenderer NS_AVAILABLE_MAC(11);

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
#if ENABLE_STATS
    NSArray<iTermHistogram *> *_statHistograms;
#endif
    int _dropped;
    int _total;

    // Private queue access only
    BOOL _expireNonASCIIGlyphs;

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
#if ENABLE_UNFAMILIAR_TEXTURE_WORKAROUND
    // Used to work around a bug where presentDrawable: sometimes doesn't work. It only seems to
    // happen with a never-before-seen texture. Holds weak refs to drawables' textures.
    NSPointerArray *_familiarTextures;
#endif
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
        _offscreenCommandLineTextRenderer = [[iTermOffscreenCommandLineTextRenderer alloc] initWithDevice:device];
        _backgroundColorRenderer = [[iTermBackgroundColorRenderer alloc] initWithDevice:device];
        _offscreenCommandLineBackgroundRenderer = [[iTermOffscreenCommandLineBackgroundRenderer alloc] initWithDevice:device];
        _arrowStyleMarkRenderer = [[iTermMarkRenderer alloc] initWithDevice:device];
        _lineStyleMarkRenderer = [[iTermLineStyleMarkRenderer alloc] initWithDevice:device];
        _badgeRenderer = [[iTermBadgeRenderer alloc] initWithDevice:device];
        _flashRenderer = [[iTermFullScreenFlashRenderer alloc] initWithDevice:device];
        _timestampsRenderer = [[iTermTimestampsRenderer alloc] initWithDevice:device];
        _indicatorRenderer = [[iTermIndicatorRenderer alloc] initWithDevice:device];
        _broadcastStripesRenderer = [[iTermBroadcastStripesRenderer alloc] initWithDevice:device];
        _cursorGuideRenderer = [[iTermCursorGuideRenderer alloc] initWithDevice:device];
        _highlightRowRenderer = [[iTermHighlightRowRenderer alloc] initWithDevice:device];
        _imageRenderer = [[iTermImageRenderer alloc] initWithDevice:device];
        _horizontalShadowCursorRenderer = [iTermCursorRenderer newHorizontalShadowCursorRendererWithDevice:device];
        _verticalShadowCursorRenderer = [iTermCursorRenderer newVerticalShadowCursorRendererWithDevice:device];
        _underlineCursorRenderer = [iTermCursorRenderer newUnderlineCursorRendererWithDevice:device];
        _barCursorRenderer = [iTermCursorRenderer newBarCursorRendererWithDevice:device];
        _imeCursorRenderer = [iTermCursorRenderer newIMECursorRendererWithDevice:device];
        _blockCursorRenderer = [iTermCursorRenderer newBlockCursorRendererWithDevice:device];
        _frameCursorRenderer = [iTermCursorRenderer newFrameCursorRendererWithDevice:device];
        _copyModeCursorRenderer = [iTermCursorRenderer newCopyModeCursorRendererWithDevice:device];
        _keyCursorRenderer = [iTermCursorRenderer newKeyCursorRendererWithDevice:device];
        _copyBackgroundRenderer = [[iTermCopyBackgroundRenderer alloc] initWithDevice:device];
        if (iTermTextIsMonochrome()) {} else {
            _copyToDrawableRenderer = [[iTermCopyToDrawableRenderer alloc] initWithDevice:device];
        }
        _blockRenderer = [[iTermBlockRenderer alloc] initWithDevice:device];
        if (@available(macOS 11, *)) {
            _terminalButtonRenderer = [[iTermTerminalButtonRenderer alloc] initWithDevice:device];
        }

        _commandQueue = [device newCommandQueue];
#if ENABLE_PRIVATE_QUEUE
        // TexturePageCollection, TexturePage, and iTermTexturePageCollectionSharedPointer are shared
        // among all sessions but are not thread-safe. For now move all metal drivers to a single
        // queue to serialize access to these data structures to avoid data races. Longer term I
        // think I should rewrite them in thread-safe Swift because they are nearly incomprehensible
        // in their current form.
        static dispatch_queue_t queue;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            queue = dispatch_queue_create("com.iterm2.metalDriver", NULL);;
        });
        _queue = queue;
#endif
#if ENABLE_UNFAMILIAR_TEXTURE_WORKAROUND
        _familiarTextures = [NSPointerArray weakObjectsPointerArray];
#endif

        _currentFrames = [NSMutableArray array];
        _currentDrawableTime = [[MovingAverage alloc] init];
        _currentDrawableTime.alpha = 0.75;

        _fpsMovingAverage = [[MovingAverage alloc] init];
        _fpsMovingAverage.alpha = 0.75;
#if ENABLE_STATS
        iTermMetalFrameDataStatsBundleInitialize(_stats);
        _statHistograms = [[NSArray sequenceWithRange:NSMakeRange(0, iTermMetalFrameDataStatCount)] mapWithBlock:^id(NSNumber *anObject) {
            return [[iTermHistogram alloc] init];
        }];
#endif
        _maxFramesInFlight = iTermMetalDriverMaximumNumberOfFramesInFlight;
        _needsDrawAfterDuration = INFINITY;

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
#if ENABLE_STATS
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
#endif  // ENABLE_STATS
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
            context:(CGContextRef)context
legacyScrollbarWidth:(unsigned int)legacyScrollbarWidth {
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
    self.mainThreadState->legacyScrollbarWidth = legacyScrollbarWidth * scale;
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
    self.mainThreadState->viewportSize.x = size.width;
    self.mainThreadState->viewportSize.y = size.height;
}

// Called whenever the view needs to render a frame
- (void)drawInMTKView:(nonnull MTKView *)view {
    DLog(@"Draw metal");
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

- (void)expireNonASCIIGlyphs {
    DLog(@"On main queue.\n%@", [NSThread callStackSymbols]);
    dispatch_async(_queue, ^{
        DLog(@"On queue: Set _expireNonASCIIGlyphs <- YES");
        self->_expireNonASCIIGlyphs = YES;
    });
}

- (MTLCaptureDescriptor *)triggerProgrammaticCapture:(id<MTLDevice>)device NS_AVAILABLE_MAC(10_15) {
    MTLCaptureManager* captureManager = [MTLCaptureManager sharedCaptureManager];
    MTLCaptureDescriptor* captureDescriptor = [[MTLCaptureDescriptor alloc] init];
    NSString *filename = [NSString stringWithFormat:@"/tmp/%@.gputrace", [[NSUUID UUID] UUIDString]];
    captureDescriptor.outputURL = [NSURL fileURLWithPath:filename];
    captureDescriptor.destination = MTLCaptureDestinationGPUTraceDocument;
    captureDescriptor.captureObject = device;

    NSError *error;
    if (![captureManager startCaptureWithDescriptor:captureDescriptor error:&error]) {
        DLog(@"Failed to start capture, error %@", error);
        return nil;
    }
    return captureDescriptor;
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
    if (@available(macOS 10.15, *)) {
        self.mainThreadState->maximumExtendedDynamicRangeColorComponentValue = view.window.screen.maximumPotentialExtendedDynamicRangeColorComponentValue;
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
            self.needsDrawAfterDuration = MIN(self.needsDrawAfterDuration, 1/60.0);
            return NO;
        }
    }

    if (self.captureDebugInfoForNextFrame) {
        frameData.debugInfo = [[iTermMetalDebugInfo alloc] init];
        if (@available(macOS 10.15, *)) {
            frameData.captureDescriptor = [self triggerProgrammaticCapture:frameData.device];
        }
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
            self.needsDrawAfterDuration = MIN(self.needsDrawAfterDuration, 1/60.0);
            return NO;
        }
    }
#if ENABLE_UNFAMILIAR_TEXTURE_WORKAROUND
    if (!frameData.textureIsFamiliar) {
        if (_mainThreadState.unfamiliarTextureCount < _maxFramesInFlight) {
            DLog(@"Texture is unfamiliar for %@", frameData);
            self.needsDrawAfterDuration = 0;
        } else {
            DLog(@"Avoid redrawing unfamiliar texture to break loop");
        }
        _mainThreadState.unfamiliarTextureCount += 1;
    } else {
        _mainThreadState.unfamiliarTextureCount = 0;
    }
#endif  // ENABLE_UNFAMILIAR_TEXTURE_WORKAROUND
#endif  // ENABLE_PRIVATE_QUEUE

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
    if (![_dataSource metalDriverShouldDrawFrame]) {
        DLog(@"Metal driver declined to draw");
        return nil;
    }
    iTermMetalFrameData *frameData = [[iTermMetalFrameData alloc] initWithView:view
                                                           fullSizeTexturePool:_fullSizeTexturePool];

    [frameData measureTimeForStat:iTermMetalFrameDataStatMtExtractFromApp ofBlock:^{
        frameData.viewportSize = self.mainThreadState->viewportSize;
        frameData.legacyScrollbarWidth = self.mainThreadState->legacyScrollbarWidth;
        frameData.asciiOffset = self.mainThreadState->asciiOffset;

        // This is the slow part
        frameData.perFrameState = [self->_dataSource metalDriverWillBeginDrawingFrame];
        frameData.colorSpace = frameData.perFrameState.colorSpace;

        frameData.rows = [NSMutableArray array];
        frameData.gridSize = frameData.perFrameState.gridSize;

        const CGFloat scale = self.mainThreadState->scale;
        CGSize (^rescale)(CGSize) = ^CGSize(CGSize size) {
            return CGSizeMake(size.width * scale, size.height * scale);
        };
        frameData.cellSize = rescale(frameData.perFrameState.cellSize);
        frameData.cellSizeWithoutSpacing = rescale(frameData.perFrameState.cellSizeWithoutSpacing);
        frameData.glyphSize = self.mainThreadState->glyphSize;
        
        frameData.scale = scale;
        frameData.hasBackgroundImage = frameData.perFrameState.hasBackgroundImage;
        const NSEdgeInsets pointInsets = frameData.perFrameState.extraMargins;
        frameData.extraMargins = NSEdgeInsetsMake(pointInsets.top * scale,
                                                  pointInsets.left * scale,
                                                  pointInsets.bottom * scale,
                                                  pointInsets.right * scale);
        frameData.vmargin = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
        if (@available(macOS 10.15, *)) {
            frameData.maximumExtendedDynamicRangeColorComponentValue = self.mainThreadState->maximumExtendedDynamicRangeColorComponentValue;
        }
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

    // If we're rendering to an intermediate texture because there's something complicated
    // behind text and we need to use the fancy subpixel antialiasing algorithm, create it now.
    // This has to be done before updates so the copyBackgroundRenderer's `enabled` flag can be
    // set properly.
    if (!iTermTextIsMonochrome()) {
        [frameData createIntermediateRenderPassDescriptor];
        [frameData createTemporaryRenderPassDescriptor];
    }

    // Set properties of the renderers for values that tend not to change very often and which
    // are used to create transient states. This must happen before creating transient states
    // since renderers use this info to decide if they should return a nil transient state.
    [frameData measureTimeForStat:iTermMetalFrameDataStatPqUpdateRenderers ofBlock:^{
        [self updateRenderersForNewFrameData:frameData];
    }];

    // Create each renderer's transient state, which its per-frame object.
    __block id<MTLCommandBuffer> commandBuffer;
    [frameData measureTimeForStat:iTermMetalFrameDataStatPqCreateTransientStates ofBlock:^{
        commandBuffer = [self->_commandQueue commandBuffer];
        frameData.commandBuffer = commandBuffer;
        [self createTransientStatesWithFrameData:frameData view:view commandBuffer:commandBuffer];
    }];

    // Copy state from frame data to transient states
    [frameData measureTimeForStat:iTermMetalFrameDataStatPqPopulateTransientStates ofBlock:^{
        [self populateTransientStatesWithFrameData:frameData range:NSMakeRange(0, frameData.rows.count)];
    }];

#if !ENABLE_PRIVATE_QUEUE
    [self acquireScarceResources:frameData view:view];
    if (!frameData.deferCurrentDrawable) {
        if (frameData.destinationTexture == nil || frameData.renderPassDescriptor == nil) {
            DLog(@"  abort: failed to get drawable or RPD");
            self.needsDrawAfterDuration = MIN(self.needsDrawAfterDuration, 1/60.0);
            [self complete:frameData];
            return;
        }
    }
#endif

    [frameData enqueueDrawCallsWithBlock:^{
        [self enqueueDrawCallsForFrameData:frameData
                             commandBuffer:commandBuffer];
    }];
}

- (void)addRowDataToFrameData:(iTermMetalFrameData *)frameData {
    for (int y = 0; y < frameData.gridSize.height; y++) {
        const int columns = frameData.gridSize.width;
        iTermMetalRowData *rowData = [[iTermMetalRowData alloc] init];
        [frameData.rows addObject:rowData];
        rowData.y = y;
        rowData.keysData = [iTermGlyphKeyData dataOfLength:sizeof(iTermMetalGlyphKey) * columns];
        rowData.attributesData = [iTermAttributesData dataOfLength:sizeof(iTermMetalGlyphAttributes) * columns];
        rowData.backgroundColorRLEData = [iTermBackgroundColorRLEsData dataOfLength:sizeof(iTermMetalBackgroundColorRLE) * columns];
        rowData.screenCharArray = [frameData.perFrameState screenCharArrayForRow:y];
        iTermMetalGlyphKey *glyphKeys = (iTermMetalGlyphKey *)rowData.keysData.mutableBytes;
        int drawableGlyphs = 0;
        int rles = 0;
        iTermMarkStyle markStyle;
        BOOL lineStyleMark = NO;
        int lineStyleMarkRightInset = 0;
        NSDate *date;
        BOOL belongsToBlock;
        [frameData.perFrameState metalGetGlyphKeys:glyphKeys
                                        attributes:rowData.attributesData.mutableBytes
                                         imageRuns:rowData.imageRuns
                                        background:rowData.backgroundColorRLEData.mutableBytes
                                          rleCount:&rles
                                         markStyle:&markStyle
                                     lineStyleMark:&lineStyleMark
                           lineStyleMarkRightInset:&lineStyleMarkRightInset
                                               row:y
                                             width:columns
                                    drawableGlyphs:&drawableGlyphs
                                              date:&date
                                    belongsToBlock:&belongsToBlock];
        rowData.backgroundColorRLEData.length = rles * sizeof(iTermMetalBackgroundColorRLE);
        rowData.date = date;
        rowData.numberOfBackgroundRLEs = rles;
        rowData.belongsToBlock = belongsToBlock;
        rowData.numberOfDrawableGlyphs = drawableGlyphs;
        ITConservativeBetaAssert(drawableGlyphs <= rowData.keysData.length / sizeof(iTermMetalGlyphKey),
                                 @"Have %@ drawable glyphs with %@ glyph keys",
                                 @(drawableGlyphs),
                                 @(rowData.keysData.length / sizeof(iTermMetalGlyphKey)));
        rowData.markStyle = markStyle;
        rowData.lineStyleMark = lineStyleMark;
        rowData.lineStyleMarkRightInset = lineStyleMarkRightInset;
        [rowData.keysData checkForOverrun];
        [rowData.attributesData checkForOverrun];
        [rowData.backgroundColorRLEData checkForOverrun];
        [frameData.debugInfo addRowData:rowData];
    }
}

- (BOOL)shouldCreateIntermediateRenderPassDescriptor:(iTermMetalFrameData *)frameData {
    return !iTermTextIsMonochrome();
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
    [self populateBlockRendererTransientStateWithFrameData:frameData];
    if (@available(macOS 11, *)) {
        [self populateTerminalButtonRendererTransientStateWithFrameData:frameData];
    }
}

- (id<MTLTexture>)destinationTextureForFrameData:(iTermMetalFrameData *)frameData {
    if (frameData.debugInfo) {
        // Render to offscreen first
        MTLPixelFormat pixelFormat;
        if ([iTermAdvancedSettingsModel hdrCursor]) {
            pixelFormat = MTLPixelFormatRGBA16Float;
        } else {
            pixelFormat = MTLPixelFormatBGRA8Unorm;
        }
        MTLTextureDescriptor *textureDescriptor =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pixelFormat
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

#if ENABLE_UNFAMILIAR_TEXTURE_WORKAROUND
- (BOOL)textureIsFamiliar:(id<MTLTexture>)texture {
    // -compact only does its job if you manually insert a nil pointer!
    // https://stackoverflow.com/questions/31322290/nspointerarray-weird-compaction/40274426
    [_familiarTextures addPointer:nil];
    [_familiarTextures compact];

    for (id candidate in _familiarTextures) {
        if (candidate == texture) {
            return YES;
        }
    }
    return NO;
}
#endif

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
#if ENABLE_UNFAMILIAR_TEXTURE_WORKAROUND
                frameData.textureIsFamiliar = [self textureIsFamiliar:frameData.destinationDrawable.texture];
                if (!frameData.textureIsFamiliar) {
                    [_familiarTextures addPointer:(__bridge void *)frameData.destinationDrawable.texture];
                }
                while (_familiarTextures.count > _maxFramesInFlight) {
                    [_familiarTextures removePointerAtIndex:0];
                }
#endif
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

    if (!frameData.perFrameState.haveOffscreenCommandLine) {
        [self drawRenderer:_indicatorRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawIndicators];
    }

    [self drawCellRenderer:_timestampsRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawTimestamps];

    if (_terminalButtonRenderer) {
        [self drawCellRenderer:_terminalButtonRenderer
                     frameData:frameData
                          stat:iTermMetalFrameDataStatPqEnqueueDrawButtons];
    }

    [self drawRenderer:_flashRenderer
             frameData:frameData
                  stat:iTermMetalFrameDataStatPqEnqueueDrawFullScreenFlash];

    [self drawCellRenderer:_highlightRowRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawHighlightRow];

    [self drawRenderer:_offscreenCommandLineBackgroundRenderer
             frameData:frameData
                  stat:iTermMetalFrameDataStatPqEnqueueDrawOffscreenCommandLineBg];

    if (	frameData.perFrameState.haveOffscreenCommandLine) {
        [self drawRenderer:_indicatorRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawIndicators];
    }


    [self drawCellRenderer:_offscreenCommandLineTextRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawOffscreenCommandLineFg];

    [self finishDrawingWithCommandBuffer:commandBuffer
                               frameData:frameData];
}

#pragma mark - Update Renderers

- (void)updateTextRendererForFrameData:(iTermMetalFrameData *)frameData {
    if (_textRenderer.rendererDisabled) {
        return;
    }
    [self configureTextRenderer:_textRenderer frameData:frameData];
    [self configureTextRenderer:_offscreenCommandLineTextRenderer frameData:frameData];
}

- (void)configureTextRenderer:(iTermTextRenderer *)textRenderer
                    frameData:(iTermMetalFrameData *)frameData {
    __weak __typeof(self) weakSelf = self;
    CGSize cellSize = frameData.cellSize;
    CGSize glyphSize = frameData.glyphSize;
    CGFloat scale = frameData.scale;
    __weak iTermMetalFrameData *weakFrameData = frameData;

    // Set up the ASCII fast path
    [textRenderer setASCIICellSize:cellSize
                            offset:frameData.asciiOffset
                        descriptor:[frameData.perFrameState characterSourceDescriptorForASCIIWithGlyphSize:glyphSize
                                                                                               asciiOffset:frameData.asciiOffset]
                creationIdentifier:[frameData.perFrameState metalASCIICreationIdentifierWithOffset:frameData.asciiOffset]
                          creation:^NSDictionary<NSNumber *, iTermCharacterBitmap *> *(char c, iTermASCIITextureAttributes attributes) {
        __typeof(self) strongSelf = weakSelf;
        iTermMetalFrameData *strongFrameData = weakFrameData;
        if (strongSelf && strongFrameData) {
            return [strongSelf dictionaryForASCIICharacter:c
                                            withAttributes:attributes
                                                 frameData:strongFrameData
                                                 glyphSize:glyphSize
                                                     scale:scale];
        } else {
            return nil;
        }
    }];
}

- (NSDictionary<NSNumber *, iTermCharacterBitmap *> *)dictionaryForASCIICharacter:(char)c
                                                                   withAttributes:(iTermASCIITextureAttributes)attributes
                                                                        frameData:(iTermMetalFrameData *)frameData
                                                                        glyphSize:(CGSize)glyphSize
                                                                            scale:(CGFloat)scale {
    static const int typefaceMask = ((1 << iTermMetalGlyphKeyTypefaceNumberOfBitsNeeded) - 1);
    iTermMetalGlyphKey glyphKey = {
        .code = c,
        .combiningSuccessor = 0,
        .isComplex = NO,
        .boxDrawing = NO,
        .thinStrokes = !!(attributes & iTermASCIITextureAttributesThinStrokes),
        .drawable = YES,
        .typeface = (attributes & typefaceMask),
    };
    BOOL emoji = NO;
    // Don't need to pass predecessor or successor because ASCII never has combining spacing marks.
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
    iTermImageWrapper *backgroundImage = [frameData.perFrameState metalBackgroundImageGetMode:&mode];
    [_backgroundImageRenderer setImage:backgroundImage
                                  mode:mode
                                 frame:frameData.perFrameState.relativeFrame
                         containerRect:frameData.perFrameState.containerRect
                                 color:frameData.perFrameState.defaultBackgroundColor
                            colorSpace:frameData.perFrameState.colorSpace
                               context:frameData.framePoolContext];
}

- (void)updateCopyBackgroundRendererForFrameData:(iTermMetalFrameData *)frameData {
    if (_copyBackgroundRenderer.rendererDisabled) {
        return;
    }
    _copyBackgroundRenderer.enabled = (frameData.intermediateRenderPassDescriptor != nil);
    if (iTermTextIsMonochrome()) {} else {
        _copyToDrawableRenderer.enabled = YES;
    }
}

- (void)updateBadgeRendererForFrameData:(iTermMetalFrameData *)frameData {
    if (_badgeRenderer.rendererDisabled) {
        return;
    }
    [_badgeRenderer setBadgeImage:frameData.perFrameState.badgeImage
                       colorSpace:frameData.perFrameState.colorSpace
                          context:frameData.framePoolContext];
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
        [self->_indicatorRenderer addIndicator:indicator
                                    colorSpace:frameData.perFrameState.colorSpace
                                       context:frameData.framePoolContext];
    }];
}

- (void)updateBroadcastStripesRendererForFrameData:(iTermMetalFrameData *)frameData {
    if (_broadcastStripesRenderer.rendererDisabled) {
        return;
    }
    _broadcastStripesRenderer.enabled = frameData.perFrameState.showBroadcastStripes;
    [_broadcastStripesRenderer setColorSpace:frameData.perFrameState.colorSpace];
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

- (void)populateCopyBackgroundRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    if (_copyBackgroundRenderer.rendererDisabled) {
        return;
    }
    // Copy state
    iTermCopyBackgroundRendererTransientState *copyState = [frameData transientStateForRenderer:_copyBackgroundRenderer];
    copyState.sourceTexture = frameData.intermediateRenderPassDescriptor.colorAttachments[0].texture;

    iTermCopyToDrawableRendererTransientState *dState = [frameData transientStateForRenderer:_copyToDrawableRenderer];
    dState.sourceTexture = frameData.temporaryRenderPassDescriptor.colorAttachments[0].texture;
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
        glyphAttributes[cursorInfo.coord.x].hasUnderlineColor = NO;
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
        tState.backgroundIsDark = SIMDPerceivedBrightness(cursorInfo.backgroundColor) < 0.5;
    } else if (cursorInfo.cursorVisible) {
        switch (cursorInfo.type) {
            case CURSOR_UNDERLINE: {
                iTermCursorRendererTransientState *tState = [frameData transientStateForRenderer:_underlineCursorRenderer];
                tState.coord = cursorInfo.coord;
                tState.color = cursorInfo.cursorColor;
                tState.doubleWidth = cursorInfo.doubleWidth;

                iTermCursorRendererTransientState *shadowTState = [frameData transientStateForRenderer:_horizontalShadowCursorRenderer];
                shadowTState.coord = cursorInfo.coord;
                shadowTState.color = cursorInfo.cursorColor;
                shadowTState.doubleWidth = cursorInfo.doubleWidth;
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

                iTermCursorRendererTransientState *shadowTState = [frameData transientStateForRenderer:_verticalShadowCursorRenderer];
                shadowTState.coord = cursorInfo.coord;
                shadowTState.color = cursorInfo.cursorColor;
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
        tState.color = [NSColor it_colorInDefaultColorSpaceWithRed:iTermIMEColor.x
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

// The meaning of drawOffscreenCommandLine is:
//   nil - just draw
//   @YES - draw only first line
//   @NO - draw all but first line
- (iTermTextRendererTransientState *)_populateTextRenderer:(iTermTextRenderer *)textRenderer
                                             withFrameData:(iTermMetalFrameData *)frameData
                                  drawOffscreenCommandLine:(NSNumber *)drawOffscreenCommandLine {
    // Update the text renderer's transient state with current glyphs and colors.
    const CGFloat scale = frameData.scale;
    iTermTextRendererTransientState *textState = [frameData transientStateForRenderer:textRenderer];
    if (_expireNonASCIIGlyphs) {
        DLog(@"Will expire non-ascii glyphs. Set _expireNonASCIIGlyphs <- NO");
        _expireNonASCIIGlyphs = NO;
        [textState expireNonASCIIGlyphs];
    }

    // Set the background texture if one is available.
    textState.backgroundTexture = frameData.intermediateRenderPassDescriptor.colorAttachments[0].texture;

    // Configure underlines
    iTermMetalUnderlineDescriptor asciiUnderlineDescriptor;
    iTermMetalUnderlineDescriptor nonAsciiUnderlineDescriptor;
    iTermMetalUnderlineDescriptor strikethroughUnderlineDescriptor;
    [frameData.perFrameState metalGetUnderlineDescriptorsForASCII:&asciiUnderlineDescriptor
                                                         nonASCII:&nonAsciiUnderlineDescriptor
                                                    strikethrough:&strikethroughUnderlineDescriptor];
    textState.asciiUnderlineDescriptor = asciiUnderlineDescriptor;
    textState.nonAsciiUnderlineDescriptor = nonAsciiUnderlineDescriptor;
    textState.strikethroughUnderlineDescriptor = strikethroughUnderlineDescriptor;

    CGSize glyphSize = textState.cellConfiguration.glyphSize;

    iTermMetalIMEInfo *imeInfo = frameData.perFrameState.imeInfo;

    [frameData.rows enumerateObjectsUsingBlock:^(iTermMetalRowData * _Nonnull rowData, NSUInteger idx, BOOL * _Nonnull stop) {
        NSRange markedRangeOnLine = NSMakeRange(NSNotFound, 0);
        if (drawOffscreenCommandLine) {
            if (drawOffscreenCommandLine.boolValue && idx != 0) {
                return;
            }
            if (!drawOffscreenCommandLine.boolValue && idx == 0) {
                return;
            }
        }
        if (imeInfo &&
            rowData.y >= imeInfo.markedRange.start.y &&
            rowData.y <= imeInfo.markedRange.end.y &&
            !drawOffscreenCommandLine.boolValue) {
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

        if (!textRenderer.rendererDisabled) {
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
    return textState;
}

- (void)_populateBackgroundRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    iTermBackgroundColorRendererTransientState *backgroundState = [frameData transientStateForRenderer:_backgroundColorRenderer];
    backgroundState.defaultBackgroundColor = frameData.perFrameState.processedDefaultBackgroundColor;

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
                    array1[i].color.w != array2[i].color.w ||
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
}

- (void)_populateOffscreenCommandLineBackgroundRendererWithFrameData:(iTermMetalFrameData *)frameData {
    if (!_offscreenCommandLineBackgroundRenderer.rendererDisabled) {
        iTermOffscreenCommandLineBackgroundRendererTransientState *offscreenState = [frameData transientStateForRenderer:_offscreenCommandLineBackgroundRenderer];
        if (!frameData.perFrameState.haveOffscreenCommandLine) {
            offscreenState.shouldDraw = NO;
        } else {
            offscreenState.shouldDraw = YES;
            [offscreenState setOutlineColor:frameData.perFrameState.offscreenCommandLineOutlineColor
                            backgroundColor:frameData.perFrameState.offscreenCommandLineBackgroundColor
                                  rowHeight:frameData.cellSize.height];
        }
    }
}

- (void)populateTextAndBackgroundRenderersTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    if (_textRenderer.rendererDisabled && _backgroundColorRenderer.rendererDisabled) {
        return;
    }

    iTermTextRendererTransientState *textState;
    if (frameData.perFrameState.haveOffscreenCommandLine && !_offscreenCommandLineTextRenderer.rendererDisabled) {
        textState = [self _populateTextRenderer:_textRenderer withFrameData:frameData drawOffscreenCommandLine:@NO];
    } else {
        textState = [self _populateTextRenderer:_textRenderer withFrameData:frameData drawOffscreenCommandLine:nil];
    }

    [self _populateBackgroundRendererTransientStateWithFrameData:frameData];
    [self _populateOffscreenCommandLineBackgroundRendererWithFrameData:frameData];

    // Tell the text state that it's done getting row data.
    if (!_textRenderer.rendererDisabled) {
        [textState willDraw];
    }

    if (!_offscreenCommandLineTextRenderer.rendererDisabled) {
        _offscreenCommandLineTextRenderer.verticalOffset = frameData.scale * (frameData.vmargin - iTermOffscreenCommandLineVerticalPadding + 1);
        if (frameData.perFrameState.haveOffscreenCommandLine) {
            textState = [self _populateTextRenderer:_offscreenCommandLineTextRenderer withFrameData:frameData drawOffscreenCommandLine:@YES];
            [textState willDraw];
        }
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
    [self populateArrowStyleMarkRendererTransientStateWithFrameData:frameData];
    [self populateLineStyleMarkRendererTransientStateWithFrameData:frameData];
}

- (void)populateArrowStyleMarkRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    iTermMarkRendererTransientState *tState = [frameData transientStateForRenderer:_arrowStyleMarkRenderer];
    [frameData.rows enumerateObjectsUsingBlock:^(iTermMetalRowData * _Nonnull rowData, NSUInteger idx, BOOL * _Nonnull stop) {
        if (VT100GridRangeContains(frameData.perFrameState.linesToSuppressDrawing, rowData.y)) {
            return;
        }
        if (!rowData.lineStyleMark) {
            [tState setMarkStyle:rowData.markStyle row:idx];
        }
    }];
}

- (void)populateLineStyleMarkRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    iTermLineStyleMarkRendererTransientState *tState = [frameData transientStateForRenderer:_lineStyleMarkRenderer];
    [frameData.rows enumerateObjectsUsingBlock:^(iTermMetalRowData * _Nonnull rowData, NSUInteger idx, BOOL * _Nonnull stop) {
        if (VT100GridRangeContains(frameData.perFrameState.linesToSuppressDrawing, rowData.y)) {
            return;
        }
        if (rowData.lineStyleMark) {
            [tState setMarkStyle:rowData.markStyle row:idx rightInset:rowData.lineStyleMarkRightInset];
        }
    }];
    tState.colors = frameData.perFrameState.lineStyleMarkColors;
}

- (void)populateHighlightRowRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    iTermHighlightRowRendererTransientState *tState = [frameData transientStateForRenderer:_highlightRowRenderer];
    [frameData.perFrameState metalEnumerateHighlightedRows:^(vector_float3 color, NSTimeInterval age, int row) {
        const CGFloat opacity = MAX(0, PTYTextViewHighlightLineAnimationDuration - age);
        [tState setOpacity:opacity color:color row:row];
    }];
}

- (void)populateCursorGuideRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    iTermCursorGuideRendererTransientState *tState = [frameData transientStateForRenderer:_cursorGuideRenderer];
    iTermMetalCursorInfo *cursorInfo = frameData.perFrameState.metalDriverCursorInfo;
    if (cursorInfo.coord.y >= 0 &&
        cursorInfo.coord.y < frameData.gridSize.height) {
        const int row = frameData.perFrameState.metalDriverCursorInfo.coord.y;
        if (VT100GridRangeContains(frameData.perFrameState.linesToSuppressDrawing, row)) {
            [tState setRow:-1];
        } else {
            [tState setRow:row];
        }
    } else {
        [tState setRow:-1];
    }
}

- (void)populateTimestampsRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    iTermTimestampsRendererTransientState *tState = [frameData transientStateForRenderer:_timestampsRenderer];
    if (frameData.perFrameState.timestampsEnabled) {
        tState.useThinStrokes = frameData.perFrameState.thinStrokesForTimestamps;
        tState.antialiased = frameData.perFrameState.asciiAntiAliased;
        tState.backgroundColor = frameData.perFrameState.timestampsBackgroundColor;
        tState.textColor = frameData.perFrameState.timestampsTextColor;
        tState.font = frameData.perFrameState.timestampFont;
        tState.obscured = frameData.cellSize.height / frameData.scale + iTermOffscreenCommandLineVerticalPadding * 2;
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

- (void)populateBlockRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData {
    iTermBlockRendererTransientState *tState = [frameData transientStateForRenderer:_blockRenderer];
    vector_float4 color = frameData.perFrameState.processedDefaultTextColor;
    [tState setColor:color];
    [frameData.rows enumerateObjectsUsingBlock:^(iTermMetalRowData * _Nonnull rowData, NSUInteger idx, BOOL * _Nonnull stop) {
        if (rowData.belongsToBlock) {
            [tState addRow:idx];
        }
    }];
}

- (void)populateTerminalButtonRendererTransientStateWithFrameData:(iTermMetalFrameData *)frameData NS_AVAILABLE_MAC(11) {
    if (!_terminalButtonRenderer) {
        return;
    }
    iTermTerminalButtonRendererTransientState *tState = [frameData transientStateForRenderer:_terminalButtonRenderer];

    const long long firstLine = frameData.perFrameState.firstVisibleAbsoluteLineNumber;
    for (iTermTerminalButton *button in frameData.perFrameState.terminalButtons) {
        if (button.absCoord.y < firstLine ||
            button.absCoord.y >= firstLine + frameData.perFrameState.gridSize.height) {
            continue;
        }
        [tState addButton:button
             onScreenLine:button.absCoord.y - firstLine
                   column:button.absCoord.x
          foregroundColor:frameData.perFrameState.processedDefaultTextColor
          backgroundColor:frameData.perFrameState.processedDefaultBackgroundColor
            selectedColor:frameData.perFrameState.selectedBackgroundColor];
    }
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
    tState.computedAlpha = iTermAlphaValueForBottomView(1 - frameData.perFrameState.transparencyAlpha,
                                                        frameData.perFrameState.blend);
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
        useTemporaryTexture = YES;
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
                [self drawCellRenderer:_underlineCursorRenderer
                             frameData:frameData
                                  stat:iTermMetalFrameDataStatPqEnqueueDrawCursor];
                break;
            case CURSOR_BOX:
                // This is a necessary departure from how the cursor is drawn in the legacy renderer.
                // The legacy renderer draws the character over the cursor, but that is way too
                // expensive to do here so instead we draw the cursor before the character and
                // modify the character's color for a single draw.
                if (!cursorInfo.frameOnly) {
                    [self drawCellRenderer:_blockCursorRenderer
                                 frameData:frameData
                                      stat:iTermMetalFrameDataStatPqEnqueueDrawCursor];
                }
                break;
            case CURSOR_VERTICAL:
                [self drawCellRenderer:_barCursorRenderer
                             frameData:frameData
                                  stat:iTermMetalFrameDataStatPqEnqueueDrawCursor];
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
                    if (cursorInfo.cursorShadow) {
                        [self drawCellRenderer:_horizontalShadowCursorRenderer frameData:frameData stat:iTermMetalFrameDataStatPqEnqueueDrawCursor];
                    }
                    break;
                case CURSOR_VERTICAL:
                    if (cursorInfo.cursorShadow) {
                        [self drawCellRenderer:_verticalShadowCursorRenderer frameData:frameData stat:iTermMetalFrameDataStatPqEnqueueDrawCursor];
                    }
                    break;
                case CURSOR_BOX:
                    if (cursorInfo.frameOnly) {
                        [self drawCellRenderer:_frameCursorRenderer
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

    [self drawCellRenderer:_lineStyleMarkRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawMarks];

    [self drawCellRenderer:_arrowStyleMarkRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawMarks];

    [self drawCellRenderer:_blockRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawBlocks];
    
    [self drawRenderer:_badgeRenderer
             frameData:frameData
                  stat:iTermMetalFrameDataStatPqEnqueueBadge];

    [self drawCellRenderer:_broadcastStripesRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueBroadcastStripes];

    [self drawCellRenderer:_cursorGuideRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawCursorGuide];

    [self drawCursorBeforeTextWithFrameData:frameData];

    if (!iTermTextIsMonochrome()) {
        // This is weird but intentional! We draw the offscreen background twice. The first one gets
        // encoded into the background that the second one samples for subpixel AA. Exactly the
        // same renderer is used both times.
        [self drawRenderer:_offscreenCommandLineBackgroundRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueDrawOffscreenCommandLineBgPre];
    }
    
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
            self.needsDrawAfterDuration = MIN(self.needsDrawAfterDuration, 1/60.0);
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
    DLog(@"Finish drawing frameData %@", frameData);
    BOOL shouldCopyToDrawable = YES;

    if (iTermTextIsMonochromeOnMojave()) {
        shouldCopyToDrawable = NO;
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
        DLog(@"  Copy to drawable %@", frameData);
        frameData.currentPass = 2;
        [frameData.renderEncoder endEncoding];

        [self updateRenderEncoderForCurrentPass:frameData label:@"Copy to drawable"];
        [self drawRenderer:_copyToDrawableRenderer
                 frameData:frameData
                      stat:iTermMetalFrameDataStatPqEnqueueCopyToDrawable];
    }
    [frameData measureTimeForStat:iTermMetalFrameDataStatPqEnqueueDrawEndEncodingToDrawable ofBlock:^{
        DLog(@"  endEncoding %@", frameData);
        [frameData.renderEncoder endEncoding];
    }];

    if (frameData.debugInfo) {
        DLog(@"  Copy offscreen texture to drawable %@", frameData);
        [self copyOffscreenTextureToDrawableInFrameData:frameData];
    }
    [frameData measureTimeForStat:iTermMetalFrameDataStatPqEnqueueDrawPresentAndCommit ofBlock:^{
#if !ENABLE_SYNCHRONOUS_PRESENTATION
        if (frameData.destinationDrawable) {
            DLog(@"  presentDrawable %@", frameData);
            [commandBuffer presentDrawable:frameData.destinationDrawable];
        }
#endif

#if ENABLE_STATS
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
#endif
        __block BOOL completed = NO;
        void (^completedBlock)(void) = [^{
            completed = [self didComplete:completed withFrameData:frameData];
        } copy];

        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull buffer) {
#if ENABLE_PRIVATE_QUEUE
            [frameData dispatchToQueue:self->_queue forCompletion:completedBlock];
#else
            [frameData dispatchToQueue:dispatch_get_main_queue() forCompletion:completedBlock];
#endif
        }];

        DLog(@"  commit %@", frameData);
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
        DLog(@"first time completed %@", frameData);
        if (frameData.debugInfo) {
            DLog(@"have debug info %@", frameData);
            if (@available(macOS 10.15, *)) {
                if (frameData.captureDescriptor) {
                    MTLCaptureManager* captureManager = [MTLCaptureManager sharedCaptureManager];
                    [captureManager stopCapture];
                    [frameData.debugInfo addMetalCapture:frameData.captureDescriptor.outputURL];
                }
            }
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
    if (!_offscreenCommandLineTextRenderer.rendererDisabled) {
        iTermTextRendererTransientState *textState = [frameData transientStateForRenderer:_offscreenCommandLineTextRenderer];
        [textState didComplete];
    }
    DLog(@"  Recording final stats");
#if ENABLE_STATS
    [frameData didCompleteWithAggregateStats:_stats
                                  histograms:_statHistograms
                                       owner:_identifier];
#else
    [frameData didCompleteWithAggregateStats:nil
                                  histograms:nil
                                       owner:_identifier];
#endif

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
    return [@[ _marginRenderer,
              _textRenderer,
              _offscreenCommandLineTextRenderer,
              _backgroundColorRenderer,
              _broadcastStripesRenderer,
              _arrowStyleMarkRenderer,
              _lineStyleMarkRenderer,
              _cursorGuideRenderer,
              _highlightRowRenderer,
              _imageRenderer,
              _underlineCursorRenderer,
              _barCursorRenderer,
              _horizontalShadowCursorRenderer,
              _verticalShadowCursorRenderer,
              _imeCursorRenderer,
              _blockCursorRenderer,
              _frameCursorRenderer,
              _copyModeCursorRenderer,
              _keyCursorRenderer,
              _timestampsRenderer,
              _blockRenderer,
              _terminalButtonRenderer ?: [NSNull null]] arrayByRemovingNulls];
}

- (NSArray<id<iTermMetalRenderer>> *)nonCellRenderers {
    NSArray *shared = @[ _backgroundImageRenderer,
                         _offscreenCommandLineBackgroundRenderer,
                         _badgeRenderer,
                         _copyBackgroundRenderer,
                         _indicatorRenderer,
                         _flashRenderer ];

    BOOL useTemporaryTexture;
    if (iTermTextIsMonochrome()) {
        useTemporaryTexture = NO;
    } else {
        useTemporaryTexture = YES;
    }
    
    if (useTemporaryTexture) {
        return [shared arrayByAddingObject:_copyToDrawableRenderer];
    } else {
        return shared;
    }
}

- (void)scheduleDrawIfNeededInView:(MTKView *)view {
    const NSTimeInterval duration = self.needsDrawAfterDuration;
    if (duration < INFINITY) {
        void (^block)(void) = ^{
            if (self.needsDrawAfterDuration < INFINITY) {
                self.needsDrawAfterDuration = INFINITY;
                DLog(@"Calling setNeedsDisplay because of needsDraw");
                [view setNeedsDisplay:YES];
            }
        };
        DLog(@"Schedule redraw after %f ms", duration * 1000);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(duration * NSEC_PER_SEC)),
                       dispatch_get_main_queue(),
                       block);
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
