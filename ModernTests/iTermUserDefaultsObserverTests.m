//
//  iTermUserDefaultsObserverTests.m
//  ModernTests
//
//  Issue 13233: every PTYSession registered a tab-style observer that was never removed, and each
//  registration ran every session's block, so one theme change ran N² blocks. Sessions now own an
//  iTermUserDefaultsObserver, which removes its registrations on dealloc and ignores writes that
//  leave the value unchanged.
//

#import <XCTest/XCTest.h>
#import "iTermUserDefaults.h"
#import "iTermUserDefaultsObserver.h"

static NSString *const kTestKey = @"NoSynciTermUserDefaultsObserverTestKey";

@interface iTermUserDefaultsObserverTests : XCTestCase
@end

@implementation iTermUserDefaultsObserverTests

- (void)setUp {
    [super setUp];
    [[iTermUserDefaults userDefaults] removeObjectForKey:kTestKey];
}

- (void)tearDown {
    [[iTermUserDefaults userDefaults] removeObjectForKey:kTestKey];
    [super tearDown];
}

// Blocks run async on the main queue. Blocks dispatched before this call run before the sentinel,
// so after it returns every pending delivery has been counted.
- (void)drainMainQueue {
    XCTestExpectation *sentinel = [self expectationWithDescription:@"main queue drained"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [sentinel fulfill];
    });
    [self waitForExpectations:@[ sentinel ] timeout:60];
}

- (void)testEachObserverRunsOncePerChange {
    enum { n = 5 };
    int counts[n] = { 0 };
    int *countsPtr = counts;
    XCTestExpectation *ran = [self expectationWithDescription:@"all blocks ran"];
    ran.expectedFulfillmentCount = n;
    ran.assertForOverFulfill = NO;
    NSMutableArray<iTermUserDefaultsObserver *> *observers = [NSMutableArray array];
    for (int i = 0; i < n; i++) {
        iTermUserDefaultsObserver *observer = [[iTermUserDefaultsObserver alloc] init];
        [observer observeKey:kTestKey block:^{
            countsPtr[i]++;
            [ran fulfill];
        }];
        [observers addObject:observer];
    }

    [[iTermUserDefaults userDefaults] setInteger:1 forKey:kTestKey];
    [self waitForExpectations:@[ ran ] timeout:60];
    [self drainMainQueue];

    for (int i = 0; i < n; i++) {
        XCTAssertEqual(counts[i], 1, @"observer %d", i);
    }
}

- (void)testUnchangedValueDoesNotRunBlock {
    __block int count = 0;
    XCTestExpectation *ran = [self expectationWithDescription:@"first write"];
    iTermUserDefaultsObserver *observer = [[iTermUserDefaultsObserver alloc] init];
    [observer observeKey:kTestKey block:^{
        count++;
        [ran fulfill];
    }];

    [[iTermUserDefaults userDefaults] setInteger:1 forKey:kTestKey];
    [self waitForExpectations:@[ ran ] timeout:60];
    [[iTermUserDefaults userDefaults] setInteger:1 forKey:kTestKey];
    [self drainMainQueue];

    XCTAssertEqual(count, 1);
}

- (void)testDeallocatedObserverDoesNotRunBlock {
    __block int count = 0;
    @autoreleasepool {
        iTermUserDefaultsObserver *observer = [[iTermUserDefaultsObserver alloc] init];
        [observer observeKey:kTestKey block:^{
            count++;
        }];
        observer = nil;
    }

    [[iTermUserDefaults userDefaults] setInteger:2 forKey:kTestKey];
    [self drainMainQueue];

    XCTAssertEqual(count, 0);
}

// Observing a key twice used to add a second KVO registration that -dealloc never removed, so a
// later write messaged the freed observer.
- (void)testObservingKeyTwiceReplacesBlockAndDeallocsCleanly {
    __block int firstCount = 0;
    __block int secondCount = 0;
    XCTestExpectation *ran = [self expectationWithDescription:@"second block"];
    @autoreleasepool {
        iTermUserDefaultsObserver *observer = [[iTermUserDefaultsObserver alloc] init];
        [observer observeKey:kTestKey block:^{
            firstCount++;
        }];
        [observer observeKey:kTestKey block:^{
            secondCount++;
            [ran fulfill];
        }];

        [[iTermUserDefaults userDefaults] setInteger:3 forKey:kTestKey];
        [self waitForExpectations:@[ ran ] timeout:60];
        [self drainMainQueue];
        observer = nil;
    }

    XCTAssertEqual(firstCount, 0);
    XCTAssertEqual(secondCount, 1);

    // Must not crash.
    [[iTermUserDefaults userDefaults] setInteger:4 forKey:kTestKey];
    [self drainMainQueue];
    XCTAssertEqual(secondCount, 1);
}

@end
