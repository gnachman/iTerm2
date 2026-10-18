//
//  TmuxGatewayOutputBeforeNotificationsTests.m
//  ModernTests
//
//  Output that arrives before the gateway accepts notifications (while the initial windows are
//  being opened) isn't displayed, but it may carry state such as a user variable set by the
//  shell's first prompt on a brand-new session. It must reach the delegate as dropped output.
//  QA finding F-345.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "TmuxController.h"
#import "TmuxControllerRegistry.h"
#import "TmuxGatewayTestFakes.h"

@interface TmuxOutputBeforeNotificationsDelegate : TmuxFakeGatewayDelegate
@property(nonatomic, readonly) NSMutableArray<NSString *> *dropped;
@property(nonatomic, readonly) NSMutableArray<NSString *> *read;
@end

@implementation TmuxOutputBeforeNotificationsDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _dropped = [NSMutableArray array];
        _read = [NSMutableArray array];
    }
    return self;
}

- (void)tmuxReadTask:(NSData *)data windowPane:(int)wp latency:(NSNumber *)latency {
    [_read addObject:[NSString stringWithFormat:@"%d:%@", wp, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]]];
}

- (void)tmuxDidDropOutputBeforeAcceptingNotifications:(NSData *)data windowPane:(int)wp {
    [_dropped addObject:[NSString stringWithFormat:@"%d:%@", wp, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]]];
}

@end

@interface TmuxGatewayOutputBeforeNotificationsTests : XCTestCase
@end

@implementation TmuxGatewayOutputBeforeNotificationsTests {
    TmuxOutputBeforeNotificationsDelegate *_delegate;
    TmuxRecordingGateway *_gateway;
}

- (void)setUp {
    [super setUp];
    _delegate = [[TmuxOutputBeforeNotificationsDelegate alloc] init];
    _gateway = [[TmuxRecordingGateway alloc] initWithDelegate:_delegate dcsID:@"dcs"];
    _gateway.minimumServerVersion = [NSDecimalNumber decimalNumberWithString:@"3.4"];
}

- (void)testOutputBeforeAcceptingNotificationsIsDropped {
    XCTAssertFalse(_gateway.acceptNotifications);
    [_gateway feedLine:@"%output %0 \\033]1337;SetUserVar=foo=YmFy\\007"];
    [_gateway feedLine:@"%extended-output %1 5 : hi"];

    XCTAssertEqualObjects(_delegate.dropped, (@[ @"0:\e]1337;SetUserVar=foo=YmFy\a", @"1:hi" ]));
    XCTAssertEqualObjects(_delegate.read, @[]);
    XCTAssertNil(_gateway.abortMessage);
}

- (void)testMalformedOutputBeforeAcceptingNotificationsIsIgnored {
    [_gateway feedLine:@"%output bogus"];

    XCTAssertEqualObjects(_delegate.dropped, @[]);
    XCTAssertNil(_gateway.abortMessage);
}

- (void)testOutputAfterAcceptingNotificationsIsRead {
    _gateway.acceptNotifications = YES;
    [_gateway feedLine:@"%output %0 hi"];

    XCTAssertEqualObjects(_delegate.read, @[ @"0:hi" ]);
    XCTAssertEqualObjects(_delegate.dropped, @[]);
}

@end

@interface TmuxGateway (TmuxInitialWindowsDroppedOutputTests)
- (void)enableWrites;
@end

@interface TmuxController (TmuxInitialWindowsDroppedOutputTests)
- (void)initialListWindowsResponse:(NSString *)response;
@end

// The controller scans dropped output for every pane until the initial windows are listed, then
// keeps only what it captured for panes it is opening.
@interface TmuxInitialWindowsDroppedOutputTests : XCTestCase
@end

@implementation TmuxInitialWindowsDroppedOutputTests {
    TmuxFakeGatewayDelegate *_delegate;
    TmuxRecordingGateway *_gateway;
    TmuxController *_controller;
}

- (void)setUp {
    [super setUp];
    _delegate = [[TmuxFakeGatewayDelegate alloc] init];
    _gateway = [[TmuxRecordingGateway alloc] initWithDelegate:_delegate dcsID:@"dcs"];
    _gateway.minimumServerVersion = [NSDecimalNumber decimalNumberWithString:@"3.4"];
    [_gateway enableWrites];
    _controller = [[TmuxController alloc] initWithGateway:_gateway
                                               clientName:@"initial-windows-dropped-output-test"
                                                  profile:@{}
                                             profileModel:nil];
}

- (void)tearDown {
    [[TmuxControllerRegistry sharedInstance] setController:nil forClient:_controller.clientName];
    _controller = nil;
    [super tearDown];
}

// One list-windows record in the -listWindowsDetailedFormat field order (tmux 2.4+). The window's
// only pane has the same ID as the window.
- (NSString *)recordForWindow:(int)wid {
    NSString *layout = [NSString stringWithFormat:@"af3d,80x25,0,0,%d", wid];
    return [@[ @"s", [NSString stringWithFormat:@"@%d", wid], @"zsh", @"80", @"25",
               layout, @"*", @"1", layout, @"off" ] componentsJoinedByString:@"\t"];
}

- (void)testUserVarOfOpenedPaneSurvivesInitialListingButHiddenPaneIsDiscarded {
    [_controller setValue:[NSMutableSet setWithObject:@2] forKey:@"hiddenWindows_"];
    NSData *output = [@"\e]1337;SetUserVar=foo=YmFy\a" dataUsingEncoding:NSUTF8StringEncoding];
    [_controller didDropOutput:output forPane:1];
    [_controller didDropOutput:output forPane:2];

    NSString *response = [@[ [self recordForWindow:1], [self recordForWindow:2] ] componentsJoinedByString:@"\n"];
    [_controller initialListWindowsResponse:response];

    XCTAssertEqual([_controller takeDeferredTokensForPane:1].count, 1);
    XCTAssertEqual([_controller takeDeferredTokensForPane:2].count, 0);
    XCTAssertNil(_gateway.abortMessage);
}

@end
