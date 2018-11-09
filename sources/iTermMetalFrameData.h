//
//  iTermMetalFrameData.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/27/17.
//

#import <Foundation/Foundation.h>

#import "iTermMetalConfig.h"
#import "iTermPreciseTimer.h"
#import "VT100GridTypes.h"

#import <Metal/Metal.h>
#import <simd/simd.h>

@protocol iTermMetalRenderer;

typedef NS_ENUM(int, iTermMetalFrameDataStat) {
    iTermMetalFrameDataStatEndToEnd,

    iTermMetalFrameDataStatGpu,
    iTermMetalFrameDataStatGpuScheduleWait,
    iTermMetalFrameDataStatDispatchToPrivateQueueForCompletion,

    iTermMetalFrameDataStatCPU,
    iTermMetalFrameDataStatMainQueueTotal,

    iTermMetalFrameDataStatMtExtractFromApp,
    iTermMetalFrameDataStatMtGetCurrentDrawable,
    iTermMetalFrameDataStatMtGetRenderPassDescriptor,
    iTermMetalFrameDataStatDispatchToPrivateQueue,

    iTermMetalFrameDataStatPrivateQueueTotal,


    iTermMetalFrameDataStatPqBuildRowData,
    iTermMetalFrameDataStatPqCreateIntermediate,
    iTermMetalFrameDataStatPqCreateTemporary,
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
    iTermMetalFrameDataStatPqCreateCornerCutoutTS,

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
    iTermMetalFrameDataStatPqEnqueueDrawCornerCutout,

    iTermMetalFrameDataStatPqEnqueueDrawCreateThirdRenderEncoder,
    iTermMetalFrameDataStatPqBlockOnSynchronousGetDrawable,
    iTermMetalFrameDataStatPqEnqueueCopyToDrawable,
    iTermMetalFrameDataStatPqEnqueueDrawEndEncodingToDrawable,
    iTermMetalFrameDataStatPqEnqueueDrawPresentAndCommit,

    iTermMetalFrameDataStatCount,
    iTermMetalFrameDataStatNA = -1
};

extern void iTermMetalFrameDataStatsBundleInitialize(iTermPreciseTimerStats *bundle);
extern void iTermMetalFrameDataStatsBundleAdd(iTermPreciseTimerStats *dest, iTermPreciseTimerStats *source);

@class iTermCellRenderConfiguration;
@class iTermHistogram;

NS_CLASS_AVAILABLE(10_11, NA)
@protocol iTermMetalDriverDataSourcePerFrameState;
@class iTermMetalBufferPoolContext;
@class iTermMetalDebugInfo;
@class iTermMetalRendererTransientState;
@class iTermMetalRowData;
@class iTermTexturePool;
@class MTKView;
@class MTLRenderPassDescriptor;
@protocol CAMetalDrawable;

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalFrameData : NSObject
@property (atomic, readonly) iTermTexturePool *fullSizeTexturePool;
@property (atomic, strong) id<iTermMetalDriverDataSourcePerFrameState> perFrameState;
@property (atomic, strong) NSMutableArray<iTermMetalRowData *> *rows;
@property (atomic) vector_uint2 viewportSize;
@property (atomic) VT100GridSize gridSize;
@property (atomic) CGSize cellSize;
@property (atomic) CGSize glyphSize;
@property (atomic) CGSize cellSizeWithoutSpacing;
@property (atomic) CGFloat scale;
@property (atomic) BOOL hasBackgroundImage;
@property (atomic) CGSize asciiOffset;
@property (atomic, strong) NSString *status;
@property (atomic, strong) id<MTLDevice> device;
@property (atomic, strong, readonly) MTKView *view;
@property (nonatomic, readonly) NSInteger frameNumber;
@property (nonatomic, readonly) iTermPreciseTimerStats *stats;
@property (nonatomic, readonly) NSArray<iTermHistogram *> *statHistograms;
@property (nonatomic, strong) id<CAMetalDrawable> destinationDrawable;
@property (nonatomic, strong) id<MTLTexture> destinationTexture;
@property (nonatomic, strong) MTLRenderPassDescriptor *renderPassDescriptor;
@property (nonatomic, strong) MTLRenderPassDescriptor *debugRealRenderPassDescriptor;
@property (nonatomic, readonly) iTermMetalBufferPoolContext *framePoolContext;
@property (nonatomic, strong) iTermMetalDebugInfo *debugInfo;
@property (nonatomic, readonly) iTermCellRenderConfiguration *cellConfiguration;
@property (nonatomic, strong) id<MTLCommandBuffer> commandBuffer;
@property (nonatomic, strong) id<MTLRenderCommandEncoder> renderEncoder;
@property (nonatomic, strong) dispatch_group_t group;  // nonnil implies synchronous
@property (nonatomic) BOOL hasManyColorCombos;
@property (nonatomic) BOOL deferCurrentDrawable;

// When drawing to an intermediate texture there may be two passes (i.e., two render encoders)
@property (nonatomic) int currentPass;

// For debugging. Gives an order to the log files.
@property (nonatomic) int numberOfRenderersDrawn;

// If nonnil then all draw stages before text draw with encoders from this render pass descriptor.
// It will have a texture identical to the drawable's texture. Invoke createIntermediateRenderPassDescriptor
// to create this if it's nil.
@property (nonatomic, strong) MTLRenderPassDescriptor *intermediateRenderPassDescriptor NS_DEPRECATED_MAC(10_12, 10_14);
#if ENABLE_USE_TEMPORARY_TEXTURE
@property (nonatomic, strong) MTLRenderPassDescriptor *temporaryRenderPassDescriptor NS_DEPRECATED_MAC(10_12, 10_14);
#endif

- (instancetype)initWithView:(MTKView *)view
         fullSizeTexturePool:(iTermTexturePool *)fullSizeTexturePool NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSTimeInterval)measureTimeForStat:(iTermMetalFrameDataStat)stat ofBlock:(void (^)(void))block;
#if ENABLE_PRIVATE_QUEUE
- (void)dispatchToPrivateQueue:(dispatch_queue_t)queue forPreparation:(void (^)(void))block;
#endif
- (void)createpostmultipliedRenderPassDescriptor NS_AVAILABLE_MAC(10_14);
- (void)createIntermediateRenderPassDescriptor NS_DEPRECATED_MAC(10_12, 10_14);
#if ENABLE_USE_TEMPORARY_TEXTURE
- (void)createTemporaryRenderPassDescriptor NS_DEPRECATED_MAC(10_12, 10_14);;
#endif
- (void)dispatchToQueue:(dispatch_queue_t)queue forCompletion:(void (^)(void))block;
- (void)enqueueDrawCallsWithBlock:(void (^)(void))block;
- (void)didCompleteWithAggregateStats:(iTermPreciseTimerStats *)aggregateStats
                           histograms:(NSArray<iTermHistogram *> *)aggregateHistograms
                                owner:(NSString *)owner;

- (__kindof iTermMetalRendererTransientState *)transientStateForRenderer:(NSObject *)renderer;
- (void)setTransientState:(iTermMetalRendererTransientState *)tState forRenderer:(NSObject *)renderer;
- (MTLRenderPassDescriptor *)newRenderPassDescriptorWithLabel:(NSString *)label
                                                         fast:(BOOL)fast;

- (void)updateRenderEncoderWithRenderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor
                                               stat:(iTermMetalFrameDataStat)stat
                                              label:(NSString *)label;

@end

