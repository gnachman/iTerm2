//
//  VT100ScreenSideEffects.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/21/21.
//

#import "VT100ScreenSideEffects.h"

@interface VT100ScreenSideEffect: NSObject

- (instancetype)initWithBlock:(VT100ScreenSideEffectBlock)block;
- (instancetype)init NS_UNAVAILABLE;

- (void)executeWithDelegate:(id<VT100ScreenDelegate>)delegate;

@end

@implementation VT100ScreenSideEffect {
    void (^_block)(id<VT100ScreenDelegate> delegate);
}

- (instancetype)initWithBlock:(VT100ScreenSideEffectBlock)block {
    self = [super init];
    if (self) {
        _block = [block copy];
    }
    return self;
}

- (void)executeWithDelegate:(id<VT100ScreenDelegate>)delegate {
    _block(delegate);
}

@end

@implementation VT100ScreenSideEffectQueue {
    NSMutableArray<VT100ScreenSideEffect *> *_queue;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = [NSMutableArray array];
    }
    return self;
}

- (void)addSideEffect:(VT100ScreenSideEffectBlock)block {
    VT100ScreenSideEffect *sideEffect = [[VT100ScreenSideEffect alloc] initWithBlock:block];
    [_queue addObject:sideEffect];
}

- (void)executeWithDelegate:(id<VT100ScreenDelegate>)delegate {
    NSArray<VT100ScreenSideEffect *> *queue;
    queue = [_queue copy];
    [_queue removeAllObjects];
    for (VT100ScreenSideEffect *sideEffect in queue) {
        [sideEffect executeWithDelegate:delegate];
    }
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    VT100ScreenSideEffectQueue *copy = [[VT100ScreenSideEffectQueue alloc] init];
    [copy->_queue addObjectsFromArray:_queue];
    [_queue removeAllObjects];
    return _queue;
}

@end

