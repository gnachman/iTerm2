//
//  iTermMetalFrameData.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/27/17.
//

#import "iTermMetalFrameData.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermHistogram.h"
#import "iTermMetalCellRenderer.h"
#import "iTermMetalRenderer.h"
#import "iTermTexture.h"
#import "iTermTexturePool.h"
#import "NSArray+iTerm.h"

#import <MetalKit/MetalKit.h>

static NSMutableDictionary *sHistograms;

void iTermMetalFrameDataStatsBundleInitialize(iTermPreciseTimerStats *bundle) {
    iTermPreciseTimerSetEnabled(YES);

    const char *names[iTermMetalFrameDataStatCount] = {
        "endToEnd",

        "gpu<",
        "scheduleWait<<",
        "dispatchToPQ2<<",

        "cpu<",

        "mainQueue<<",
        "ExtractFromApp<<<",
        "GetDrawable<<<",
        "GetRenderPassD<<<",
        "dispatchToPQ<<<",

        "privateQueue<<",
        "BuildRowData<<<",
        "BuildIntermed<<<",
        "BuildTemp<<<",
        "UpdateRenderers<<<",

        "CreateTransient<<<",
        "badge<<<<",
        "backgroundImage<<<<",
        "backgroundColor<<<<",
        "cursorGuide<<<<",
        "highlightRow<<<<",
        "image<<<<",
        "bcastStripes<<<<",
        "copyBackground<<<<",
        "mark<<<<",
        "cursor<<<<",
        "margin<<<<",
        "text<<<<",
        "indicators<<<<",
        "timestamps<<<<",
        "flash<<<<",
        "corner<<<<",

        "PopulateTrans<<<",
        "dispatchToMain<<<",

        "EnqueueDrawCalls<<<",
        "Create1stRE<<<<",
        "DrawMargin<<<<",
        "DrawBgImage<<<<",
        "DrawBgColor<<<<",
        "DrawStripes<<<<",
        "DrawBadge<<<<",
        "DrawCursor<<<<",
        "DrawMarks<<<<",
        "DrawCrGuide<<<<",
        "DrawHighlite<<<<",
        "DrawImage<<<<",
        "EndEncodingInt<<<<",
        "Create2ndRE<<<<",
        "enqueueCopyBg<<<<",
        "enqueueDrawText<<<<",
        "DrawIndicators<<<<",
        "DrawTimestamps<<<<",
        "DrawFlash<<<<",
        "DrawCorners<<<<",
        "Create3rdRE<<<<",
        "SyncGetDrawable<<<<",
        "enqueueCopyToDr<<<<",
        "EndEncDrawable<<<<",
        "PresentCommit<<<<",
    };

    for (int i = 0; i < iTermMetalFrameDataStatCount; i++) {
        iTermPreciseTimerStatsInit(&bundle[i], names[i]);
    }
}

static NSInteger gNextFrameDataNumber;

@interface iTermMetalFrameData()
@property (readonly, strong) NSMutableDictionary<NSString *, __kindof iTermMetalRendererTransientState *> *transientStates;
@property (atomic, strong, readwrite) MTKView *view;
@end

@implementation iTermMetalFrameData {
    NSTimeInterval _creation;
    iTermPreciseTimerStats _stats[iTermMetalFrameDataStatCount];
    iTermCellRenderConfiguration *_cellConfiguration;
}

- (instancetype)initWithView:(MTKView *)view fullSizeTexturePool:(iTermTexturePool *)fullSizeTexturePool {
    self = [super init];
    if (self) {
        _view = view;
        _fullSizeTexturePool = fullSizeTexturePool;
        _device = view.device;
        _creation = [NSDate timeIntervalSinceReferenceDate];
        _frameNumber = gNextFrameDataNumber++;
        _framePoolContext = [[iTermMetalBufferPoolContext alloc] init];
        _transientStates = [NSMutableDictionary dictionary];
        iTermMetalFrameDataStatsBundleInitialize(_stats);
        _statHistograms = [[NSArray sequenceWithRange:NSMakeRange(0, iTermMetalFrameDataStatCount)] mapWithBlock:^id(NSNumber *anObject) {
            return [[iTermHistogram alloc] init];
        }];
        iTermPreciseTimerStatsStartTimer(&_stats[iTermMetalFrameDataStatEndToEnd]);
        iTermPreciseTimerStatsStartTimer(&_stats[iTermMetalFrameDataStatCPU]);
        iTermPreciseTimerStatsStartTimer(&_stats[iTermMetalFrameDataStatMainQueueTotal]);
        self.status = @"just created";
    }
    return self;
}

- (NSString *)description {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    return [NSString stringWithFormat:@"<%@: %p age=%f frameNumber=%@/%@ status=%@>",
            self.class,
            self,
            now - _creation,
            @(_frameNumber),
            @(gNextFrameDataNumber),
            self.status];
}

- (void)setRenderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor {
    _renderPassDescriptor = renderPassDescriptor;
    [_debugInfo setRenderPassDescriptor:renderPassDescriptor];
}

- (NSTimeInterval)measureTimeForStat:(iTermMetalFrameDataStat)stat ofBlock:(void (^)(void))block {
    if (stat == iTermMetalFrameDataStatNA) {
        block();
        return 0;
    }
    
    self.status = [NSString stringWithUTF8String:_stats[stat].name];
    iTermPreciseTimerStatsStartTimer(&_stats[stat]);
    block();
    const double duration = iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[stat]);
    [_statHistograms[stat] addValue:duration * 1000];
    return duration;
}

- (void)extractStateFromAppInBlock:(void (^)(void))block {
    iTermPreciseTimerStatsStartTimer(&_stats[iTermMetalFrameDataStatMtExtractFromApp]);
    block();
    const double duration = iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[iTermMetalFrameDataStatMtExtractFromApp]);
    [_statHistograms[iTermMetalFrameDataStatMtExtractFromApp] addValue:duration * 1000];
}

- (void)dispatchToPrivateQueue:(dispatch_queue_t)queue forPreparation:(void (^)(void))block {
    const double duration = iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[iTermMetalFrameDataStatMainQueueTotal]);
    [_statHistograms[iTermMetalFrameDataStatMainQueueTotal] addValue:duration * 1000];

    iTermPreciseTimerStatsStartTimer(&_stats[iTermMetalFrameDataStatDispatchToPrivateQueue]);
    dispatch_async(queue, ^{
        iTermPreciseTimerStatsStartTimer(&self->_stats[iTermMetalFrameDataStatPrivateQueueTotal]);
        const double duration = iTermPreciseTimerStatsMeasureAndRecordTimer(&self->_stats[iTermMetalFrameDataStatDispatchToPrivateQueue]);
        [self->_statHistograms[iTermMetalFrameDataStatPrivateQueueTotal] addValue:duration * 1000];

        block();
    });
}

- (void)dispatchToMainQueueForDrawing:(void (^)(void))block {
    iTermPreciseTimerStatsStartTimer(&_stats[iTermMetalFrameDataStatDispatchToMainQueue]);
    dispatch_async(dispatch_get_main_queue(), ^{
        const double duration = iTermPreciseTimerStatsMeasureAndRecordTimer(&self->_stats[iTermMetalFrameDataStatDispatchToMainQueue]);
        [self->_statHistograms[iTermMetalFrameDataStatDispatchToMainQueue] addValue:duration * 1000];

        block();
    });
}

- (void)dispatchToQueue:(dispatch_queue_t)queue forCompletion:(void (^)(void))block {
    self.status = @"completion handler, waiting for dispatch";
    iTermPreciseTimerStatsStartTimer(&_stats[iTermMetalFrameDataStatDispatchToPrivateQueueForCompletion]);
    dispatch_async(queue, ^{
        self.status = @"completion handler on private queue";
        const double duration = iTermPreciseTimerStatsMeasureAndRecordTimer(&self->_stats[iTermMetalFrameDataStatDispatchToPrivateQueueForCompletion]);
        [self->_statHistograms[iTermMetalFrameDataStatDispatchToPrivateQueueForCompletion] addValue:duration * 1000];
        block();
    });
}

- (void)willHandOffToGPU {
    double duration;
    duration = iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[iTermMetalFrameDataStatCPU]);
    [_statHistograms[iTermMetalFrameDataStatCPU] addValue:duration * 1000];

    duration = iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[iTermMetalFrameDataStatPrivateQueueTotal]);
    [_statHistograms[iTermMetalFrameDataStatPrivateQueueTotal] addValue:duration * 1000];

    iTermPreciseTimerStatsStartTimer(&_stats[iTermMetalFrameDataStatGpu]);
}

- (void)updateRenderEncoderWithRenderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor
                                               stat:(iTermMetalFrameDataStat)stat
                                              label:(NSString *)label {
    [self measureTimeForStat:stat ofBlock:^{
        self.renderEncoder = [self newRenderEncoderWithDescriptor:renderPassDescriptor
                                                    commandBuffer:self.commandBuffer
                                                     viewportSize:self.viewportSize
                                                            label:label];
    }];
}

- (id<MTLRenderCommandEncoder>)newRenderEncoderWithDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor
                                                commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                                 viewportSize:(vector_uint2)viewportSize
                                                        label:(NSString *)label {
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderEncoder.label = label;

    // Set the region of the drawable to which we'll draw.
    MTLViewport viewport = {
        -(double)viewportSize.x,
        0.0,
        viewportSize.x * 2,
        viewportSize.y * 2,
        -1.0,
        1.0
    };
    [renderEncoder setViewport:viewport];
    return renderEncoder;
}

- (MTLRenderPassDescriptor *)newRenderPassDescriptorWithLabel:(NSString *)label
                                                         fast:(BOOL)fast {
    MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    MTLRenderPassColorAttachmentDescriptor *colorAttachment = renderPassDescriptor.colorAttachments[0];
    colorAttachment.storeAction = MTLStoreActionStore;
    colorAttachment.texture = fast ? [self.fullSizeTexturePool requestTextureOfSize:self.viewportSize] : nil;
    if (!colorAttachment.texture) {
        // Allocate a new texture.
        MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                                     width:self.viewportSize.x
                                                                                                    height:self.viewportSize.y
                                                                                                 mipmapped:NO];
        if (fast) {
            textureDescriptor.usage = (MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget);
        } else {
            textureDescriptor.usage = (MTLTextureUsageShaderRead |
                                       MTLTextureUsageShaderWrite |
                                       MTLTextureUsageRenderTarget |
                                       MTLTextureUsagePixelFormatView);
        }
        colorAttachment.texture = [self.device newTextureWithDescriptor:textureDescriptor];
        [iTermTexture setBytesPerRow:self.viewportSize.x * 4
                         rawDataSize:self.viewportSize.x * self.viewportSize.y * 4
                     samplesPerPixel:4
                          forTexture:colorAttachment.texture];
        colorAttachment.texture.label = label;
        if (fast) {
            [self.fullSizeTexturePool stampTextureWithGeneration:colorAttachment.texture];
        }
    } else {
        colorAttachment.texture.label = label;
    }

    assert(renderPassDescriptor.colorAttachments[0].texture != nil);
    return renderPassDescriptor;
}

- (void)createpostmultipliedRenderPassDescriptor NS_AVAILABLE_MAC(10_14) {
    [self measureTimeForStat:iTermMetalFrameDataStatPqCreateTemporary ofBlock:^{
        assert(!self.postmultipliedRenderPassDescriptor);
        
        self.postmultipliedRenderPassDescriptor = [self newRenderPassDescriptorWithLabel:@"SRGB Texture"
                                                                          fast:YES];
        
        [self->_debugInfo setPostmultipliedRenderPassDescriptor:self.postmultipliedRenderPassDescriptor];
    }];
}

- (void)createIntermediateRenderPassDescriptor {
    [self measureTimeForStat:iTermMetalFrameDataStatPqCreateIntermediate ofBlock:^{
        assert(!self.intermediateRenderPassDescriptor);

        self.intermediateRenderPassDescriptor = [self newRenderPassDescriptorWithLabel:@"Intermediate Texture"
                                                                                  fast:YES];

        [self->_debugInfo setIntermediateRenderPassDescriptor:self.intermediateRenderPassDescriptor];
    }];
}

#if ENABLE_USE_TEMPORARY_TEXTURE
- (void)createTemporaryRenderPassDescriptor {
    [self measureTimeForStat:iTermMetalFrameDataStatPqCreateTemporary ofBlock:^{
        assert(!self.temporaryRenderPassDescriptor);

        self.temporaryRenderPassDescriptor = [self newRenderPassDescriptorWithLabel:@"Temporary Texture"
                                                                               fast:YES];

        [self->_debugInfo setTemporaryRenderPassDescriptor:self.temporaryRenderPassDescriptor];
    }];
}
#endif

- (void)didCompleteWithAggregateStats:(iTermPreciseTimerStats *)aggregateStats
                           histograms:(NSArray<iTermHistogram *> *)aggregateHistograms
                                owner:(NSString *)owner {
    self.status = @"complete";
    if (self.intermediateRenderPassDescriptor) {
        [self.fullSizeTexturePool returnTexture:self.intermediateRenderPassDescriptor.colorAttachments[0].texture];
    }
    if (@available(macOS 10.14, *)) {
        if (self.postmultipliedRenderPassDescriptor) {
            [self.fullSizeTexturePool returnTexture:self.postmultipliedRenderPassDescriptor.colorAttachments[0].texture];
        }
    }
#if ENABLE_USE_TEMPORARY_TEXTURE
    if (self.temporaryRenderPassDescriptor) {
        [self.fullSizeTexturePool returnTexture:self.temporaryRenderPassDescriptor.colorAttachments[0].texture];
    }
#endif
    double duration;

    duration = iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[iTermMetalFrameDataStatGpu]);
    [_statHistograms[iTermMetalFrameDataStatGpu] addValue:duration * 1000];

    duration = iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[iTermMetalFrameDataStatEndToEnd]);
    [_statHistograms[iTermMetalFrameDataStatEndToEnd] addValue:duration * 1000];

#if ENABLE_PER_FRAME_METAL_STATS
    NSLog(@"Stats for %@", self);
    iTermPreciseTimerLogOneEvent(_stats, iTermMetalFrameDataStatCount, YES);

    [self.transientStates enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, __kindof iTermMetalRendererTransientState * _Nonnull tState, BOOL * _Nonnull stop) {
        if ([tState numberOfStats] > 0) {
            iTermPreciseTimerLogOneEvent([tState stats], [tState numberOfStats], YES);
        }
    }];

    NSLog(@"%@", [_framePoolContext summaryStatisticsWithName:@"Frame"]);
    [self.transientStates enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, __kindof iTermMetalRendererTransientState * _Nonnull tState, BOOL * _Nonnull stop) {
        NSLog(@"%@", [tState.poolContext summaryStatisticsWithName:NSStringFromClass([tState class])]);
    }];
#endif
    [self mergeHistogram:_framePoolContext.histogram name:@"Global buffer sizes"];
    [self mergeHistogram:_framePoolContext.textureHistogram name:@"Global texture sizes"];
    [self mergeHistogram:_framePoolContext.wasteHistogram name:@"Global wasted space"];
    [self.transientStates enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, __kindof iTermMetalRendererTransientState * _Nonnull tState, BOOL * _Nonnull stop) {
        [self mergeHistogram:tState.poolContext.histogram name:[NSString stringWithFormat:@"%@: buffer sizes", NSStringFromClass(tState.class)]];
        [self mergeHistogram:tState.poolContext.textureHistogram name:[NSString stringWithFormat:@"%@: texture sizes", NSStringFromClass(tState.class)]];
        [self mergeHistogram:tState.poolContext.wasteHistogram name:[NSString stringWithFormat:@"%@: wasted space", NSStringFromClass(tState.class)]];
    }];
    iTermPreciseTimerSaveLog([NSString stringWithFormat:@"%@: Histograms", owner], [self histogramsString]);

    [self addStatsTo:aggregateStats];

    iTermPreciseTimerStats temp[iTermMetalFrameDataStatCount];
    for (int i = 0; i < iTermMetalFrameDataStatCount; i++) {
        temp[i] = aggregateStats[i];
        [aggregateHistograms[i] mergeFrom:_statHistograms[i]];
    }
    iTermPreciseTimerPeriodicLog([NSString stringWithFormat:@"%@: Metal Frame Data", owner], temp, iTermMetalFrameDataStatCount, 1, [iTermAdvancedSettingsModel logDrawingPerformance], aggregateHistograms);
}

- (__kindof iTermMetalRendererTransientState *)transientStateForRenderer:(NSObject *)renderer {
    return self.transientStates[NSStringFromClass([renderer class])];
}

- (void)setTransientState:(iTermMetalRendererTransientState *)tState forRenderer:(NSObject *)renderer {
    self.transientStates[NSStringFromClass([renderer class])] = tState;
}

- (void)mergeHistogram:(iTermHistogram *)histogramToMerge name:(NSString *)name {
    if (!name) {
        return;
    }
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sHistograms = [[NSMutableDictionary alloc] init];
    });
    @synchronized(sHistograms) {
        iTermHistogram *hist = sHistograms[name];
        if (!hist) {
            hist = [[iTermHistogram alloc] init];
            sHistograms[name] = hist;
        }
        [hist mergeFrom:histogramToMerge];
    }
}

- (NSString *)histogramsString {
    NSMutableString *result = [NSMutableString string];
    @synchronized(sHistograms) {
        [[sHistograms.allKeys sortedArrayUsingSelector:@selector(compare:)] enumerateObjectsUsingBlock:^(NSString * _Nonnull name, NSUInteger idx, BOOL * _Nonnull stop) {
            iTermHistogram *histogram = sHistograms[name];
            [result appendFormat:@"%@: %@\n", name, [histogram sparklines]];
        }];
    }
    return result;
}

- (void)addStatsTo:(iTermPreciseTimerStats *)dest {
    for (int i = 0; i < iTermMetalFrameDataStatCount; i++) {
        iTermPreciseTimerStatsRecord(&dest[i], _stats[i].mean * _stats[i].n, _stats[i].n);
    }
}

- (iTermPreciseTimerStats *)stats {
    return _stats;
}

- (void)enqueueDrawCallsWithBlock:(void (^)(void))block {
#if ENABLE_DISPATCH_TO_MAIN_QUEUE_FOR_ENQUEUEING_DRAW_CALLS
    [self dispatchToMainQueueForDrawing:^{
        block();
        [self willHandOffToGPU];
    }];
#else
    [self measureTimeForStat:iTermMetalFrameDataStatPqEnqueueDrawCalls ofBlock:block];
#endif
    [self willHandOffToGPU];
}

- (iTermCellRenderConfiguration *)cellConfiguration {
    if (!_cellConfiguration) {
        _cellConfiguration = [[iTermCellRenderConfiguration alloc] initWithViewportSize:self.viewportSize
                                                                                  scale:self.scale
                                                                     hasBackgroundImage:self.hasBackgroundImage
                                                                               cellSize:self.cellSize
                                                                              glyphSize:self.glyphSize
                                                                 cellSizeWithoutSpacing:self.cellSizeWithoutSpacing
                                                                               gridSize:self.gridSize
                                                                  usingIntermediatePass:(self.intermediateRenderPassDescriptor != nil)];
    }
    return _cellConfiguration;
}

@end


