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
#import "iTermMetalRenderer.h"

#import <MetalKit/MetalKit.h>

static NSMutableDictionary *sHistograms;

void iTermMetalFrameDataStatsBundleInitialize(iTermPreciseTimerStats *bundle) {
    iTermPreciseTimerSetEnabled([iTermAdvancedSettingsModel logDrawingPerformance]);

    const char *names[iTermMetalFrameDataStatCount] = {
        "endToEnd",

        "mt.ExtractFromApp<",
        "mt.GetDrawable<",
        "mt.GetRenderPassD<",
        "dispatchToPQ<",
        "BuildRowData<",
        "UpdateRenderers<",
        "CreateTransient<",

        "badgeTS<<",
        "backgroundImageTS<<",
        "backgroundColorTS<<",
        "cursorGuideTS<<",
        "bcastStripesTS<<",
        "copyBackgroundTS<<",
        "markTS<<",
        "cursorTS<<",
        "marginTS<<",
        "textTS<<",

        "PopulateTransient<",
        "dispatchToMain<",
        "EnqueueDrawCalls<",
        "Create1stRE<<",
        "DrawMargin<<",
        "DrawBgImage<<",
        "DrawBgColor<<",
        "DrawBadge<<",
        "DrawCursor<<",
        "EndEncodingInt<<",
        "Create2ndRE<<",
        "enqueueCopyBg<<",
        "enqueueDrawText<<",
        "EndEncodingDrwbl<<",
        "PresentCommit<<",

        "gpu<",
        "scheduleWait<<",

        "dispatchToPQ2<",
    };

    for (int i = 0; i < iTermMetalFrameDataStatCount; i++) {
        iTermPreciseTimerStatsInit(&bundle[i], names[i]);
    }
}

static NSInteger gNextFrameDataNumber;

@interface iTermMetalFrameData()
@property (atomic, strong, readwrite) MTKView *view;
@end

@implementation iTermMetalFrameData {
    NSTimeInterval _creation;
    iTermPreciseTimerStats _stats[iTermMetalFrameDataStatCount];
}

- (instancetype)initWithView:(MTKView *)view {
    self = [super init];
    if (self) {
        _view = view;
        _device = view.device;
        _creation = [NSDate timeIntervalSinceReferenceDate];
        _frameNumber = gNextFrameDataNumber++;
        _framePoolContext = [[iTermMetalBufferPoolContext alloc] init];
        iTermMetalFrameDataStatsBundleInitialize(_stats);

        iTermPreciseTimerStatsStartTimer(&_stats[iTermMetalFrameDataStatEndToEnd]);
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

- (void)measureTimeForStat:(iTermMetalFrameDataStat)stat ofBlock:(void (^)(void))block {
    self.status = [NSString stringWithUTF8String:_stats[stat].name];
    iTermPreciseTimerStatsStartTimer(&_stats[stat]);
    block();
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[stat]);
}

- (void)extractStateFromAppInBlock:(void (^)(void))block {
    iTermPreciseTimerStatsStartTimer(&_stats[iTermMetalFrameDataStatMtExtractFromApp]);
    block();
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[iTermMetalFrameDataStatMtExtractFromApp]);
}

- (void)dispatchToPrivateQueue:(dispatch_queue_t)queue forPreparation:(void (^)(void))block {
    iTermPreciseTimerStatsStartTimer(&_stats[iTermMetalFrameDataStatDispatchToPrivateQueue]);
    dispatch_async(queue, ^{
        iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[iTermMetalFrameDataStatDispatchToPrivateQueue]);
        block();
    });
}

- (void)dispatchToMainQueueForDrawing:(void (^)(void))block {
    iTermPreciseTimerStatsStartTimer(&_stats[iTermMetalFrameDataStatDispatchToMainQueue]);
    dispatch_async(dispatch_get_main_queue(), ^{
        iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[iTermMetalFrameDataStatDispatchToMainQueue]);
        block();
    });
}

- (void)dispatchToPrivateQueue:(dispatch_queue_t)queue forCompletion:(void (^)(void))block {
    self.status = @"completion handler, waiting for dispatch";
    iTermPreciseTimerStatsStartTimer(&_stats[iTermMetalFrameDataStatDispatchToPrivateQueueForCompletion]);
    dispatch_async(queue, ^{
        self.status = @"completion handler on private queue";
        iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[iTermMetalFrameDataStatDispatchToPrivateQueueForCompletion]);
        block();
    });
}

- (void)willHandOffToGPU {
    iTermPreciseTimerStatsStartTimer(&_stats[iTermMetalFrameDataStatGpu]);
}

- (void)didCompleteWithAggregateStats:(iTermPreciseTimerStats *)aggregateStats {
    self.status = @"complete";
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[iTermMetalFrameDataStatGpu]);
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[iTermMetalFrameDataStatEndToEnd]);

#define ENABLE_PER_FRAME_METAL_STATS 0
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
    iTermPreciseTimerSaveLog(@"Histograms", [self histogramsString]);

    [self addStatsTo:aggregateStats];

    iTermPreciseTimerStats temp[iTermMetalFrameDataStatCount];
    for (int i = 0; i < iTermMetalFrameDataStatCount; i++) {
        temp[i] = aggregateStats[i];
    }
    iTermPreciseTimerPeriodicLog(@"Metal Frame Data", temp, iTermMetalFrameDataStatCount, 1, YES);
}

- (void)mergeHistogram:(iTermHistogram *)histogramToMerge name:(NSString *)name {
    @synchronized(sHistograms) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            sHistograms = [[NSMutableDictionary alloc] init];
        });
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
            [result appendFormat:@"%@:\n%@\n\n", name, [histogram stringValue]];
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

@end


