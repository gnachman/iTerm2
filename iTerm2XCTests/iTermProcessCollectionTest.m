//
//  iTermProcessCollectionTest.m
//  iTerm2
//
//  Created by George Nachman on 4/30/17.
//
//

#import <XCTest/XCTest.h>
#import "iTermProcessCollection.h"

@interface iTermProcessCollectionTest : XCTestCase

@end

@implementation iTermProcessCollectionTest

- (void)testBasic {
    iTermProcessCollection *collection = [[iTermProcessCollection alloc] init];
    // ? -> a -> b+
    [collection addProcessWithName:@"a" processID:2 parentProcessID:1 isForegroundJob:NO];
    [collection addProcessWithName:@"b" processID:3 parentProcessID:2 isForegroundJob:YES];

    // ? -> x -> y+
    [collection addProcessWithName:@"x" processID:10 parentProcessID:9 isForegroundJob:NO];
    [collection addProcessWithName:@"y" processID:11 parentProcessID:10 isForegroundJob:YES];

    [collection commit];

    int actual;
    actual = [[[collection infoForProcessID:2] deepestForegroundJob] processID];
    XCTAssertEqual(actual, 3);

    actual = [[[collection infoForProcessID:11] deepestForegroundJob] processID];
    XCTAssertEqual(actual, 11);
}

- (void)testMultipleChildren {
    // ? -> a -> b
    //        -> c -> d+
    //        -> e -> f -> g+

    iTermProcessCollection *collection = [[iTermProcessCollection alloc] init];
    const int a=1, b=2, c=3, d=4, e=5, f=6, g=8;
    [collection addProcessWithName:@"a" processID:a parentProcessID:0 isForegroundJob:NO];
    [collection addProcessWithName:@"b" processID:b parentProcessID:a isForegroundJob:NO];
    [collection addProcessWithName:@"c" processID:c parentProcessID:a isForegroundJob:NO];
    [collection addProcessWithName:@"d" processID:d parentProcessID:c isForegroundJob:YES];
    [collection addProcessWithName:@"e" processID:e parentProcessID:a isForegroundJob:NO];
    [collection addProcessWithName:@"f" processID:f parentProcessID:e isForegroundJob:NO];
    [collection addProcessWithName:@"g" processID:g parentProcessID:f isForegroundJob:YES];

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
    const int a=1, b=2, c=3, d=4, e=5, f=6, g=8;
    [collection addProcessWithName:@"a" processID:a parentProcessID:0 isForegroundJob:NO];
    [collection addProcessWithName:@"b" processID:b parentProcessID:a isForegroundJob:NO];
    [collection addProcessWithName:@"c" processID:c parentProcessID:a isForegroundJob:NO];
    [collection addProcessWithName:@"d" processID:d parentProcessID:c isForegroundJob:NO];
    [collection addProcessWithName:@"e" processID:e parentProcessID:a isForegroundJob:NO];
    [collection addProcessWithName:@"f" processID:f parentProcessID:e isForegroundJob:NO];
    [collection addProcessWithName:@"g" processID:g parentProcessID:f isForegroundJob:NO];

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

    const int a=1, b=2, c=3, d=4, e=5, f=6, g=8;
    [collection addProcessWithName:@"a" processID:a parentProcessID:g isForegroundJob:NO];
    [collection addProcessWithName:@"b" processID:b parentProcessID:a isForegroundJob:NO];
    [collection addProcessWithName:@"c" processID:c parentProcessID:a isForegroundJob:NO];
    [collection addProcessWithName:@"d" processID:d parentProcessID:c isForegroundJob:YES];
    [collection addProcessWithName:@"e" processID:e parentProcessID:a isForegroundJob:NO];
    [collection addProcessWithName:@"f" processID:f parentProcessID:e isForegroundJob:NO];
    [collection addProcessWithName:@"g" processID:g parentProcessID:f isForegroundJob:YES];

    [collection commit];

    iTermProcessInfo *actual;
    actual = [[collection infoForProcessID:a] deepestForegroundJob];
    XCTAssertNil(actual);
    actual = [[collection infoForProcessID:b] deepestForegroundJob];
    XCTAssertNil(actual);
    actual = [[collection infoForProcessID:c] deepestForegroundJob];
    XCTAssertEqual(actual.processID, d);
    actual = [[collection infoForProcessID:d] deepestForegroundJob];
    XCTAssertEqual(actual.processID, d);
    actual = [[collection infoForProcessID:e] deepestForegroundJob];
    XCTAssertNil(actual);
    actual = [[collection infoForProcessID:f] deepestForegroundJob];
    XCTAssertNil(actual);
    actual = [[collection infoForProcessID:g] deepestForegroundJob];
    XCTAssertNil(actual);
}

- (void)testMultipleForegroundJobs {
    // a -> b+ -> c+
    const int a = 1, b = 2, c = 3;
    iTermProcessCollection *collection = [[iTermProcessCollection alloc] init];
    [collection addProcessWithName:@"a" processID:a parentProcessID:0 isForegroundJob:NO];
    [collection addProcessWithName:@"b" processID:b parentProcessID:a isForegroundJob:YES];
    [collection addProcessWithName:@"c" processID:c parentProcessID:b isForegroundJob:YES];
    [collection commit];
    int actual;
    actual = [[[collection infoForProcessID:a] deepestForegroundJob] processID];
    XCTAssertEqual(actual, c);
}

@end
