//
//  TabBarVisibilityWindowSizeTests.m
//  ModernTests
//
//  Issue 13165. Showing or hiding the tab bar through refreshTerminal: (a tab drag beginning or
//  ending, or a change to the tab bar visibility setting) ignored “Preserve window size when tab
//  bar shows or hides”, and a window as tall as the screen ended up shorter after any tab drag
//  because it could not grow when the drag showed its tab bar.
//

#import <XCTest/XCTest.h>

#import "ITAddressBookMgr.h"
#import "PSMTabBarControl.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PreferencePanel.h"
#import "ProfileModel.h"
#import "PseudoTerminal.h"
#import "iTermPreferences.h"
#import "iTermRootTerminalView.h"
#import "iTermSessionFactory.h"

// Creates sessions as usual but never launches a process.
@interface TabBarSizeSessionFactory : iTermSessionFactory
@end

@implementation TabBarSizeSessionFactory
- (void)attachOrLaunchWithRequest:(iTermSessionAttachOrLaunchRequest *)request {
}
@end

@interface TabBarSizeTerminal : PseudoTerminal
@property (nonatomic, strong) TabBarSizeSessionFactory *spyFactory;
@end

@implementation TabBarSizeTerminal
- (iTermSessionFactory *)sessionFactory {
    return self.spyFactory;
}
@end

@interface TabBarVisibilityWindowSizeTests : XCTestCase
@end

@implementation TabBarVisibilityWindowSizeTests {
    NSMutableArray<TabBarSizeTerminal *> *_terms;
    Profile *_profile;
    NSDictionary<NSString *, id> *_savedPrefs;
    int _savedTabStyle;
    int _savedTabPosition;
}

- (void)setUp {
    [super setUp];
    // Orders terminal windows onto the screen. See OnscreenTestGate.swift.
    XCTSkipUnless([NSProcessInfo.processInfo.environment[@"ITERM2_ONSCREEN_TESTS"] isEqualToString:@"1"],
                  @"Puts windows on screen. Set ITERM2_ONSCREEN_TESTS=1 to run.");
    _profile = [[ProfileModel sharedInstance] defaultBookmark];
    _terms = [NSMutableArray array];
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (NSString *key in [self prefKeys]) {
        saved[key] = @([iTermPreferences boolForKey:key]);
    }
    _savedPrefs = saved;
    _savedTabStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    _savedTabPosition = [iTermPreferences intForKey:kPreferenceKeyTabPosition];
    // In this style a visible top tab bar is a titlebar accessory. The BottomTabs tests cover the
    // tab bar living in the content view.
    [iTermPreferences setInt:TAB_STYLE_LIGHT forKey:kPreferenceKeyTabStyle];
    [iTermPreferences setInt:PSMTab_TopTab forKey:kPreferenceKeyTabPosition];
    [iTermPreferences setBool:YES forKey:kPreferenceKeyHideTabBar];
    [iTermPreferences setBool:NO forKey:kPreferenceKeyPreserveWindowSizeWhenTabBarVisibilityChanges];
    [iTermPreferences setBool:NO forKey:kPreferenceKeyPreserveWindowSizeToKeepOnScreenWhenTabBarVisibilityChanges];
    [iTermPreferences setHideTabBarSuppressedDuringDrag:NO];
}

- (void)tearDown {
    [iTermPreferences setHideTabBarSuppressedDuringDrag:NO];
    [_savedPrefs enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *value, BOOL *stop) {
        [iTermPreferences setBool:value.boolValue forKey:key];
    }];
    [iTermPreferences setInt:_savedTabStyle forKey:kPreferenceKeyTabStyle];
    [iTermPreferences setInt:_savedTabPosition forKey:kPreferenceKeyTabPosition];
    for (TabBarSizeTerminal *term in _terms) {
        [term.window close];
    }
    _terms = nil;
    [super tearDown];
}

- (NSArray<NSString *> *)prefKeys {
    return @[ kPreferenceKeyHideTabBar,
              kPreferenceKeyPreserveWindowSizeWhenTabBarVisibilityChanges,
              kPreferenceKeyPreserveWindowSizeToKeepOnScreenWhenTabBarVisibilityChanges ];
}

#pragma mark - Helpers

- (TabBarSizeTerminal *)terminalWithTabs:(NSInteger)numberOfTabs {
    TabBarSizeTerminal *term = [[TabBarSizeTerminal alloc] initWithSmartLayout:NO
                                                                     windowType:WINDOW_TYPE_NORMAL
                                                                savedWindowType:WINDOW_TYPE_NORMAL
                                                                     percentage:(iTermPercentage){0, 0}
                                                                         screen:-1
                                                                        profile:_profile];
    term.spyFactory = [[TabBarSizeSessionFactory alloc] init];
    for (NSInteger i = 0; i < numberOfTabs; i++) {
        PTYSession *session = [term.spyFactory newSessionWithProfile:_profile parent:nil];
        [term addSessionInNewTab:session];
    }
    [term.window orderFront:nil];
    [_terms addObject:term];
    return term;
}

// As tall as the screen allows, so it can't grow to fit a tab bar.
- (NSRect)fullHeightFrameFor:(PseudoTerminal *)term {
    const NSRect visible = (term.window.screen ?: NSScreen.mainScreen).visibleFrame;
    return NSMakeRect(NSMinX(visible) + 20, NSMinY(visible), 900, NSHeight(visible));
}

- (NSRect)ordinaryFrameFor:(PseudoTerminal *)term {
    const NSRect visible = (term.window.screen ?: NSScreen.mainScreen).visibleFrame;
    return NSMakeRect(NSMinX(visible) + 20, NSMinY(visible) + 100, 900, 500);
}

- (void)setFrame:(NSRect)frame of:(PseudoTerminal *)term {
    [term.window setFrame:frame display:YES];
    XCTAssertTrue(NSEqualRects(term.window.frame, frame),
                  @"Precondition: frame is %@, wanted %@",
                  NSStringFromRect(term.window.frame), NSStringFromRect(frame));
}

- (void)assertFrameOf:(PseudoTerminal *)term equals:(NSRect)expected {
    XCTAssertTrue(NSEqualRects(term.window.frame, expected),
                  @"Window frame is %@, expected %@",
                  NSStringFromRect(term.window.frame), NSStringFromRect(expected));
}

- (void)assertTabFillsWindow:(PseudoTerminal *)term {
    // The tab's content should track the window, not keep a stale size from while the tab bar
    // was showing.
    iTermRootTerminalView *root = (iTermRootTerminalView *)term.window.contentView;
    XCTAssertTrue([root isKindOfClass:[iTermRootTerminalView class]]);
    const NSSize content = term.currentTab.realRootView.frame.size;
    const NSSize tabView = root.tabView.contentRect.size;
    XCTAssertEqualWithAccuracy(content.height, tabView.height, 1,
                               @"Tab content %@ vs tab view %@",
                               NSStringFromSize(content), NSStringFromSize(tabView));
}

#pragma mark - A drag that doesn't add or remove this window's tabs

- (void)testDragRestoresFullHeightWindow {
    TabBarSizeTerminal *term = [self terminalWithTabs:1];
    const NSRect frame = [self fullHeightFrameFor:term];
    [self setFrame:frame of:term];

    [iTermPreferences setHideTabBarSuppressedDuringDrag:YES];
    XCTAssertTrue([term tabBarShouldBeVisibleWithAdditionalTabs:0]);
    [iTermPreferences setHideTabBarSuppressedDuringDrag:NO];

    XCTAssertFalse([term tabBarShouldBeVisibleWithAdditionalTabs:0]);
    [self assertFrameOf:term equals:frame];
    [self assertTabFillsWindow:term];
}

- (void)testDragRestoresOrdinaryWindow {
    TabBarSizeTerminal *term = [self terminalWithTabs:1];
    const NSRect frame = [self ordinaryFrameFor:term];
    [self setFrame:frame of:term];

    [iTermPreferences setHideTabBarSuppressedDuringDrag:YES];
    [iTermPreferences setHideTabBarSuppressedDuringDrag:NO];

    [self assertFrameOf:term equals:frame];
    [self assertTabFillsWindow:term];
}

- (void)testDragRestoresFullHeightWindowWithPreserveSetting {
    [iTermPreferences setBool:YES forKey:kPreferenceKeyPreserveWindowSizeWhenTabBarVisibilityChanges];
    TabBarSizeTerminal *term = [self terminalWithTabs:1];
    const NSRect frame = [self fullHeightFrameFor:term];
    [self setFrame:frame of:term];

    [iTermPreferences setHideTabBarSuppressedDuringDrag:YES];
    // With the setting on, the window doesn't change while the drag shows its tab bar.
    [self assertFrameOf:term equals:frame];
    [iTermPreferences setHideTabBarSuppressedDuringDrag:NO];

    [self assertFrameOf:term equals:frame];
    [self assertTabFillsWindow:term];
}

- (void)testDragRestoresWindowWithVisibleTabBar {
    TabBarSizeTerminal *term = [self terminalWithTabs:2];
    const NSRect frame = [self fullHeightFrameFor:term];
    [self setFrame:frame of:term];

    [iTermPreferences setHideTabBarSuppressedDuringDrag:YES];
    [iTermPreferences setHideTabBarSuppressedDuringDrag:NO];

    XCTAssertTrue([term tabBarShouldBeVisibleWithAdditionalTabs:0]);
    [self assertFrameOf:term equals:frame];
}

// Dropping a window's lone tab on the desktop moves the window before the drag ends
// (-[PSMTabDragAssistant cancelDragMovingWindowTo:]). That move must survive the restore.
- (void)moveDuringDragThenCheck:(PseudoTerminal *)term
                     startFrame:(NSRect)frame
                             dx:(CGFloat)dx
                             dy:(CGFloat)dy {
    [self setFrame:frame of:term];

    [iTermPreferences setHideTabBarSuppressedDuringDrag:YES];
    const NSRect duringDrag = term.window.frame;
    [term.window setFrameTopLeftPoint:NSMakePoint(NSMinX(duringDrag) + dx, NSMaxY(duringDrag) + dy)];
    [iTermPreferences setHideTabBarSuppressedDuringDrag:NO];

    [self assertFrameOf:term equals:NSOffsetRect(frame, dx, dy)];
    [self assertTabFillsWindow:term];
}

- (void)testDragKeepsWindowMoveMadeDuringDrag {
    TabBarSizeTerminal *term = [self terminalWithTabs:1];
    [self moveDuringDragThenCheck:term startFrame:[self ordinaryFrameFor:term] dx:60 dy:-40];
}

- (void)testDragKeepsMoveOfFullHeightWindowMadeDuringDrag {
    TabBarSizeTerminal *term = [self terminalWithTabs:1];
    [self moveDuringDragThenCheck:term startFrame:[self fullHeightFrameFor:term] dx:60 dy:0];
}

- (void)testBottomTabsDragKeepsWindowMoveMadeDuringDrag {
    [iTermPreferences setInt:PSMTab_BottomTab forKey:kPreferenceKeyTabPosition];
    TabBarSizeTerminal *term = [self terminalWithTabs:1];
    [self moveDuringDragThenCheck:term startFrame:[self ordinaryFrameFor:term] dx:60 dy:-40];
}

- (void)testDragDoesNotUndoResizeMadeDuringDrag {
    TabBarSizeTerminal *term = [self terminalWithTabs:1];
    const NSRect frame = [self ordinaryFrameFor:term];
    [self setFrame:frame of:term];

    [iTermPreferences setHideTabBarSuppressedDuringDrag:YES];
    NSRect resized = term.window.frame;
    resized.size.width -= 200;
    [term.window setFrame:resized display:YES];
    [iTermPreferences setHideTabBarSuppressedDuringDrag:NO];

    XCTAssertFalse(NSEqualRects(term.window.frame, frame));
    XCTAssertEqualWithAccuracy(NSWidth(term.window.frame), NSWidth(resized), 1);
    XCTAssertEqualWithAccuracy(NSMinX(term.window.frame), NSMinX(resized), 1);
    [self assertTabFillsWindow:term];
}

#pragma mark - A drag that takes a tab out of this window (scenarios 1 and 2)

- (void)testDraggingTabOutKeepsSizeWithPreserveSetting {
    [iTermPreferences setBool:YES forKey:kPreferenceKeyPreserveWindowSizeWhenTabBarVisibilityChanges];
    TabBarSizeTerminal *term = [self terminalWithTabs:2];
    const NSRect frame = [self fullHeightFrameFor:term];
    [self setFrame:frame of:term];

    [iTermPreferences setHideTabBarSuppressedDuringDrag:YES];
    // Stands in for the dragged tab landing in another window or another tab's split.
    [term closeTab:term.tabs.lastObject];
    XCTAssertEqual(term.numberOfTabs, 1);
    [iTermPreferences setHideTabBarSuppressedDuringDrag:NO];

    XCTAssertFalse([term tabBarShouldBeVisibleWithAdditionalTabs:0]);
    [self assertFrameOf:term equals:frame];
    [self assertTabFillsWindow:term];
}

- (void)testDraggingTabOutShrinksWithoutPreserveSetting {
    TabBarSizeTerminal *term = [self terminalWithTabs:2];
    const NSRect frame = [self ordinaryFrameFor:term];
    [self setFrame:frame of:term];

    [iTermPreferences setHideTabBarSuppressedDuringDrag:YES];
    [term closeTab:term.tabs.lastObject];
    [iTermPreferences setHideTabBarSuppressedDuringDrag:NO];

    // Without the setting the window gives up the tab bar's height, as closing a tab does.
    XCTAssertFalse([term tabBarShouldBeVisibleWithAdditionalTabs:0]);
    XCTAssertLessThan(NSHeight(term.window.frame), NSHeight(frame));
    XCTAssertEqualWithAccuracy(NSMaxY(term.window.frame), NSMaxY(frame), 1);
}

#pragma mark - Turning off “Show tab bar even when there is only one tab” (scenario 3)

- (void)testHidingTabBarInSettingsKeepsSizeWithPreserveSetting {
    [iTermPreferences setBool:YES forKey:kPreferenceKeyPreserveWindowSizeWhenTabBarVisibilityChanges];
    [iTermPreferences setBool:NO forKey:kPreferenceKeyHideTabBar];
    TabBarSizeTerminal *term = [self terminalWithTabs:1];
    const NSRect frame = [self fullHeightFrameFor:term];
    [self setFrame:frame of:term];
    XCTAssertTrue([term tabBarShouldBeVisibleWithAdditionalTabs:0]);

    [iTermPreferences setBool:YES forKey:kPreferenceKeyHideTabBar];
    [[NSNotificationCenter defaultCenter] postNotificationName:kRefreshTerminalNotification object:nil];

    XCTAssertFalse([term tabBarShouldBeVisibleWithAdditionalTabs:0]);
    [self assertFrameOf:term equals:frame];
    [self assertTabFillsWindow:term];
}

- (void)testShowingTabBarInSettingsKeepsSizeWithPreserveSetting {
    [iTermPreferences setBool:YES forKey:kPreferenceKeyPreserveWindowSizeWhenTabBarVisibilityChanges];
    TabBarSizeTerminal *term = [self terminalWithTabs:1];
    const NSRect frame = [self ordinaryFrameFor:term];
    [self setFrame:frame of:term];
    XCTAssertFalse([term tabBarShouldBeVisibleWithAdditionalTabs:0]);

    [iTermPreferences setBool:NO forKey:kPreferenceKeyHideTabBar];
    [[NSNotificationCenter defaultCenter] postNotificationName:kRefreshTerminalNotification object:nil];

    XCTAssertTrue([term tabBarShouldBeVisibleWithAdditionalTabs:0]);
    [self assertFrameOf:term equals:frame];
    [self assertTabFillsWindow:term];
}

- (void)testBottomTabsDragRestoresFullHeightWindow {
    [iTermPreferences setInt:PSMTab_BottomTab forKey:kPreferenceKeyTabPosition];
    [self testDragRestoresFullHeightWindow];
}

- (void)testBottomTabsDraggingTabOutKeepsSizeWithPreserveSetting {
    [iTermPreferences setInt:PSMTab_BottomTab forKey:kPreferenceKeyTabPosition];
    [self testDraggingTabOutKeepsSizeWithPreserveSetting];
}

- (void)testBottomTabsHidingTabBarInSettingsKeepsSizeWithPreserveSetting {
    [iTermPreferences setInt:PSMTab_BottomTab forKey:kPreferenceKeyTabPosition];
    [self testHidingTabBarInSettingsKeepsSizeWithPreserveSetting];
}

- (void)testHidingTabBarInSettingsShrinksWithoutPreserveSetting {
    [iTermPreferences setBool:NO forKey:kPreferenceKeyHideTabBar];
    TabBarSizeTerminal *term = [self terminalWithTabs:1];
    const NSRect frame = [self ordinaryFrameFor:term];
    [self setFrame:frame of:term];

    [iTermPreferences setBool:YES forKey:kPreferenceKeyHideTabBar];
    [[NSNotificationCenter defaultCenter] postNotificationName:kRefreshTerminalNotification object:nil];

    XCTAssertFalse([term tabBarShouldBeVisibleWithAdditionalTabs:0]);
    XCTAssertLessThan(NSHeight(term.window.frame), NSHeight(frame));
}

@end
