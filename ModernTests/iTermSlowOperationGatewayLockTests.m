//
//  iTermSlowOperationGatewayLockTests.m
//  ModernTests
//
//  Which lock iTermSlowOperationGateway holds while it changes its list of pending recent-branch
//  callbacks. -didGetRecentBranches:box: (which runs on an arbitrary queue) and -didInterrupt
//  hold @synchronized(_gitRecentBranchFetchCallbacks) while they change the list, so registering a
//  new callback must hold the same lock or the mutable array can be changed from two threads at
//  once. The check is structural, not a race: the array itself records whether the calling thread
//  holds the lock on it at the moment it is changed.
//

#import <XCTest/XCTest.h>
#import <objc/objc-sync.h>

#import "iTermSlowOperationGateway.h"

// objc_sync_exit succeeds only when the calling thread holds the lock on `object`. Re-entering
// afterwards restores the caller's recursion count, so this is safe to call inside a lock.
static BOOL iTermCurrentThreadHoldsLock(id object) {
    if (objc_sync_exit(object) != OBJC_SYNC_SUCCESS) {
        return NO;
    }
    objc_sync_enter(object);
    return YES;
}

// A mutable array that records, for each object added, whether the adding thread held the
// @synchronized lock on the array itself.
@interface iTermLockRecordingMutableArray : NSMutableArray
@property (nonatomic, readonly) NSArray<NSNumber *> *lockHeldOnAdd;
@end

@implementation iTermLockRecordingMutableArray {
    NSMutableArray *_storage;
    NSMutableArray<NSNumber *> *_lockHeldOnAdd;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _storage = [[NSMutableArray alloc] init];
        _lockHeldOnAdd = [[NSMutableArray alloc] init];
    }
    return self;
}

- (NSArray<NSNumber *> *)lockHeldOnAdd {
    return [_lockHeldOnAdd copy];
}

- (NSUInteger)count {
    return _storage.count;
}

- (id)objectAtIndex:(NSUInteger)index {
    return _storage[index];
}

- (void)insertObject:(id)anObject atIndex:(NSUInteger)index {
    [_lockHeldOnAdd addObject:@(iTermCurrentThreadHoldsLock(self))];
    [_storage insertObject:anObject atIndex:index];
}

- (void)addObject:(id)anObject {
    [self insertObject:anObject atIndex:_storage.count];
}

- (void)removeObjectAtIndex:(NSUInteger)index {
    [_storage removeObjectAtIndex:index];
}

- (void)removeLastObject {
    [_storage removeLastObject];
}

- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject {
    [_storage replaceObjectAtIndex:index withObject:anObject];
}

@end

@interface iTermSlowOperationGatewayLockTests : XCTestCase
@end

@implementation iTermSlowOperationGatewayLockTests

- (void)testFetchRecentBranchesRegistersItsCallbackUnderTheCallbackListsLock {
    iTermLockRecordingMutableArray *callbacks = [[iTermLockRecordingMutableArray alloc] init];
    iTermSlowOperationGateway *gateway =
        [[iTermSlowOperationGateway alloc] initForTestingWithRecentBranchFetchCallbacks:callbacks];

    [gateway fetchRecentBranchesAt:@"/" count:1 completion:^(NSArray<NSString *> *branches) {}];

    XCTAssertEqual(callbacks.count, 1);
    XCTAssertEqualObjects(callbacks.lockHeldOnAdd, @[ @YES ],
                          @"The callback must be added while holding @synchronized on the callback "
                          @"list, the lock its other users hold");
    // And not still held afterward.
    XCTAssertFalse(iTermCurrentThreadHoldsLock(callbacks));
}

@end
