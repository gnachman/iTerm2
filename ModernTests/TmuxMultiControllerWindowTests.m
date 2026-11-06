//
//  TmuxMultiControllerWindowTests.m
//  ModernTests
//
//  A native window can hold tabs from more than one tmux session, for example after dragging a
//  tmux tab into another session's window. Code that assumed one controller per window acted on
//  the wrong session:
//  - tmux reporting a new current window in one session selected its tab even while the user was
//    working in another session's tab, so keystrokes went to the wrong session.
//  - Closing the last tab of one session asked about every session's windows and detached the
//    selected tab's session instead of the closing one. Closing the window detached only one.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "SessionView.h"
#import "TmuxController.h"
#import "TmuxControllerRegistry.h"
#import "iTermWarning.h"

@interface TmuxController (TmuxMultiControllerWindowTests)
- (void)retainWindow:(int)window withTab:(PTYTab *)tab;
- (void)releaseWindow:(int)window;
@end

@interface PseudoTerminal (TmuxMultiControllerWindowTests)
- (BOOL)killOrHideTmuxWindowForController:(TmuxController *)controller;
@end

#pragma mark - Fakes

@interface TmuxMultiSpyController : TmuxController
@property (nonatomic) NSInteger detachCount;
@property (nonatomic, readonly) NSMutableArray<NSNumber *> *hiddenWindows;
@property (nonatomic, readonly) NSMutableArray<NSNumber *> *killedWindows;
@end

@implementation TmuxMultiSpyController

- (instancetype)initWithClientName:(NSString *)clientName {
    self = [super initWithGateway:nil clientName:clientName profile:@{} profileModel:nil];
    if (self) {
        _hiddenWindows = [NSMutableArray array];
        _killedWindows = [NSMutableArray array];
    }
    return self;
}

- (void)requestDetach {
    self.detachCount += 1;
}

- (void)hideWindow:(int)windowId {
    [self.hiddenWindows addObject:@(windowId)];
}

- (void)killWindow:(int)window {
    [self.killedWindows addObject:@(window)];
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

// Answers the close prompt with the button titled `buttonTitle` and records the prompt's text.
@interface TmuxMultiWarningHandler : NSObject<iTermWarningHandler>
@property (nonatomic, copy) NSString *buttonTitle;
@property (nonatomic, readonly) NSMutableArray<NSString *> *messages;
@end

@implementation TmuxMultiWarningHandler

- (instancetype)init {
    self = [super init];
    if (self) {
        _messages = [NSMutableArray array];
    }
    return self;
}

- (NSModalResponse)warningWouldShowAlert:(NSAlert *)alert identifier:(NSString *)identifier {
    [self.messages addObject:alert.informativeText ?: @""];
    for (NSButton *button in alert.buttons) {
        if ([button.title isEqualToString:self.buttonTitle]) {
            return button.tag;
        }
    }
    XCTFail(@"No button titled %@ in %@", self.buttonTitle, [alert.buttons valueForKey:@"title"]);
    return NSAlertFirstButtonReturn;
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
    id<iTermWarningHandler> _savedHandler;
    TmuxMultiWarningHandler *_handler;
}

- (void)setUp {
    [super setUp];
    _a = [[TmuxMultiSpyController alloc] initWithClientName:@"multi-controller-window-test-a"];
    _b = [[TmuxMultiSpyController alloc] initWithClientName:@"multi-controller-window-test-b"];
    // Doesn't load a window.
    _terminal = [[TmuxMultiSpyTerminal alloc] initWithWindowNibName:@"PseudoTerminal"];
    _tabs = [NSMutableArray array];
    _retainedWindows = [NSMutableArray array];
    _savedHandler = [iTermWarning warningHandler];
    _handler = [[TmuxMultiWarningHandler alloc] init];
    [iTermWarning setWarningHandler:_handler];
    [iTermWarning setIdentifier:@"ClosingTmuxWindowKillsTmuxWindows" isSilenced:NO];
}

- (void)tearDown {
    [iTermWarning setWarningHandler:_savedHandler];
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

#pragma mark Closing

- (NSString *)singleWindowPrompt {
    return NSLocalizedStringWithDefaultValue(@"PseudoTerminal.KillTmuxWindowOne", nil, [NSBundle mainBundle], @"Kill window and its jobs, hide window from view, or detach from tmux session?\n\nHidden windows may be restored from the tmux dashboard.", @"Confirmation prompt when closing a single tmux window");
}

- (NSString *)detachButtonTitle {
    return NSLocalizedStringWithDefaultValue(@"PseudoTerminal.DetachTmuxSession", nil, [NSBundle mainBundle], @"Detach tmux Session", @"Button that detaches from the tmux session");
}

- (NSString *)killButtonTitle {
    return NSLocalizedStringWithDefaultValue(@"PseudoTerminal.Kill", nil, [NSBundle mainBundle], @"Kill", @"Button that kills a tmux window");
}

// Closing A's only tab in a window that also holds three of B's asks about one window.
- (void)testClosingLastTabOfSessionAsksAboutOnlyThatSessionsWindows {
    [self addTabForController:_a window:1];
    [self addTabForController:_b window:1];
    [self addTabForController:_b window:2];
    [self addTabForController:_b window:3];
    _handler.buttonTitle = [self killButtonTitle];

    XCTAssertTrue([_terminal killOrHideTmuxWindowForController:_a]);

    XCTAssertEqualObjects(_handler.messages, @[ [self singleWindowPrompt] ]);
    XCTAssertEqualObjects(_a.killedWindows, @[ @1 ]);
    XCTAssertEqualObjects(_b.killedWindows, @[]);
}

- (void)testDetachingWhenClosingLastTabOfSessionDetachesThatSession {
    [self addTabForController:_a window:1];
    [self addTabForController:_b window:1];
    _handler.buttonTitle = [self detachButtonTitle];

    XCTAssertTrue([_terminal killOrHideTmuxWindowForController:_a]);

    XCTAssertEqual(_a.detachCount, 1);
    XCTAssertEqual(_b.detachCount, 0);
}

- (void)testDetachingWhenClosingWindowDetachesEverySession {
    [self addTabForController:nil window:0];
    [self addTabForController:_a window:1];
    [self addTabForController:_b window:1];
    [self addTabForController:_b window:2];
    _handler.buttonTitle = [self detachButtonTitle];

    XCTAssertTrue([_terminal killOrHideTmuxWindowForController:nil]);

    XCTAssertEqual(_a.detachCount, 1);
    XCTAssertEqual(_b.detachCount, 1);
}

// Control: killing when closing the window kills every session's windows.
- (void)testKillingWhenClosingWindowKillsEverySessionsWindows {
    [self addTabForController:_a window:1];
    [self addTabForController:_b window:1];
    [self addTabForController:_b window:2];
    _handler.buttonTitle = [self killButtonTitle];

    XCTAssertTrue([_terminal killOrHideTmuxWindowForController:nil]);

    XCTAssertEqualObjects(_a.killedWindows, @[ @1 ]);
    XCTAssertEqualObjects(_b.killedWindows, (@[ @1, @2 ]));
}

@end
