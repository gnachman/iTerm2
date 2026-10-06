//
//  TmuxFloatsOnlyLayoutTests.m
//  ModernTests
//
//  tmux 3.8 added floating panes. A control client that has not opted in to the new layout
//  format gets an empty layout for a window whose panes are all floating. iTerm2 used to treat
//  that as a parse failure and end the connection. The protocol lines below were recorded from
//  tmux next-3.9 with a control client attached while the last tiled pane of a window was killed,
//  leaving one floating pane:
//
//    %layout-change @0 aafd,120x40,0,0,0 aafd,120x40,0,0,0 *
//    %layout-change @0   *
//
//  and list-windows -F "#{window_id} [#{window_layout}] [#{window_visible_layout}]" then gave
//  "@0 [] []".
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "PTYSession.h"
#import "PTYTab.h"
#import "SessionView.h"
#import "TmuxController.h"
#import "TmuxControllerRegistry.h"
#import "TmuxGateway.h"
#import "TmuxLayoutParser.h"
#import "TmuxWindowOpener.h"
#import "VT100Token.h"

// Records aborts instead of showing a modal alert, which would hang the test run.
@interface TmuxFloatsOnlyRecordingGateway : TmuxGateway
@property(nonatomic, copy) NSString *abortMessage;
@end

@implementation TmuxFloatsOnlyRecordingGateway
- (void)abortWithErrorMessage:(NSString *)message title:(NSString *)title {
    self.abortMessage = message ?: @"(nil)";
}
@end

@interface TmuxFloatsOnlyFakeDelegate : NSObject<TmuxGatewayDelegate>
@property(nonatomic) BOOL sawLayoutChange;
@property(nonatomic, copy) NSString *layout;
@property(nonatomic, copy) NSString *visibleLayout;
@property(nonatomic, strong) NSNumber *zoomed;
@end

@implementation TmuxFloatsOnlyFakeDelegate

- (TmuxController *)tmuxController { return nil; }
- (BOOL)tmuxUpdateLayoutForWindow:(int)windowId layout:(NSString *)layout visibleLayout:(NSString *)visibleLayout zoomed:(NSNumber *)zoomed only:(BOOL)only {
    self.sawLayoutChange = YES;
    self.layout = layout;
    self.visibleLayout = visibleLayout;
    self.zoomed = zoomed;
    return NO;
}
- (void)tmuxWindowAddedWithId:(int)windowId {}
- (void)tmuxWindowClosedWithId:(int)windowId {}
- (void)tmuxWindowRenamedWithId:(int)windowId to:(NSString *)newName {}
- (void)tmuxHostDisconnected:(NSString *)dcsID {}
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

@interface TmuxFloatsOnlyLayoutTests : XCTestCase
@end

@implementation TmuxFloatsOnlyLayoutTests {
    TmuxFloatsOnlyFakeDelegate *_delegate;
    TmuxFloatsOnlyRecordingGateway *_gateway;
    TmuxController *_controller;
}

- (void)setUp {
    [super setUp];
    _delegate = [[TmuxFloatsOnlyFakeDelegate alloc] init];
    _gateway = [[TmuxFloatsOnlyRecordingGateway alloc] initWithDelegate:_delegate dcsID:@"dcs"];
}

- (void)tearDown {
    if (_controller) {
        [[TmuxControllerRegistry sharedInstance] setController:nil forClient:_controller.clientName];
        _controller = nil;
    }
    [super tearDown];
}

- (void)feedLine:(NSString *)line {
    VT100Token *token = [[VT100Token alloc] init];
    token.type = TMUX_LINE;
    token.string = line;
    token.savedData = [line dataUsingEncoding:NSUTF8StringEncoding];
    [_gateway executeToken:token];
}

- (TmuxWindowOpener *)openerWithLayout:(NSString *)layout {
    TmuxWindowOpener *opener = [TmuxWindowOpener windowOpener];
    opener.windowIndex = 0;
    opener.layout = layout;
    opener.visibleLayout = layout;
    opener.gateway = _gateway;
    return opener;
}

#pragma mark - Parser

- (void)testEmptyLayoutHasNoTiledPanes {
    TmuxLayoutParser *parser = [TmuxLayoutParser sharedInstance];
    XCTAssertTrue([parser layoutHasNoTiledPanes:@""]);
    XCTAssertTrue([parser layoutHasNoTiledPanes:@"0000,"]);
    XCTAssertTrue([parser layoutHasNoTiledPanes:@"aafd,"]);
}

- (void)testRealAndMalformedLayoutsAreNotMistakenForEmpty {
    TmuxLayoutParser *parser = [TmuxLayoutParser sharedInstance];
    XCTAssertFalse([parser layoutHasNoTiledPanes:nil]);
    XCTAssertFalse([parser layoutHasNoTiledPanes:@"aafd,120x40,0,0,0"]);
    XCTAssertFalse([parser layoutHasNoTiledPanes:@"garbage"]);
    XCTAssertFalse([parser layoutHasNoTiledPanes:@"aafd,120x40"]);
}

#pragma mark - Gateway

- (void)testRecordedLayoutChangeDeliversEmptyLayouts {
    _gateway.acceptNotifications = YES;
    [self feedLine:@"%layout-change @0   *"];
    XCTAssertTrue(_delegate.sawLayoutChange);
    XCTAssertEqualObjects(_delegate.layout, @"");
    XCTAssertEqualObjects(_delegate.visibleLayout, @"");
    XCTAssertEqualObjects(_delegate.zoomed, @NO);
    XCTAssertNil(_gateway.abortMessage);
}

#pragma mark - Window opener

- (void)testOpeningAFloatsOnlyWindowSkipsItWithoutEndingTheConnection {
    TmuxWindowOpener *opener = [self openerWithLayout:@""];
    XCTAssertFalse([opener openWindows:YES]);
    XCTAssertNil(_gateway.abortMessage, @"a floats-only window must not end the connection");
}

- (void)testLayoutChangeToFloatsOnlyLeavesTheTabWithoutEndingTheConnection {
    _controller = [[TmuxController alloc] initWithGateway:_gateway
                                               clientName:@"floats-only-test"
                                                  profile:@{}
                                             profileModel:nil];
    PTYSession *session = [[PTYSession alloc] initSynthetic:NO];
    session.view = [[SessionView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    PTYTab *tab = [[PTYTab alloc] initWithSession:session parentWindow:nil];

    TmuxWindowOpener *opener = [self openerWithLayout:@""];
    opener.controller = _controller;
    XCTAssertFalse([opener updateLayoutInTab:tab]);
    XCTAssertNil(_gateway.abortMessage, @"a floats-only layout change must not end the connection");
    XCTAssertEqual(tab.sessions.count, 1u, @"the tab is left as it was");
}

- (void)testMalformedLayoutStillEndsTheConnection {
    TmuxWindowOpener *opener = [self openerWithLayout:@"aafd,garbage"];
    XCTAssertFalse([opener openWindows:YES]);
    XCTAssertNotNil(_gateway.abortMessage);
}

@end
