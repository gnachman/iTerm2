//
//  MenuBarItemForcedTests.m
//  ModernTests
//
//  While iTerm2 is excluded from the Dock, the menu bar icon is the only way back to Settings, so
//  Settings shows “Show menu bar icon” as on and can't be changed. With “…but only if all windows
//  are hotkey windows” also on, iTerm2 is an ordinary Dock app whenever a normal window is open,
//  and then the icon follows the saved setting. Forcing the checkbox anyway showed it on while
//  the icon was missing and kept the user from changing it (QA finding F-250). Once only hotkey
//  windows are open, iTerm2 leaves the Dock and the icon is shown regardless, so the checkbox must
//  be forced again (QA finding F-423).
//

#import <XCTest/XCTest.h>

#import "AppearancePreferencesViewController.h"

@interface MenuBarItemForcedTests : XCTestCase
@end

@implementation MenuBarItemForcedTests

- (void)testForcedWhenAlwaysExcludedFromDock {
    XCTAssertTrue([AppearancePreferencesViewController menuBarItemIsForcedWhenExcludedFromDock:YES
                                                                  onlyIfAllWindowsAreHotkeyWindows:NO
                                                                                currentlyUIElement:YES
                                                                                     statusBarIcon:YES]);
}

- (void)testNotForcedWhileAnOrdinaryWindowKeepsTheAppInTheDock {
    XCTAssertFalse([AppearancePreferencesViewController menuBarItemIsForcedWhenExcludedFromDock:YES
                                                                   onlyIfAllWindowsAreHotkeyWindows:YES
                                                                                 currentlyUIElement:NO
                                                                                      statusBarIcon:YES]);
}

- (void)testForcedWhileOnlyHotkeyWindowsKeepTheAppOutOfTheDock {
    XCTAssertTrue([AppearancePreferencesViewController menuBarItemIsForcedWhenExcludedFromDock:YES
                                                                  onlyIfAllWindowsAreHotkeyWindows:YES
                                                                                currentlyUIElement:YES
                                                                                     statusBarIcon:YES]);
}

- (void)testNotForcedInTheDock {
    XCTAssertFalse([AppearancePreferencesViewController menuBarItemIsForcedWhenExcludedFromDock:NO
                                                                   onlyIfAllWindowsAreHotkeyWindows:NO
                                                                                 currentlyUIElement:NO
                                                                                      statusBarIcon:YES]);
}

- (void)testNotForcedWithoutTheStatusBarIcon {
    XCTAssertFalse([AppearancePreferencesViewController menuBarItemIsForcedWhenExcludedFromDock:YES
                                                                   onlyIfAllWindowsAreHotkeyWindows:NO
                                                                                 currentlyUIElement:YES
                                                                                      statusBarIcon:NO]);
    XCTAssertFalse([AppearancePreferencesViewController menuBarItemIsForcedWhenExcludedFromDock:YES
                                                                   onlyIfAllWindowsAreHotkeyWindows:YES
                                                                                 currentlyUIElement:YES
                                                                                      statusBarIcon:NO]);
}

@end
