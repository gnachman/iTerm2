//
//  iTermDirectedGraphTest.m
//  iTerm2
//
//  Created by George Nachman on 23/02/19.
//

#import <XCTest/XCTest.h>

#import "iTermDirectedGraph.h"

@interface iTermDirectedGraphTest : XCTestCase

@end

@implementation iTermDirectedGraphTest

- (void)testContainsCycleEmptyGraph {
    iTermDirectedGraph<NSString *> *graph = [[[iTermDirectedGraph alloc] init] autorelease];
    BOOL containsCycle = [[[iTermDirectedGraphCycleDetector alloc] initWithDirectedGraph:graph] containsCycle];
    XCTAssertFalse(containsCycle);
}

- (void)testContainsCycleLinkedList {
    iTermDirectedGraph<NSString *> *graph = [[[iTermDirectedGraph alloc] init] autorelease];
    [graph addEdgeFrom:@"a" to:@"b"];
    [graph addEdgeFrom:@"b" to:@"c"];
    [graph addEdgeFrom:@"c" to:@"d"];
    BOOL containsCycle = [[[iTermDirectedGraphCycleDetector alloc] initWithDirectedGraph:graph] containsCycle];
    XCTAssertFalse(containsCycle);
}

- (void)testContainsCycleForestOfLinkedLists {
    iTermDirectedGraph<NSString *> *graph = [[[iTermDirectedGraph alloc] init] autorelease];
    [graph addEdgeFrom:@"a" to:@"b"];
    [graph addEdgeFrom:@"b" to:@"c"];
    [graph addEdgeFrom:@"c" to:@"d"];

    [graph addEdgeFrom:@"A" to:@"B"];
    [graph addEdgeFrom:@"B" to:@"C"];
    [graph addEdgeFrom:@"C" to:@"D"];
    BOOL containsCycle = [[[iTermDirectedGraphCycleDetector alloc] initWithDirectedGraph:graph] containsCycle];
    XCTAssertFalse(containsCycle);
}

- (void)testContainsCycleRing {
    iTermDirectedGraph<NSString *> *graph = [[[iTermDirectedGraph alloc] init] autorelease];
    [graph addEdgeFrom:@"a" to:@"b"];
    [graph addEdgeFrom:@"b" to:@"c"];
    [graph addEdgeFrom:@"c" to:@"d"];
    [graph addEdgeFrom:@"d" to:@"a"];
    BOOL containsCycle = [[[iTermDirectedGraphCycleDetector alloc] initWithDirectedGraph:graph] containsCycle];
    XCTAssertTrue(containsCycle);
}

- (void)testContainsCycleBig {
    iTermDirectedGraph<NSNumber *> *graph = [[[iTermDirectedGraph alloc] init] autorelease];
    for (NSInteger i = 0; i < 1000; i++) {
        [graph addEdgeFrom:@(i) to:@(i + 1)];
    }
    for (NSInteger i = 2000; i < 3000; i++) {
        [graph addEdgeFrom:@(i) to:@(i + 1)];
    }
    // 0->1->...->500->501->...->600->601->...->700->701->...
    //          \                ^                |
    //           \                \_______________)______
    //            \                               |      \
    //             \                              V       \
    //              ->2500->2501->...->2600->...->2800->...->2900->...
    [graph addEdgeFrom:@500 to:@2500];
    [graph addEdgeFrom:@2900 to:@600];
    [graph addEdgeFrom:@700 to:@2800];

    BOOL containsCycle = [[[iTermDirectedGraphCycleDetector alloc] initWithDirectedGraph:graph] containsCycle];
    XCTAssertTrue(containsCycle);
}

@end
