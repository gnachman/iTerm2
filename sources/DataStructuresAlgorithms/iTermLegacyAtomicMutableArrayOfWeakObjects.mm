//
//  iTermLegacyAtomicMutableArrayOfWeakObjects.mm
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/3/23.
//

#import "iTermLegacyAtomicMutableArrayOfWeakObjects.h"

extern "C" {
#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "iTermWeakBox.h"
}

#include <atomic>

@implementation iTermLegacyAtomicMutableArrayOfWeakObjects {
    NSMutableArray<iTermWeakBox *> *_array;
    id _lock;
}

// Sanity check
static std::atomic<int> iTermLegacyAtomicMutableArrayOfWeakObjectsLockCount;
static void iTermLegacyAtomicMutableArrayOfWeakObjectsLock(void) {
    iTermLegacyAtomicMutableArrayOfWeakObjectsLockCount += 1;
    assert(iTermLegacyAtomicMutableArrayOfWeakObjectsLockCount == 1);
}

static void iTermLegacyAtomicMutableArrayOfWeakObjectsLockUnlock(void) {
    iTermLegacyAtomicMutableArrayOfWeakObjectsLockCount -= 1;
    assert(iTermLegacyAtomicMutableArrayOfWeakObjectsLockCount == 0);
}

+ (id)lock {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[NSObject alloc] init];
    });
    return instance;
}

+ (instancetype)array {
    return [[self alloc] init];
}

- (instancetype)init {
    if (self = [super init]) {
        _array = [NSMutableArray array];
    }
    return self;
}

- (void)removeObjectsPassingTest:(BOOL (^)(id anObject))block {
    @synchronized([iTermLegacyAtomicMutableArrayOfWeakObjects lock]) {
        iTermLegacyAtomicMutableArrayOfWeakObjectsLock();
        @try {
            [_array removeObjectsPassingTest:^(iTermWeakBox *box) {
                return block(box.object);
            }];
        } @catch (NSException *exception) {
            const int count = iTermLegacyAtomicMutableArrayOfWeakObjectsLockCount;
            CrashLog(@"%@ with lock count=%@", exception.debugDescription, @(count));
            @throw exception;
        }
        iTermLegacyAtomicMutableArrayOfWeakObjectsLockUnlock();
    }
}

- (NSArray *)strongObjects {
    @synchronized([iTermLegacyAtomicMutableArrayOfWeakObjects lock]) {
        iTermLegacyAtomicMutableArrayOfWeakObjectsLock();
        NSArray *result = [_array mapWithBlock:^(iTermWeakBox *box) { return box.object; }];
        iTermLegacyAtomicMutableArrayOfWeakObjectsLockUnlock();
        return result;
    }
}

- (void)removeAllObjects {
    @synchronized([iTermLegacyAtomicMutableArrayOfWeakObjects lock]) {
        iTermLegacyAtomicMutableArrayOfWeakObjectsLock();
        [_array removeAllObjects];
        iTermLegacyAtomicMutableArrayOfWeakObjectsLockUnlock();
    }
}

- (void)addObject:(id)object {
    @synchronized([iTermLegacyAtomicMutableArrayOfWeakObjects lock]) {
        iTermLegacyAtomicMutableArrayOfWeakObjectsLock();
        [_array addObject:[iTermWeakBox boxFor:object]];
        iTermLegacyAtomicMutableArrayOfWeakObjectsLockUnlock();
    }
}

- (NSUInteger)count {
    @synchronized([iTermLegacyAtomicMutableArrayOfWeakObjects lock]) {
        iTermLegacyAtomicMutableArrayOfWeakObjectsLock();
        const NSUInteger result = _array.count;
        iTermLegacyAtomicMutableArrayOfWeakObjectsLockUnlock();
        return result;
    }
}

- (void)prune {
    [self removeObjectsPassingTest:^BOOL(id anObject) {
        return anObject == nil;
    }];
}

- (iTermLegacyAtomicMutableArrayOfWeakObjects *)compactMap:(id (^)(id))block {
    iTermLegacyAtomicMutableArrayOfWeakObjects *result = [[iTermLegacyAtomicMutableArrayOfWeakObjects alloc] init];
    for (id object in [self strongObjects]) {
        id mapped = block(object);
        if (mapped) {
            [result addObject:mapped];
        }
    }
    return result;
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained _Nullable *)buffer count:(NSUInteger)len {
    return [self.strongObjects countByEnumeratingWithState:state objects:buffer count:len];
}

@end
