//
//  TmuxDetachWithdrawsIT2ClientTests.m
//  ModernTests
//
//  A tmux integration client advertises itself to it2 with an @it2_client_<hex> server option and
//  withdraws it when it detaches. Detaching from the gateway (Esc) did, but Shell > tmux > Detach,
//  which goes through -[TmuxController requestDetach], did not, so the option lingered. QA finding
//  F-068.
//

#import <XCTest/XCTest.h>

#import "TmuxController.h"
#import "TmuxControllerRegistry.h"
#import "TmuxGatewayTestFakes.h"

@interface TmuxGateway (DetachWithdrawsIT2ClientTesting)
- (void)enableWrites;
@end

@interface TmuxController (DetachWithdrawsIT2ClientTesting)
- (void)didLoadTmuxClientName:(NSString *)response;
@end

@interface TmuxDetachWithdrawsIT2ClientTests : XCTestCase
@end

@implementation TmuxDetachWithdrawsIT2ClientTests {
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
                                               clientName:@"detach-withdraw-test"
                                                  profile:@{}
                                             profileModel:nil];
}

- (void)tearDown {
    [[TmuxControllerRegistry sharedInstance] setController:nil forClient:_controller.clientName];
    _controller = nil;
    [super tearDown];
}

- (void)testRequestDetachWithdrawsTheRecordBeforeDetaching {
    [_controller didLoadTmuxClientName:@"/dev/ttys004\n"];
    [_delegate.writtenStrings removeAllObjects];

    [_controller requestDetach];

    NSString *withdraw = [TmuxController commandWithdrawingIT2ClientRecordForTmuxClientName:@"/dev/ttys004"];
    NSString *written = [_delegate.writtenStrings componentsJoinedByString:@""];
    const NSRange withdrawRange = [written rangeOfString:withdraw];
    const NSRange detachRange = [written rangeOfString:@"detach" options:NSBackwardsSearch];
    XCTAssertNotEqual(withdrawRange.location, NSNotFound, @"%@", written);
    XCTAssertNotEqual(detachRange.location, NSNotFound, @"%@", written);
    XCTAssertLessThan(withdrawRange.location, detachRange.location, @"%@", written);
}

@end
