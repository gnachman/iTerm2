//
//  iTermMetalBufferPool.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/14/17.
//

#import "iTermMetalBufferPool.h"
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermMetalBufferPoolContextStackKey = @"iTermMetalBufferPoolContextStackKey";

@interface iTermMetalBufferPool()
- (void)returnBuffer:(id<MTLBuffer>)buffer;
@end

@interface iTermMetalBufferPoolContextEntry : NSObject
@property (nonatomic, strong) id<MTLBuffer> buffer;
@property (nonatomic, strong) iTermMetalBufferPool *pool;
@end

@implementation iTermMetalBufferPoolContextEntry
@end

@interface iTermMetalBufferPoolContext()
- (void)addBuffer:(id<MTLBuffer>)buffer pool:(iTermMetalBufferPool *)pool;
@end

@implementation iTermMetalBufferPoolContext {
    NSMutableArray<iTermMetalBufferPoolContextEntry *> *_entries;
}
- (instancetype)init {
    self = [super init];
    if (self) {
        _entries = [NSMutableArray array];
    }
    return self;
}

- (void)dealloc {
    for (iTermMetalBufferPoolContextEntry *entry in _entries) {
        [entry.pool returnBuffer:entry.buffer];
    }
    [_entries removeAllObjects];
}

- (void)addBuffer:(id<MTLBuffer>)buffer pool:(iTermMetalBufferPool *)pool {
    iTermMetalBufferPoolContextEntry *entry = [[iTermMetalBufferPoolContextEntry alloc] init];
    entry.buffer = buffer;
    entry.pool = pool;
    [_entries addObject:entry];
}

@end

@implementation iTermMetalBufferPool {
    id<MTLDevice> _device;
    size_t _bufferSize;
    NSMutableArray<id<MTLBuffer>> *_buffers;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
                    bufferSize:(size_t)bufferSize {
    self = [super init];
    if (self) {
        _device = device;
        _bufferSize = bufferSize;
        _buffers = [NSMutableArray array];
    }
    return self;
}

- (void)setBufferSize:(size_t)bufferSize {
    @synchronized(self) {
        if (bufferSize != _bufferSize) {
            _bufferSize = bufferSize;
            [_buffers removeAllObjects];
        }
    }

}
- (id<MTLBuffer>)requestBufferFromContext:(iTermMetalBufferPoolContext *)context {
    assert(context);
    @synchronized(self) {
        id<MTLBuffer> buffer;
        if (_buffers.count) {
            buffer = _buffers.lastObject;
            [_buffers removeLastObject];
        } else {
            buffer = [_device newBufferWithLength:_bufferSize options:MTLResourceStorageModeShared];
        }
        [context addBuffer:buffer pool:self];
        return buffer;
    }
}

- (id<MTLBuffer>)requestBufferFromContext:(iTermMetalBufferPoolContext *)context
                                withBytes:(const void *)bytes
                           checkIfChanged:(BOOL)checkIfChanged {
    assert(context);
    @synchronized(self) {
        id<MTLBuffer> buffer;
        if (_buffers.count) {
            buffer = _buffers.lastObject;
            [_buffers removeLastObject];
            if (checkIfChanged) {
                if (memcmp(bytes, buffer.contents, _bufferSize)) {
                    memcpy(buffer.contents, bytes, _bufferSize);
                }
            } else {
                memcpy(buffer.contents, bytes, _bufferSize);
            }
        } else {
            buffer = [_device newBufferWithBytes:bytes length:_bufferSize options:MTLResourceStorageModeShared];
        }
        [context addBuffer:buffer pool:self];
        return buffer;
    }
}

- (void)returnBuffer:(id<MTLBuffer>)buffer {
    @synchronized(self) {
        [_buffers addObject:buffer];
    }
}

@end

NS_ASSUME_NONNULL_END
