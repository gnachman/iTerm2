//
//  NativeFloatingPaneTmuxWiringTests.m
//  ModernTests
//
//  The Floating Pane open style (an external open with NewInstanceOpenStyle=4, or Open URL in
//  Floating Pane) creates a session iTerm2 runs itself. It must not go into a tmux tab as a float,
//  even when the tmux server supports floats, so the launcher opens it in a new tab instead.
//

#import <XCTest/XCTest.h>

#import "ITAddressBookMgr.h"
#import "PTYTab.h"
#import "PseudoTerminal.h"
#import "iTermSessionLauncher.h"

// Declared in iTermSessionLauncher.m.
@interface iTermSessionLauncher (NativeFloatTesting)
- (iTermOpenStyle)styleForWindowController:(PseudoTerminal *)windowController;
- (iTermOpenStyle)resolveStyleForWindowController:(PseudoTerminal *)windowController;
- (iTermObjectType)objectType;
@end

// Stands in for the current tab; only -isTmuxTab is asked of it.
@interface NativeFloatFakeTab : NSObject
@property (nonatomic) BOOL isTmuxTab;
@end

@implementation NativeFloatFakeTab
@end

// A window whose generic float checks (a tab, no layout lock, no instant replay) are fixed by the
// test, so only the tmux-ness of the current tab decides.
@interface NativeFloatSpyTerminal : PseudoTerminal
@property (nonatomic) BOOL floatsAllowed;
@property (nonatomic, strong) NativeFloatFakeTab *fakeTab;
@end

@implementation NativeFloatSpyTerminal
- (BOOL)canCreateFloatingPane {
    return self.floatsAllowed;
}
- (PTYTab *)currentTab {
    return (PTYTab *)self.fakeTab;
}
@end

@interface NativeFloatingPaneTmuxWiringTests : XCTestCase
@end

@implementation NativeFloatingPaneTmuxWiringTests

- (NativeFloatSpyTerminal *)terminalWithFloatsAllowed:(BOOL)floatsAllowed tmux:(BOOL)tmux {
    // Doesn't load a window.
    NativeFloatSpyTerminal *term = [[NativeFloatSpyTerminal alloc] initWithWindowNibName:@"PseudoTerminal"];
    term.floatsAllowed = floatsAllowed;
    term.fakeTab = [[NativeFloatFakeTab alloc] init];
    term.fakeTab.isTmuxTab = tmux;
    return term;
}

- (iTermSessionLauncher *)floatingPaneLauncherFor:(PseudoTerminal *)term {
    iTermSessionLauncher *launcher = [[iTermSessionLauncher alloc] initWithProfile:nil windowController:term];
    launcher.style = iTermOpenStyleFloatingPane;
    return launcher;
}

#pragma mark - PseudoTerminal

- (void)testWindowAllowsNativeFloatInNonTmuxTab {
    XCTAssertTrue([[self terminalWithFloatsAllowed:YES tmux:NO] canInstallNativeFloatingPane]);
}

// tmux 3.8 and later: the window allows floats, but only tmux's own.
- (void)testWindowRefusesNativeFloatInTmuxTabThatSupportsFloats {
    XCTAssertFalse([[self terminalWithFloatsAllowed:YES tmux:YES] canInstallNativeFloatingPane]);
}

- (void)testWindowRefusesNativeFloatWhenFloatsAreNotAllowed {
    XCTAssertFalse([[self terminalWithFloatsAllowed:NO tmux:NO] canInstallNativeFloatingPane]);
}

#pragma mark - Launcher

- (void)testLauncherFloatsInNonTmuxTab {
    NativeFloatSpyTerminal *term = [self terminalWithFloatsAllowed:YES tmux:NO];
    iTermSessionLauncher *launcher = [self floatingPaneLauncherFor:term];
    XCTAssertEqual([launcher styleForWindowController:term], iTermOpenStyleFloatingPane);
    XCTAssertEqual(launcher.objectType, iTermPaneObject);
}

// F-047: tmux 3.8 tab.
- (void)testLauncherOpensTabInsteadOfFloatInTmuxTabThatSupportsFloats {
    NativeFloatSpyTerminal *term = [self terminalWithFloatsAllowed:YES tmux:YES];
    iTermSessionLauncher *launcher = [self floatingPaneLauncherFor:term];
    XCTAssertEqual([launcher styleForWindowController:term], iTermOpenStyleTab);
    XCTAssertEqual(launcher.objectType, iTermTabObject);
}

// F-046: tmux 3.6 tab, where the float used to be installed by the fall-through anyway.
- (void)testLauncherOpensTabInsteadOfFloatInTmuxTabWithoutFloatSupport {
    NativeFloatSpyTerminal *term = [self terminalWithFloatsAllowed:NO tmux:YES];
    iTermSessionLauncher *launcher = [self floatingPaneLauncherFor:term];
    XCTAssertEqual([launcher styleForWindowController:term], iTermOpenStyleTab);
    XCTAssertEqual(launcher.objectType, iTermTabObject);
}

// The tab the session opens in becomes current before the launch request asks for the object
// type, so the type must reflect the style that was actually used.
- (void)testLauncherObjectTypeStaysTabAfterNewTabBecomesCurrent {
    NativeFloatSpyTerminal *term = [self terminalWithFloatsAllowed:YES tmux:YES];
    iTermSessionLauncher *launcher = [self floatingPaneLauncherFor:term];
    XCTAssertEqual([launcher resolveStyleForWindowController:term], iTermOpenStyleTab);
    term.fakeTab.isTmuxTab = NO;
    XCTAssertEqual(launcher.objectType, iTermTabObject);
}

// Instant replay, layout lock, and so on.
- (void)testLauncherOpensTabWhenFloatsAreNotAllowed {
    NativeFloatSpyTerminal *term = [self terminalWithFloatsAllowed:NO tmux:NO];
    iTermSessionLauncher *launcher = [self floatingPaneLauncherFor:term];
    XCTAssertEqual([launcher styleForWindowController:term], iTermOpenStyleTab);
    XCTAssertEqual(launcher.objectType, iTermTabObject);
}

- (void)testLauncherLeavesOtherStylesAlone {
    NativeFloatSpyTerminal *term = [self terminalWithFloatsAllowed:YES tmux:YES];
    iTermSessionLauncher *launcher = [[iTermSessionLauncher alloc] initWithProfile:nil windowController:term];
    launcher.style = iTermOpenStyleVerticalSplit;
    XCTAssertEqual([launcher styleForWindowController:term], iTermOpenStyleVerticalSplit);
    launcher.style = iTermOpenStyleWindow;
    XCTAssertEqual([launcher styleForWindowController:term], iTermOpenStyleWindow);
}

@end
