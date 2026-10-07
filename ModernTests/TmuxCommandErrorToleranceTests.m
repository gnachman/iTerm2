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

- (void)testFailedResizeDoesNotEndTheConnectionOrLeaveAResizeOutstanding {
    [_controller windowPane:2 resizedBy:2 horizontally:NO];
    XCTAssertTrue([_controller hasOutstandingWindowResize]);
    [_gateway feedLines:[self errorReply:@"pane is modal"]];
    XCTAssertNil(_gateway.abortMessage, @"resize-pane failing must not end the connection");
    XCTAssertFalse([_controller hasOutstandingWindowResize],
                   @"the list-windows that follows the resize is failed too, and must still be counted");
    [self assertGatewayStillWorks];
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
