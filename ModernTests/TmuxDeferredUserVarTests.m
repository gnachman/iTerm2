//
//  TmuxDeferredUserVarTests.m
//  ModernTests
//
//  A user variable set by a pane's shell while its window is opening must win over the stale
//  @uservars value fetched during the open, both in the controller (which seeds the new
//  session's variables) and in tmux. See issue 13006.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "TmuxController.h"
#import "TmuxGateway.h"

// Writes are normally enabled once tmux reports the session.
@interface TmuxGateway (TmuxDeferredUserVarTests)
- (void)enableWrites;
@end

@interface TmuxDeferredUserVarFakeDelegate : NSObject<TmuxGatewayDelegate>
@property(nonatomic, strong) NSMutableArray<NSString *> *writes;
@end

@implementation TmuxDeferredUserVarFakeDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _writes = [NSMutableArray array];
    }
    return self;
}

- (TmuxController *)tmuxController { return nil; }
- (BOOL)tmuxUpdateLayoutForWindow:(int)windowId layout:(NSString *)layout visibleLayout:(NSString *)visibleLayout zoomed:(NSNumber *)zoomed only:(BOOL)only { return NO; }
- (void)tmuxWindowAddedWithId:(int)windowId {}
- (void)tmuxWindowClosedWithId:(int)windowId {}
- (void)tmuxWindowRenamedWithId:(int)windowId to:(NSString *)newName {}
- (void)tmuxHostDisconnected:(NSString *)dcsID {}
- (void)tmuxWriteString:(NSString *)string { [_writes addObject:string]; }
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

@interface TmuxDeferredUserVarTests : XCTestCase
@end

@implementation TmuxDeferredUserVarTests {
    TmuxDeferredUserVarFakeDelegate *_delegate;
    TmuxGateway *_gateway;
    TmuxController *_controller;
}

- (void)setUp {
    [super setUp];
    _delegate = [[TmuxDeferredUserVarFakeDelegate alloc] init];
    _gateway = [[TmuxGateway alloc] initWithDelegate:_delegate dcsID:@"dcs"];
    _gateway.minimumServerVersion = [NSDecimalNumber decimalNumberWithString:@"3.4"];
    [_gateway enableWrites];
    _controller = [[TmuxController alloc] initWithGateway:_gateway
                                               clientName:@"test"
                                                  profile:@{}
                                             profileModel:nil];
}

- (void)tearDown {
    [_controller detach];
    [super tearDown];
}

- (void)testDeferredUserVarOverridesStaleUserVarsOfReopenedPane {
    // The opener fetched @uservars as it was before the open.
    [_controller setEncodedUserVars:@"user.host_name=old" forPane:3];

    // While the window was opening, the shell set host_name to "new".
    [_controller willOpenPane:3];
    NSData *output = [@"\e]1337;SetUserVar=host_name=bmV3\a" dataUsingEncoding:NSUTF8StringEncoding];
    [_controller didDropOutput:output forPane:3];
    [_delegate.writes removeAllObjects];

    NSArray *tokens = [_controller takeDeferredTokensForPane:3];

    XCTAssertEqual(tokens.count, 1);
    XCTAssertEqualObjects([_controller userVarsForPane:3][@"user.host_name"], @"new");
    NSString *write = [_delegate.writes componentsJoinedByString:@""];
    XCTAssertTrue([write containsString:@"set -p -t %3 @uservars"], @"%@", write);
}

- (void)testDeferredUnsetRemovesStaleUserVar {
    [_controller setEncodedUserVars:@"user.host_name=old" forPane:3];
    [_controller willOpenPane:3];
    NSData *output = [@"\e]1337;SetUserVar=host_name\a" dataUsingEncoding:NSUTF8StringEncoding];
    [_controller didDropOutput:output forPane:3];

    [_controller takeDeferredTokensForPane:3];

    XCTAssertNil([_controller userVarsForPane:3][@"user.host_name"]);
}

@end
