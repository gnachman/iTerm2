//
//  iTermMetalFrameData.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/27/17.
//

#import "iTermMetalFrameData.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermMetalRenderer.h"

#import <MetalKit/MetalKit.h>

void iTermMetalFrameDataStatsBundleInitialize(iTermPreciseTimerStats *bundle) {
    iTermPreciseTimerSetEnabled([iTermAdvancedSettingsModel logDrawingPerformance]);

    const char *names[iTermMetalFrameDataStatCount] = {
        "mt.ExtractFromApp",
        "mt.GetCurrentDrawable",
        "mt.GetRenderPassD",
        "dispatchToPrivateQueue",
        "BuildRowData",
        "UpdateRenderers",
        "CreateTransient",

        "badgeTS<",
        "backgroundImageTS<",
        "backgroundColorTS<",
        "cursorGuideTS<",
        "broadcastStripesTS<",
        "copyBackgroundTS<",
        "markTS<",
        "cursorTS<",
        "marginTS<",
        "textTS<",

        "PopulateTransient",
        "EnqueueDrawCalls",
        "Create1stRE<",
        "DrawMargin<",
        "DrawBgImage<",
        "DrawBgColor<",
        "DrawCursor<",
        "EndEncodingInt<",
        "Create2ndRE<",
        "enqueueCopyBg<",
        "enqueueDrawText<",
        "EndEncodingDrwbl<",
        "PresentCommit<",
        "gpu",
        "endToEnd",
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

- (void)willHandOffToGPU {
    iTermPreciseTimerStatsStartTimer(&_stats[iTermMetalFrameDataStatGpu]);
}

- (void)didCompleteWithAggregateStats:(iTermPreciseTimerStats *)aggregateStats {
    self.status = @"complete";
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[iTermMetalFrameDataStatGpu]);
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats[iTermMetalFrameDataStatEndToEnd]);

#define ENABLE_PER_FRAME_METAL_STATS 1
#if ENABLE_PER_FRAME_METAL_STATS
    NSLog(@"Stats for %@", self);
    iTermPreciseTimerLogOneEvent(_stats, iTermMetalFrameDataStatCount, YES);

    [self.transientStates enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, __kindof iTermMetalRendererTransientState * _Nonnull tState, BOOL * _Nonnull stop) {
        if ([tState numberOfStats] > 0) {
            iTermPreciseTimerLogOneEvent([tState stats], [tState numberOfStats], YES);
        }
    }];
#endif

    [self addStatsTo:aggregateStats];

    iTermPreciseTimerStats temp[iTermMetalFrameDataStatCount];
    for (int i = 0; i < iTermMetalFrameDataStatCount; i++) {
        temp[i] = aggregateStats[i];
    }
    iTermPreciseTimerPeriodicLog(temp, iTermMetalFrameDataStatCount, 1, YES);
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


