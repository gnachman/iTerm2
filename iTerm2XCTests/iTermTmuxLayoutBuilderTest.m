//
//  iTermTmuxLayoutBuilderTest.m
//  iTerm2
//
//  Created by George Nachman on 5/8/19.
//

#import <XCTest/XCTest.h>

#import "iTermTmuxLayoutBuilder.h"

@interface iTermTmuxLayoutBuilderTest : XCTestCase

@end

@implementation iTermTmuxLayoutBuilderTest

- (void)testSinglePane {
    iTermTmuxLayoutBuilderLeafNode *root = [[iTermTmuxLayoutBuilderLeafNode alloc] initWithSessionOfSize:VT100GridSizeMake(80, 25)
                                                                                              windowPane:0];
    iTermTmuxLayoutBuilder *builder = [[iTermTmuxLayoutBuilder alloc] initWithRootNode:root];
    NSString *actual = builder.layoutString;
    XCTAssertEqualObjects(actual, @"b65d,80x25,0,0,0");
}

- (void)testOneHorizontalDivider {
    iTermTmuxLayoutBuilderInteriorNode *root = [[iTermTmuxLayoutBuilderInteriorNode alloc] initWithVerticalDividers:NO];
    iTermTmuxLayoutBuilderLeafNode *child1 = [[iTermTmuxLayoutBuilderLeafNode alloc] initWithSessionOfSize:VT100GridSizeMake(80, 12)
                                                                                                windowPane:0];
    iTermTmuxLayoutBuilderLeafNode *child2 = [[iTermTmuxLayoutBuilderLeafNode alloc] initWithSessionOfSize:VT100GridSizeMake(80, 12)
                                                                                                windowPane:1];
    [root addNode:child1];
    [root addNode:child2];

    iTermTmuxLayoutBuilder *builder = [[iTermTmuxLayoutBuilder alloc] initWithRootNode:root];
    NSString *actual = builder.layoutString;
    XCTAssertEqualObjects(actual, @"c299,80x25,0,0[80x12,0,0,0,80x12,0,13,1]");
}

// horizontal(vertical(0, 3), 1)
- (void)testThreePanes {
    iTermTmuxLayoutBuilderInteriorNode *root = [[iTermTmuxLayoutBuilderInteriorNode alloc] initWithVerticalDividers:NO];
    iTermTmuxLayoutBuilderInteriorNode *top = [[iTermTmuxLayoutBuilderInteriorNode alloc] initWithVerticalDividers:YES];
    iTermTmuxLayoutBuilderLeafNode *session0 = [[iTermTmuxLayoutBuilderLeafNode alloc] initWithSessionOfSize:VT100GridSizeMake(40, 12)
                                                                                                  windowPane:0];
    iTermTmuxLayoutBuilderLeafNode *session3 = [[iTermTmuxLayoutBuilderLeafNode alloc] initWithSessionOfSize:VT100GridSizeMake(39, 12)
                                                                                                windowPane:3];
    iTermTmuxLayoutBuilderLeafNode *session1 = [[iTermTmuxLayoutBuilderLeafNode alloc] initWithSessionOfSize:VT100GridSizeMake(80, 12)
                                                                                                  windowPane:1];
    [top addNode:session0];
    [top addNode:session3];
    [root addNode:top];
    [root addNode:session1];
    
    iTermTmuxLayoutBuilder *builder = [[iTermTmuxLayoutBuilder alloc] initWithRootNode:root];
    NSString *actual = builder.layoutString;
    XCTAssertEqualObjects(actual, @"7023,80x25,0,0[80x12,0,0{40x12,0,0,0,39x12,41,0,3},80x12,0,13,1]");
}

// You can get this if you destroy a vertical split inside a horizontal split by removing all but one of its sessions.
// Begin with:
// horizontal(vertical(0, horizontal(3, 4)), 1)
// Then close wp 0, leaving:
// horizontal(horizontal(3, 4), 1)
- (void)testNonNormalized {
    iTermTmuxLayoutBuilderInteriorNode *root = [[iTermTmuxLayoutBuilderInteriorNode alloc] initWithVerticalDividers:NO];
    iTermTmuxLayoutBuilderInteriorNode *inner = [[iTermTmuxLayoutBuilderInteriorNode alloc] initWithVerticalDividers:NO];
    iTermTmuxLayoutBuilderLeafNode *session3 = [[iTermTmuxLayoutBuilderLeafNode alloc] initWithSessionOfSize:VT100GridSizeMake(80, 6)
                                                                                                  windowPane:3];
    iTermTmuxLayoutBuilderLeafNode *session4 = [[iTermTmuxLayoutBuilderLeafNode alloc] initWithSessionOfSize:VT100GridSizeMake(80, 5)
                                                                                                  windowPane:4];
    iTermTmuxLayoutBuilderLeafNode *session1 = [[iTermTmuxLayoutBuilderLeafNode alloc] initWithSessionOfSize:VT100GridSizeMake(80, 12)
                                                                                                  windowPane:1];
    [inner addNode:session3];
    [inner addNode:session4];
    [root addNode:inner];
    [root addNode:session1];

    iTermTmuxLayoutBuilder *builder = [[iTermTmuxLayoutBuilder alloc] initWithRootNode:root];
    NSString *actual = builder.layoutString;
    XCTAssertEqualObjects(actual, @"c397,80x25,0,0[80x12,0,0[80x6,0,0,3,80x5,0,7,4],80x12,0,13,1]");
}

- (void)testStackOfThree {
    iTermTmuxLayoutBuilderInteriorNode *root = [[iTermTmuxLayoutBuilderInteriorNode alloc] initWithVerticalDividers:NO];
    iTermTmuxLayoutBuilderLeafNode *session3 = [[iTermTmuxLayoutBuilderLeafNode alloc] initWithSessionOfSize:VT100GridSizeMake(80, 6)
                                                                                                  windowPane:3];
    iTermTmuxLayoutBuilderLeafNode *session4 = [[iTermTmuxLayoutBuilderLeafNode alloc] initWithSessionOfSize:VT100GridSizeMake(80, 5)
                                                                                                  windowPane:4];
    iTermTmuxLayoutBuilderLeafNode *session1 = [[iTermTmuxLayoutBuilderLeafNode alloc] initWithSessionOfSize:VT100GridSizeMake(80, 12)
                                                                                                  windowPane:1];
    [root addNode:session3];
    [root addNode:session4];
    [root addNode:session1];
    
    iTermTmuxLayoutBuilder *builder = [[iTermTmuxLayoutBuilder alloc] initWithRootNode:root];
    NSString *actual = builder.layoutString;
    XCTAssertEqualObjects(actual, @"4787,80x25,0,0[80x6,0,0,3,80x5,0,7,4,80x12,0,13,1]");
}

@end
