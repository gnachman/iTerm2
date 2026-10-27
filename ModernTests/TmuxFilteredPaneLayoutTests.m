//
//  TmuxFilteredPaneLayoutTests.m
//  ModernTests
//
//  With Find > Filter open on a tmux -CC pane, the tab shows a synthetic stand-in session in place
//  of the tmux pane. The stand-in is not a tmux client, so its own tmux pane id reads as 0. A
//  layout change from tmux used that id to decide which pane was active, so focus went to pane %0
//  instead of the filtered pane, and to decide whether the filtered pane was becoming a float.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "PTYSession.h"
#import "PTYSplitView.h"
#import "PTYTab.h"
#import "SessionView.h"
#import "TaskNotifier.h"
#import "TmuxController.h"
#import "TmuxControllerRegistry.h"
#import "TmuxGateway.h"
#import "TmuxGatewayTestFakes.h"
#import "TmuxLayoutParser.h"

@interface PTYTab (TmuxFilteredPaneLayoutTesting)
- (void)replaceViewHierarchyWithParseTree:(NSMutableDictionary *)parseTree
                           tmuxController:(TmuxController *)tmuxController;
- (void)replaceActiveSessionWithSyntheticSession:(PTYSession *)newSession;
- (void)setTmuxWindow:(int)window;
@end

@interface TmuxFilteredPaneLayoutTests : XCTestCase
@end

@implementation TmuxFilteredPaneLayoutTests {
    NSMutableArray<PTYSession *> *_tmuxSessions;
    TmuxFakeGatewayDelegate *_gatewayDelegate;
    TmuxRecordingGateway *_gateway;
    TmuxController *_controller;
}

- (void)setUp {
    [super setUp];
    _tmuxSessions = [NSMutableArray array];
}

- (void)tearDown {
    // -setTmuxPane: registers the session's task with the shared notifier.
    for (PTYSession *session in _tmuxSessions) {
        id<iTermTask> task = (id<iTermTask>)session.shell;
        if (task) {
            [[TaskNotifier sharedInstance] deregisterTask:task];
        }
    }
    _tmuxSessions = nil;
    if (_controller) {
        [[TmuxControllerRegistry sharedInstance] setController:nil forClient:_controller.clientName];
        _controller = nil;
    }
    [super tearDown];
}

- (PTYSession *)tmuxSessionForPane:(int)pane {
    PTYSession *session = [[PTYSession alloc] initSynthetic:NO];
    session.view = [[SessionView alloc] initWithFrame:NSMakeRect(0, 0, 200, 300)];
    [session setTmuxPane:pane];
    [_tmuxSessions addObject:session];
    XCTAssertTrue(session.isTmuxClient);
    return session;
}

- (PTYSession *)nativeSession {
    PTYSession *session = [[PTYSession alloc] initSynthetic:NO];
    session.view = [[SessionView alloc] initWithFrame:NSMakeRect(0, 0, 200, 300)];
    XCTAssertFalse(session.isTmuxClient);
    return session;
}

- (PTYSession *)standInForSession:(PTYSession *)live {
    PTYSession *standIn = [[PTYSession alloc] initSynthetic:YES];
    standIn.view = [[SessionView alloc] initWithFrame:live.view.frame];
    standIn.liveSession = live;
    return standIn;
}

#pragma mark - The pane a session stands for in a tmux layout

- (void)testTmuxSessionUsesItsOwnPane {
    PTYSession *pane2 = [self tmuxSessionForPane:2];
    XCTAssertEqual([PTYTab tmuxLayoutPaneForSession:pane2], 2);
}

- (void)testTmuxPaneZeroIsPaneZero {
    PTYSession *pane0 = [self tmuxSessionForPane:0];
    XCTAssertEqual([PTYTab tmuxLayoutPaneForSession:pane0], 0);
}

- (void)testStandInUsesItsLiveSessionsPane {
    PTYSession *pane2 = [self tmuxSessionForPane:2];
    PTYSession *standIn = [self standInForSession:pane2];
    XCTAssertEqual(standIn.tmuxPane, 0, @"the stand-in's own id reads as 0");
    XCTAssertEqual([PTYTab tmuxLayoutPaneForSession:standIn], 2);
}

- (void)testNativeSessionHasNoPane {
    PTYSession *native = [self nativeSession];
    XCTAssertEqual(native.tmuxPane, 0);
    XCTAssertEqual([PTYTab tmuxLayoutPaneForSession:native], -1);
}

- (void)testStandInForNativeSessionHasNoPane {
    PTYSession *native = [self nativeSession];
    PTYSession *standIn = [self standInForSession:native];
    XCTAssertEqual([PTYTab tmuxLayoutPaneForSession:standIn], -1);
}

- (void)testNilSessionHasNoPane {
    XCTAssertEqual([PTYTab tmuxLayoutPaneForSession:nil], -1);
}

#pragma mark - Anchoring floats

// QA finding F-131: floats are placed over the tiled pane that contains them. A filter's stand-in
// listed before the real %0 must not be taken for %0.
- (void)testFloatAnchorLookupDoesNotTakeAStandInForPaneZero {
    PTYSession *pane0 = [self tmuxSessionForPane:0];
    PTYSession *pane1 = [self tmuxSessionForPane:1];
    PTYSession *standIn = [self standInForSession:pane1];
    NSArray<PTYSession *> *tiled = @[ standIn, pane0 ];
    XCTAssertEqual([PTYTab sessionShowingTmuxPane:0 amongSessions:tiled], pane0);
    XCTAssertEqual([PTYTab sessionShowingTmuxPane:1 amongSessions:tiled], standIn);
    XCTAssertNil([PTYTab sessionShowingTmuxPane:2 amongSessions:tiled]);
}

- (void)testFloatAnchorLookupIgnoresNativeSessions {
    PTYSession *native = [self nativeSession];
    XCTAssertNil([PTYTab sessionShowingTmuxPane:0 amongSessions:@[ native ]]);
    XCTAssertNil([PTYTab sessionShowingTmuxPane:-1 amongSessions:@[ native ]]);
}

#pragma mark - Which sessions become floats

- (void)testFilteredPaneThatBecomesFloatIsKeptAsAFloat {
    PTYSession *pane2 = [self tmuxSessionForPane:2];
    PTYSession *standIn = [self standInForSession:pane2];
    NSArray<PTYSession *> *floats = [PTYTab sessionsBecomingTmuxFloatsAmong:@[ standIn ]
                                                              floatingPanes:[NSSet setWithObject:@2]];
    XCTAssertEqualObjects(floats, @[ standIn ]);
}

- (void)testFilteredPaneIsNotTakenForPaneZeroBecomingAFloat {
    PTYSession *pane2 = [self tmuxSessionForPane:2];
    PTYSession *standIn = [self standInForSession:pane2];
    NSArray<PTYSession *> *floats = [PTYTab sessionsBecomingTmuxFloatsAmong:@[ standIn ]
                                                              floatingPanes:[NSSet setWithObject:@0]];
    XCTAssertEqualObjects(floats, @[]);
}

- (void)testNativeSessionNeverBecomesAFloat {
    PTYSession *native = [self nativeSession];
    NSArray<PTYSession *> *floats = [PTYTab sessionsBecomingTmuxFloatsAmong:@[ native ]
                                                              floatingPanes:[NSSet setWithObject:@0]];
    XCTAssertEqualObjects(floats, @[]);
}

- (void)testTmuxPaneZeroBecomesAFloat {
    PTYSession *pane0 = [self tmuxSessionForPane:0];
    PTYSession *pane1 = [self tmuxSessionForPane:1];
    NSArray<PTYSession *> *floats = [PTYTab sessionsBecomingTmuxFloatsAmong:@[ pane0, pane1 ]
                                                              floatingPanes:[NSSet setWithObject:@0]];
    XCTAssertEqualObjects(floats, @[ pane0 ]);
}

#pragma mark - A layout change with a filtered pane

// Three side-by-side tmux panes %0 %1 %2 with a filter open on %2, which is active.
- (PTYTab *)tabWithFilteredPaneTwo:(PTYSession **)standInOut
                             panes:(NSArray<PTYSession *> **)panesOut {
    PTYSplitView *root = [[PTYSplitView alloc] initWithFrame:NSMakeRect(0, 0, 602, 300)];
    root.vertical = YES;
    NSMapTable<SessionView *, PTYSession *> *map = [NSMapTable strongToStrongObjectsMapTable];
    NSMutableArray<PTYSession *> *panes = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        PTYSession *session = [self tmuxSessionForPane:i];
        [root addSubview:session.view];
        [map setObject:session forKey:session.view];
        [panes addObject:session];
    }
    PTYTab *tab = [[PTYTab alloc] initWithRoot:root sessions:map];
    _gatewayDelegate = [[TmuxFakeGatewayDelegate alloc] init];
    _gateway = [[TmuxRecordingGateway alloc] initWithDelegate:_gatewayDelegate dcsID:@"dcs"];
    _controller = [[TmuxController alloc] initWithGateway:_gateway
                                               clientName:@"filtered-pane-layout-test"
                                                  profile:@{}
                                             profileModel:nil];
    // A tmux tab gets its controller when it is opened from a tmux layout.
    [tab setValue:_controller forKey:@"tmuxController_"];
    [tab setTmuxWindow:1];
    for (PTYSession *session in panes) {
        session.delegate = tab;
    }
    [tab setActiveSession:panes[2]];
    XCTAssertEqual(tab.activeSession, panes[2]);

    PTYSession *standIn = [[PTYSession alloc] initSynthetic:YES];
    standIn.view = [[SessionView alloc] initWithFrame:panes[2].view.frame];
    standIn.delegate = tab;
    [tab replaceActiveSessionWithSyntheticSession:standIn];
    XCTAssertEqual(tab.activeSession, standIn);
    XCTAssertEqual(standIn.liveSession, panes[2]);

    *standInOut = standIn;
    *panesOut = panes;
    return tab;
}

- (NSMutableDictionary *)parseTreeForLayout:(NSString *)layout {
    NSMutableDictionary *tree = [[TmuxLayoutParser sharedInstance] parsedLayoutFromString:layout];
    XCTAssertNotNil(tree);
    return tree;
}

// The stand-in isn't a tmux client, so its grid fits its view as in any tab. Left at the live
// session's size, a view without the live session's chrome (e.g. a workgroup toolbar) is taller
// than the grid and the uncovered rows draw black. QA finding F-833.
- (void)testStandInFitsItsViewInATmuxTab {
    PTYSession *standIn = nil;
    NSArray<PTYSession *> *panes = nil;
    PTYTab *tab = [self tabWithFilteredPaneTwo:&standIn panes:&panes];
    XCTAssertTrue(tab.isTmuxTab);
    XCTAssertFalse([tab fitSessionToCurrentViewSize:standIn], @"already fitted when it was swapped in");
}

// A layout from tmux resizes the stand-in's view, as when a filter is put back while the tab is
// still settling after a peer switch from another Mac; its grid must follow, or the rows it no
// longer covers draw as a black band. QA finding F-833.
- (void)testStandInFitsItsViewAfterATmuxLayout {
    PTYSession *standIn = nil;
    NSArray<PTYSession *> *panes = nil;
    PTYTab *tab = [self tabWithFilteredPaneTwo:&standIn panes:&panes];
    [tab replaceViewHierarchyWithParseTree:[self parseTreeForLayout:@"abcd,80x24,0,0[80x8,0,0,0,80x7,0,9,1,80x7,0,17,2]"]
                            tmuxController:_controller];
    XCTAssertFalse([tab fitSessionToCurrentViewSize:standIn], @"fitted after the layout");
}

// tmux rearranges the same three panes (e.g. select-layout even-vertical).
- (void)testLayoutChangeKeepsFocusOnFilteredPane {
    PTYSession *standIn = nil;
    NSArray<PTYSession *> *panes = nil;
    PTYTab *tab = [self tabWithFilteredPaneTwo:&standIn panes:&panes];

    [tab replaceViewHierarchyWithParseTree:[self parseTreeForLayout:@"abcd,80x24,0,0[80x8,0,0,0,80x7,0,9,1,80x7,0,17,2]"]
                            tmuxController:_controller];

    XCTAssertEqual(tab.activeSession, standIn, @"focus must stay on the filtered pane, not jump to %%0");
    NSArray<PTYSession *> *tiled = tab.tiledSessions;
    XCTAssertEqual(tiled.count, 3u);
    XCTAssertEqual(tiled[0], panes[0], @"pane %%0 keeps its slot");
    XCTAssertEqual(tiled[1], panes[1]);
    XCTAssertEqual(tiled[2], standIn, @"the stand-in stays in %%2's slot");
}

// tmux makes the filtered pane %2 a float (tmux 3.8 and later).
- (void)testFilteredPaneThatTmuxMakesAFloatKeepsItsStandIn {
    PTYSession *standIn = nil;
    NSArray<PTYSession *> *panes = nil;
    PTYTab *tab = [self tabWithFilteredPaneTwo:&standIn panes:&panes];

    [tab setTmuxLayout:[self parseTreeForLayout:@"abcd,80x24,0,0[80x12,0,0,0,80x11,0,13,1]<30x8,4,2,2>"]
         visibleLayout:nil
        tmuxController:_controller
                zoomed:@NO];

    NSArray<PTYSession *> *tiled = tab.tiledSessions;
    XCTAssertEqual(tiled.count, 2u);
    XCTAssertEqual(tiled[0], panes[0]);
    XCTAssertEqual(tiled[1], panes[1]);
    XCTAssertEqualObjects(tab.floatingSessions, @[ standIn ], @"the filtered pane floats with its stand-in");
    XCTAssertFalse(standIn.exited);
    // ModernTests can't import the Swift header, so read the float's state by key.
    NSObject *standInPane = (NSObject *)[tab floatingPaneForSession:standIn];
    XCTAssertNotNil(standInPane);
    XCTAssertFalse([[standInPane valueForKey:@"isHiddenByTmux"] boolValue],
                   @"tmux shows float %%2, so it must not be hidden");
}

@end
