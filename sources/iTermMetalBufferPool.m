//
//  iTermMetalBufferPool.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/14/17.
//

#import "iTermMetalBufferPool.h"

#import "DebugLogging.h"
#import "iTermHistogram.h"
#import "NSArray+iTerm.h"
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermMetalBufferPoolContextStackKey = @"iTermMetalBufferPoolContextStackKey";

@protocol iTermMetalBufferPool<NSObject>
- (void)returnBuffer:(id<MTLBuffer>)buffer;
@end

@interface iTermMetalBufferPool()<iTermMetalBufferPool>
@end

@interface iTermMetalMixedSizeBufferPool()<iTermMetalBufferPool>
@end

@interface iTermMetalBufferPoolContextEntry : NSObject
@property (nonatomic, strong) id<MTLBuffer> buffer;
@property (nonatomic, strong) id<iTermMetalBufferPool> pool;
@end

@implementation iTermMetalBufferPoolContextEntry
@end

@interface iTermMetalBufferPoolContext()
- (void)addBuffer:(id<MTLBuffer>)buffer pool:(id<iTermMetalBufferPool>)pool;
@end

@implementation iTermMetalBufferPoolContext {
    NSMutableArray<iTermMetalBufferPoolContextEntry *> *_entries;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _entries = [NSMutableArray array];
        _histogram = [[iTermHistogram alloc] init];
        _textureHistogram = [[iTermHistogram alloc] init];
        _wasteHistogram = [[iTermHistogram alloc] init];
    }
    return self;
}

- (void)dealloc {
    for (iTermMetalBufferPoolContextEntry *entry in _entries) {
        [entry.pool returnBuffer:entry.buffer];
    }
    [_entries removeAllObjects];
}

- (void)didAddTextureOfSize:(double)size {
    [_textureHistogram addValue:size];
}

- (void)addBuffer:(id<MTLBuffer>)buffer pool:(id<iTermMetalBufferPool>)pool {
    [_histogram addValue:buffer.length];
    iTermMetalBufferPoolContextEntry *entry = [[iTermMetalBufferPoolContextEntry alloc] init];
    entry.buffer = buffer;
    entry.pool = pool;
    [_entries addObject:entry];
}

- (void)relinquishOwnershipOfBuffer:(id<MTLBuffer>)buffer {
    [_entries removeObjectsPassingTest:^BOOL(iTermMetalBufferPoolContextEntry *entry) {
        return entry.buffer == buffer;
    }];
}

- (void)addWastedSpace:(double)wastedSpace {
    [_wasteHistogram addValue:wastedSpace];
}

- (NSString *)summaryStatisticsWithName:(NSString *)name {
    NSMutableString *string = [NSMutableString stringWithFormat:@"%@\n", name];
    if (_histogram.count) {
        [string appendFormat:@"  Buffer sizes: %@\n", [_histogram sparklines]];
    }
    if (_wasteHistogram.count) {
        [string appendFormat:@"  Wasted space: %@\n", [_wasteHistogram sparklines]];
    }
    if (_textureHistogram.count) {
        [string appendFormat:@"  New textures: %@\n", [_textureHistogram sparklines]];
    }
    return string;
}

@end

@implementation iTermMetalMixedSizeBufferPool {
    id<MTLDevice> _device;
    NSMutableArray<id<MTLBuffer>> *_buffers;
    NSUInteger _capacity;
    NSInteger _numberOutstanding;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device capacity:(NSUInteger)capacity name:(nonnull NSString *)name {
    self = [super init];
    if (self) {
        _name = [name copy];
        _device = device;
        _capacity = capacity;
        _buffers = [NSMutableArray arrayWithCapacity:capacity];
    }
    return self;
}

- (id<MTLBuffer>)requestBufferFromContext:(iTermMetalBufferPoolContext *)context
                                     size:(size_t)size {
    assert(context);
    @synchronized(self) {
        id<MTLBuffer> buffer;
        id<MTLBuffer> bestMatch = [[[_buffers filteredArrayUsingBlock:^BOOL(id<MTLBuffer> buffer) {
            return buffer.length > size;
        }] mininumsWithComparator:^NSComparisonResult(id<MTLBuffer> a, id<MTLBuffer> b) {
            return [@(a.length) compare:@(b.length)];
        }] firstObject];
        if (bestMatch != nil) {
            [_buffers removeObject:bestMatch];
            buffer = bestMatch;
        } else {
            buffer = [_device newBufferWithLength:size options:MTLResourceStorageModeShared];
        }
        [context addBuffer:buffer pool:self];
        [context addWastedSpace:buffer.length - size];
        return buffer;
    }
}

- (NSInteger)insertionIndexForBufferOfSize:(size_t)size {
    return [_buffers indexOfObject:(id)@(MAX(0, size - 1))
                     inSortedRange:NSMakeRange(0, _buffers.count)
                           options:NSBinarySearchingInsertionIndex
                   usingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
                       NSNumber *size1;
                       if ([obj1 isKindOfClass:[NSNumber class]]) {
                           size1 = obj1;
                       } else {
                           size1 = @([(id<MTLBuffer>)obj1 length]);
                       }
                       NSNumber *size2;
                       if ([obj2 isKindOfClass:[NSNumber class]]) {
                           size2 = obj2;
                       } else {
                           size2 = @([(id<MTLBuffer>)obj2 length]);
                       }
                       return [size1 compare:size2];
                   }];
}

- (id<MTLBuffer>)requestBufferFromContext:(iTermMetalBufferPoolContext *)context
                                     size:(size_t)size
                                    bytes:(nonnull const void *)bytes {
    assert(context);
    @synchronized(self) {
        id<MTLBuffer> buffer;
        NSInteger index = [self insertionIndexForBufferOfSize:size];
        if (index < _buffers.count) {
            id<MTLBuffer> bestMatch = _buffers[index];
            [_buffers removeObjectAtIndex:index];
            buffer = bestMatch;
            memcpy(buffer.contents, bytes, size);
        } else {
            // size was larger than the largest item
            DLog(@"%@ allocating a new buffer of size %d (%d outstanding)", _name, (int)size, (int)_numberOutstanding);
            buffer = [_device newBufferWithBytes:bytes length:size options:MTLResourceStorageModeShared];
        }
        [context addBuffer:buffer pool:self];
        [context addWastedSpace:buffer.length - size];
        _numberOutstanding++;
        return buffer;
    }
}

- (void)returnBuffer:(id<MTLBuffer>)buffer {
    @synchronized(self) {
        _numberOutstanding--;
        if (_buffers.count == _capacity) {
            [_buffers removeObjectAtIndex:0];
        }
        NSInteger index = [self insertionIndexForBufferOfSize:buffer.length];
        [_buffers insertObject:buffer atIndex:index];
    }
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
