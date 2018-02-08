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

// If enabled, the drawable's -present method is called on the main queue after the GPU work is
// scheduled. This is horrible and slow but is necessary if you set presentsWithTransaction
// to YES. That should be avoided at all costs.
#define ENABLE_SYNCHRONOUS_PRESENTATION 0

// It's not clear to me if dispatching to the main queue is actually necessary, but I'm leaving
// this here so it's easy to switch back to doing so. It adds a ton of latency when enabled.
#define ENABLE_DISPATCH_TO_MAIN_QUEUE_FOR_ENQUEUEING_DRAW_CALLS 0

@protocol iTermMetalRenderer;

typedef NS_ENUM(int, iTermMetalFrameDataStat) {
    iTermMetalFrameDataStatEndToEnd,
    iTermMetalFrameDataStatCPU,
    iTermMetalFrameDataStatMainQueueTotal,
    iTermMetalFrameDataStatPrivateQueueTotal,

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
    iTermMetalFrameDataStatPqCreateHighlightRowTS,
    iTermMetalFrameDataStatPqCreateImageTS,
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
    iTermMetalFrameDataStatPqEnqueueDrawHighlightRow,
    iTermMetalFrameDataStatPqEnqueueDrawImage,
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

@class iTermCellRenderConfiguration;
NS_CLASS_AVAILABLE(10_11, NA)
@protocol iTermMetalDriverDataSourcePerFrameState;
@class iTermMetalBufferPoolContext;
@class iTermMetalDebugInfo;
@class iTermMetalRendererTransientState;
@class iTermMetalRowData;
@class MTKView;
@class MTLRenderPassDescriptor;
@protocol CAMetalDrawable;

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalFrameData : NSObject
@property (atomic, strong) id<iTermMetalDriverDataSourcePerFrameState> perFrameState;
@property (atomic, strong) NSMutableArray<iTermMetalRowData *> *rows;
@property (atomic) vector_uint2 viewportSize;
@property (atomic) VT100GridSize gridSize;
@property (atomic) CGSize cellSize;
@property (atomic) CGSize cellSizeWithoutSpacing;
@property (atomic) CGFloat scale;
@property (atomic, strong) NSString *status;
@property (atomic, strong) id<MTLDevice> device;
@property (atomic, strong, readonly) MTKView *view;
@property (nonatomic, readonly) NSInteger frameNumber;
@property (nonatomic, readonly) iTermPreciseTimerStats *stats;
@property (nonatomic, strong) id<CAMetalDrawable> destinationDrawable;
@property (nonatomic, strong) id<MTLTexture> destinationTexture;
@property (nonatomic, strong) MTLRenderPassDescriptor *renderPassDescriptor;
@property (nonatomic, strong) MTLRenderPassDescriptor *debugRealRenderPassDescriptor;
@property (nonatomic, readonly) iTermMetalBufferPoolContext *framePoolContext;
@property (nonatomic, strong) iTermMetalDebugInfo *debugInfo;
@property (nonatomic, readonly) iTermCellRenderConfiguration *cellConfiguration;
@property (nonatomic, strong) id<MTLCommandBuffer> commandBuffer;
@property (nonatomic, strong) id<MTLRenderCommandEncoder> renderEncoder;

// When drawing to an intermediate texture there may be two passes (i.e., two render encoders)
@property (nonatomic) int currentPass;

// For debugging. Gives an order to the log files.
@property (nonatomic) int numberOfRenderersDrawn;

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
- (void)didCompleteWithAggregateStats:(iTermPreciseTimerStats *)aggregateStats
                                owner:(NSString *)owner;

- (__kindof iTermMetalRendererTransientState *)transientStateForRenderer:(NSObject *)renderer;
- (void)setTransientState:(iTermMetalRendererTransientState *)tState forRenderer:(NSObject *)renderer;
- (MTLRenderPassDescriptor *)newRenderPassDescriptorWithLabel:(NSString *)label;

@end

