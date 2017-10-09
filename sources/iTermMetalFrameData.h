//
//  iTermMetalFrameData.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/27/17.
//

#import <Foundation/Foundation.h>

#import "iTermPreciseTimer.h"
#import "VT100GridTypes.h"

typedef struct {
    iTermPreciseTimerStats mainThreadStats;
    iTermPreciseTimerStats getCurrentDrawableStats;
    iTermPreciseTimerStats getCurrentRenderPassDescriptorStats;
    iTermPreciseTimerStats dispatchStats;
    iTermPreciseTimerStats prepareStats;
    iTermPreciseTimerStats waitForGroup;
    iTermPreciseTimerStats finalizeStats;
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

- (void)loadFromView:(MTKView *)view;
- (void)prepareWithBlock:(void (^)(void))block;
- (void)waitForUpdatesToFinishOnGroup:(dispatch_group_t)group
                              onQueue:(dispatch_queue_t)queue
                             finalize:(void (^)(void))finalize
                               render:(void (^)(void))render;
- (void)didComplete;
- (void)addStatsTo:(iTermMetalFrameDataStatsBundle *)dest;

@end

