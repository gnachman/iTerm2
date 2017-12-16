//
//  iTermMetalBufferPool.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/14/17.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MTLBuffer;

@interface iTermMetalBufferPoolContext : NSObject
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

- (instancetype)initWithDevice:(id<MTLDevice>)device capacity:(NSUInteger)capacity NS_DESIGNATED_INITIALIZER;

- (id<MTLBuffer>)requestBufferFromContext:(iTermMetalBufferPoolContext *)context
                                     size:(size_t)size;


@end

NS_ASSUME_NONNULL_END
