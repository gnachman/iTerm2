@import simd;
@import MetalKit;

#import "iTermMetalDriver.h"

#import "DebugLogging.h"
#import "iTermASCIITexture.h"
#import "iTermBackgroundImageRenderer.h"
#import "iTermBackgroundColorRenderer.h"
#import "iTermBadgeRenderer.h"
#import "iTermBroadcastStripesRenderer.h"
#import "iTermCopyBackgroundRenderer.h"
#import "iTermCursorGuideRenderer.h"
#import "iTermCursorRenderer.h"
#import "iTermMarginRenderer.h"
#import "iTermMetalFrameData.h"
#import "iTermMarkRenderer.h"
#import "iTermMetalRowData.h"
#import "MovingAverage.h"
#import "iTermPreciseTimer.h"
#import "iTermShaderTypes.h"
#import "iTermTextRenderer.h"
#import "iTermTextureArray.h"
#import "NSMutableData+iTerm.h"

@implementation iTermMetalCursorInfo
@end

@interface iTermMetalDriver()
// This indicates if a draw call was made while busy. When we stop being busy
// and this is set, then we must schedule another draw.
@property (atomic) BOOL needsDraw;
@end

@implementation iTermMetalDriver {
    iTermMarginRenderer *_marginRenderer;
    iTermBackgroundImageRenderer *_backgroundImageRenderer;
    iTermBackgroundColorRenderer *_backgroundColorRenderer;
    iTermTextRenderer *_textRenderer;
    iTermMarkRenderer *_markRenderer;
    iTermBadgeRenderer *_badgeRenderer;
    iTermBroadcastStripesRenderer *_broadcastStripesRenderer;
    iTermCursorGuideRenderer *_cursorGuideRenderer;
    iTermCursorRenderer *_underlineCursorRenderer;
    iTermCursorRenderer *_barCursorRenderer;
    iTermCursorRenderer *_blockCursorRenderer;
    iTermCursorRenderer *_frameCursorRenderer;
    iTermCopyModeCursorRenderer *_copyModeCursorRenderer;
    iTermCopyBackgroundRenderer *_copyBackgroundRenderer;

    // The command Queue from which we'll obtain command buffers
    id<MTLCommandQueue> _commandQueue;

    // The current size of our view so we can use this in our render pipeline
    vector_uint2 _viewportSize;
    CGSize _cellSize;
//    int _iteration;
    int _rows;
    int _columns;
    BOOL _sizeChanged;
    CGFloat _scale;

    dispatch_queue_t _queue;

    iTermPreciseTimerStats _stats[iTermMetalFrameDataStatCount];
    int _dropped;
    int _total;

    // @synchronized(self)
    int _framesInFlight;
    NSMutableArray *_currentFrames;
    NSTimeInterval _startTime;
    MovingAverage *_fpsMovingAverage;
    NSTimeInterval _lastFrameTime;
}

- (nullable instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView {
    self = [super init];
    if (self) {
        _startTime = [NSDate timeIntervalSinceReferenceDate];
        _marginRenderer = [[iTermMarginRenderer alloc] initWithDevice:mtkView.device];
        _backgroundImageRenderer = [[iTermBackgroundImageRenderer alloc] initWithDevice:mtkView.device];
        _textRenderer = [[iTermTextRenderer alloc] initWithDevice:mtkView.device];
        _backgroundColorRenderer = [[iTermBackgroundColorRenderer alloc] initWithDevice:mtkView.device];
        _markRenderer = [[iTermMarkRenderer alloc] initWithDevice:mtkView.device];
        _badgeRenderer = [[iTermBadgeRenderer alloc] initWithDevice:mtkView.device];
        _broadcastStripesRenderer = [[iTermBroadcastStripesRenderer alloc] initWithDevice:mtkView.device];
        _cursorGuideRenderer = [[iTermCursorGuideRenderer alloc] initWithDevice:mtkView.device];
        _underlineCursorRenderer = [iTermCursorRenderer newUnderlineCursorRendererWithDevice:mtkView.device];
        _barCursorRenderer = [iTermCursorRenderer newBarCursorRendererWithDevice:mtkView.device];
        _blockCursorRenderer = [iTermCursorRenderer newBlockCursorRendererWithDevice:mtkView.device];
        _frameCursorRenderer = [iTermCursorRenderer newFrameCursorRendererWithDevice:mtkView.device];
        _copyModeCursorRenderer = [iTermCursorRenderer newCopyModeCursorRendererWithDevice:mtkView.device];
        _copyBackgroundRenderer = [[iTermCopyBackgroundRenderer alloc] initWithDevice:mtkView.device];

        _commandQueue = [mtkView.device newCommandQueue];
        _queue = dispatch_queue_create("com.iterm2.metalDriver", NULL);
        _currentFrames = [NSMutableArray array];
        _fpsMovingAverage = [[MovingAverage alloc] init];
        iTermMetalFrameDataStatsBundleInitialize(_stats);
    }

    return self;
}

#pragma mark - APIs

- (void)setCellSize:(CGSize)cellSize gridSize:(VT100GridSize)gridSize scale:(CGFloat)scale {
    scale = MAX(1, scale);
    cellSize.width *= scale;
    cellSize.height *= scale;
    dispatch_async(_queue, ^{
        if (scale == 0) {
            NSLog(@"Warning: scale is 0");
        }
        NSLog(@"Cell size is now %@x%@, grid size is now %@x%@", @(cellSize.width), @(cellSize.height), @(gridSize.width), @(gridSize.height));
        _sizeChanged = YES;
        _cellSize = cellSize;
        _rows = MAX(1, gridSize.height);
        _columns = MAX(1, gridSize.width);
        _scale = scale;
    });
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
    dispatch_async(_queue, ^{
        // Save the size of the drawable as we'll pass these
        //   values to our vertex shader when we draw
        _viewportSize.x = size.width;
        _viewportSize.y = size.height;
    });
}

// Called whenever the view needs to render a frame
- (void)drawInMTKView:(nonnull MTKView *)view {
    if (_rows == 0 || _columns == 0) {
        DLog(@"  abort: uninitialized");
        [self scheduleDrawIfNeededInView:view];
        return;
    }

    _total++;
    if (_total % 60 == 0) {
        @synchronized (self) {
            NSLog(@"fps=%f (%d in flight)", (_total - _dropped) / ([NSDate timeIntervalSinceReferenceDate] - _startTime), (int)_framesInFlight);
            NSLog(@"%@", _currentFrames);
        }
    }

    iTermMetalFrameData *frameData = [self newFrameDataForView:view];
    if (VT100GridSizeEquals(frameData.gridSize, VT100GridSizeMake(0, 0))) {
        // TODO: Could early exit a lot faster since newFrameDataForView is expensive.
        NSLog(@"  abort: 0x0");
        return;
    }

    BOOL shouldDrop;
    @synchronized(self) {
        shouldDrop = (_framesInFlight == iTermMetalDriverMaximumNumberOfFramesInFlight);
        if (!shouldDrop) {
            _framesInFlight++;
        }
    }
    if (shouldDrop) {
        NSLog(@"  abort: busy (dropped %@%%, number in flight: %d)", @((_dropped * 100)/_total), (int)_framesInFlight);
        @synchronized(self) {
            NSLog(@"  current frames:\n%@", _currentFrames);
        }

        _dropped++;
        self.needsDraw = YES;
        return;
    }

    @synchronized(self) {
        [_currentFrames addObject:frameData];
    }

    [frameData measureTimeForStat:iTermMetalFrameDataStatMtGetCurrentDrawable ofBlock:^{
        frameData.drawable = view.currentDrawable;
    }];

    [frameData measureTimeForStat:iTermMetalFrameDataStatMtGetRenderPassDescriptor ofBlock:^{
        frameData.renderPassDescriptor = view.currentRenderPassDescriptor;
    }];


    [frameData dispatchToPrivateQueue:_queue forPreparation:^{
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (_lastFrameTime) {
            [_fpsMovingAverage addValue:now - _lastFrameTime];
        }
        _lastFrameTime = now;

        [self performPrivateQueueSetupForFrameData:frameData view:view];
    }];
}

#pragma mark - Drawing

// Called on the main queue
- (iTermMetalFrameData *)newFrameDataForView:(MTKView *)view {
    iTermMetalFrameData *frameData = [[iTermMetalFrameData alloc] initWithView:view];

    [frameData measureTimeForStat:iTermMetalFrameDataStatMtExtractFromApp ofBlock:^{
        frameData.viewportSize = _viewportSize;

        // This is the slow part
        frameData.perFrameState = [_dataSource metalDriverWillBeginDrawingFrame];

        frameData.transientStates = [NSMutableDictionary dictionary];
        frameData.rows = [NSMutableArray array];
        frameData.gridSize = frameData.perFrameState.gridSize;
        frameData.scale = _scale;
    }];
    return frameData;
}

// Runs in private queue
- (void)performPrivateQueueSetupForFrameData:(iTermMetalFrameData *)frameData
                                        view:(nonnull MTKView *)view {
    // Get glyph keys, attributes, background colors, etc. from datasource.
    [frameData measureTimeForStat:iTermMetalFrameDataStatPqBuildRowData ofBlock:^{
        [self addRowDataToFrameData:frameData];
    }];

    // Set properties of the renderers for values that tend not to change very often and which
    // are used to create transient states. This must happen before creating transient states
    // since renderers use this info to decide if they should return a nil transient state.
    [frameData measureTimeForStat:iTermMetalFrameDataStatPqUpdateRenderers ofBlock:^{
        [self updateRenderersForNewFrameData:frameData];
    }];

    // Create each renderer's transient state, which its per-frame object.
    __block id<MTLCommandBuffer> commandBuffer;
    [frameData measureTimeForStat:iTermMetalFrameDataStatPqCreateTransientStates ofBlock:^{
        commandBuffer = [_commandQueue commandBuffer];
        [self createTransientStatesWithFrameData:frameData view:view commandBuffer:commandBuffer];
    }];

    // Copy state from frame data to transient states
    [frameData measureTimeForStat:iTermMetalFrameDataStatPqPopulateTransientStates ofBlock:^{
        [self populateTransientStatesWithFrameData:frameData range:NSMakeRange(0, frameData.rows.count)];
    }];

    // Return to main queue and enqueue draw calls into command buffer.
    [frameData dispatchToMainQueue:^{
        [self finishInMainQueueWithFrameData:frameData
                                        view:view
                               commandBuffer:commandBuffer];
    }];
}

// Runs in main queue
- (void)finishInMainQueueWithFrameData:(iTermMetalFrameData *)frameData
                                  view:(MTKView *)view
                         commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    [frameData measureTimeForStat:iTermMetalFrameDataStatMtEnqueueDrawCalls ofBlock:^{
        [self drawIfPossibleInView:view
                         frameData:frameData
                     commandBuffer:commandBuffer
              renderPassDescriptor:frameData.renderPassDescriptor
                          drawable:frameData.drawable];
    }];
    [frameData willHandOffToGPU];
}

- (void)updateRenderersForNewFrameData:(iTermMetalFrameData *)frameData {
    __weak __typeof(self) weakSelf = self;
    CGSize cellSize = _cellSize;
    CGFloat scale = _scale;
    [_textRenderer setASCIICellSize:_cellSize
                 creationIdentifier:[frameData.perFrameState metalASCIICreationIdentifier]
                           creation:^NSDictionary<NSNumber *, iTermCharacterBitmap *> * _Nonnull(char c, iTermASCIITextureAttributes attributes) {
                               __typeof(self) strongSelf = weakSelf;
                               if (strongSelf) {
                                   static const int typefaceMask = ((1 << iTermMetalGlyphKeyTypefaceNumberOfBitsNeeded) - 1);
                                   iTermMetalGlyphKey glyphKey = {
                                       .code = c,
                                       .isComplex = NO,
                                       .image = NO,
                                       .boxDrawing = NO,
                                       .thinStrokes = !!(attributes & iTermASCIITextureAttributesThinStrokes),
                                       .drawable = YES,
                                       .typeface = (attributes & typefaceMask),
                                   };
                                   BOOL emoji = NO;
                                   return [frameData.perFrameState metalImagesForGlyphKey:&glyphKey
                                                                                     size:cellSize
                                                                                    scale:scale
                                                                                    emoji:&emoji];
                               } else {
                                   return nil;
                               }
                           }];
    CGFloat blending;
    BOOL tiled;
    NSImage *backgroundImage = [frameData.perFrameState metalBackgroundImageGetBlending:&blending tiled:&tiled];
    [_backgroundImageRenderer setImage:backgroundImage blending:blending tiled:tiled];

    // TODO: Badges and background stripes would also control this.
    _copyBackgroundRenderer.enabled = (backgroundImage != nil);
}

- (void)createTransientStatesWithFrameData:(iTermMetalFrameData *)frameData
                                      view:(nonnull MTKView *)view
                             commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    iTermRenderConfiguration *configuration = [[iTermRenderConfiguration alloc] initWithViewportSize:_viewportSize scale:frameData.scale];

    [commandBuffer enqueue];
    commandBuffer.label = @"Draw Terminal";
    for (id<iTermMetalRenderer> renderer in self.nonCellRenderers) {
        [frameData measureTimeForStat:renderer.createTransientStateStat ofBlock:^{
            __kindof iTermMetalRendererTransientState * _Nonnull tState =
            [renderer createTransientStateForConfiguration:configuration
                                             commandBuffer:commandBuffer];
            if (tState) {
                frameData.transientStates[NSStringFromClass(renderer.class)] = tState;
                [self updateRenderer:renderer
                               state:tState
                           frameData:frameData];
            }
        }];
    };
    VT100GridSize gridSize = frameData.gridSize;

    if (_backgroundImageRenderer.image != nil) {
        // We need frameData's intermediateRenderPassDescriptor to be initialized before creating
        // tstate's for subsequent objects. This assertion is there to make sure the tState exists,
        // with the assumption its IRPD is set prior to creation if it should exist.
        assert(frameData.transientStates[NSStringFromClass(_backgroundImageRenderer.class)]);
    }

    iTermCellRenderConfiguration *cellConfiguration = [[iTermCellRenderConfiguration alloc] initWithViewportSize:_viewportSize
                                                                                                           scale:frameData.scale
                                                                                                        cellSize:_cellSize
                                                                                                        gridSize:gridSize
                                                                                           usingIntermediatePass:(frameData.intermediateRenderPassDescriptor != nil)];
    for (id<iTermMetalCellRenderer> renderer in self.cellRenderers) {
        [frameData measureTimeForStat:renderer.createTransientStateStat ofBlock:^{
            __kindof iTermMetalCellRendererTransientState * _Nonnull tState =
                [renderer createTransientStateForCellConfiguration:cellConfiguration
                                                     commandBuffer:commandBuffer];
            if (tState) {
                frameData.transientStates[NSStringFromClass([renderer class])] = tState;
                [self updateRenderer:renderer
                               state:tState
                           frameData:frameData];
            }
        }];
    };
}

- (void)addRowDataToFrameData:(iTermMetalFrameData *)frameData {
    for (int y = 0; y < frameData.gridSize.height; y++) {
        iTermMetalRowData *rowData = [[iTermMetalRowData alloc] init];
        [frameData.rows addObject:rowData];
        rowData.y = y;
        rowData.keysData = [NSMutableData uninitializedDataWithLength:sizeof(iTermMetalGlyphKey) * _columns];
        rowData.attributesData = [NSMutableData uninitializedDataWithLength:sizeof(iTermMetalGlyphAttributes) * _columns];
        rowData.backgroundColorRLEData = [NSMutableData uninitializedDataWithLength:sizeof(iTermMetalBackgroundColorRLE) * _columns];
        iTermMetalGlyphKey *glyphKeys = (iTermMetalGlyphKey *)rowData.keysData.mutableBytes;
        int drawableGlyphs = 0;
        int rles = 0;
        [frameData.perFrameState metalGetGlyphKeys:glyphKeys
                                        attributes:rowData.attributesData.mutableBytes
                                        background:rowData.backgroundColorRLEData.mutableBytes
                                          rleCount:&rles
                                               row:y
                                             width:_columns
                                    drawableGlyphs:&drawableGlyphs];
        rowData.numberOfBackgroundRLEs = rles;
        rowData.numberOfDrawableGlyphs = drawableGlyphs;
    }
}

- (void)drawIfPossibleInView:(MTKView *)view
                   frameData:(iTermMetalFrameData *)frameData
               commandBuffer:(id<MTLCommandBuffer>)commandBuffer
        renderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor
                    drawable:(id<CAMetalDrawable>)drawable {
    DLog(@"  Really drawing");

    BOOL ok = YES;
    if (drawable == nil) {
        frameData.status = @"nil currentDrawable";
        ok = NO;
    }
    if (renderPassDescriptor == nil) {
        frameData.status = @"nil renderPassDescriptor";
        ok = NO;
    }
    if (!ok) {
        [commandBuffer commit];
        [self complete:frameData];
        NSLog(@"** DRAW FAILED: %@", frameData);
        return;
    }
    drawable.texture.label = @"Drawable";
    [self drawWithDrawable:drawable
      renderPassDescriptor:renderPassDescriptor
                 frameData:frameData
             commandBuffer:commandBuffer];
}

- (void)finalizeCopyBackgroundRendererWithFrameData:(iTermMetalFrameData *)frameData {
    // Copy state
    iTermCopyBackgroundRendererTransientState *copyState =
        frameData.transientStates[NSStringFromClass([_copyBackgroundRenderer class])];
    copyState.sourceTexture = frameData.intermediateRenderPassDescriptor.colorAttachments[0].texture;
}

- (void)finalizeCursorRendererWithFrameData:(iTermMetalFrameData *)frameData {
    // Update glyph attributes for block cursor if needed.
    iTermMetalCursorInfo *cursorInfo = [frameData.perFrameState metalDriverCursorInfo];
#warning TODO Why is the cursor sometimes equal to grid height?
    if (!cursorInfo.frameOnly && cursorInfo.cursorVisible && cursorInfo.shouldDrawText && cursorInfo.coord.y >= 0 && cursorInfo.coord.y < frameData.gridSize.height) {
        iTermMetalRowData *rowWithCursor = frameData.rows[cursorInfo.coord.y];
        iTermMetalGlyphAttributes *glyphAttributes = (iTermMetalGlyphAttributes *)rowWithCursor.attributesData.mutableBytes;
        glyphAttributes[cursorInfo.coord.x].foregroundColor = cursorInfo.textColor;
        glyphAttributes[cursorInfo.coord.x].backgroundColor = simd_make_float4(cursorInfo.cursorColor.redComponent,
                                                                               cursorInfo.cursorColor.greenComponent,
                                                                               cursorInfo.cursorColor.blueComponent,
                                                                               1);
    }
}

- (NSInteger)finalizeTextAndBackgroundRenderersWithFrameData:(iTermMetalFrameData *)frameData {
    // Update the text renderer's transient state with current glyphs and colors.
    CGFloat scale = frameData.scale;
    iTermTextRendererTransientState *textState =
    frameData.transientStates[NSStringFromClass([_textRenderer class])];

    // Set the background texture if one is available.
    textState.backgroundTexture = frameData.intermediateRenderPassDescriptor.colorAttachments[0].texture;

    // Configure underlines
    iTermMetalUnderlineDescriptor asciiUnderlineDescriptor;
    iTermMetalUnderlineDescriptor nonAsciiUnderlineDescriptor;
    [frameData.perFrameState metalGetUnderlineDescriptorsForASCII:&asciiUnderlineDescriptor
                                                         nonASCII:&nonAsciiUnderlineDescriptor];
    textState.asciiUnderlineDescriptor = asciiUnderlineDescriptor;
    textState.nonAsciiUnderlineDescriptor = nonAsciiUnderlineDescriptor;
    textState.defaultBackgroundColor = frameData.perFrameState.defaultBackgroundColor;
    
    CGSize cellSize = textState.cellConfiguration.cellSize;
    iTermBackgroundColorRendererTransientState *backgroundState =
    frameData.transientStates[NSStringFromClass([_backgroundColorRenderer class])];
    __block NSUInteger numberOfRows = 0;
    [frameData.rows enumerateObjectsUsingBlock:^(iTermMetalRowData * _Nonnull rowData, NSUInteger idx, BOOL * _Nonnull stop) {
        iTermMetalGlyphKey *glyphKeys = (iTermMetalGlyphKey *)rowData.keysData.mutableBytes;
#if ENABLE_ONSCREEN_STATS
        if (idx == 0) {
            iTermMetalGlyphAttributes *attributes = (iTermMetalGlyphAttributes *)rowData.attributesData.bytes;
            char frame[80];
            sprintf(frame, sizeof(frame) - 1, "Frame %d, %d fps", (int)frameData.frameNumber, (int)(1.0 / [_fpsMovingAverage value]));
            for (int i = 0; frame[i]; i++) {
                glyphKeys[i].code = frame[i];
                glyphKeys[i].isComplex = NO;
                glyphKeys[i].image = NO;
                glyphKeys[i].drawable = YES;
                glyphKeys[i].typeface = iTermMetalGlyphKeyTypefaceRegular;

                attributes[i].backgroundColor = simd_make_float4(1.0, 0.0, 0.0, 1.0);
                attributes[i].foregroundColor = simd_make_float4(1.0, 1.0, 1.0, 1.0);
                attributes[i].underlineStyle = iTermMetalGlyphAttributesUnderlineNone;
            }
        }
#endif

        [textState setGlyphKeysData:rowData.keysData
                              count:rowData.numberOfDrawableGlyphs
                     attributesData:rowData.attributesData
                                row:rowData.y
             backgroundColorRLEData:rowData.backgroundColorRLEData
                           creation:^NSDictionary<NSNumber *, iTermCharacterBitmap *> * _Nonnull(int x, BOOL *emoji) {
                               return [frameData.perFrameState metalImagesForGlyphKey:&glyphKeys[x]
                                                                                 size:cellSize
                                                                                scale:scale
                                                                                emoji:emoji];
                           }];
        [backgroundState setColorRLEs:(const iTermMetalBackgroundColorRLE *)rowData.backgroundColorRLEData.bytes
                                count:rowData.numberOfBackgroundRLEs
                                  row:rowData.y
                                width:frameData.gridSize.width];
        numberOfRows++;
    }];

    // Tell the text state that it's done getting row data.
    [textState willDraw];
    return numberOfRows;
}

// Called when all renderers have transient state
- (void)populateTransientStatesWithFrameData:(iTermMetalFrameData *)frameData
                                       range:(NSRange)range {
    // TODO: call setMarkStyle:row: for each mark

    [self finalizeCopyBackgroundRendererWithFrameData:frameData];
    [self finalizeCursorRendererWithFrameData:frameData];
    [self finalizeTextAndBackgroundRenderersWithFrameData:frameData];
}

- (void)drawRenderer:(id<iTermMetalRenderer>)renderer
           frameData:(iTermMetalFrameData *)frameData
       renderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
                stat:(iTermPreciseTimerStats *)stat {
    iTermPreciseTimerStatsStartTimer(stat);

    NSString *className = NSStringFromClass([renderer class]);
    iTermMetalRendererTransientState *state = frameData.transientStates[className];
    // NOTE: State may be nil if we determined it should be skipped early on.
    if (state != nil && !state.skipRenderer) {
        [renderer drawWithRenderEncoder:renderEncoder transientState:state];
    }

    iTermPreciseTimerStatsMeasureAndRecordTimer(stat);
}

- (void)drawCellRenderer:(id<iTermMetalCellRenderer>)renderer
               frameData:(iTermMetalFrameData *)frameData
           renderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
                    stat:(iTermPreciseTimerStats *)stat {
    iTermPreciseTimerStatsStartTimer(stat);

    NSString *className = NSStringFromClass([renderer class]);
    iTermMetalCellRendererTransientState *state = frameData.transientStates[className];
    ITDebugAssert(state);
    if (!state.skipRenderer) {
        [renderer drawWithRenderEncoder:renderEncoder transientState:state];
    }

    iTermPreciseTimerStatsMeasureAndRecordTimer(stat);
}

- (void)drawContentBehindTextWithFrameData:(iTermMetalFrameData *)frameData renderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder {
    [self drawCellRenderer:_marginRenderer
                 frameData:frameData
             renderEncoder:renderEncoder
                      stat:&frameData.stats[iTermMetalFrameDataStatMtEnqueueDrawMargin]];

    [self drawRenderer:_backgroundImageRenderer
             frameData:frameData
         renderEncoder:renderEncoder
                  stat:&frameData.stats[iTermMetalFrameDataStatMtEnqueueDrawBackgroundImage]];

    [self drawCellRenderer:_backgroundColorRenderer
                 frameData:frameData
             renderEncoder:renderEncoder
                      stat:&frameData.stats[iTermMetalFrameDataStatMtEnqueueDrawBackgroundColor]];

    //        [_broadcastStripesRenderer drawWithRenderEncoder:renderEncoder];
    //        [_badgeRenderer drawWithRenderEncoder:renderEncoder];
    //        [_cursorGuideRenderer drawWithRenderEncoder:renderEncoder];
    //

    iTermMetalCursorInfo *cursorInfo = [frameData.perFrameState metalDriverCursorInfo];
    if (cursorInfo.cursorVisible) {
        switch (cursorInfo.type) {
            case CURSOR_UNDERLINE:
                [self drawCellRenderer:_underlineCursorRenderer
                             frameData:frameData
                         renderEncoder:renderEncoder
                                  stat:&frameData.stats[iTermMetalFrameDataStatMtEnqueueDrawCursor]];
                break;
            case CURSOR_BOX:
                if (cursorInfo.frameOnly) {
                    [self drawCellRenderer:_frameCursorRenderer
                                 frameData:frameData
                             renderEncoder:renderEncoder
                                      stat:&frameData.stats[iTermMetalFrameDataStatMtEnqueueDrawCursor]];
                } else {
                    [self drawCellRenderer:_blockCursorRenderer
                                 frameData:frameData
                             renderEncoder:renderEncoder
                                      stat:&frameData.stats[iTermMetalFrameDataStatMtEnqueueDrawCursor]];
                }
                break;
            case CURSOR_VERTICAL:
                [self drawCellRenderer:_barCursorRenderer
                             frameData:frameData
                         renderEncoder:renderEncoder
                                  stat:&frameData.stats[iTermMetalFrameDataStatMtEnqueueDrawCursor]];
                break;
            case CURSOR_DEFAULT:
                break;
        }
    }

    //        [_copyModeCursorRenderer drawWithRenderEncoder:renderEncoder];

    if (frameData.intermediateRenderPassDescriptor) {
        [frameData measureTimeForStat:iTermMetalFrameDataStatMtEnqueueDrawEndEncodingToIntermediateTexture ofBlock:^{
            [renderEncoder endEncoding];
        }];
    }
}

- (void)finishDrawingWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                              drawable:(id<CAMetalDrawable>)drawable
                             frameData:(iTermMetalFrameData *)frameData
                         renderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder {
    [frameData measureTimeForStat:iTermMetalFrameDataStatMtEnqueueDrawEndEncodingToDrawable ofBlock:^{
        [renderEncoder endEncoding];
    }];
    [frameData measureTimeForStat:iTermMetalFrameDataStatMtEnqueueDrawPresentAndCommit ofBlock:^{
        [commandBuffer presentDrawable:drawable];

        int counter;
        static int nextCounter;
        counter = nextCounter++;
        __block BOOL completed = NO;

        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull buffer) {
            frameData.status = @"completion handler, waiting for dispatch";
            dispatch_async(_queue, ^{
                frameData.status = @"completion handler on main queue";
                if (!completed) {
                    completed = YES;
                    [self complete:frameData];
                    [self scheduleDrawIfNeededInView:frameData.view];

                    __weak __typeof(self) weakSelf = self;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [weakSelf.dataSource metalDriverDidDrawFrame];
                    });
                }
            });
        }];

        [commandBuffer commit];
    }];
}

- (void)drawWithDrawable:(id<CAMetalDrawable>)drawable
    renderPassDescriptor:(MTLRenderPassDescriptor *)viewRenderPassDescriptor
               frameData:(iTermMetalFrameData *)frameData
           commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    MTLRenderPassDescriptor *renderPassDescriptor = frameData.intermediateRenderPassDescriptor ?: viewRenderPassDescriptor;
    if (!renderPassDescriptor) {
        frameData.status = @"failed to get a render pass descriptor";
        [commandBuffer commit];
        [self complete:frameData];
        return;
    }

    NSString *label = frameData.intermediateRenderPassDescriptor ? @"Render background to intermediate" : @"Render All Layers of Terminal";;
    id<MTLRenderCommandEncoder> renderEncoder;
    renderEncoder = [self newRenderEncoderFromCommandBuffer:commandBuffer
                                       renderPassDescriptor:renderPassDescriptor
                                                      label:label
                                                  frameData:frameData
                                                       stat:iTermMetalFrameDataStatMtEnqueueDrawCreateFirstRenderEncoder];

    [self drawContentBehindTextWithFrameData:frameData renderEncoder:renderEncoder];

    renderPassDescriptor = viewRenderPassDescriptor;

    // If we're using an intermediate render pass, copy from it to the view for final steps.
    if (frameData.intermediateRenderPassDescriptor) {
        renderEncoder = [self newRenderEncoderFromCommandBuffer:commandBuffer
                                           renderPassDescriptor:viewRenderPassDescriptor
                                                          label:@"Copy bg and render text"
                                                      frameData:frameData
                                                           stat:iTermMetalFrameDataStatMtEnqueueDrawCreateSecondRenderEncoder];
        [self drawRenderer:_copyBackgroundRenderer
                 frameData:frameData
             renderEncoder:renderEncoder
                      stat:&frameData.stats[iTermMetalFrameDataStatMtEnqueueCopyBackground]];
    }

    [self drawCellRenderer:_textRenderer
                 frameData:frameData
             renderEncoder:renderEncoder
                      stat:&frameData.stats[iTermMetalFrameDataStatMtEnqueueDrawText]];

    //        [_markRenderer drawWithRenderEncoder:renderEncoder];

    [self finishDrawingWithCommandBuffer:commandBuffer drawable:drawable frameData:frameData renderEncoder:renderEncoder];
}

- (id<MTLRenderCommandEncoder>)newRenderEncoderFromCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                            renderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor
                                                           label:(NSString *)label
                                                       frameData:(iTermMetalFrameData *)frameData
                                                            stat:(iTermMetalFrameDataStat)stat {
    __block id<MTLRenderCommandEncoder> renderEncoder;
    [frameData measureTimeForStat:stat ofBlock:^{
        renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = label;

        // Set the region of the drawable to which we'll draw.
        MTLViewport viewport = {
            -(double)frameData.viewportSize.x,
            0.0,
            frameData.viewportSize.x * 2,
            frameData.viewportSize.y * 2,
            -1.0,
            1.0
        };
        [renderEncoder setViewport:viewport];
    }];

    return renderEncoder;
}

- (void)complete:(iTermMetalFrameData *)frameData {
    DLog(@"  Completed");

    // Unlock indices and free up the stage texture.
    iTermTextRendererTransientState *textState =
        frameData.transientStates[NSStringFromClass([_textRenderer class])];
    [textState didComplete];

    iTermBackgroundImageRendererTransientState *backgroundImageState = frameData.transientStates[NSStringFromClass([_backgroundImageRenderer class])];
    if (backgroundImageState != nil && !backgroundImageState.skipRenderer) {
        [_backgroundImageRenderer didFinishWithTransientState:backgroundImageState];
    }

    DLog(@"  Recording final stats");
    [frameData didCompleteWithAggregateStats:_stats];

    @synchronized(self) {
        _framesInFlight--;
        @synchronized(self) {
            frameData.status = @"retired";
            [_currentFrames removeObject:frameData];
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self scheduleDrawIfNeededInView:frameData.view];
    });
}

#pragma mark - Updating

- (void)updateRenderer:(id)renderer
                 state:(__kindof iTermMetalRendererTransientState *)tState
             frameData:(iTermMetalFrameData *)frameData {
    id<iTermMetalDriverDataSourcePerFrameState> perFrameState = frameData.perFrameState;
    
    if (renderer == _backgroundImageRenderer) {
        [self updateBackgroundImageRendererWithTransientState:tState withFrameData:frameData];
    } else if (renderer == _backgroundColorRenderer ||
               renderer == _textRenderer ||
               renderer == _markRenderer ||
               renderer == _broadcastStripesRenderer) {
        // Nothing to do here
    } else if (renderer == _marginRenderer) {
        [self updateMarginRendererWithTransientState:tState
                                       perFrameState:perFrameState];
    } else if (renderer == _badgeRenderer) {
        [self updateBadgeRendererWithPerFrameState:perFrameState];
    } else if (renderer == _cursorGuideRenderer) {
        [self updateCursorGuideRendererWithPerFrameState:perFrameState];
    } else if (renderer == _underlineCursorRenderer ||
               renderer == _barCursorRenderer ||
               renderer == _blockCursorRenderer ||
               renderer == _frameCursorRenderer ||
               renderer == _copyBackgroundRenderer) {
        [self updateCursorRendererWithPerFrameState:perFrameState];
    } else if (renderer == _copyModeCursorRenderer) {
        [self updateCopyModeCursorRendererWithPerFrameState:perFrameState];
    }
}

- (void)updateMarginRendererWithTransientState:(iTermMarginRendererTransientState *)marginState
                                 perFrameState:(id<iTermMetalDriverDataSourcePerFrameState>)perFrameState {
    [marginState setColor:perFrameState.defaultBackgroundColor];
}

- (void)updateBackgroundImageRendererWithTransientState:(iTermBackgroundImageRendererTransientState *)tState
                                          withFrameData:(iTermMetalFrameData *)frameData {
    // TODO: Change the image if needed
    frameData.intermediateRenderPassDescriptor = tState.intermediateRenderPassDescriptor;
}

- (void)updateBadgeRendererWithPerFrameState:(id<iTermMetalDriverDataSourcePerFrameState>)perFrameState {
    // TODO: call setBadgeImage: if needed
}

- (void)updateCursorGuideRendererWithPerFrameState:(id<iTermMetalDriverDataSourcePerFrameState>)perFrameState {
    // TODO:
    // [_cursorGuideRenderer setRow:_dataSource.cursorGuideRow];
    // [_cursorGuideRenderer setColor:_dataSource.cursorGuideColor];
}

- (void)updateCursorRendererWithPerFrameState:(id<iTermMetalDriverDataSourcePerFrameState>)perFrameState {
#warning TODO: I think it's a bug to modify a renderer here. Only the transient state should be changed.
    iTermMetalCursorInfo *cursorInfo = [perFrameState metalDriverCursorInfo];
    if (cursorInfo.cursorVisible) {
        switch (cursorInfo.type) {
            case CURSOR_UNDERLINE:
                [_underlineCursorRenderer setCoord:cursorInfo.coord];
                [_underlineCursorRenderer setColor:cursorInfo.cursorColor];
                break;
            case CURSOR_BOX:
                [_blockCursorRenderer setCoord:cursorInfo.coord];
                [_blockCursorRenderer setColor:cursorInfo.cursorColor];
                [_frameCursorRenderer setCoord:cursorInfo.coord];
                [_frameCursorRenderer setColor:cursorInfo.cursorColor];
                break;
            case CURSOR_VERTICAL:
                [_barCursorRenderer setCoord:cursorInfo.coord];
                [_barCursorRenderer setColor:cursorInfo.cursorColor];
                break;
            case CURSOR_DEFAULT:
                break;
        }
    }
}

- (void)updateCopyModeCursorRendererWithPerFrameState:(id<iTermMetalDriverDataSourcePerFrameState>)perFrameState {
    // TODO
    // setCoord, setSelecting:
}

#pragma mark - Helpers

- (NSArray<id<iTermMetalCellRenderer>> *)cellRenderers {
    return @[ _marginRenderer,
              _textRenderer,
              _backgroundColorRenderer,
              _markRenderer,
              _cursorGuideRenderer,
              _underlineCursorRenderer,
              _barCursorRenderer,
              _blockCursorRenderer,
              _frameCursorRenderer,
              _copyModeCursorRenderer ];
}

- (NSArray<id<iTermMetalRenderer>> *)nonCellRenderers {
    return @[ _backgroundImageRenderer,
              _badgeRenderer,
              _broadcastStripesRenderer,
              _copyBackgroundRenderer ];
}

- (void)scheduleDrawIfNeededInView:(MTKView *)view {
    if (self.needsDraw) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.needsDraw) {
                self.needsDraw = NO;
                [view setNeedsDisplay:YES];
            }
        });
    }
}

@end

