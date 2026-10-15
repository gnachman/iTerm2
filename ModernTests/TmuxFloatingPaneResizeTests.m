//
//  TmuxFloatingPaneResizeTests.m
//  ModernTests
//
//  A request to resize a session (the Python API's grid_size, View > Restore Text and Session
//  Size, and so on) used to resize a tmux float's session in place without telling tmux. The
//  float's content was laid out at the new size inside its old frame, and tmux kept the old size.
//  QA findings F-048 and F-130.
//

#import <XCTest/XCTest.h>

#import "PTYSession.h"
#import "PTYTab.h"
#import "SessionView.h"
#import "TaskNotifier.h"
#import "TmuxController.h"
#import "TmuxControllerRegistry.h"
#import "TmuxGatewayTestFakes.h"

@interface TmuxFloatResizeSpyController : TmuxController
@property (nonatomic) NSInteger resizeCount;
@property (nonatomic) int resizedPane;
@property (nonatomic) int dx;
@property (nonatomic) int dy;
@property (nonatomic) int dw;
@property (nonatomic) int dh;
@end

@implementation TmuxFloatResizeSpyController

- (void)resizeFloatingPane:(int)wp
              moveByColumns:(int)dx
                       rows:(int)dy
            growingByColumns:(int)dw
                       rows:(int)dh {
    self.resizeCount += 1;
    self.resizedPane = wp;
    self.dx = dx;
    self.dy = dy;
    self.dw = dw;
    self.dh = dh;
}

@end

// A tmux tab whose only float is `floatSession`.
@interface TmuxFloatResizeSpyTab : PTYTab
@property (nonatomic, strong) TmuxFloatResizeSpyController *spyController;
@property (nonatomic, strong) PTYSession *floatSession;
// Only checked for nil by the code under test. The Swift float view isn't visible to ObjC tests.
@property (nonatomic, strong) NSView *floatPane;
@end

@implementation TmuxFloatResizeSpyTab

- (BOOL)isTmuxTab {
    return YES;
}

- (TmuxController *)tmuxController {
    return self.spyController;
}

- (iTermFloatingPaneView *)floatingPaneForSession:(PTYSession *)session {
    return session == self.floatSession ? (iTermFloatingPaneView *)self.floatPane : nil;
}

@end

@interface TmuxFloatingPaneResizeTests : XCTestCase
@end

@implementation TmuxFloatingPaneResizeTests {
    TmuxFakeGatewayDelegate *_delegate;
    TmuxRecordingGateway *_gateway;
    TmuxFloatResizeSpyController *_controller;
    PTYSession *_float;
    TmuxFloatResizeSpyTab *_tab;
}

- (void)setUp {
    [super setUp];
    _delegate = [[TmuxFakeGatewayDelegate alloc] init];
    _gateway = [[TmuxRecordingGateway alloc] initWithDelegate:_delegate dcsID:@"dcs"];
    _controller = [[TmuxFloatResizeSpyController alloc] initWithGateway:_gateway
                                                             clientName:@"float-resize-test"
                                                                profile:@{}
                                                           profileModel:nil];
    PTYSession *tiled = [[PTYSession alloc] initSynthetic:NO];
    tiled.view = [[SessionView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    _tab = [[TmuxFloatResizeSpyTab alloc] initWithSession:tiled parentWindow:nil];
    _tab.spyController = _controller;

    _float = [[PTYSession alloc] initSynthetic:NO];
    [_float setTmuxPane:7];
    _tab.floatSession = _float;
    _tab.floatPane = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
}

- (void)tearDown {
    // -setTmuxPane: registers the session's task with the shared notifier.
    if ([(id)_float.shell conformsToProtocol:@protocol(iTermTask)]) {
        [[TaskNotifier sharedInstance] deregisterTask:(id<iTermTask>)_float.shell];
    }
    [[TmuxControllerRegistry sharedInstance] setController:nil forClient:_controller.clientName];
    _controller = nil;
    _tab = nil;
    _float = nil;
    [super tearDown];
}

- (void)testResizingATmuxFloatAsksTmuxAndLeavesTheSessionAlone {
    const int columns = _float.columns;
    const int rows = _float.rows;
    XCTAssertGreaterThan(columns, 20, @"test setup: the float is wider than the requested size");

    XCTAssertTrue([_tab sessionResizeFloatingPane:_float columns:20 rows:6]);

    XCTAssertEqual(_controller.resizeCount, 1);
    XCTAssertEqual(_controller.resizedPane, 7);
    XCTAssertEqual(_controller.dx, 0, @"the float stays where it is");
    XCTAssertEqual(_controller.dy, 0);
    XCTAssertEqual(_controller.dw, 20 - columns);
    XCTAssertEqual(_controller.dh, 6 - rows);
    XCTAssertEqual(_float.columns, columns, @"tmux's layout change resizes the session, not this");
    XCTAssertEqual(_float.rows, rows);
}

- (void)testResizingATmuxFloatToItsOwnSizeSendsNothing {
    XCTAssertTrue([_tab sessionResizeFloatingPane:_float columns:_float.columns rows:_float.rows]);
    XCTAssertEqual(_controller.resizeCount, 0);
}

- (void)testATiledTmuxSessionIsNotHandledAsAFloat {
    PTYSession *tiled = [[PTYSession alloc] initSynthetic:NO];
    XCTAssertFalse([_tab sessionResizeFloatingPane:tiled columns:20 rows:6]);
    XCTAssertEqual(_controller.resizeCount, 0);
}

@end
