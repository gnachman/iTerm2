//
//  iTermTmuxLayoutBuilderTest.m
//  ModernTests
//
//  Covers the outbound half of the pane-border-status fix (issue 12925): the
//  builder must grow the edge leaves so the size and layout reported to tmux
//  leave room for the border row tmux carves out. The expected clientSize and
//  layout strings match what tmux 3.7b reports for the same window.
//

#import <XCTest/XCTest.h>

#import "iTermTmuxLayoutBuilder.h"
#import "TmuxLayoutParser.h"

@interface iTermTmuxLayoutBuilderTest : XCTestCase
@end

@implementation iTermTmuxLayoutBuilderTest

- (iTermTmuxLayoutBuilderLeafNode *)leaf:(int)width :(int)height :(int)pane {
    return [[iTermTmuxLayoutBuilderLeafNode alloc] initWithSessionOfSize:VT100GridSizeMake(width, height)
                                                             windowPane:pane];
}

// Strips the checksum prefix so tests don't depend on it.
- (NSString *)layoutBody:(NSString *)layoutString {
    NSRange comma = [layoutString rangeOfString:@","];
    XCTAssertNotEqual(comma.location, NSNotFound);
    return [layoutString substringFromIndex:comma.location + 1];
}

#pragma mark - single pane

- (void)testSingleTopReportsWindowOneRowTaller {
    iTermTmuxLayoutBuilder *builder =
        [[iTermTmuxLayoutBuilder alloc] initWithRootNode:[self leaf:164 :48 :0]];
    [builder adjustForPaneBorderStatus:iTermTmuxPaneBorderStatusTop];
    XCTAssertEqual(builder.clientSize.width, 164);
    XCTAssertEqual(builder.clientSize.height, 49);
    XCTAssertEqualObjects([self layoutBody:builder.layoutString], @"164x49,0,0,0");
}

- (void)testSingleOffIsUnchanged {
    iTermTmuxLayoutBuilder *builder =
        [[iTermTmuxLayoutBuilder alloc] initWithRootNode:[self leaf:164 :48 :0]];
    [builder adjustForPaneBorderStatus:iTermTmuxPaneBorderStatusOff];
    XCTAssertEqual(builder.clientSize.height, 48);
    XCTAssertEqualObjects([self layoutBody:builder.layoutString], @"164x48,0,0,0");
}

#pragma mark - stacked: only the edge pane grows

- (void)testStackedTop {
    iTermTmuxLayoutBuilderInteriorNode *root =
        [[iTermTmuxLayoutBuilderInteriorNode alloc] initWithVerticalDividers:NO];
    [root addNode:[self leaf:80 :11 :0]];
    [root addNode:[self leaf:80 :11 :1]];
    iTermTmuxLayoutBuilder *builder = [[iTermTmuxLayoutBuilder alloc] initWithRootNode:root];
    [builder adjustForPaneBorderStatus:iTermTmuxPaneBorderStatusTop];
    XCTAssertEqual(builder.clientSize.width, 80);
    XCTAssertEqual(builder.clientSize.height, 24);
    XCTAssertEqualObjects([self layoutBody:builder.layoutString],
                          @"80x24,0,0[80x12,0,0,0,80x11,0,13,1]");
}

- (void)testStackedBottom {
    iTermTmuxLayoutBuilderInteriorNode *root =
        [[iTermTmuxLayoutBuilderInteriorNode alloc] initWithVerticalDividers:NO];
    [root addNode:[self leaf:80 :12 :0]];
    [root addNode:[self leaf:80 :10 :1]];
    iTermTmuxLayoutBuilder *builder = [[iTermTmuxLayoutBuilder alloc] initWithRootNode:root];
    [builder adjustForPaneBorderStatus:iTermTmuxPaneBorderStatusBottom];
    XCTAssertEqual(builder.clientSize.height, 24);
    XCTAssertEqualObjects([self layoutBody:builder.layoutString],
                          @"80x24,0,0[80x12,0,0,0,80x11,0,13,1]");
}

#pragma mark - side by side: both panes grow but the window grows by one

- (void)testSideBySideTop {
    iTermTmuxLayoutBuilderInteriorNode *root =
        [[iTermTmuxLayoutBuilderInteriorNode alloc] initWithVerticalDividers:YES];
    [root addNode:[self leaf:40 :23 :0]];
    [root addNode:[self leaf:39 :23 :1]];
    iTermTmuxLayoutBuilder *builder = [[iTermTmuxLayoutBuilder alloc] initWithRootNode:root];
    [builder adjustForPaneBorderStatus:iTermTmuxPaneBorderStatusTop];
    XCTAssertEqual(builder.clientSize.width, 80);
    XCTAssertEqual(builder.clientSize.height, 24);
    XCTAssertEqualObjects([self layoutBody:builder.layoutString],
                          @"80x24,0,0{40x24,0,0,0,39x24,41,0,1}");
}

#pragma mark - round trip: outbound then inbound recovers the real grid

// The builder starts from the real session grids; after the outbound growth and
// a round trip through the parser's inbound correction, the leaf sizes must be
// exactly what we started with (heights and widths).
- (void)assertRoundTripForBuilder:(iTermTmuxLayoutBuilder *)builder
                           status:(iTermTmuxPaneBorderStatus)status
                    expectedSizes:(NSDictionary<NSNumber *, NSValue *> *)expected {
    [builder adjustForPaneBorderStatus:status];
    NSString *layout = builder.layoutString;
    TmuxLayoutParser *parser = [TmuxLayoutParser sharedInstance];
    NSMutableDictionary *tree = [parser parsedLayoutFromString:layout];
    [parser parseTree:tree adjustedForPaneBorderStatus:status];
    for (NSNumber *pane in expected) {
        NSMutableDictionary *leaf = [parser windowPane:pane.intValue inParseTree:tree];
        XCTAssertNotNil(leaf, @"pane %@", pane);
        const NSSize want = expected[pane].sizeValue;
        XCTAssertEqual([leaf[kLayoutDictWidthKey] intValue], (int)want.width, @"pane %@ width", pane);
        XCTAssertEqual([leaf[kLayoutDictHeightKey] intValue], (int)want.height, @"pane %@ height", pane);
    }
}

- (void)testRoundTripStackedTop {
    iTermTmuxLayoutBuilderInteriorNode *root =
        [[iTermTmuxLayoutBuilderInteriorNode alloc] initWithVerticalDividers:NO];
    [root addNode:[self leaf:80 :11 :0]];
    [root addNode:[self leaf:80 :11 :1]];
    [self assertRoundTripForBuilder:[[iTermTmuxLayoutBuilder alloc] initWithRootNode:root]
                             status:iTermTmuxPaneBorderStatusTop
                      expectedSizes:@{@0: [NSValue valueWithSize:NSMakeSize(80, 11)],
                                      @1: [NSValue valueWithSize:NSMakeSize(80, 11)]}];
}

- (void)testRoundTripSideBySideBottom {
    iTermTmuxLayoutBuilderInteriorNode *root =
        [[iTermTmuxLayoutBuilderInteriorNode alloc] initWithVerticalDividers:YES];
    [root addNode:[self leaf:40 :23 :0]];
    [root addNode:[self leaf:39 :23 :1]];
    [self assertRoundTripForBuilder:[[iTermTmuxLayoutBuilder alloc] initWithRootNode:root]
                             status:iTermTmuxPaneBorderStatusBottom
                      expectedSizes:@{@0: [NSValue valueWithSize:NSMakeSize(40, 23)],
                                      @1: [NSValue valueWithSize:NSMakeSize(39, 23)]}];
}

@end
