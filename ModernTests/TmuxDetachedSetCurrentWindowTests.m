//
//  TmuxDetachedSetCurrentWindowTests.m
//  ModernTests
//
//  After a detach that leaves the tmux windows open, making one of them key calls
//  -setCurrentWindow:. The gateway is gone by then, so it must do nothing rather than crash.
//  QA finding F-211.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "TmuxController.h"
#import "TmuxControllerRegistry.h"
#import "TmuxGatewayTestFakes.h"

// Writes are normally enabled once tmux reports the session.
@interface TmuxGateway (TmuxDetachedSetCurrentWindowTests)
- (void)enableWrites;
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

@end
