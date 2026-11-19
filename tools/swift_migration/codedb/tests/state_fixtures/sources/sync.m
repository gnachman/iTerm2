// Fixture: @synchronized, directly and through a copy of ITNonnilLock, compiled with ARC. Line numbers are part of the expectations.
#import "state_base.h"
void it_lockFailed(const char *text);
// A copy of ITNonnilLock in sources/Logging/DebugLogging.h, with ITBetaAssert reduced to a call.
#define ITNonnilLock(lockExpression) \
  ({ \
    id it_nonnilLock_ = (lockExpression); \
    do { if (!(it_nonnilLock_ != (id)0)) { it_lockFailed(#lockExpression); } } while (0); \
    it_nonnilLock_; \
  })
static id sLock;
@interface Locker : Root
- (id)other;
@end
@implementation Locker {
    id _lock;
    int _a;
    int _b;
}
- (id)other {
    return _lock;
}
- (void)work {
    @synchronized (ITNonnilLock(_lock)) {
        _a = 1;
        _b++;
    }
    @synchronized (_lock) {
        _b = 0;
    }
    @synchronized (self) {
        _a = 2;
    }
    @synchronized (ITNonnilLock(sLock)) {
        _a = 3;
    }
    @synchronized ([Locker class]) {
        _b = 4;
    }
    @synchronized (ITNonnilLock([self other])) {
        void (^blk)(void) = ^{ _a = 5; };
        blk();
    }
    _a = 6;
}
@end
