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

NS_ASSUME_NONNULL_BEGIN

@protocol iTermMetalRenderer;
@class NSColorSpace;

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
    iTermMetalFrameDataStatPqCreateOffscreenCommandLineTS,
    iTermMetalFrameDataStatPqCreateMarginTS,
    iTermMetalFrameDataStatPqCreateBlockTS,
    iTermMetalFrameDataStatPqCreateRectangleTS,
    iTermMetalFrameDataStatPqCreateTextTS,
    iTermMetalFrameDataStatPqCreateIndicatorsTS,
    iTermMetalFrameDataStatPqCreateTimestampsTS,
    iTermMetalFrameDataStatPqCreateFullScreenFlashTS,
    iTermMetalFrameDataStatPqCreateCornerCutoutTS,
    iTermMetalFrameDataStatPqCreateButtonsTS,

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
    iTermMetalFrameDataStatPqEnqueueDrawBlocks,
    iTermMetalFrameDataStatPqEnqueueDrawRectangles,
    iTermMetalFrameDataStatPqEnqueueDrawCursorGuide,
    iTermMetalFrameDataStatPqEnqueueDrawOffscreenCommandLineBgPre,
    iTermMetalFrameDataStatPqEnqueueDrawOffscreenCommandLineBg,
    iTermMetalFrameDataStatPqEnqueueDrawOffscreenCommandLineBgColors,
    iTermMetalFrameDataStatPqEnqueueDrawOffscreenCommandLineFg,
    iTermMetalFrameDataStatPqEnqueueDrawHighlightRow,
    iTermMetalFrameDataStatPqEnqueueDrawImage,
    iTermMetalFrameDataStatPqEnqueueDrawButtons,
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
@class iTermMetalView;
@class MTLRenderPassDescriptor;
@protocol CAMetalDrawable;

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalFrameData : NSObject
@property (atomic, readonly) iTermTexturePool *fullSizeTexturePool;
@property (atomic, strong, nullable) id<iTermMetalDriverDataSourcePerFrameState> perFrameState;
@property (atomic, strong, nullable) NSMutableArray<iTermMetalRowData *> *rows;
@property (atomic) vector_uint2 viewportSize;
@property (atomic) unsigned int legacyScrollbarWidth;
@property (atomic) VT100GridSize gridSize;
@property (atomic) CGSize cellSize;
@property (atomic) CGSize glyphSize;
@property (atomic) CGSize cellSizeWithoutSpacing;
@property (atomic) CGFloat scale;
@property (atomic) BOOL hasBackgroundImage;
@property (atomic) NSEdgeInsets extraMargins;
@property (atomic) CGSize asciiOffset;
@property (atomic, strong, nullable) NSString *status;
@property (atomic, strong) id<MTLDevice> device;
@property (atomic, strong, readonly) iTermMetalView *view;
@property (atomic, strong, nullable) NSColorSpace *colorSpace;
@property (atomic) BOOL extendBackgroundColorIntoMargins;
@property (nonatomic, readonly) NSInteger frameNumber;
#if ENABLE_STATS
@property (nonatomic, readonly) iTermPreciseTimerStats *stats;
@property (nonatomic, readonly) NSArray<iTermHistogram *> *statHistograms;
#endif
@property (nonatomic, strong, nullable) id<CAMetalDrawable> destinationDrawable;
@property (nonatomic, strong, nullable) id<MTLTexture> destinationTexture;
@property (nonatomic, strong, nullable) MTLRenderPassDescriptor *renderPassDescriptor;
@property (nonatomic, strong, nullable) MTLRenderPassDescriptor *debugRealRenderPassDescriptor;
@property (nonatomic, readonly, nullable) iTermMetalBufferPoolContext *framePoolContext;
@property (nonatomic, strong, nullable) iTermMetalDebugInfo *debugInfo;
@property (nonatomic, readonly) iTermCellRenderConfiguration *cellConfiguration;
@property (nonatomic, strong, nullable) id<MTLCommandBuffer> commandBuffer;
@property (nonatomic, strong, nullable) id<MTLRenderCommandEncoder> renderEncoder;
@property (nonatomic, strong, nullable) dispatch_group_t group;  // nonnil implies synchronous
@property (nonatomic) BOOL deferCurrentDrawable;
@property (nonatomic, strong, nullable) MTLCaptureDescriptor *captureDescriptor NS_AVAILABLE_MAC(10_15);
#if ENABLE_UNFAMILIAR_TEXTURE_WORKAROUND
@property (nonatomic) BOOL textureIsFamiliar;
#endif  // ENABLE_UNFAMILIAR_TEXTURE_WORKAROUND
@property (nonatomic) CGFloat maximumExtendedDynamicRangeColorComponentValue;
@property (nonatomic) CGFloat rightExtraPixels;
@property (nonatomic) CGFloat vmargin;

// When drawing to an intermediate texture there may be two passes (i.e., two render encoders)
@property (nonatomic) int currentPass;

// For debugging. Gives an order to the log files.
@property (nonatomic) int numberOfRenderersDrawn;

// When using subpixel AA, all draw stages prior to Text write to this descriptor.
@property (nonatomic, strong, nullable) MTLRenderPassDescriptor *intermediateRenderPassDescriptor;

// When using subpixel AA, the intermediate rpd's texture is copied to the temporary rpd's texture
// and then text is rendered to this rpd while sampling from the intermediate rpd's texture.
// Eventually this gets copied to the drawable.
@property (nonatomic, strong, nullable) MTLRenderPassDescriptor *temporaryRenderPassDescriptor;

- (instancetype)initWithView:(iTermMetalView *)view
         fullSizeTexturePool:(iTermTexturePool *)fullSizeTexturePool NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSTimeInterval)measureTimeForStat:(iTermMetalFrameDataStat)stat ofBlock:(void (^ NS_NOESCAPE)(void))block;
#if ENABLE_PRIVATE_QUEUE
- (void)dispatchToPrivateQueue:(dispatch_queue_t)queue forPreparation:(void (^)(void))block;
#endif
- (void)createIntermediateRenderPassDescriptor;
- (void)createTemporaryRenderPassDescriptor;
- (void)dispatchToQueue:(dispatch_queue_t)queue forCompletion:(void (^)(void))block;
- (void)enqueueDrawCallsWithBlock:(void (^)(void))block;
- (void)didCompleteWithAggregateStats:(iTermPreciseTimerStats *)aggregateStats
                           histograms:(NSArray<iTermHistogram *> *)aggregateHistograms
                                owner:(NSString *)owner
                           additional:(NSString *)additional;

- (__kindof iTermMetalRendererTransientState * _Nullable)transientStateForRenderer:(NSObject *)renderer;
- (void)setTransientState:(iTermMetalRendererTransientState *)tState forRenderer:(NSObject *)renderer;
- (MTLRenderPassDescriptor *)newRenderPassDescriptorWithLabel:(NSString *)label
                                                         fast:(BOOL)fast;

- (void)updateRenderEncoderWithRenderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor
                                               stat:(iTermMetalFrameDataStat)stat
                                              label:(NSString *)label;

@end

NS_ASSUME_NONNULL_END
