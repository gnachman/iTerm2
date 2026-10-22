//
//  TmuxCommandErrorToleranceTests.m
//  ModernTests
//
//  With floating and modal panes (tmux 3.8 and later), commands that used to always succeed can
//  fail, and a failed command that does not tolerate errors ends the whole tmux connection. The
//  error replies below were recorded from tmux next-3.9 with a modal floating pane (new-pane -O)
//  in a window with two tiled panes. When the first command of a list fails, tmux sends one
//  %error block and runs nothing after it.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "iTermTuple.h"
#import "TmuxController.h"
#import "TmuxControllerRegistry.h"
#import "TmuxGatewayTestFakes.h"

@interface TmuxController (ErrorToleranceTesting)
- (void)newWindowWithAffinityCreated:(NSString *)responseStr
         affinityWindowAndCompletion:(iTermTriple *)tuple;
@end

@interface TmuxGateway (ErrorToleranceTesting)
- (void)enableWrites;
@end

@interface TmuxCommandErrorToleranceTests : XCTestCase
@end

@implementation TmuxCommandErrorToleranceTests {
    TmuxFakeGatewayDelegate *_delegate;
    TmuxRecordingGateway *_gateway;
    TmuxController *_controller;
    NSString *_lastReply;
}

- (void)setUp {
    [super setUp];
    _delegate = [[TmuxFakeGatewayDelegate alloc] init];
    _gateway = [[TmuxRecordingGateway alloc] initWithDelegate:_delegate dcsID:@"dcs"];
    _gateway.acceptNotifications = YES;
    // Writes are held until the gateway is told it can write; the tests below check what was sent.
    [_gateway enableWrites];
    _controller = [[TmuxController alloc] initWithGateway:_gateway
                                               clientName:@"error-tolerance-test"
                                                  profile:@{}
                                             profileModel:nil];
}

- (void)tearDown {
    [[TmuxControllerRegistry sharedInstance] setController:nil forClient:_controller.clientName];
    _controller = nil;
    [super tearDown];
}

- (NSArray<NSString *> *)errorReply:(NSString *)message {
    return @[ @"%begin 1791255943 321 1", message, @"%error 1791255943 321 1" ];
}

// After the failed reply, a later command must still get its own reply. This checks that the
// gateway's queue was left in step with the server.
- (void)assertGatewayStillWorks {
    _lastReply = nil;
    [_gateway sendCommand:@"display-message -p ok"
           responseTarget:self
         responseSelector:@selector(recordReply:)];
    [_gateway feedLines:@[ @"%begin 1791255944 330 1", @"ok", @"%end 1791255944 330 1" ]];
    XCTAssertEqualObjects(_lastReply, @"ok");
    XCTAssertNil(_gateway.abortMessage);
}

- (void)recordReply:(NSString *)reply {
    _lastReply = reply;
}

- (void)testSwapWithModalPaneDoesNotEndTheConnection {
    [_controller swapPane:2 withPane:0];
    [_gateway feedLines:[self errorReply:@"pane is modal"]];
    XCTAssertNil(_gateway.abortMessage, @"swap-pane failing must not end the connection");
    [self assertGatewayStillWorks];
}

- (void)testBreakingOutModalPaneDoesNotEndTheConnection {
    [_controller breakOutWindowPane:2 toTabAside:@"1"];
    [_gateway feedLines:[self errorReply:@"pane is modal"]];
    XCTAssertNil(_gateway.abortMessage, @"break-pane failing must not end the connection");
    [self assertGatewayStillWorks];
}

- (void)testRejectedLayoutDoesNotEndTheConnection {
    [_controller setLayoutInWindow:0 toLayout:@"aafd,120x40,0,0,0"];
    [_gateway feedLines:[self errorReply:@"have 2 panes but need 1: aafd,120x40,0,0,0"]];
    XCTAssertNil(_gateway.abortMessage, @"select-layout failing must not end the connection");
    [self assertGatewayStillWorks];
}

// A moved divider's layout is absolute, so until tmux replies it must count as an outstanding
// resize. Otherwise a second drag would be built from the layout it is about to replace. If tmux
// rejects it, the UI still shows the dragged divider, so tmux's layout must be fetched again.
- (void)testRejectedMovedDividerLayoutDoesNotEndTheConnectionAndResyncs {
    [_controller setLayoutInWindow:0 toLayoutWithMovedDivider:@"aafd,120x40,0,0,0"];
    XCTAssertTrue([_controller hasOutstandingWindowResize]);
    [_delegate.writtenStrings removeAllObjects];
    [_gateway feedLines:[self errorReply:@"have 2 panes but need 1: aafd,120x40,0,0,0"]];
    XCTAssertNil(_gateway.abortMessage, @"select-layout failing must not end the connection");
    XCTAssertTrue([[_delegate.writtenStrings componentsJoinedByString:@""] containsString:@"list-windows"],
                  @"a rejected layout must be followed by a fresh list-windows");
    XCTAssertTrue([_controller hasOutstandingWindowResize], @"the re-sync is still outstanding");
    [_gateway feedLines:@[ @"%begin 1791255944 322 1", @"%end 1791255944 322 1" ]];
    XCTAssertFalse([_controller hasOutstandingWindowResize]);
    [self assertGatewayStillWorks];
}

// Layouts with splits have braces, which tmux parses as a command block unless they are quoted.
- (void)testLayoutWithBracesIsQuoted {
    NSString *layout = @"21fb,118x23,0,0{58x23,0,0,1,59x23,59,0,2}";
    NSString *expected = [NSString stringWithFormat:@"select-layout -t @3 \"%@\"", layout];
    [_controller setLayoutInWindow:3 toLayout:layout];
    XCTAssertTrue([[_delegate.writtenStrings componentsJoinedByString:@""] containsString:expected]);
    [_delegate.writtenStrings removeAllObjects];
    [_controller setLayoutInWindow:3 toLayoutWithMovedDivider:layout];
    XCTAssertTrue([[_delegate.writtenStrings componentsJoinedByString:@""] containsString:expected]);
}

- (void)testFailedResizeDoesNotEndTheConnectionOrLeaveAResizeOutstanding {
    [_controller windowPane:2 resizedBy:2 horizontally:NO];
    XCTAssertTrue([_controller hasOutstandingWindowResize]);
    [_gateway feedLines:[self errorReply:@"pane is modal"]];
    XCTAssertNil(_gateway.abortMessage, @"resize-pane failing must not end the connection");
    XCTAssertFalse([_controller hasOutstandingWindowResize],
                   @"the list-windows that follows the resize is failed too, and must still be counted");
    [self assertGatewayStillWorks];
}

// Errors from tmux 3.8 and earlier wordings. A malformed command is a bug in iTerm2; a refusal is
// the server's answer about its state.
- (void)testMalformedCommandErrorsAreToldApartFromRefusals {
    NSArray<NSString *> *malformed = @[ @"parse error: syntax error",
                                        @"unknown command: frobnicate",
                                        @"command resize-pane: unknown flag -Q",
                                        @"too many arguments (need at most 1)",
                                        @"usage: select-layout [-Enop] [-t target-pane] [layout-name]",
                                        @"invalid layout: 21fb,118x23",
                                        @"size mismatch after applying layout: 21fb,118x23" ];
    for (NSString *error in malformed) {
        XCTAssertTrue([TmuxGateway errorIndicatesMalformedCommand:error], @"%@", error);
    }
    NSArray<NSString *> *refusals = @[ @"pane is modal",
                                       @"can't find pane: %45",
                                       @"have 2 panes but need 1: aafd,120x40,0,0,0",
                                       @"window already has a modal pane",
                                       // Before tmux 3.3, select-layout said this for every failure,
                                       // including a window that gained a pane since the layout was made.
                                       @"can't set layout: 21fb,118x23",
                                       @"" ];
    for (NSString *error in refusals) {
        XCTAssertFalse([TmuxGateway errorIndicatesMalformedCommand:error], @"%@", error);
    }
}

#pragma mark - Adversarial resize bookkeeping

- (NSArray<NSString *> *)okReply:(NSString *)output {
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObject:@"%begin 1791255950 400 1"];
    if (output) {
        [lines addObject:output];
    }
    [lines addObject:@"%end 1791255950 400 1"];
    return lines;
}

- (NSString *)written {
    return [_delegate.writtenStrings componentsJoinedByString:@""];
}

// hasOutstandingWindowResize only says whether the count is positive, so an extra decrement would
// go unnoticed until the next drag sent an absolute layout too early. Starting one more resize
// shows the count really is zero: it must be outstanding until its own replies arrive.
- (void)assertNoResizeOutstanding {
    XCTAssertFalse([_controller hasOutstandingWindowResize]);
    [_controller refreshLayoutsFromTmux];
    XCTAssertTrue([_controller hasOutstandingWindowResize], @"the count went below zero");
    [_gateway feedLines:[self okReply:nil]];
    XCTAssertFalse([_controller hasOutstandingWindowResize], @"the count was left above zero");
    [self assertGatewayStillWorks];
}

// An accepted select-layout replies with no output. That must not be mistaken for a failure, which
// would send a needless list-windows after every drag.
- (void)testAcceptedMovedDividerDoesNotResync {
    [_controller setLayoutInWindow:0 toLayoutWithMovedDivider:@"aafd,120x40,0,0,0"];
    [_delegate.writtenStrings removeAllObjects];
    [_gateway feedLines:[self okReply:nil]];
    XCTAssertFalse([[self written] containsString:@"list-windows"], @"%@", [self written]);
    XCTAssertTrue([_controller hasOutstandingWindowResize], @"its list-windows hasn't replied yet");
    [_gateway feedLines:[self okReply:nil]];
    XCTAssertNil(_gateway.abortMessage);
    [self assertNoResizeOutstanding];
}

// Two drags before tmux answers: the second must not see the first as finished until both of the
// first's replies are in, and nothing may be counted twice.
- (void)testBackToBackMovedDividersStayOutstandingUntilAllReply {
    [_controller setLayoutInWindow:0 toLayoutWithMovedDivider:@"aafd,120x40,0,0,0"];
    [_controller setLayoutInWindow:0 toLayoutWithMovedDivider:@"aafe,120x40,0,0,0"];
    for (int i = 0; i < 3; i++) {
        [_gateway feedLines:[self okReply:nil]];
        XCTAssertTrue([_controller hasOutstandingWindowResize], @"after reply %d", i);
    }
    [_gateway feedLines:[self okReply:nil]];
    XCTAssertNil(_gateway.abortMessage);
    [self assertNoResizeOutstanding];
}

// tmux takes the layout but the list-windows after it fails.
- (void)testMovedDividerWhoseListWindowsFailsIsNotLeftOutstanding {
    [_controller setLayoutInWindow:0 toLayoutWithMovedDivider:@"aafd,120x40,0,0,0"];
    [_gateway feedLines:[self okReply:nil]];
    [_gateway feedLines:[self errorReply:@"no current session"]];
    XCTAssertNil(_gateway.abortMessage);
    [self assertNoResizeOutstanding];
}

// Both a rejected layout and the re-sync it causes fail.
- (void)testRejectedMovedDividerWhoseResyncAlsoFails {
    [_controller setLayoutInWindow:0 toLayoutWithMovedDivider:@"aafd,120x40,0,0,0"];
    [_gateway feedLines:[self errorReply:@"have 2 panes but need 1: aafd,120x40,0,0,0"]];
    XCTAssertTrue([_controller hasOutstandingWindowResize]);
    [_gateway feedLines:[self errorReply:@"no current session"]];
    XCTAssertNil(_gateway.abortMessage);
    [self assertNoResizeOutstanding];
}

// A rejected layout while a resize-pane from an earlier drag is still in flight, with every kind
// of reply mixed together.
- (void)testInterleavedResizeAndRejectedLayout {
    [_controller windowPane:2 resizedBy:-3 horizontally:YES];
    [_controller setLayoutInWindow:0 toLayoutWithMovedDivider:@"aafd,120x40,0,0,0"];
    [_controller refreshLayoutsFromTmux];
    [_gateway feedLines:[self errorReply:@"pane is modal"]];  // resize-pane; its list-windows is skipped
    XCTAssertTrue([_controller hasOutstandingWindowResize]);
    [_gateway feedLines:[self errorReply:@"have 2 panes but need 1: aafd,120x40,0,0,0"]];  // select-layout
    XCTAssertTrue([_controller hasOutstandingWindowResize]);
    [_gateway feedLines:[self okReply:nil]];  // refreshLayoutsFromTmux
    XCTAssertTrue([_controller hasOutstandingWindowResize], @"the re-sync from the rejected layout is pending");
    [_gateway feedLines:[self okReply:nil]];  // re-sync
    XCTAssertNil(_gateway.abortMessage);
    [self assertNoResizeOutstanding];
}

// Notifications can arrive between replies. They must not be taken for a reply.
- (void)testNotificationsBetweenRepliesAreNotCountedAsReplies {
    [_controller setLayoutInWindow:0 toLayoutWithMovedDivider:@"aafd,120x40,0,0,0"];
    [_gateway feedLines:[self okReply:nil]];
    [_gateway feedLine:@"%window-renamed @0 foo"];
    [_gateway feedLine:@"%session-window-changed $0 @0"];
    XCTAssertTrue([_controller hasOutstandingWindowResize]);
    [_gateway feedLines:[self okReply:nil]];
    XCTAssertNil(_gateway.abortMessage);
    [self assertNoResizeOutstanding];
}

// A layout is only digits and punctuation, but whatever is sent must not be able to leave its
// quotes or start a second command (control mode takes one command per line).
- (void)testLayoutCannotEscapeItsQuotes {
    NSString *hostile = @"x\" ; kill-server ; \"\\\" \n kill-server";
    [_controller setLayoutInWindow:3 toLayoutWithMovedDivider:hostile];
    NSString *written = [self written];
    XCTAssertTrue([written containsString:@"select-layout -t @3 \"x\\\" ; kill-server ; \\\"\\\\\\\" \\012 kill-server\""],
                  @"%@", written);
    NSArray<NSString *> *lines = [written componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        XCTAssertFalse([line hasPrefix:@" kill-server"], @"%@", written);
    }
}

- (void)testFailedNewWindowCallsCompletionWithAnInvalidWindow {
    __block int windowID = 12345;
    void (^completion)(int) = ^(int newWindowID) {
        windowID = newWindowID;
    };
    [_controller newWindowWithAffinityCreated:nil
                  affinityWindowAndCompletion:[iTermTriple tripleWithObject:nil
                                                                  andObject:completion
                                                                     object:nil]];
    XCTAssertEqual(windowID, -1, @"a caller waiting on a new window must learn that it failed");
}

@end
