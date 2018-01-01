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

// Perform most metal activities on a private queue? Relieves the main thread of most drawing
// work when enabled.
#define ENABLE_PRIVATE_QUEUE 1

// It's not clear to me if dispatching to the main queue is actually necessary, but I'm leaving
// this here so it's easy to switch back to doing so. It adds a ton of latency when enabled.
#define ENABLE_DISPATCH_TO_MAIN_QUEUE_FOR_ENQUEUEING_DRAW_CALLS 0

@protocol iTermMetalRenderer;

typedef NS_ENUM(int, iTermMetalFrameDataStat) {
    iTermMetalFrameDataStatEndToEnd,

    iTermMetalFrameDataStatMtExtractFromApp,
    iTermMetalFrameDataStatMtGetCurrentDrawable,
    iTermMetalFrameDataStatMtGetRenderPassDescriptor,

    iTermMetalFrameDataStatDispatchToPrivateQueue,
    iTermMetalFrameDataStatPqBuildRowData,
    iTermMetalFrameDataStatPqCreateIntermediate,
    iTermMetalFrameDataStatPqUpdateRenderers,
    iTermMetalFrameDataStatPqCreateTransientStates,

    iTermMetalFrameDataStatPqCreateBadgeTS,
    iTermMetalFrameDataStatPqCreateBackgroundImageTS,
    iTermMetalFrameDataStatPqCreateBackgroundColorTS,
    iTermMetalFrameDataStatPqCreateCursorGuideTS,
    iTermMetalFrameDataStatPqCreateBroadcastStripesTS,
    iTermMetalFrameDataStatPqCreateCopyBackgroundTS,
    iTermMetalFrameDataStatPqCreateMarkTS,
    iTermMetalFrameDataStatPqCreateCursorTS,
    iTermMetalFrameDataStatPqCreateMarginTS,
    iTermMetalFrameDataStatPqCreateTextTS,
    iTermMetalFrameDataStatPqCreateIndicatorsTS,
    iTermMetalFrameDataStatPqCreateTimestampsTS,
    iTermMetalFrameDataStatPqCreateFullScreenFlashTS,

    iTermMetalFrameDataStatPqPopulateTransientStates,

    iTermMetalFrameDataStatDispatchToMainQueue,
    iTermMetalFrameDataStatPqEnqueueDrawCalls,
    iTermMetalFrameDataStatPqEnqueueDrawCreateFirstRenderEncoder,
    iTermMetalFrameDataStatPqEnqueueDrawMargin,
    iTermMetalFrameDataStatPqEnqueueDrawBackgroundImage,
    iTermMetalFrameDataStatPqEnqueueDrawBackgroundColor,
    iTermMetalFrameDataStatPqEnqueueBroadcastStripes,
    iTermMetalFrameDataStatPqEnqueueBadge,
    iTermMetalFrameDataStatPqEnqueueDrawCursor,
    iTermMetalFrameDataStatPqEnqueueDrawMarks,
    iTermMetalFrameDataStatPqEnqueueDrawCursorGuide,
    iTermMetalFrameDataStatPqEnqueueDrawEndEncodingToIntermediateTexture,

    iTermMetalFrameDataStatPqEnqueueDrawCreateSecondRenderEncoder,
    iTermMetalFrameDataStatPqEnqueueCopyBackground,
    iTermMetalFrameDataStatPqEnqueueDrawText,
    iTermMetalFrameDataStatPqEnqueueDrawIndicators,
    iTermMetalFrameDataStatPqEnqueueDrawTimestamps,
    iTermMetalFrameDataStatPqEnqueueDrawFullScreenFlash,
    iTermMetalFrameDataStatPqEnqueueDrawEndEncodingToDrawable,
    iTermMetalFrameDataStatPqEnqueueDrawPresentAndCommit,

    iTermMetalFrameDataStatGpu,
    iTermMetalFrameDataStatGpuScheduleWait,
    iTermMetalFrameDataStatDispatchToPrivateQueueForCompletion,

    iTermMetalFrameDataStatCount
};

extern void iTermMetalFrameDataStatsBundleInitialize(iTermPreciseTimerStats *bundle);
extern void iTermMetalFrameDataStatsBundleAdd(iTermPreciseTimerStats *dest, iTermPreciseTimerStats *source);

NS_CLASS_AVAILABLE(10_11, NA)
@protocol iTermMetalDriverDataSourcePerFrameState;
@class iTermMetalBufferPoolContext;
@class iTermMetalRendererTransientState;
@class iTermMetalRowData;
@class MTKView;
@class MTLRenderPassDescriptor;
@protocol CAMetalDrawable;

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalFrameData : NSObject
@property (atomic, strong) id<iTermMetalDriverDataSourcePerFrameState> perFrameState;
@property (atomic, readonly, strong) NSMutableDictionary<NSString *, __kindof iTermMetalRendererTransientState *> *transientStates;
@property (atomic, strong) NSMutableArray<iTermMetalRowData *> *rows;
@property (atomic) vector_uint2 viewportSize;
@property (atomic) VT100GridSize gridSize;
@property (atomic) CGFloat scale;
@property (atomic, strong) NSString *status;
@property (atomic, strong) id<MTLDevice> device;
@property (atomic, strong, readonly) MTKView *view;
@property (nonatomic, readonly) NSInteger frameNumber;
@property (nonatomic, readonly) iTermPreciseTimerStats *stats;
@property (nonatomic, strong) id<CAMetalDrawable> drawable;
@property (nonatomic, strong) MTLRenderPassDescriptor *renderPassDescriptor;
@property (nonatomic, readonly) iTermMetalBufferPoolContext *framePoolContext;

// If nonnil then all draw stages before text draw with encoders from this render pass descriptor.
// It will have a texture identical to the drawable's texture. Invoke createIntermediateRenderPassDescriptor
// to create this if it's nil.
@property (nonatomic, strong) MTLRenderPassDescriptor *intermediateRenderPassDescriptor;

- (instancetype)initWithView:(MTKView *)view NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)measureTimeForStat:(iTermMetalFrameDataStat)stat ofBlock:(void (^)(void))block;
#if ENABLE_PRIVATE_QUEUE
- (void)dispatchToPrivateQueue:(dispatch_queue_t)queue forPreparation:(void (^)(void))block;
#endif
- (void)createIntermediateRenderPassDescriptor;
- (void)dispatchToQueue:(dispatch_queue_t)queue forCompletion:(void (^)(void))block;
- (void)enqueueDrawCallsWithBlock:(void (^)(void))block;
- (void)didCompleteWithAggregateStats:(iTermPreciseTimerStats *)aggregateStats;

- (__kindof iTermMetalRendererTransientState *)transientStateForRenderer:(NSObject *)renderer;
- (void)setTransientState:(iTermMetalRendererTransientState *)tState forRenderer:(NSObject *)renderer;

@end

