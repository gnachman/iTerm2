//
//  MenuBarItemForcedTests.m
//  ModernTests
//
//  While iTerm2 is excluded from the Dock, the menu bar icon is the only way back to Settings, so
//  Settings shows “Show menu bar icon” as on and can't be changed. With “…but only if all windows
//  are hotkey windows” also on, iTerm2 is an ordinary Dock app whenever a normal window is open,
//  and then the icon follows the saved setting. Forcing the checkbox anyway showed it on while
//  the icon was missing and kept the user from changing it (QA finding F-250).
//

#import <XCTest/XCTest.h>

#import "AppearancePreferencesViewController.h"

@interface MenuBarItemForcedTests : XCTestCase
@end

@implementation MenuBarItemForcedTests

- (void)testForcedWhenAlwaysExcludedFromDock {
    XCTAssertTrue([AppearancePreferencesViewController menuBarItemIsForcedWhenExcludedFromDock:YES
                                                                  onlyIfAllWindowsAreHotkeyWindows:NO
                                                                                     statusBarIcon:YES]);
}

- (void)testNotForcedWhenExcludedOnlyWhileAllWindowsAreHotkeyWindows {
    XCTAssertFalse([AppearancePreferencesViewController menuBarItemIsForcedWhenExcludedFromDock:YES
                                                                   onlyIfAllWindowsAreHotkeyWindows:YES
                                                                                      statusBarIcon:YES]);
}

- (void)testNotForcedInTheDock {
    XCTAssertFalse([AppearancePreferencesViewController menuBarItemIsForcedWhenExcludedFromDock:NO
                                                                   onlyIfAllWindowsAreHotkeyWindows:NO
                                                                                      statusBarIcon:YES]);
}

- (void)testNotForcedWithoutTheStatusBarIcon {
    XCTAssertFalse([AppearancePreferencesViewController menuBarItemIsForcedWhenExcludedFromDock:YES
                                                                   onlyIfAllWindowsAreHotkeyWindows:NO
                                                                                      statusBarIcon:NO]);
}

@end
