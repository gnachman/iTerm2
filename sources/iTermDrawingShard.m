//
//  iTermDrawingShard.m
//  iTerm2
//
//  Created by George Nachman on 7/28/16.
//
//

#import "iTermDrawingShard.h"

static uint64_t gDrawingEpoch;
dispatch_queue_t gCompositingQueue;

void ResetDrawingEpoch() {
    gDrawingEpoch = mach_absolute_time();
}

NSTimeInterval MillisSinceDrawingEpoch() {
    static mach_timebase_info_data_t sTimebaseInfo;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mach_timebase_info(&sTimebaseInfo);
    });

    double nanoseconds = (mach_absolute_time() - gDrawingEpoch) * sTimebaseInfo.numer / sTimebaseInfo.denom;
    double ms = nanoseconds / 1000000.0;
    return ms;
}


@implementation iTermDrawingShard {
    NSMutableData *_data;
    dispatch_queue_t _queue;
    NSMutableArray *_events;
    CGFloat _scale;
}

+ (dispatch_queue_t)queueForShardNumber:(int)shardNumber {
    static NSMutableArray<dispatch_queue_t> *queues;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queues = [[NSMutableArray alloc] init];
    });
    while (queues.count <= shardNumber) {
        [queues addObject:dispatch_queue_create("com.googlecode.iterm2.DrawingQueue", DISPATCH_QUEUE_SERIAL)];
    }
    
    return queues[shardNumber];
}

+ (CGLayerRef)layerOfSize:(NSSize)size scale:(CGFloat)scale data:(NSMutableData *)data context:(CGContextRef)context {
    CGSize scaledSize = CGSizeMake(size.width * scale, size.height * scale);
    return CGLayerCreateWithContext(context, scaledSize, NULL);
}

+ (CGContextRef)bitmapContextOfSize:(NSSize)size scale:(CGFloat)scale data:(NSMutableData *)data {
    NSInteger bytesPerRow = size.width * scale * 4;
    NSUInteger storageNeeded = bytesPerRow * scale * size.height;
    NSLog(@"%0.6fms: Calling setLength: %d", MillisSinceDrawingEpoch(), (int)storageNeeded);
    [data setLength:storageNeeded];
    
    NSLog(@"%0.6fms: Calling CGColorSpaceCreateDeviceRGB", MillisSinceDrawingEpoch());

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    NSLog(@"%0.6fms: Calling CGBitmapContextCreate", MillisSinceDrawingEpoch());

    CGContextRef bitmapContext = CGBitmapContextCreate((void *)data.mutableBytes,
                                                       size.width * scale,
                                                       size.height * scale,
                                                       8,
                                                       bytesPerRow,
                                                       colorSpace,
                                                       (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    NSLog(@"%0.6fms: Returned from CGBitmapContextCreate", MillisSinceDrawingEpoch());
    assert(bitmapContext);
    CGColorSpaceRelease(colorSpace);
    CGContextScaleCTM(bitmapContext, scale, scale);
    return bitmapContext;

}

- (instancetype)initWithRect:(NSRect)rect
                       scale:(CGFloat)scale
                       range:(NSRange)range
               bitmapContext:(CGContextRef)bitmapContext
                       queue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        _data = [[NSMutableData alloc] init];
        _events = [[NSMutableArray alloc] init];
        [self addEvent:@"Begin Initialize shard"];
        _range = range;
        _rect = rect;
        _scale = scale;
        _group = dispatch_group_create();
        self.bitmapContext = bitmapContext;
        _queue = queue;
        _capacity = rect.size;
        if (queue) {
            dispatch_retain(queue);
        }
        if (bitmapContext) {
            CFRetain(bitmapContext);
        }
        [self addEvent:@"End Initialize shard"];
    }
    return self;
}

- (void)setBitmapContext:(CGContextRef)bitmapContext {
    if (_bitmapContext) {
        CFRelease(_bitmapContext);
    }
    _bitmapContext = bitmapContext;
    if (bitmapContext) {
        CFRetain(bitmapContext);
    }
}

// [[iTermDrawingShard alloc] initWithSize:NSMakeSize(width * scale, _cellSize.height * scale) scale:self.isRetina ? 2.0 : 1.0];
- (instancetype)initWithRect:(NSRect)rect scale:(CGFloat)scale range:(NSRange)range shardNumber:(int)shardNumber {
    if (range.length == 0 || rect.size.height <= 0) {
        return nil;
    }
    NSLog(@"%0.6fms: Creating bitmap context for shard %d", MillisSinceDrawingEpoch(), shardNumber);
//    CGContextRef bitmapContext = [iTermDrawingShard bitmapContextOfSize:rect.size scale:scale data:_data];
    NSLog(@"%0.6fms: Done creating bitmap context for shard %d", MillisSinceDrawingEpoch(), shardNumber);
    dispatch_queue_t queue = [iTermDrawingShard queueForShardNumber:shardNumber];
    self = [self initWithRect:rect scale:scale range:range bitmapContext:nil queue:queue];
//    CFRelease(bitmapContext);
    CFRelease(queue);
    if (self) {
        if (shardNumber >= 0) {
            _shardNumber = shardNumber;
            dispatch_retain(_queue);
        }
    }
    return self;
}

- (void)dealloc {
    if (_bitmapContext) {
        CFRelease(_bitmapContext);
    }
    if (_queue) {
        dispatch_release(_queue);
    }
    dispatch_release(_group);
    [_events release];
    [_data release];
    [super dealloc];
}

- (void)setLayerContextFromContext:(CGContextRef)context {
    if (_layer) {
        CFRelease(_layer);
        _layer = nil;
    }
    if (context) {
        _layer = [iTermDrawingShard layerOfSize:_rect.size scale:_scale data:_data context:context];
        self.bitmapContext = CGLayerGetContext(_layer);
    } else {
        self.bitmapContext = nil;
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p number=%d destination=%@ range=%@>",
            NSStringFromClass([self class]), self, _shardNumber, NSStringFromRect(_rect),
            NSStringFromRange(_range)];
}

- (void)addDebugEvent:(NSString *)event {
    [self addEvent:event];
}

- (void)addEvent:(NSString *)event {
    @synchronized(self) {
        [_events addObject:[NSString stringWithFormat:@"%0.6fms: %@", MillisSinceDrawingEpoch(), event]];
    }
}

- (void)removeAllEvents {
    @synchronized(self) {
        [_events removeAllObjects];
    }
}

- (void)drawWithBlock:(void (^)())block {
    [self addDebugEvent:@"Queue drawing block"];
    dispatch_group_enter(_group);
    dispatch_async(_queue, ^{
        [self addDebugEvent:@"Begin drawing"];
        block();
        [self addDebugEvent:@"End drawing"];
        [self addEvent:[NSString stringWithFormat:@"Shard %d drew", _shardNumber]];
        dispatch_group_leave(_group);
    });
}

- (void)compositeWhenReady {
    if (_compositingBlock) {
        dispatch_group_notify(_group, gCompositingQueue, ^() {
            [self addEvent:@"Begin compositing"];
            _compositingBlock();
            [self addEvent:@"End compositing"];
        });
    }
}

@end

@implementation iTermSynchronousDrawingShard

- (void)drawWithBlock:(void (^)())block {
//    NSLog(@"Perform draw on synchronous shard");
    block();
}

@end

