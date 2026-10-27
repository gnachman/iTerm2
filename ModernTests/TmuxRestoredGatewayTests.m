//
//  TmuxRestoredGatewayTests.m
//  ModernTests
//
//  A session restored as a tmux gateway after iTerm2 was killed may no longer be in tmux (tmux was
//  detached before, and the state wasn't saved since). It used to type its tmux commands into the
//  shell once its one-second wait was up. When its foreground job is a shell, it now leaves tmux
//  mode and drops what was waiting to be written. QA finding F-832.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "PTYSession.h"
#import "TmuxGateway.h"
#import "TmuxGatewayTestFakes.h"

@interface TmuxRestoredGatewayTests : XCTestCase
@end

@implementation TmuxRestoredGatewayTests

- (void)testShellNames {
    XCTAssertTrue([PTYSession processNameIsAShell:@"-zsh"]);
    XCTAssertTrue([PTYSession processNameIsAShell:@"zsh"]);
    XCTAssertTrue([PTYSession processNameIsAShell:@"/bin/bash"]);
    XCTAssertTrue([PTYSession processNameIsAShell:@"fish"]);
    XCTAssertFalse([PTYSession processNameIsAShell:@"tmux"]);
    XCTAssertFalse([PTYSession processNameIsAShell:@"ssh"]);
    XCTAssertFalse([PTYSession processNameIsAShell:@""]);
    XCTAssertFalse([PTYSession processNameIsAShell:nil]);
}

- (void)testCancelledDelayedWritesWriteNothing {
    TmuxFakeGatewayDelegate *delegate = [[TmuxFakeGatewayDelegate alloc] init];
    TmuxRecordingGateway *gateway = [[TmuxRecordingGateway alloc] initWithDelegate:delegate dcsID:@"dcs"];
    [gateway enableWritesAfterDelay];
    [gateway sendCommand:@"list-windows" responseTarget:nil responseSelector:nil];
    [gateway cancelDelayedWritesAndDiscardQueue];

    XCTestExpectation *waited = [self expectationWithDescription:@"past the delay"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [waited fulfill];
    });
    [self waitForExpectations:@[ waited ] timeout:10];
    XCTAssertEqualObjects([delegate.writtenStrings componentsJoinedByString:@""], @"");
}

@end
