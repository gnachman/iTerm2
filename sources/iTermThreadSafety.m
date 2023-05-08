//
//  iTermThreadSafety.m
//  iTerm2
//
//  Created by George Nachman on 3/14/20.
//

#import "iTermThreadSafety.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

#define CHECK_DOUBLE_INVOKES BETA

@interface iTermSynchronizedState()
@property (atomic) BOOL ready;
@end

@implementation iTermSynchronizedState {
    const char *_queueLabel;
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    self = [super init];
    if (self) {
        _queue = queue;
        _queueLabel = dispatch_queue_get_label(queue);
        assert(_queueLabel);
    }
    return self;
}

- (void)dealloc {
    [super dealloc];
}

static void Check(iTermSynchronizedState *self) {
    assert(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) == self->_queueLabel);
}

- (instancetype)retain {
    id result = [super retain];
    [self check];
    return result;
}

// Can't check on release because autorelease pools can be drained on a different thread.

- (instancetype)autorelease {
    [self check];
    return [super autorelease];
}

- (id)state {
    [self check];
    return self;
}

- (void)check {
    if (self.ready) {
        Check(self);
    }
}

@end

@implementation iTermMainThreadState
+ (instancetype)uncheckedSharedInstance {
    static iTermMainThreadState *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[iTermMainThreadState alloc] initWithQueue:dispatch_get_main_queue()];
    });
    return instance;
}

+ (instancetype)sharedInstance {
    iTermMainThreadState *instance = [self uncheckedSharedInstance];
    [instance check];
    return instance;
}
@end

#if CHECK_DOUBLE_INVOKES
// Weak references to all iTermThread objects.
NSPointerArray *gThreads;
#endif

@implementation iTermThread {
    iTermSynchronizedState *_state;
    NSMutableArray *_deferred;
#if CHECK_DOUBLE_INVOKES
    NSArray<NSString *> *_stacks;
#endif
}

+ (instancetype)main {
    static iTermThread *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initWithQueue:dispatch_get_main_queue()
                              stateFactory:
                ^iTermSynchronizedState * _Nullable(dispatch_queue_t  _Nonnull queue) {
            return [iTermMainThreadState uncheckedSharedInstance];
        }];
    });
    return instance;
}

+ (instancetype)withLabel:(NSString *)label
             stateFactory:(iTermThreadStateFactoryBlockType)stateFactory {
    return [[self alloc] initWithLabel:label stateFactory:stateFactory];
}

#if CHECK_DOUBLE_INVOKES
+ (iTermThread *)currentThread {
    const char *currentLabel = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
    @synchronized (gThreads) {
        for (iTermThread *thread in gThreads) {
            if ([[thread retain] autorelease] == nil) {
                continue;
            }
            if (dispatch_queue_get_label(thread->_queue) == currentLabel) {
                return thread;
            }
        }
    }
    return nil;
}
#endif

- (instancetype)initWithQueue:(dispatch_queue_t)queue
                 stateFactory:(iTermThreadStateFactoryBlockType)stateFactory {
    self = [super init];
    if (self) {
        _queue = queue;
        dispatch_retain(_queue);
        _state = [stateFactory(_queue) retain];
        _state.ready = YES;
#if CHECK_DOUBLE_INVOKES
        _stacks = [@[] retain];
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            gThreads = [[NSPointerArray weakObjectsPointerArray] retain];
        });
        @synchronized (gThreads) {
            [gThreads addPointer:self];
        }
#endif
    }
    return self;
}

+ (NSString *)uniqueQueueLabelWithName:(NSString *)label {
    static _Atomic int threadNumber;
    int i = threadNumber++;
    return [NSString stringWithFormat:@"%@.%d", label, i];
}

- (instancetype)initWithLabel:(NSString *)label
                 stateFactory:(iTermThreadStateFactoryBlockType)stateFactory {
    const char *cstr = [iTermThread uniqueQueueLabelWithName:label].UTF8String;
    return [self initWithQueue:dispatch_queue_create(cstr, DISPATCH_QUEUE_SERIAL)
                  stateFactory:stateFactory];
}

- (void)dealloc {
    dispatch_release(_queue);
    assert(!_deferred);
    [_state release];
#if CHECK_DOUBLE_INVOKES
    [_stacks release];
#endif
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p queue=%@>",
            NSStringFromClass(self.class), self, _queue];
}

- (NSString *)label {
    return [NSString stringWithUTF8String:dispatch_queue_get_label(_queue)];
}

#if CHECK_DOUBLE_INVOKES
- (NSString *)stack {
    return [_stacks componentsJoinedByString:@"\n\n"];
}

- (NSArray<NSString *> *)currentStacks {
    NSArray *frames = [[NSThread callStackSymbols] subarrayFromIndex:1];
    frames = [@[ self.label ] arrayByAddingObjectsFromArray:frames];
    NSString *stack = [frames componentsJoinedByString:@"\n"];
    return [@[stack] arrayByAddingObjectsFromArray:_stacks];
}

- (NSString *)currentStack {
    return [self.currentStacks componentsJoinedByString:@"\n\n"];
}
#endif

- (void)performDeferredBlocksAfter:(void (^ NS_NOESCAPE)(void))block {
    @synchronized(self) {
        assert(!_deferred);
        _deferred = [NSMutableArray array];
    }
    block();
    while (YES) {
        NSArray *blocks = nil;
        @synchronized (self) {
            blocks = [[_deferred copy] autorelease];
            [_deferred removeAllObjects];
            if (blocks.count == 0) {
                _deferred = nil;
                break;
            }
        }
        for (void (^block)(id) in blocks) {
            [self dispatchSync:^(id  _Nullable state) {
                block(state);
            }];
        }
    }
}

- (void)dispatchAsync:(void (^)(id))block {
    [self retain];
    @synchronized (self) {
        if (_deferred) {
            [_deferred addObject:[[block copy] autorelease]];
            return;
        }
    }
#if CHECK_DOUBLE_INVOKES
    NSArray *stacks = [[iTermThread currentThread] currentStacks] ?: @[ [[NSThread callStackSymbols]  componentsJoinedByString:@"\n"] ];
    [stacks retain];
#endif
    dispatch_async(_queue, ^{
#if CHECK_DOUBLE_INVOKES
        NSArray *saved = [_stacks retain];
        _stacks = stacks;
#endif
        block(self->_state);
#if CHECK_DOUBLE_INVOKES
        _stacks = saved;
        [stacks release];
        [saved release];
#endif
        [self release];
    });
}

- (void)dispatchSync:(void (^ NS_NOESCAPE)(id))block {
    [self retain];
    assert(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) != dispatch_queue_get_label(_queue));
    dispatch_sync(_queue, ^{
        block(self->_state);
        [self release];
    });
}

- (void)dispatchRecursiveSync:(void (^ NS_NOESCAPE)(id))block {
    if (dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) == dispatch_queue_get_label(_queue)) {
        block(self->_state);
    } else {
        [self dispatchSync:block];
    }
}

- (iTermCallback *)newCallbackWithBlock:(void (^)(id, id))callback {
    return [[iTermCallback onThread:self block:callback] retain];
}

- (iTermCallback *)newCallbackWithWeakTarget:(id)target selector:(SEL)selector userInfo:(id)userInfo {
    __weak id weakTarget = target;
    return [self newCallbackWithBlock:^(id  _Nonnull state, id  _Nullable value) {
        [weakTarget it_performNonObjectReturningSelector:selector
                                              withObject:state
                                                  object:value
                                                  object:userInfo];
    }];
}

- (void)check {
    [_state check];
}

@end

@implementation iTermCallback {
    void (^_block)(id, id);
    dispatch_group_t _group;
#if CHECK_DOUBLE_INVOKES
    NSString *_invokeStack;
    NSString *_creationStack;
    int _magic;
    NSMutableString *_debugInfo;
#endif
}

+ (instancetype)onThread:(iTermThread *)thread block:(void (^)(id, id))block {
    return [[[self alloc] initWithThread:thread block:block] autorelease];
}

- (instancetype)initWithThread:(iTermThread *)thread block:(void (^)(id, id))block {
    self = [super init];
    if (self) {
        _thread = [thread retain];
        _block = [block copy];
        _group = dispatch_group_create();
        dispatch_group_enter(_group);
#if CHECK_DOUBLE_INVOKES
        _debugInfo = [[NSMutableString alloc] init];
        _magic = 0xdeadbeef;
        _creationStack = [[[NSThread callStackSymbols] componentsJoinedByString:@"\n"] copy];
#endif
    }
    return self;
}

- (void)dealloc {
    [_thread release];
    [_block release];
#if CHECK_DOUBLE_INVOKES
    assert(_magic == 0xdeadbeef);
    [_invokeStack release];
    [_creationStack release];
    [_debugInfo release];
    _magic = 0;
#endif
    dispatch_release(_group);
    _block = nil;
    _group = nil;
    [super dealloc];
}

- (void)invokeWithObject:(id)object {
#if DEBUG
    BOOL trace = self.trace;
#endif
    void (^block)(id, id) = [_block retain];
    [self retain];
#if CHECK_DOUBLE_INVOKES
    NSString *stack = [[[iTermThread currentThread] currentStack] retain];
#endif
    [_thread dispatchAsync:^(iTermSynchronizedState *state) {
#if CHECK_DOUBLE_INVOKES
        ITAssertWithMessage(!self->_invokeStack, @"Previously invoked from:\n%@\n\nNow invoked from:\n%@\n\nCreated from:\n%@\n%@",
                     _invokeStack, stack, _creationStack, _debugInfo);
        _invokeStack = [stack copy];
        [stack release];
#endif
#if DEBUG
        if (trace) {
            NSLog(@"%@", stack);
        }
#endif
        block(state, object);
        [block release];
        dispatch_group_leave(_group);
        [self release];
    }];
}

- (void)invokeMaybeImmediatelyWithObject:(id)object {
    void (^block)(id, id) = [_block retain];
    [self retain];
#if CHECK_DOUBLE_INVOKES
    NSString *stack = [[_thread currentStack] retain];
#endif
    [_thread dispatchRecursiveSync:^(iTermSynchronizedState *state) {
#if CHECK_DOUBLE_INVOKES
        ITAssertWithMessage(!self->_invokeStack, @"Previously invoked from:\n%@\n\nNow invoked from:\n%@\n\nCreated from:\n%@\n%@",
                     _invokeStack, stack, _creationStack, _debugInfo);

        _invokeStack = [stack copy];
        [stack release];
#endif
        block(state, object);
        [block release];
        dispatch_group_leave(_group);
        [self release];
    }];
}

- (void)waitUntilInvoked {
    dispatch_group_wait(_group, DISPATCH_TIME_FOREVER);
}

- (void)addDebugInfo:(NSString *)debugInfo {
#if CHECK_DOUBLE_INVOKES
    [_debugInfo appendString:debugInfo];
    [_debugInfo appendString:@"\n"];
#endif
}

@end

@implementation iTermThreadChecker {
    __weak iTermThread *_thread;
}

- (instancetype)initWithThread:(iTermThread *)thread {
    self = [super init];
    if (self) {
        _thread = thread;
    }
    return self;
}

- (void)check {
    [_thread check];
}

- (instancetype)retain {
    id result = [super retain];
    [self check];
    return result;
}

- (oneway void)release {
    [self check];
    [super release];
}

- (instancetype)autorelease {
    [self check];
    return [super autorelease];
}

@end
