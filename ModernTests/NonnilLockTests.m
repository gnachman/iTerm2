//
//  NonnilLockTests.m
//  ModernTests
//
//  Tests for ITNonnilLock (DebugLogging.h), which wraps the lock expression of a
//  @synchronized statement with a beta assertion that it is not nil. Only the non-nil path is
//  tested: in builds compiled with BETA a nil lock fails ITBetaAssert, which calls assert(NO) and
//  would crash the test host, and ITBetaAssert has no seam for observing a failure.
//

#import <XCTest/XCTest.h>
#import <objc/objc-sync.h>

#import "DebugLogging.h"

@interface NonnilLockTests : XCTestCase
@end

@implementation NonnilLockTests {
    NSInteger _evaluations;
    NSObject *_lockToReturn;
}

- (NSObject *)countedLock {
    _evaluations += 1;
    return _lockToReturn;
}

// objc_sync_exit succeeds only when the calling thread holds the lock on `object`. Re-entering
// afterwards restores the caller's recursion count, so this is safe to call inside a lock.
- (BOOL)currentThreadHoldsLock:(id)object {
    if (objc_sync_exit(object) != OBJC_SYNC_SUCCESS) {
        return NO;
    }
    objc_sync_enter(object);
    return YES;
}

- (void)testYieldsTheSameObject {
    NSObject *object = [[NSObject alloc] init];
    XCTAssertTrue(ITNonnilLock(object) == object);
}

- (void)testEvaluatesTheExpressionOnce {
    _lockToReturn = [[NSObject alloc] init];
    _evaluations = 0;
    @synchronized(ITNonnilLock([self countedLock])) {
        XCTAssertEqual(_evaluations, 1);
    }
    XCTAssertEqual(_evaluations, 1);
}

- (void)testLocksTheObjectAndReleasesItAfterTheBlock {
    NSObject *object = [[NSObject alloc] init];
    XCTAssertFalse([self currentThreadHoldsLock:object]);
    @synchronized(ITNonnilLock(object)) {
        XCTAssertTrue([self currentThreadHoldsLock:object]);
    }
    XCTAssertFalse([self currentThreadHoldsLock:object]);
}

- (void)testLocksTheResultOfACall {
    _lockToReturn = [[NSObject alloc] init];
    @synchronized(ITNonnilLock([self countedLock])) {
        XCTAssertTrue([self currentThreadHoldsLock:_lockToReturn]);
    }
    XCTAssertFalse([self currentThreadHoldsLock:_lockToReturn]);
}

- (void)testReleasesOnReturnFromTheBlock {
    NSObject *object = [[NSObject alloc] init];
    XCTAssertEqual([self returnFromInsideLock:object], 5);
    XCTAssertFalse([self currentThreadHoldsLock:object]);
}

- (NSInteger)returnFromInsideLock:(NSObject *)object {
    @synchronized(ITNonnilLock(object)) {
        return 5;
    }
}

- (void)testReentrantOnTheSameThread {
    NSObject *object = [[NSObject alloc] init];
    NSInteger depth = 0;
    @synchronized(ITNonnilLock(object)) {
        depth += 1;
        @synchronized(ITNonnilLock(object)) {
            depth += 1;
            @synchronized(object) {
                depth += 1;
            }
            XCTAssertTrue([self currentThreadHoldsLock:object]);
        }
        XCTAssertTrue([self currentThreadHoldsLock:object]);
    }
    XCTAssertEqual(depth, 3);
    XCTAssertFalse([self currentThreadHoldsLock:object]);
}

// While this thread holds the lock through ITNonnilLock, another thread that takes the same
// object with a plain @synchronized does not enter until this thread has left. The other thread
// records whether this thread had already left when it got in. No timing is assumed: if the lock
// works, the recorded value is YES whatever the scheduling; the timeout is only a failure limit.
- (void)testExcludesAPlainSynchronizedOnAnotherThread {
    NSObject *object = [[NSObject alloc] init];
    dispatch_semaphore_t aboutToLock = dispatch_semaphore_create(0);
    XCTestExpectation *entered = [self expectationWithDescription:@"other thread entered"];
    __block BOOL leaving = NO;
    __block BOOL sawLeaving = NO;
    __block BOOL otherThreadHeldLock = NO;

    @synchronized(ITNonnilLock(object)) {
        NSThread *thread = [[NSThread alloc] initWithBlock:^{
            XCTAssertFalse(objc_sync_exit(object) == OBJC_SYNC_SUCCESS);
            dispatch_semaphore_signal(aboutToLock);
            @synchronized(object) {
                @synchronized(self) {
                    sawLeaving = leaving;
                }
                otherThreadHeldLock = YES;
            }
            [entered fulfill];
        }];
        // Match the waiting thread's priority so the wait is not a priority inversion.
        thread.qualityOfService = NSQualityOfServiceUserInteractive;
        [thread start];
        dispatch_semaphore_wait(aboutToLock, DISPATCH_TIME_FOREVER);
        @synchronized(self) {
            leaving = YES;
        }
    }
    [self waitForExpectations:@[ entered ] timeout:30];
    XCTAssertTrue(otherThreadHeldLock);
    XCTAssertTrue(sawLeaving);
}

@end
