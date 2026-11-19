// Fixtures for extract_check.py: Objective-C. Compiled with ARC. Each range is
// the lines between "// NAME{" and "// NAME}". The file declares its own root
// class so that it needs no SDK framework.

#define nil ((id)0)

void log_line(const char *file, int line, const char *function, const char *message);
#define DLOG(msg) do { log_line(__FILE__, __LINE__, __FUNCTION__, msg); } while (0)

__attribute__((objc_root_class))
@interface Base {
@public
    int _count;
}
- (int)value;
- (void)tick;
@end

@interface Thing : Base
@property (nonatomic) int value2;
@end

@implementation Base
- (int)value { return _count; }
- (void)tick { _count++; }
@end

void consume(id);
void consumeInt(int);
int makeInt(void);
const char *sel_getName(SEL);
id make(void);
void run(void (^)(void));

@implementation Thing

- (int)value {
    int base = 0;
    // self_uses{
    base = [super value];
    _count = base + 1;
    [self tick];
    DLOG(sel_getName(_cmd));
    // self_uses}
    return base;
}

- (void)synchronized:(id)lock {
    @synchronized (lock) {
        // return_in_synchronized{
        if (!lock) {
            return;
        }
        consume(lock);
        // return_in_synchronized}
    }
}

- (void)pool {
    // pool_inside{
    @autoreleasepool {
        consume(make());
    }
    // pool_inside}
}

- (int)tryFinally:(int)x {
    @try {
        // return_in_try{
        if (x < 0) {
            return -1;
        }
        consume(nil);
        // return_in_try}
    } @finally {
        consume(nil);
    }
    return 0;
}

- (void)rethrow {
    @try {
        consume(nil);
    } @catch (id e) {
        // rethrow{
        consume(e);
        @throw;
        // rethrow}
    }
}

- (int)blockCopy {
    int x = 1;
    // block_copy{
    x = 2;
    run(^{ consumeInt(x); });
    // block_copy}
    return x;
}

- (int)blockByref {
    __block int x = 1;
    // block_byref{
    run(^{ x = 3; });
    // block_byref}
    return x;
}

- (int)returnInBlock {
    int y = 0;
    // return_in_block{
    run(^{
        if (y) {
            return;
        }
        consume(nil);
    });
    // return_in_block}
    return y;
}

- (void)objects {
    id strongThing = make();
    __weak id weakThing = strongThing;
    __autoreleasing id arThing = nil;
    // objects{
    strongThing = make();
    consume(weakThing);
    arThing = strongThing;
    // objects}
    consume(strongThing);
    consume(arThing);
}

- (void)inBlock {
    run(^{
        int inner = 0;
        // inside_block{
        inner = makeInt();
        consumeInt(inner);
        // inside_block}
    });
}

- (void)forIn:(id)collection {
    id last = nil;
    // for_in{
    for (last in collection) {
        consume(last);
    }
    // for_in}
    consume(last);
}

- (void)propertyAndMessage:(Thing *)other {
    int v = 0;
    // message_receiver{
    v = [other value];
    // message_receiver}
    consumeInt(v);
}

- (void)setterUse:(Thing *)other {
    int v = makeInt();
    // setter{
    other.value2 = v;
    // setter}
}

@end
