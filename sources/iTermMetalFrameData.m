//
//  iTermMetalFrameData.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/27/17.
//

#import "iTermMetalFrameData.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"

#import <MetalKit/MetalKit.h>

void iTermMetalFrameDataStatsBundleInitialize(iTermMetalFrameDataStatsBundle *bundle) {
    iTermPreciseTimerSetEnabled([iTermAdvancedSettingsModel logDrawingPerformance]);
    iTermPreciseTimerStatsInit(&bundle->mainThreadStats, "main thread");
    iTermPreciseTimerStatsInit(&bundle->extractFromApp, "mt.extractFromApp");

    iTermPreciseTimerStatsInit(&bundle->dispatchForPrepareStats, "dispatchForPrepare");
    iTermPreciseTimerStatsInit(&bundle->prepareStats, "prepare");
    iTermPreciseTimerStatsInit(&bundle->waitForGroup, "wait for group");
    iTermPreciseTimerStatsInit(&bundle->finalizeStats, "finalize");

    iTermPreciseTimerStatsInit(&bundle->fzCopyBackgroundRenderer, "fin cp bg<");
    iTermPreciseTimerStatsInit(&bundle->fzCursor, "fin cursor<");
    iTermPreciseTimerStatsInit(&bundle->fzText, "fin text<");

    iTermPreciseTimerStatsInit(&bundle->getScarceResources, "mt.get scarce");
    iTermPreciseTimerStatsInit(&bundle->getCurrentDrawableStats, "mt.currentDrawable<<");
    iTermPreciseTimerStatsInit(&bundle->getCurrentRenderPassDescriptorStats, "mt.renderPassDescr<<");

    iTermPreciseTimerStatsInit(&bundle->drawStats, "draw<");
    iTermPreciseTimerStatsInit(&bundle->drawMargins, "drawMargins<<");
    iTermPreciseTimerStatsInit(&bundle->drawBGImage, "drawBGImage<<");
    iTermPreciseTimerStatsInit(&bundle->drawBGColor, "drawBGColor<<");
    iTermPreciseTimerStatsInit(&bundle->drawCursor, "drawCursor<<");
    iTermPreciseTimerStatsInit(&bundle->drawCopyBG, "drawCopyBG<<");
    iTermPreciseTimerStatsInit(&bundle->drawText, "drawText<<");


    iTermPreciseTimerStatsInit(&bundle->renderingStats, "rendering");
    iTermPreciseTimerStatsInit(&bundle->endToEnd, "end to end");
}

static NSInteger gNextFrameDataNumber;

@interface iTermMetalFrameData()
@property (atomic, strong, readwrite) MTKView *view;
@end

@implementation iTermMetalFrameData {
    NSTimeInterval _creation;
    iTermMetalFrameDataStatsBundle _stats;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _creation = [NSDate timeIntervalSinceReferenceDate];
        _frameNumber = gNextFrameDataNumber++;
        iTermMetalFrameDataStatsBundleInitialize(&_stats);

        iTermPreciseTimerStatsStartTimer(&_stats.endToEnd);
        iTermPreciseTimerStatsStartTimer(&_stats.mainThreadStats);
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

- (void)loadFromView:(MTKView *)view {
    self.view = view;
    self.device = view.device;
}

- (void)extractStateFromAppInBlock:(void (^)(void))block {
    iTermPreciseTimerStatsStartTimer(&_stats.extractFromApp);
    block();
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.extractFromApp);
}

- (void)performBlockWithScarceResources:(void (^)(MTLRenderPassDescriptor *, id<CAMetalDrawable>))block {
    iTermPreciseTimerStatsStartTimer(&_stats.getScarceResources);
    dispatch_sync(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            id<CAMetalDrawable> drawable;
            MTLRenderPassDescriptor *renderPassDescriptor;
            iTermPreciseTimerStatsStartTimer(&_stats.getCurrentDrawableStats);
            drawable = self.view.currentDrawable;
            iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.getCurrentDrawableStats);
            
            iTermPreciseTimerStatsStartTimer(&_stats.getCurrentRenderPassDescriptorStats);
            renderPassDescriptor = self.view.currentRenderPassDescriptor;
            iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.getCurrentRenderPassDescriptorStats);
            block(renderPassDescriptor, drawable);
            iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.getScarceResources);
        }
    });
}

- (void)dispatchToPrivateQueue:(dispatch_queue_t)queue forPreparation:(void (^)(void))block {
    iTermPreciseTimerStatsStartTimer(&_stats.dispatchForPrepareStats);
    dispatch_async(queue, ^{
        iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.dispatchForPrepareStats);
        block();
    });
}

- (void)prepareWithBlock:(void (^)(void))block {
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.mainThreadStats);
    iTermPreciseTimerStatsStartTimer(&_stats.prepareStats);
    self.status = @"before prepare";
    block();
    self.status = @"after prepare";
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.prepareStats);
}

- (void)waitForUpdatesToFinishOnGroup:(dispatch_group_t)group
                              onQueue:(dispatch_queue_t)queue
                             finalize:(void (^)(void))finalize
                               render:(void (^)(void))render {
    iTermPreciseTimerStatsStartTimer(&_stats.waitForGroup);
    dispatch_group_notify(group, queue, ^{
        self.status = @"before finalize";
        iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.waitForGroup);

        iTermPreciseTimerStatsStartTimer(&_stats.finalizeStats);
        self.status = @"finalizing";
        finalize();
        iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.finalizeStats);

        iTermPreciseTimerStatsStartTimer(&_stats.drawStats);
        self.status = @"doing metal setup";
        render();
        self.status = @"waiting for render to complete";
        iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.drawStats);

        iTermPreciseTimerStatsStartTimer(&_stats.renderingStats);
    });
}

- (iTermPreciseTimerStats **)statsArrayFromBundle:(iTermMetalFrameDataStatsBundle *)bundle count:(int *)countOut {
    iTermPreciseTimerStats *stats[] = {
        &bundle->mainThreadStats,
        &bundle->extractFromApp,
        &bundle->dispatchForPrepareStats,
        &bundle->prepareStats,
        &bundle->waitForGroup,

        &bundle->finalizeStats,
        &bundle->fzCopyBackgroundRenderer,
        &bundle->fzCursor,
        &bundle->fzText,

        &bundle->getScarceResources,
        &bundle->getCurrentDrawableStats,
        &bundle->getCurrentRenderPassDescriptorStats,

        &bundle->drawStats,
        &bundle->drawMargins,
        &bundle->drawBGImage,
        &bundle->drawBGColor,
        &bundle->drawCursor,
        &bundle->drawCopyBG,
        &bundle->drawText,

        &bundle->renderingStats,
        &bundle->endToEnd
    };

    *countOut = sizeof(stats) / sizeof(*stats);
    NSMutableData *data = [NSMutableData dataWithBytes:stats length:sizeof(stats)];
    return (iTermPreciseTimerStats **)data.mutableBytes;
}

- (void)finalizeTextRendererWithBlock:(void (^)(void))block {
    iTermPreciseTimerStatsStartTimer(&_stats.fzText);
    block();
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.fzText);
}

- (void)finalizeCursorRendererWithBlock:(void (^)(void))block {
    iTermPreciseTimerStatsStartTimer(&_stats.fzCursor);
    block();
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.fzCursor);
}

- (void)finalizeCopyBackgroundRendererWithBlock:(void (^)(void))block {
    iTermPreciseTimerStatsStartTimer(&_stats.fzCopyBackgroundRenderer);
    block();
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.fzCopyBackgroundRenderer);
}

- (void)didCompleteWithAggregateStats:(iTermMetalFrameDataStatsBundle *)aggregateStats {
    self.status = @"complete";
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.renderingStats);
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.endToEnd);

    int numStats;
    iTermPreciseTimerStats **array = [self statsArrayFromBundle:&_stats count:&numStats];
#define ENABLE_PER_FRAME_METAL_STATS 0
#if ENABLE_PER_FRAME_METAL_STATS
    iTermPreciseTimerLog(array, numStats, YES);
#endif

    [self addStatsTo:aggregateStats];

    array = [self statsArrayFromBundle:aggregateStats count:&numStats];
    iTermPreciseTimerStats *temp = malloc(sizeof(iTermPreciseTimerStats) * numStats);
    for (int i = 0; i < numStats; i++) {
        temp[i] = *array[i];
    }
    iTermPreciseTimerPeriodicLog(temp, numStats, 1, YES);
    free(temp);
}

- (void)addStatsTo:(iTermMetalFrameDataStatsBundle *)dest {
    int n;
    iTermPreciseTimerStats **destArray = [self statsArrayFromBundle:dest count:&n];
    iTermPreciseTimerStats **sourceArray = [self statsArrayFromBundle:&_stats count:&n];
    for (int i = 0; i < n; i++) {
        iTermPreciseTimerStatsRecord(destArray[i], sourceArray[i]->mean * sourceArray[i]->n, sourceArray[i]->n);
    }
}

- (iTermMetalFrameDataStatsBundle *)stats {
    return &_stats;
}

@end

