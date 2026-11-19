// Fixture: ivar and static references, compiled with ARC. Line numbers are part of the expectations.
#import "holder.h"
#define BUMP(x) ((x)++)
#define RESET_COUNT _count = 0
int gHolderCount = 0;
NSString *const kExported = @"exported";
static int sCounter;
static NSString *const kName = @"name";
static NSString *sMutable;
static const char *sPrefix = "p";
void Fill(int *p);
@interface Holder () {
    int _extCount;
}
@end
@implementation Holder {
    __unsafe_unretained id _unsafe;
    int _storage;
    Boxed2 _boxed;
}
@synthesize renamed = _storage;
@synthesize other;
- (void)run:(Holder *)peer {
    _count = 1;
    _count += 2;
    _count++;
    int c = _count;
    Fill(&_count);
    int *p = &_extCount;
    self->_count = c + *p;
    peer->_count = 3;
    _rect.origin.x = 1;
    _buf[2] = 5;
    @synchronized (_plain) {
    }
    (void)sizeof(_count);
    BUMP(_count);
    RESET_COUNT;
    _unsafe = _plain;
    sCounter = sCounter + 1;
    sMutable = kName;
    gHolderCount++;
    (void)sPrefix;
    (void)kHeaderLimit;
    _cursor = 0;
}
- (void)blocks {
    void (^b)(void) = ^{ _count = 4; };
    __weak typeof(self) weakSelf = self;
    void (^d)(void) = ^{
        typeof(self) strongSelf = weakSelf;
        strongSelf->_count = 5;
    };
    b();
    d();
}
+ (Holder *)shared {
    static Holder *sShared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sShared = [[Holder alloc] init];
    });
    static int calls;
    calls++;
    return sShared;
}
@end
