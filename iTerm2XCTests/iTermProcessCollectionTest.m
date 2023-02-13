//
//  iTermProcessCollectionTest.m
//  iTerm2
//
//  Created by George Nachman on 4/30/17.
//
//

// TODO: Some day fix the unit tests
#if 0

#import <XCTest/XCTest.h>
#import "iTermProcessCollection.h"

@interface iTermProcessCollectionTest : XCTestCase

@end

@implementation iTermProcessCollectionTest

- (void)testBasic {
    iTermProcessCollection *collection = [[iTermProcessCollection alloc] init];
    // ? -> a -> b+
    [collection addProcessWithProcessID:2 parentProcessID:1];
    iTermProcessInfo *info3 = [collection addProcessWithProcessID:3 parentProcessID:2];
    [info3 privateSetIsForegroundJob:YES];

    // ? -> x -> y+
    [collection addProcessWithProcessID:10 parentProcessID:9];
    [[collection addProcessWithProcessID:11 parentProcessID:10] privateSetIsForegroundJob:YES];

    [collection commit];

    int actual;
    actual = [[[collection infoForProcessID:2] deepestForegroundJob] processID];
    XCTAssertEqual(actual, 3);

    actual = [[[collection infoForProcessID:11] deepestForegroundJob] processID];
    XCTAssertEqual(actual, 11);
}

- (void)inCollection:(iTermProcessCollection *)collection
addProcessWithProcessID:(pid_t)pid
     parentProcessID:(pid_t)parentPid
     isForegroundJob:(BOOL)isForegroundJob {
    iTermProcessInfo *info = [collection addProcessWithProcessID:pid parentProcessID:parentPid];
    [info privateSetIsForegroundJob:isForegroundJob];
}

- (void)testMultipleChildren {
    // ? -> a -> b
    //        -> c -> d+
    //        -> e -> f -> g+

    iTermProcessCollection *collection = [[iTermProcessCollection alloc] init];
    const pid_t a=1, b=2, c=3, d=4, e=5, f=6, g=8;
    [self inCollection:collection addProcessWithProcessID:a parentProcessID:0 isForegroundJob:NO];
    [self inCollection:collection addProcessWithProcessID:b parentProcessID:a isForegroundJob:NO];
    [self inCollection:collection addProcessWithProcessID:c parentProcessID:a isForegroundJob:NO];
    [self inCollection:collection addProcessWithProcessID:d parentProcessID:c isForegroundJob:YES];
    [self inCollection:collection addProcessWithProcessID:e parentProcessID:a isForegroundJob:NO];
    [self inCollection:collection addProcessWithProcessID:f parentProcessID:e isForegroundJob:NO];
    [self inCollection:collection addProcessWithProcessID:g parentProcessID:f isForegroundJob:YES];

    [collection commit];

    int actual;
    actual = [[[collection infoForProcessID:a] deepestForegroundJob] processID];
    XCTAssertEqual(actual, g);
    actual = [[[collection infoForProcessID:b] deepestForegroundJob] processID];
    XCTAssertEqual(actual, 0);
    actual = [[[collection infoForProcessID:c] deepestForegroundJob] processID];
    XCTAssertEqual(actual, d);
    actual = [[[collection infoForProcessID:d] deepestForegroundJob] processID];
    XCTAssertEqual(actual, d);
    actual = [[[collection infoForProcessID:e] deepestForegroundJob] processID];
    XCTAssertEqual(actual, g);
    actual = [[[collection infoForProcessID:f] deepestForegroundJob] processID];
    XCTAssertEqual(actual, g);
    actual = [[[collection infoForProcessID:g] deepestForegroundJob] processID];
    XCTAssertEqual(actual, g);
}

- (void)testNoForegroundJob {
    iTermProcessCollection *collection = [[iTermProcessCollection alloc] init];
    const pid_t a=1, b=2, c=3, d=4, e=5, f=6, g=8;
    [self inCollection:collection addProcessWithProcessID:a parentProcessID:0 isForegroundJob:NO];
    [self inCollection:collection addProcessWithProcessID:b parentProcessID:a isForegroundJob:NO];
    [self inCollection:collection addProcessWithProcessID:c parentProcessID:a isForegroundJob:NO];
    [self inCollection:collection addProcessWithProcessID:d parentProcessID:c isForegroundJob:NO];
    [self inCollection:collection addProcessWithProcessID:e parentProcessID:a isForegroundJob:NO];
    [self inCollection:collection addProcessWithProcessID:f parentProcessID:e isForegroundJob:NO];
    [self inCollection:collection addProcessWithProcessID:g parentProcessID:f isForegroundJob:NO];

    [collection commit];

    for (int i = a; i <= g; i++) {
        id actual = [[collection infoForProcessID:i] deepestForegroundJob];
        XCTAssertNil(actual);
    }
}

- (void)testCycle {
    iTermProcessCollection *collection = [[iTermProcessCollection alloc] init];
    //  +-> a -> b
    //  |     -> c -> d+
    //  |     -> e -> f -> g+ -+
    //  |                      |
    //  +----------------------+

    const pid_t a=1, b=2, c=3, d=4, e=5, f=6, g=8;
    [self inCollection:collection addProcessWithProcessID:a parentProcessID:g isForegroundJob:NO];
    [self inCollection:collection addProcessWithProcessID:b parentProcessID:a isForegroundJob:NO];
    [self inCollection:collection addProcessWithProcessID:c parentProcessID:a isForegroundJob:NO];
    [self inCollection:collection addProcessWithProcessID:d parentProcessID:c isForegroundJob:YES];
    [self inCollection:collection addProcessWithProcessID:e parentProcessID:a isForegroundJob:NO];
    [self inCollection:collection addProcessWithProcessID:f parentProcessID:e isForegroundJob:NO];
    [self inCollection:collection addProcessWithProcessID:g parentProcessID:f isForegroundJob:YES];

    [collection commit];

    iTermProcessInfo *actual;
    actual = [[collection infoForProcessID:a] deepestForegroundJob];
    XCTAssertNil(actual, @"failed to find cycle in collection %@", collection.treeString);
    actual = [[collection infoForProcessID:b] deepestForegroundJob];
    XCTAssertNil(actual, @"failed to find cycle in collection %@", collection.treeString);
    actual = [[collection infoForProcessID:c] deepestForegroundJob];
    XCTAssertEqual(actual.processID, d);
    actual = [[collection infoForProcessID:d] deepestForegroundJob];
    XCTAssertEqual(actual.processID, d);
    actual = [[collection infoForProcessID:e] deepestForegroundJob];
    XCTAssertNil(actual, @"failed to find cycle in collection %@", collection.treeString);
    actual = [[collection infoForProcessID:f] deepestForegroundJob];
    XCTAssertNil(actual, @"failed to find cycle in collection %@", collection.treeString);
    actual = [[collection infoForProcessID:g] deepestForegroundJob];
    XCTAssertNil(actual, @"failed to find cycle in collection %@", collection.treeString);
}

- (void)testMultipleForegroundJobs {
    // a -> b+ -> c+
    const pid_t a = 1, b = 2, c = 3;
    iTermProcessCollection *collection = [[iTermProcessCollection alloc] init];
    [self inCollection:collection addProcessWithProcessID:a parentProcessID:0 isForegroundJob:NO];
    [self inCollection:collection addProcessWithProcessID:b parentProcessID:a isForegroundJob:YES];
    [self inCollection:collection addProcessWithProcessID:c parentProcessID:b isForegroundJob:YES];
    [collection commit];
    int actual;
    actual = [[[collection infoForProcessID:a] deepestForegroundJob] processID];
    XCTAssertEqual(actual, c);
}

@end

#endif
