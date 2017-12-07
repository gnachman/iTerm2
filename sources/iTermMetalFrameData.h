//
//  iTermMetalFrameData.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/27/17.
//

#import <Foundation/Foundation.h>

#import "iTermPreciseTimer.h"
#import "VT100GridTypes.h"

#import <Metal/Metal.h>
#import <simd/simd.h>

typedef struct {
    iTermPreciseTimerStats mainThreadStats;
    iTermPreciseTimerStats getScarceResources;
    iTermPreciseTimerStats getCurrentDrawableStats;
    iTermPreciseTimerStats getCurrentRenderPassDescriptorStats;
    iTermPreciseTimerStats extractFromApp;
    iTermPreciseTimerStats dispatchForPrepareStats;
    iTermPreciseTimerStats prepareStats;
    iTermPreciseTimerStats waitForGroup;
    iTermPreciseTimerStats finalizeStats;

    // Finalize stats
    iTermPreciseTimerStats fzCopyBackgroundRenderer;
    iTermPreciseTimerStats fzCursor;
    iTermPreciseTimerStats fzText;

    iTermPreciseTimerStats drawStats;
    iTermPreciseTimerStats drawMargins;
    iTermPreciseTimerStats drawBGImage;
    iTermPreciseTimerStats drawBGColor;
    iTermPreciseTimerStats drawCursor;
    iTermPreciseTimerStats drawCopyBG;
    iTermPreciseTimerStats drawText;

    iTermPreciseTimerStats renderingStats;
    iTermPreciseTimerStats endToEnd;
} iTermMetalFrameDataStatsBundle;

extern void iTermMetalFrameDataStatsBundleInitialize(iTermMetalFrameDataStatsBundle *bundle);
extern void iTermMetalFrameDataStatsBundleAdd(iTermMetalFrameDataStatsBundle *dest, iTermMetalFrameDataStatsBundle *source);

@protocol iTermMetalDriverDataSourcePerFrameState;
@class iTermMetalRendererTransientState;
@class iTermMetalRowData;
@class MTKView;
@class MTLRenderPassDescriptor;
@protocol CAMetalDrawable;

@interface iTermMetalFrameData : NSObject
@property (atomic, strong) id<iTermMetalDriverDataSourcePerFrameState> perFrameState;
@property (atomic, strong) NSMutableDictionary<NSString *, __kindof iTermMetalRendererTransientState *> *transientStates;
@property (atomic, strong) NSMutableArray<iTermMetalRowData *> *rows;
@property (atomic) vector_uint2 viewportSize;
@property (atomic) VT100GridSize gridSize;
@property (atomic) CGFloat scale;
@property (atomic, strong) NSString *status;
@property (atomic, strong) id<MTLDevice> device;
@property (atomic, strong, readonly) MTKView *view;
@property (nonatomic, readonly) NSInteger frameNumber;
@property (nonatomic, readonly) iTermMetalFrameDataStatsBundle *stats;

// If nonnil then all draw stages before text draw with encoders from this render pass descriptor.
// It will have a texture identical to the drawable's texture.
@property (nonatomic, strong) MTLRenderPassDescriptor *intermediateRenderPassDescriptor;

- (void)loadFromView:(MTKView *)view;
- (void)extractStateFromAppInBlock:(void (^)(void))block;
- (void)dispatchToPrivateQueue:(dispatch_queue_t)queue forPreparation:(void (^)(void))block;
- (void)prepareWithBlock:(void (^)(void))block;
- (void)waitForUpdatesToFinishOnGroup:(dispatch_group_t)group
                              onQueue:(dispatch_queue_t)queue
                             finalize:(void (^)(void))finalize
                               render:(void (^)(void))render;
- (void)didCompleteWithAggregateStats:(iTermMetalFrameDataStatsBundle *)aggregateStats;

- (void)finalizeCopyBackgroundRendererWithBlock:(void (^)(void))block;
- (void)finalizeCursorRendererWithBlock:(void (^)(void))block;
- (void)finalizeTextRendererWithBlock:(void (^)(void))block;

- (void)performBlockWithScarceResources:(void (^)(MTLRenderPassDescriptor *renderPassDescriptor,
                                                  id<CAMetalDrawable> drawable))block;

@end

