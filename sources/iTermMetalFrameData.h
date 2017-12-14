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

typedef NS_ENUM(int, iTermMetalFrameDataStat) {
    iTermMetalFrameDataStatMtExtractFromApp,
    iTermMetalFrameDataStatDispatchToPrivateQueue,
    iTermMetalFrameDataStatPqBuildRowData,
    iTermMetalFrameDataStatPqUpdateRenderers,
    iTermMetalFrameDataStatPqCreateTransientStates,
    iTermMetalFrameDataStatPqPopulateTransientStates,
    iTermMetalFrameDataStatDispatchToMainQueue,
    iTermMetalFrameDataStatMtGetCurrentDrawable,
    iTermMetalFrameDataStatMtGetRenderPassDescriptor,
    iTermMetalFrameDataStatMtEnqueueDrawCalls,
    iTermMetalFrameDataStatMtEnqueueDrawMargin,
    iTermMetalFrameDataStatMtEnqueueDrawBackgroundImage,
    iTermMetalFrameDataStatMtEnqueueDrawBackgroundColor,
    iTermMetalFrameDataStatMtEnqueueDrawCursor,
    iTermMetalFrameDataStatMtEnqueueCopyBackground,
    iTermMetalFrameDataStatMtEnqueueDrawText,
    
    iTermMetalFrameDataStatGpu,
    iTermMetalFrameDataStatEndToEnd,

    iTermMetalFrameDataStatCount
};

extern void iTermMetalFrameDataStatsBundleInitialize(iTermPreciseTimerStats *bundle);
extern void iTermMetalFrameDataStatsBundleAdd(iTermPreciseTimerStats *dest, iTermPreciseTimerStats *source);

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
@property (nonatomic, readonly) iTermPreciseTimerStats *stats;

// If nonnil then all draw stages before text draw with encoders from this render pass descriptor.
// It will have a texture identical to the drawable's texture.
@property (nonatomic, strong) MTLRenderPassDescriptor *intermediateRenderPassDescriptor;

- (instancetype)initWithView:(MTKView *)view NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)measureTimeForStat:(iTermMetalFrameDataStat)stat ofBlock:(void (^)(void))block;
- (void)dispatchToPrivateQueue:(dispatch_queue_t)queue forPreparation:(void (^)(void))block;
- (void)dispatchToMainQueue:(void (^)(void))block;
- (void)willHandOffToGPU;
- (void)didCompleteWithAggregateStats:(iTermPreciseTimerStats *)aggregateStats;

@end

