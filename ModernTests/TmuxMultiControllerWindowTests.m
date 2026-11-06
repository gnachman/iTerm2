//
//  TmuxMultiControllerWindowTests.m
//  ModernTests
//
//  A native window can hold tabs from more than one tmux session, for example after dragging a
//  tmux tab into another session's window. Code that assumed one controller per window acted on
//  the wrong session:
//  - tmux reporting a new current window in one session selected its tab even while the user was
//    working in another session's tab, so keystrokes went to the wrong session.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "SessionView.h"
#import "TmuxController.h"
#import "TmuxControllerRegistry.h"

@interface TmuxController (TmuxMultiControllerWindowTests)
- (void)retainWindow:(int)window withTab:(PTYTab *)tab;
- (void)releaseWindow:(int)window;
@end

#pragma mark - Fakes

@interface TmuxMultiSpyController : TmuxController
@end

@implementation TmuxMultiSpyController

- (instancetype)initWithClientName:(NSString *)clientName {
    return [super initWithGateway:nil clientName:clientName profile:@{} profileModel:nil];
}

@end

// A tmux tab whose controller, window id, and native window are fixed by the test.
@interface TmuxMultiSpyTab : PTYTab
@property (nonatomic, strong) TmuxController *spyController;
@property (nonatomic) int spyWindow;
@property (nonatomic, weak) NSWindowController<iTermWindowController> *spyParentWindow;
@property (nonatomic) NSInteger makeActiveCount;
@end

@implementation TmuxMultiSpyTab

- (BOOL)isTmuxTab {
    return self.spyController != nil;
}

- (TmuxController *)tmuxController {
    return self.spyController;
}

- (int)tmuxWindow {
    return self.spyWindow;
}

- (NSWindowController<iTermWindowController> *)realParentWindow {
    return self.spyParentWindow;
}

- (void)makeActive {
    self.makeActiveCount += 1;
}

@end

// A window whose tabs and current tab are fixed by the test. It never loads its nib, so it has no
// content view and no selected tab view item.
@interface TmuxMultiSpyTerminal : PseudoTerminal
@property (nonatomic, copy) NSArray<PTYTab *> *spyTabs;
@property (nonatomic, weak) PTYTab *spyCurrentTab;
@end

@implementation TmuxMultiSpyTerminal

- (NSArray<PTYTab *> *)tabs {
    return self.spyTabs;
}

- (PTYTab *)currentTab {
    return self.spyCurrentTab;
}

- (NSWindow *)window {
    return nil;
}

@end

#pragma mark - Tests

@interface TmuxMultiControllerWindowTests : XCTestCase
@end

@implementation TmuxMultiControllerWindowTests {
    TmuxMultiSpyController *_a;
    TmuxMultiSpyController *_b;
    TmuxMultiSpyTerminal *_terminal;
    NSMutableArray<PTYTab *> *_tabs;
    NSMutableArray<NSArray *> *_retainedWindows;
}

- (void)setUp {
    [super setUp];
    _a = [[TmuxMultiSpyController alloc] initWithClientName:@"multi-controller-window-test-a"];
    _b = [[TmuxMultiSpyController alloc] initWithClientName:@"multi-controller-window-test-b"];
    // Doesn't load a window.
    _terminal = [[TmuxMultiSpyTerminal alloc] initWithWindowNibName:@"PseudoTerminal"];
    _tabs = [NSMutableArray array];
    _retainedWindows = [NSMutableArray array];
}

- (void)tearDown {
    for (NSArray *pair in _retainedWindows) {
        [(TmuxController *)pair[0] releaseWindow:[pair[1] intValue]];
    }
    for (TmuxController *controller in @[ _a, _b ]) {
        [[TmuxControllerRegistry sharedInstance] setController:nil forClient:controller.clientName];
    }
    _terminal = nil;
    _tabs = nil;
    _a = nil;
    _b = nil;
    [super tearDown];
}

// Adds a tab for `controller`'s window `window` (or a regular tab if `controller` is nil).
- (TmuxMultiSpyTab *)addTabForController:(TmuxController *)controller window:(int)window {
    PTYSession *session = [[PTYSession alloc] initSynthetic:NO];
    session.view = [[SessionView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    TmuxMultiSpyTab *tab = [[TmuxMultiSpyTab alloc] initWithSession:session parentWindow:nil];
    tab.spyController = controller;
    tab.spyWindow = window;
    tab.spyParentWindow = _terminal;
    if (controller) {
        [controller retainWindow:window withTab:tab];
        [_retainedWindows addObject:@[ controller, @(window) ]];
    }
    [_tabs addObject:tab];
    _terminal.spyTabs = _tabs;
    return tab;
}

#pragma mark Another session's current-window change

// Control: tmux switching windows within the session the user is working in follows along.
- (void)testActiveWindowChangeSelectsTabWhenSameSessionsTabIsCurrent {
    TmuxMultiSpyTab *b1 = [self addTabForController:_b window:1];
    TmuxMultiSpyTab *b2 = [self addTabForController:_b window:2];
    _terminal.spyCurrentTab = b1;

    [_b activeWindowDidChangeTo:2];

    XCTAssertEqual(b2.makeActiveCount, 1);
}

// Control: a regular tab doesn't stop the session's tab from being selected, as before.
- (void)testActiveWindowChangeSelectsTabWhenRegularTabIsCurrent {
    TmuxMultiSpyTab *regular = [self addTabForController:nil window:0];
    TmuxMultiSpyTab *b1 = [self addTabForController:_b window:1];
    _terminal.spyCurrentTab = regular;

    [_b activeWindowDidChangeTo:1];

    XCTAssertEqual(b1.makeActiveCount, 1);
}

- (void)testActiveWindowChangeDoesNotSelectTabWhileAnotherSessionsTabIsCurrent {
    TmuxMultiSpyTab *a1 = [self addTabForController:_a window:1];
    TmuxMultiSpyTab *b1 = [self addTabForController:_b window:1];
    _terminal.spyCurrentTab = a1;

    [_b activeWindowDidChangeTo:1];

    XCTAssertEqual(b1.makeActiveCount, 0, @"The user is typing in A's tab; B must not take over");
}

@end
