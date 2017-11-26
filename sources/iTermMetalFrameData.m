//
//  iTermMetalFrameData.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/27/17.
//

#import "iTermMetalFrameData.h"

#import <MetalKit/MetalKit.h>

void iTermMetalFrameDataStatsBundleInitialize(iTermMetalFrameDataStatsBundle *bundle) {
    iTermPreciseTimerStatsInit(&bundle->mainThreadStats, "main thread");
    iTermPreciseTimerStatsInit(&bundle->getCurrentDrawableStats, "mt.currentDrawable");
    iTermPreciseTimerStatsInit(&bundle->getCurrentRenderPassDescriptorStats, "mt.renderPassDescr");
    iTermPreciseTimerStatsInit(&bundle->dispatchStats, "dispatch");
    iTermPreciseTimerStatsInit(&bundle->prepareStats, "prepare");
    iTermPreciseTimerStatsInit(&bundle->waitForGroup, "wait for group");
    iTermPreciseTimerStatsInit(&bundle->finalizeStats, "finalize");
    iTermPreciseTimerStatsInit(&bundle->metalSetupStats, "metal setup");
    iTermPreciseTimerStatsInit(&bundle->renderingStats, "rendering");
    iTermPreciseTimerStatsInit(&bundle->endToEnd, "end to end");
}

static NSInteger gNextFrameDataNumber;

@implementation iTermMetalFrameData {
    NSTimeInterval _creation;
    NSInteger _frameNumber;
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
    return [NSString stringWithFormat:@"<%@: %p age=%f frameNumber=%@/%@ status=%@>",
            self.class,
            self,
            [NSDate timeIntervalSinceReferenceDate] - _creation,
            @(_frameNumber),
            @(gNextFrameDataNumber),
            self.status];
}

- (void)loadFromView:(MTKView *)view {
    self.device = view.device;

    iTermPreciseTimerStatsStartTimer(&_stats.getCurrentDrawableStats);
    self.drawable = view.currentDrawable;
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.getCurrentDrawableStats);

    iTermPreciseTimerStatsStartTimer(&_stats.getCurrentRenderPassDescriptorStats);
    self.renderPassDescriptor = view.currentRenderPassDescriptor;
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.getCurrentRenderPassDescriptorStats);
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.mainThreadStats);
}

- (void)prepareWithBlock:(void (^)(void))block {
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

        iTermPreciseTimerStatsStartTimer(&_stats.metalSetupStats);
        self.status = @"doing metal setup";
        render();
        self.status = @"waiting for render to complete";
        iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.metalSetupStats);

        iTermPreciseTimerStatsStartTimer(&_stats.renderingStats);
    });
}

- (void)didComplete {
    self.status = @"complete";
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.renderingStats);
    iTermPreciseTimerStatsMeasureAndRecordTimer(&_stats.endToEnd);
}

- (void)addStatsTo:(iTermMetalFrameDataStatsBundle *)dest {
    iTermPreciseTimerStatsRecord(&dest->mainThreadStats, _stats.mainThreadStats.mean * _stats.mainThreadStats.n, _stats.mainThreadStats.n);
    iTermPreciseTimerStatsRecord(&dest->getCurrentDrawableStats, _stats.getCurrentDrawableStats.mean * _stats.getCurrentDrawableStats.n, _stats.getCurrentDrawableStats.n);
    iTermPreciseTimerStatsRecord(&dest->getCurrentRenderPassDescriptorStats, _stats.getCurrentRenderPassDescriptorStats.mean * _stats.getCurrentRenderPassDescriptorStats.n, _stats.getCurrentRenderPassDescriptorStats.n);
    iTermPreciseTimerStatsRecord(&dest->dispatchStats, _stats.dispatchStats.mean * _stats.dispatchStats.n, _stats.dispatchStats.n);
    iTermPreciseTimerStatsRecord(&dest->prepareStats, _stats.prepareStats.mean * _stats.prepareStats.n, _stats.prepareStats.n);
    iTermPreciseTimerStatsRecord(&dest->waitForGroup, _stats.waitForGroup.mean * _stats.waitForGroup.n, _stats.waitForGroup.n);
    iTermPreciseTimerStatsRecord(&dest->finalizeStats, _stats.finalizeStats.mean * _stats.finalizeStats.n, _stats.finalizeStats.n);
    iTermPreciseTimerStatsRecord(&dest->metalSetupStats, _stats.metalSetupStats.mean * _stats.metalSetupStats.n, _stats.metalSetupStats.n);
    iTermPreciseTimerStatsRecord(&dest->renderingStats, _stats.renderingStats.mean * _stats.renderingStats.n, _stats.renderingStats.n);
    iTermPreciseTimerStatsRecord(&dest->endToEnd, _stats.endToEnd.mean * _stats.endToEnd.n, _stats.endToEnd.n);
}

@end

