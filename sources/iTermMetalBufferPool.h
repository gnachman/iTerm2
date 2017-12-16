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

NS_ASSUME_NONNULL_END
