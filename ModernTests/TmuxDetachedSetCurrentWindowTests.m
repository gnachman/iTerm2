//
//  TmuxDetachedSetCurrentWindowTests.m
//  ModernTests
//
//  After a detach that leaves the tmux windows open, making one of them key calls
//  -setCurrentWindow:. The gateway is gone by then, so it must do nothing rather than crash.
//  QA finding F-211.
//
//  Other actions on those leftover windows (zoom, swap panes, arrange panes, resize a floating
//  pane, split a pane) build command lists from the gateway too, and must likewise do nothing.
//  QA finding F-096.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "TmuxController.h"
#import "TmuxControllerRegistry.h"
#import "TmuxGatewayTestFakes.h"
#import "iTermInitialDirectory.h"

// Writes are normally enabled once tmux reports the session.
@interface TmuxGateway (TmuxDetachedSetCurrentWindowTests)
- (void)enableWrites;
@end

@interface TmuxController (TmuxDetachedSetCurrentWindowTests)
- (void)didCreateWindowWithCommand:(NSString *)command;
@end

@interface TmuxDetachedSetCurrentWindowTests : XCTestCase
@end

@implementation TmuxDetachedSetCurrentWindowTests {
    TmuxFakeGatewayDelegate *_delegate;
    TmuxRecordingGateway *_gateway;
    TmuxController *_controller;
}

- (void)setUp {
    [super setUp];
    _delegate = [[TmuxFakeGatewayDelegate alloc] init];
    _gateway = [[TmuxRecordingGateway alloc] initWithDelegate:_delegate dcsID:@"dcs"];
    [_gateway enableWrites];
    _controller = [[TmuxController alloc] initWithGateway:_gateway
                                               clientName:@"detached-set-current-window-test"
                                                  profile:@{}
                                             profileModel:nil];
}

- (void)tearDown {
    [[TmuxControllerRegistry sharedInstance] setController:nil forClient:_controller.clientName];
    _controller = nil;
    [super tearDown];
}

- (NSString *)written {
    return [_delegate.writtenStrings componentsJoinedByString:@""];
}

// Control: while attached, it sends the select-window.
- (void)testSetCurrentWindowWhileAttachedSendsSelectWindow {
    [_controller setCurrentWindow:4];
    XCTAssertTrue([[self written] containsString:@"select-window -t @4"], @"%@", [self written]);
}

- (void)testSetCurrentWindowAfterDetachDoesNotThrow {
    [_controller detach];
    [_delegate.writtenStrings removeAllObjects];

    XCTAssertNoThrow([_controller setCurrentWindow:4]);
    XCTAssertEqualObjects([self written], @"");
}

#pragma mark - F-096

// Controls: while attached, each sends its command.

- (void)testToggleZoomWhileAttachedSendsResizePane {
    [_controller toggleZoomForPane:3];
    XCTAssertTrue([[self written] containsString:@"resize-pane -Z -t \"%3\""], @"%@", [self written]);
}

- (void)testSwapPaneWhileAttachedSendsSwapPane {
    [_controller swapPane:1 withPane:2];
    XCTAssertTrue([[self written] containsString:@"swap-pane -s \"%1\" -t \"%2\""], @"%@", [self written]);
}

- (void)testSetLayoutWhileAttachedSendsSelectLayout {
    [_controller setLayoutInWindow:4 toLayout:@"tiled"];
    XCTAssertTrue([[self written] containsString:@"select-layout -t @4 \"tiled\""], @"%@", [self written]);
}

- (void)testResizeFloatingPaneWhileAttachedSendsMoveAndResize {
    [_controller resizeFloatingPane:3 moveByColumns:1 rows:0 growingByColumns:2 rows:0];
    XCTAssertTrue([[self written] containsString:@"move-pane -t \"%3\" -R 1"], @"%@", [self written]);
    XCTAssertTrue([[self written] containsString:@"resize-pane -t \"%3\" -R 2"], @"%@", [self written]);
}

- (void)testDidCreateWindowWhileAttachedSendsCommand {
    [_controller didCreateWindowWithCommand:@"new-window"];
    XCTAssertTrue([[self written] containsString:@"new-window"], @"%@", [self written]);
}

- (iTermInitialDirectory *)homeDirectory {
    iTermInitialDirectory *dir = [[iTermInitialDirectory alloc] init];
    dir.mode = iTermInitialDirectoryModeHome;
    return dir;
}

- (void)testSplitWithCompletionWhileAttachedSendsSplitWindow {
    __block BOOL called = NO;
    [_controller splitWindowPane:3
                      vertically:YES
                           scope:nil
                initialDirectory:[self homeDirectory]
                      completion:^(int wp) { called = YES; }];
    XCTAssertTrue([[self written] containsString:@"split-window -h -t \"%3\""], @"%@", [self written]);
    XCTAssertFalse(called, @"Completion waits for tmux to reply");
}

// After a detach, each must do nothing rather than throw.

// The window that asked for the split waits on the completion to clean up, so it must hear of
// the failure.
- (void)testSplitWithCompletionAfterDetachFailsWithoutThrowing {
    [self detachAndClearWrites];
    __block int result = 0;
    XCTAssertNoThrow([_controller splitWindowPane:3
                                       vertically:YES
                                            scope:nil
                                 initialDirectory:[self homeDirectory]
                                       completion:^(int wp) { result = wp; }]);
    XCTAssertEqual(result, -1);
    XCTAssertEqualObjects([self written], @"");
}

- (void)detachAndClearWrites {
    [_controller detach];
    [_delegate.writtenStrings removeAllObjects];
}

- (void)testToggleZoomAfterDetachDoesNotThrow {
    [self detachAndClearWrites];
    XCTAssertNoThrow([_controller toggleZoomForPane:3]);
    XCTAssertEqualObjects([self written], @"");
}

- (void)testSwapPaneAfterDetachDoesNotThrow {
    [self detachAndClearWrites];
    XCTAssertNoThrow([_controller swapPane:1 withPane:2]);
    XCTAssertEqualObjects([self written], @"");
}

- (void)testSetLayoutAfterDetachDoesNotThrow {
    [self detachAndClearWrites];
    XCTAssertNoThrow([_controller setLayoutInWindow:4 toLayout:@"tiled"]);
    XCTAssertEqualObjects([self written], @"");
}

- (void)testResizeFloatingPaneAfterDetachDoesNotThrow {
    [self detachAndClearWrites];
    XCTAssertNoThrow([_controller resizeFloatingPane:3 moveByColumns:1 rows:0 growingByColumns:2 rows:0]);
    XCTAssertEqualObjects([self written], @"");
}

- (void)testDidCreateWindowAfterDetachDoesNotThrow {
    [self detachAndClearWrites];
    XCTAssertNoThrow([_controller didCreateWindowWithCommand:@"new-window"]);
    XCTAssertEqualObjects([self written], @"");
}

// Dropping a dragged divider in a leftover window. Nothing may be counted as outstanding either,
// or a later reattach would wait for replies that never come.
- (void)testSetLayoutWithMovedDividerAfterDetachDoesNotThrow {
    [self detachAndClearWrites];
    XCTAssertNoThrow([_controller setLayoutInWindow:4 toLayoutWithMovedDivider:@"aafd,120x40,0,0,0"]);
    XCTAssertEqualObjects([self written], @"");
    XCTAssertFalse([_controller hasOutstandingWindowResize]);
}

- (void)testRefreshLayoutsAfterDetachDoesNotThrow {
    [self detachAndClearWrites];
    XCTAssertNoThrow([_controller refreshLayoutsFromTmux]);
    XCTAssertEqualObjects([self written], @"");
    XCTAssertFalse([_controller hasOutstandingWindowResize]);
}

@end
