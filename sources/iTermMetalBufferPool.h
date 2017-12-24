//
//  iTermMetalBufferPool.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/14/17.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermHistogram;
@protocol MTLBuffer;

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalBufferPoolContext : NSObject
@property (nonatomic, readonly) iTermHistogram *histogram;
@property (nonatomic, readonly) iTermHistogram *textureHistogram;
@property (nonatomic, readonly) iTermHistogram *wasteHistogram;

- (NSString *)summaryStatisticsWithName:(NSString *)name;
- (void)didAddTextureOfSize:(double)size;

// Relinquished buffers will not automatically be returned to the pool after the frame is done.
- (void)relinquishOwnershipOfBuffer:(id<MTLBuffer>)buffer;
@end

// Creating a new buffer can be very slow. Try to reuse them.
NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalBufferPool : NSObject

@property (nonatomic) size_t bufferSize;

- (instancetype)initWithDevice:(id<MTLDevice>)device
                    bufferSize:(size_t)bufferSize NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (id<MTLBuffer>)requestBufferFromContext:(iTermMetalBufferPoolContext *)context;
- (id<MTLBuffer>)requestBufferFromContext:(iTermMetalBufferPoolContext *)context
                                withBytes:(const void *)bytes
                           checkIfChanged:(BOOL)checkIfChanged;

@end

// Keeps up to `capacity` buffers in the pool. If it exceeds that size the smallest ones are released.
// This might use more texture memory than necessary but it will stabilize quickly and stop creating
// new buffers, which is terribly slow.
NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalMixedSizeBufferPool : NSObject
@property (nonatomic, copy, readonly) NSString *name;

- (instancetype)initWithDevice:(id<MTLDevice>)device capacity:(NSUInteger)capacity name:(NSString *)name NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (id<MTLBuffer>)requestBufferFromContext:(iTermMetalBufferPoolContext *)context
                                     size:(size_t)size;

- (id<MTLBuffer>)requestBufferFromContext:(iTermMetalBufferPoolContext *)context
                                     size:(size_t)size
                                    bytes:(const void *)bytes;


@end

NS_ASSUME_NONNULL_END
