#import <stdatomic.h>
#import <Foundation/Foundation.h>

@interface AtomicCounter : NSObject
@end

@implementation AtomicCounter {
    _Atomic int _count;
    int32_t _legacy;
}

- (void)bump {
    atomic_fetch_add(&_count, 1);
    OSAtomicIncrement32Barrier(&_legacy);
}

@end
