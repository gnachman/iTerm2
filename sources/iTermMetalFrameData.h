//
//  iTermMetalFrameData.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/27/17.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "iTermPreciseTimer.h"
#import "VT100GridTypes.h"

typedef struct {
    iTermPreciseTimerStats mainThreadStats;
    iTermPreciseTimerStats getCurrentDrawableStats;
    iTermPreciseTimerStats getCurrentRenderPassDescriptorStats;
    iTermPreciseTimerStats mtWillBeginDrawing;
    iTermPreciseTimerStats dispatchStats;
    iTermPreciseTimerStats prepareStats;
    iTermPreciseTimerStats waitForGroup;
    iTermPreciseTimerStats finalizeStats;

    // Finalize stats
    iTermPreciseTimerStats fzCopyBackgroundRenderer;
    iTermPreciseTimerStats fzCursor;
    iTermPreciseTimerStats fzText;

    iTermPreciseTimerStats metalSetupStats;
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
@property (nonatomic, strong) id<iTermMetalDriverDataSourcePerFrameState> perFrameState;
@property (nonatomic, strong) NSMutableDictionary<NSString *, __kindof iTermMetalRendererTransientState *> *transientStates;
@property (nonatomic, strong) NSMutableArray<iTermMetalRowData *> *rows;
@property (nonatomic) VT100GridSize gridSize;
@property (nonatomic) CGFloat scale;
@property (atomic, strong) NSString *status;
@property (nonatomic, strong) MTLRenderPassDescriptor *renderPassDescriptor;
@property (nonatomic, strong) id<CAMetalDrawable> drawable;
@property (nonatomic, strong) id<MTLDevice> device;

// If nonnil then all draw stages before text draw with encoders from this render pass descriptor.
// It will have a texture identical to the drawable's texture.
@property (nonatomic, strong) MTLRenderPassDescriptor *intermediateRenderPassDescriptor;

- (void)loadFromView:(MTKView *)view;
- (void)prepareWithBlock:(void (^)(void))block;
- (void)waitForUpdatesToFinishOnGroup:(dispatch_group_t)group
                              onQueue:(dispatch_queue_t)queue
                             finalize:(void (^)(void))finalize
                               render:(void (^)(void))render;
- (void)didCompleteWithAggregateStats:(iTermMetalFrameDataStatsBundle *)aggregateStats;

- (void)finalizeCopyBackgroundRendererWithBlock:(void (^)(void))block;
- (void)finalizeCursorRendererWithBlock:(void (^)(void))block;
- (void)finalizeTextRendererWithBlock:(void (^)(void))block;

@end

