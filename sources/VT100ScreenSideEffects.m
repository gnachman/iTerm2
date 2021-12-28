//
//  VT100ScreenSideEffects.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/21/21.
//

#import "VT100ScreenSideEffects.h"

typedef void (^VT100ScreenSideEffectGenericBlock)(id delegate);

typedef NS_ENUM(NSUInteger, VT100ScreenSideEffectType) {
    VT100ScreenSideEffectTypeDelegate,
    VT100ScreenSideEffectTypeIntervalTreeObserver
};

@interface VT100ScreenSideEffect: NSObject
@property (nonatomic, readonly) VT100ScreenSideEffectType type;

- (instancetype)initWithType:(VT100ScreenSideEffectType)type
                       block:(VT100ScreenSideEffectGenericBlock)block;
- (instancetype)init NS_UNAVAILABLE;

- (void)executeWithDelegate:(id)delegate;

@end

@implementation VT100ScreenSideEffect {
    VT100ScreenSideEffectGenericBlock _block;
}

- (instancetype)initWithType:(VT100ScreenSideEffectType)type
                       block:(VT100ScreenSideEffectGenericBlock)block {
    self = [super init];
    if (self) {
        _type = type;
        _block = [block copy];
    }
    return self;
}

- (void)executeWithDelegate:(id)delegate {
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
    VT100ScreenSideEffect *sideEffect = [[VT100ScreenSideEffect alloc] initWithType:VT100ScreenSideEffectTypeDelegate
                                                                              block:block];
    [_queue addObject:sideEffect];
}

- (void)addIntervalTreeSideEffect:(VT100ScreenIntervalTreeSideEffectBlock)block {
    VT100ScreenSideEffect *sideEffect = [[VT100ScreenSideEffect alloc] initWithType:VT100ScreenSideEffectTypeIntervalTreeObserver
                                                                              block:(VT100ScreenSideEffectGenericBlock)block];
    [_queue addObject:sideEffect];
}

- (void)executeWithDelegate:(id<VT100ScreenDelegate>)delegate
       intervalTreeObserver:(nonnull id<iTermIntervalTreeObserver>)observer {
    NSArray<VT100ScreenSideEffect *> *queue;
    queue = [_queue copy];
    [_queue removeAllObjects];
    for (VT100ScreenSideEffect *sideEffect in queue) {
        switch (sideEffect.type) {
            case VT100ScreenSideEffectTypeDelegate:
                [sideEffect executeWithDelegate:delegate];
                break;
            case VT100ScreenSideEffectTypeIntervalTreeObserver:
                [sideEffect executeWithDelegate:observer];
                break;
        }
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

