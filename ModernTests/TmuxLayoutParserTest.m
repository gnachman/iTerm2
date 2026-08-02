//
//  TmuxLayoutParserTest.m
//  ModernTests
//
//  Covers the pane-border-status geometry correction (issue 12925). The expected
//  leaf geometries below were captured from real tmux 3.7b: for each layout the
//  window_layout string is fed to the parser and the adjusted leaves are compared
//  against the pane_width/pane_height/pane_left/pane_top tmux reports for that pane.
//

#import <XCTest/XCTest.h>

#import "TmuxLayoutParser.h"

@interface TmuxLayoutParserTest : XCTestCase
@end

@implementation TmuxLayoutParserTest

- (NSMutableDictionary *)adjust:(NSString *)layout status:(iTermTmuxPaneBorderStatus)status {
    TmuxLayoutParser *parser = [TmuxLayoutParser sharedInstance];
    NSMutableDictionary *tree = [parser parsedLayoutFromString:layout];
    XCTAssertNotNil(tree, @"Failed to parse %@", layout);
    return [parser parseTree:tree adjustedForPaneBorderStatus:status];
}

// Asserts the leaf for the given window pane has the expected geometry.
- (void)assertTree:(NSMutableDictionary *)tree
              pane:(int)pane
             width:(int)width
            height:(int)height
                 x:(int)x
                 y:(int)y {
    NSMutableDictionary *leaf = [[TmuxLayoutParser sharedInstance] windowPane:pane
                                                                 inParseTree:tree];
    XCTAssertNotNil(leaf, @"No leaf for pane %d", pane);
    XCTAssertEqual([leaf[kLayoutDictWidthKey] intValue], width, @"pane %d width", pane);
    XCTAssertEqual([leaf[kLayoutDictHeightKey] intValue], height, @"pane %d height", pane);
    XCTAssertEqual([leaf[kLayoutDictXOffsetKey] intValue], x, @"pane %d x", pane);
    XCTAssertEqual([leaf[kLayoutDictYOffsetKey] intValue], y, @"pane %d y", pane);
}

#pragma mark - off is a no-op

- (void)testOffLeavesGeometryUnchanged {
    NSMutableDictionary *tree = [self adjust:@"c195,80x24,0,0[80x12,0,0,0,80x11,0,13,1]"
                                      status:iTermTmuxPaneBorderStatusOff];
    [self assertTree:tree pane:0 width:80 height:12 x:0 y:0];
    [self assertTree:tree pane:1 width:80 height:11 x:0 y:13];
}

#pragma mark - single pane (issue 12925 repro)

- (void)testSingleTop {
    NSMutableDictionary *tree = [self adjust:@"d1fd,164x49,0,0,0"
                                      status:iTermTmuxPaneBorderStatusTop];
    [self assertTree:tree pane:0 width:164 height:48 x:0 y:1];
}

- (void)testSingleBottom {
    NSMutableDictionary *tree = [self adjust:@"d1fd,164x49,0,0,0"
                                      status:iTermTmuxPaneBorderStatusBottom];
    [self assertTree:tree pane:0 width:164 height:48 x:0 y:0];
}

#pragma mark - side-by-side: both panes touch the top and bottom edges

- (void)testHSplitTop {
    NSMutableDictionary *tree = [self adjust:@"8205,80x24,0,0{40x24,0,0,0,39x24,41,0,1}"
                                      status:iTermTmuxPaneBorderStatusTop];
    [self assertTree:tree pane:0 width:40 height:23 x:0 y:1];
    [self assertTree:tree pane:1 width:39 height:23 x:41 y:1];
}

- (void)testHSplitBottom {
    NSMutableDictionary *tree = [self adjust:@"8205,80x24,0,0{40x24,0,0,0,39x24,41,0,1}"
                                      status:iTermTmuxPaneBorderStatusBottom];
    [self assertTree:tree pane:0 width:40 height:23 x:0 y:0];
    [self assertTree:tree pane:1 width:39 height:23 x:41 y:0];
}

#pragma mark - stacked: only the pane on the affected edge shrinks

- (void)testVSplitTop {
    NSMutableDictionary *tree = [self adjust:@"c195,80x24,0,0[80x12,0,0,0,80x11,0,13,1]"
                                      status:iTermTmuxPaneBorderStatusTop];
    [self assertTree:tree pane:0 width:80 height:11 x:0 y:1];
    [self assertTree:tree pane:1 width:80 height:11 x:0 y:13];
}

- (void)testVSplitBottom {
    NSMutableDictionary *tree = [self adjust:@"c195,80x24,0,0[80x12,0,0,0,80x11,0,13,1]"
                                      status:iTermTmuxPaneBorderStatusBottom];
    [self assertTree:tree pane:0 width:80 height:12 x:0 y:0];
    [self assertTree:tree pane:1 width:80 height:10 x:0 y:13];
}

#pragma mark - three stacked: only the top (or bottom) band pane shrinks

- (void)testThreeStackTop {
    NSMutableDictionary *tree = [self adjust:@"f369,80x24,0,0[80x12,0,0,0,80x5,0,13,1,80x5,0,19,2]"
                                      status:iTermTmuxPaneBorderStatusTop];
    [self assertTree:tree pane:0 width:80 height:11 x:0 y:1];
    [self assertTree:tree pane:1 width:80 height:5 x:0 y:13];
    [self assertTree:tree pane:2 width:80 height:5 x:0 y:19];
}

- (void)testThreeStackBottom {
    NSMutableDictionary *tree = [self adjust:@"f369,80x24,0,0[80x12,0,0,0,80x5,0,13,1,80x5,0,19,2]"
                                      status:iTermTmuxPaneBorderStatusBottom];
    [self assertTree:tree pane:0 width:80 height:12 x:0 y:0];
    [self assertTree:tree pane:1 width:80 height:5 x:0 y:13];
    [self assertTree:tree pane:2 width:80 height:4 x:0 y:19];
}

#pragma mark - 2x2 grid: top band shrinks for top, bottom band for bottom

- (void)testGridTop {
    NSString *layout = @"56c2,80x24,0,0{40x24,0,0[40x12,0,0,0,40x11,0,13,2],39x24,41,0[39x12,41,0,1,39x11,41,13,3]}";
    NSMutableDictionary *tree = [self adjust:layout status:iTermTmuxPaneBorderStatusTop];
    [self assertTree:tree pane:0 width:40 height:11 x:0 y:1];
    [self assertTree:tree pane:2 width:40 height:11 x:0 y:13];
    [self assertTree:tree pane:1 width:39 height:11 x:41 y:1];
    [self assertTree:tree pane:3 width:39 height:11 x:41 y:13];
}

- (void)testGridBottom {
    NSString *layout = @"56c2,80x24,0,0{40x24,0,0[40x12,0,0,0,40x11,0,13,2],39x24,41,0[39x12,41,0,1,39x11,41,13,3]}";
    NSMutableDictionary *tree = [self adjust:layout status:iTermTmuxPaneBorderStatusBottom];
    [self assertTree:tree pane:0 width:40 height:12 x:0 y:0];
    [self assertTree:tree pane:2 width:40 height:10 x:0 y:13];
    [self assertTree:tree pane:1 width:39 height:12 x:41 y:0];
    [self assertTree:tree pane:3 width:39 height:10 x:41 y:13];
}

#pragma mark - string mapping

- (void)testStatusFromString {
    XCTAssertEqual(iTermTmuxPaneBorderStatusFromString(@"top"), iTermTmuxPaneBorderStatusTop);
    XCTAssertEqual(iTermTmuxPaneBorderStatusFromString(@"bottom"), iTermTmuxPaneBorderStatusBottom);
    XCTAssertEqual(iTermTmuxPaneBorderStatusFromString(@"off"), iTermTmuxPaneBorderStatusOff);
    XCTAssertEqual(iTermTmuxPaneBorderStatusFromString(@""), iTermTmuxPaneBorderStatusOff);
    XCTAssertEqual(iTermTmuxPaneBorderStatusFromString(@"garbage"), iTermTmuxPaneBorderStatusOff);
}

@end
