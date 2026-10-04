//
//  TmuxGatewayExitInResponseTests.m
//  ModernTests
//
//  The gateway has a workaround for tmux 1.8, which could send %exit inside a
//  %begin/%end block without closing it: on seeing %exit mid-response it ends
//  the command and treats the %exit as real. Servers from 1.9 on always close
//  the block first, so for them a %exit line inside a response is data (for
//  example capture-pane output from a pane whose scrollback holds control-mode
//  text) and must neither truncate the response nor disconnect the host.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "TmuxGateway.h"
#import "VT100Token.h"

@interface TmuxGatewayExitInResponseFakeDelegate : NSObject<TmuxGatewayDelegate>
@property(nonatomic) BOOL hostDisconnected;
@end

@implementation TmuxGatewayExitInResponseFakeDelegate

- (TmuxController *)tmuxController { return nil; }
- (BOOL)tmuxUpdateLayoutForWindow:(int)windowId layout:(NSString *)layout visibleLayout:(NSString *)visibleLayout zoomed:(NSNumber *)zoomed only:(BOOL)only { return NO; }
- (void)tmuxWindowAddedWithId:(int)windowId {}
- (void)tmuxWindowClosedWithId:(int)windowId {}
- (void)tmuxWindowRenamedWithId:(int)windowId to:(NSString *)newName {}
- (void)tmuxHostDisconnected:(NSString *)dcsID { self.hostDisconnected = YES; }
- (void)tmuxWriteString:(NSString *)string {}
- (void)tmuxReadTask:(NSData *)data windowPane:(int)wp latency:(NSNumber *)latency {}
- (void)tmuxSessionChanged:(NSString *)sessionName sessionId:(int)sessionId {}
- (void)tmuxSessionsChanged {}
- (void)tmuxWindowsDidChange {}
- (void)tmuxSession:(int)sessionId renamed:(NSString *)newName {}
- (VT100GridSize)tmuxClientSize { return VT100GridSizeMake(80, 25); }
- (NSInteger)tmuxNumberOfLinesOfScrollbackHistory { return 1000; }
- (void)tmuxSetSecureLogging:(BOOL)secureLogging {}
- (void)tmuxPrintLine:(NSString *)line {}
- (NSWindowController<iTermWindowController> *)tmuxGatewayWindow { return nil; }
- (void)tmuxInitialCommandDidCompleteSuccessfully {}
- (void)tmuxInitialCommandDidFailWithError:(NSString *)error {}
- (void)tmuxCannotSendCharactersInSupplementaryPlanes:(NSString *)string windowPane:(int)windowPane {}
- (void)tmuxDidOpenInitialWindows {}
- (void)tmuxDoubleAttachForSessionGUID:(NSString *)sessionGUID {}
- (NSString *)tmuxOwningSessionGUID { return @"guid"; }
- (NSString *)tmuxGatewayOriginIdentifier { return nil; }
- (NSDictionary<NSString *, NSString *> *)tmuxGatewayIT2ClientRecord { return nil; }
- (BOOL)tmuxGatewayShouldForceDetach { return NO; }
- (void)tmuxGatewayDidTimeOutDuringInitialization:(BOOL)duringInitialization {}
- (void)tmuxActiveWindowPaneDidChangeInWindow:(int)windowID toWindowPane:(int)paneID {}
- (void)tmuxSessionWindowDidChangeTo:(int)windowID {}
- (void)tmuxWindowPaneDidPause:(int)wp notification:(BOOL)notification {}
- (void)tmuxSessionPasteDidChange:(NSString *)pasteBufferName {}
- (void)tmuxClientSessionChanged:(NSString *)clientName {}
- (void)tmuxClientDetached:(NSString *)clientName {}
- (void)tmuxServerMayOmitEndGuardBeforeExit:(BOOL)mayOmit {}

@end

@interface TmuxGatewayExitInResponseTests : XCTestCase
@end

@implementation TmuxGatewayExitInResponseTests {
    TmuxGatewayExitInResponseFakeDelegate *_delegate;
    TmuxGateway *_gateway;
    NSMutableArray<NSString *> *_responses;
}

- (void)setUp {
    [super setUp];
    _delegate = [[TmuxGatewayExitInResponseFakeDelegate alloc] init];
    _gateway = [[TmuxGateway alloc] initWithDelegate:_delegate dcsID:@"dcs"];
    _responses = [NSMutableArray array];
}

- (void)handleResponse:(NSString *)response {
    [_responses addObject:response ?: @"(nil)"];
}

- (void)feedLine:(NSString *)line {
    VT100Token *token = [[VT100Token alloc] init];
    token.type = TMUX_LINE;
    token.string = line;
    token.savedData = [line dataUsingEncoding:NSUTF8StringEncoding];
    [_gateway executeToken:token];
}

- (void)sendCommandAndFeedResponseContainingExit {
    [_gateway sendCommand:@"capture-pane -p"
           responseTarget:self
         responseSelector:@selector(handleResponse:)];
    for (NSString *line in @[ @"%begin 1 1 1", @"some text", @"%exit", @"more text", @"%end 1 1 1" ]) {
        [self feedLine:line];
    }
}

- (void)testExitInsideResponseIsDataWhenServerIsModern {
    _gateway.minimumServerVersion = [NSDecimalNumber decimalNumberWithString:@"3.4"];
    XCTAssertFalse([_gateway serverMayOmitEndGuardBeforeExit]);

    [self sendCommandAndFeedResponseContainingExit];

    XCTAssertEqualObjects(_responses, @[ @"some text\n%exit\nmore text" ]);
    XCTAssertFalse(_delegate.hostDisconnected);
}

- (void)testExitInsideResponseEndsCommandWhenVersionUnknown {
    XCTAssertNil(_gateway.minimumServerVersion);
    XCTAssertTrue([_gateway serverMayOmitEndGuardBeforeExit]);

    [self sendCommandAndFeedResponseContainingExit];

    // The tmux 1.8 workaround: the command ends at the %exit, which is then a real exit.
    XCTAssertEqualObjects(_responses, @[ @"some text" ]);
    XCTAssertTrue(_delegate.hostDisconnected);
}

- (void)testExitInsideResponseEndsCommandOnTmux18 {
    _gateway.minimumServerVersion = [NSDecimalNumber decimalNumberWithString:@"1.8"];
    XCTAssertTrue([_gateway serverMayOmitEndGuardBeforeExit]);

    [self sendCommandAndFeedResponseContainingExit];

    XCTAssertEqualObjects(_responses, @[ @"some text" ]);
    XCTAssertTrue(_delegate.hostDisconnected);
}

- (void)testExitOutsideResponseStillDisconnectsWhenServerIsModern {
    _gateway.minimumServerVersion = [NSDecimalNumber decimalNumberWithString:@"3.4"];

    [_gateway sendCommand:@"list-windows"
           responseTarget:self
         responseSelector:@selector(handleResponse:)];
    for (NSString *line in @[ @"%begin 1 1 1", @"x", @"%end 1 1 1", @"%exit" ]) {
        [self feedLine:line];
    }

    XCTAssertEqualObjects(_responses, @[ @"x" ]);
    XCTAssertTrue(_delegate.hostDisconnected);
}

@end
