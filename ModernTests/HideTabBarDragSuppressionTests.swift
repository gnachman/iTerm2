//
//  HideTabBarDragSuppressionTests.swift
//  ModernTests
//
//  A tab drag forces “Hide tab bar when only one tab is open” off so that
//  single-tab windows become drop targets (issue 12846). Changing it refreshes
//  every window and session, so it must happen only when the effective value
//  actually changes. Otherwise drags stutter with many windows (issue 13187).
//

import XCTest
@testable import iTerm2SharedARC

final class HideTabBarDragSuppressionTests: XCTestCase {
    private var savedHideTabBar: Any?
    private var refreshCount = 0
    private var observer: NSObjectProtocol?

    override func setUp() {
        super.setUp()
        // Read the stored value, not iTermPreferences, which fills in the
        // default, so tearDown can remove a key that was unset.
        savedHideTabBar = iTermUserDefaults.userDefaults().object(forKey: kPreferenceKeyHideTabBar)
        iTermPreferences.setHideTabBarSuppressedDuringDrag(false)
        observer = NotificationCenter.default.addObserver(
            forName: .refreshTerminal,
            object: nil,
            queue: nil) { [weak self] _ in
                self?.refreshCount += 1
            }
    }

    override func tearDown() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        iTermPreferences.setHideTabBarSuppressedDuringDrag(false)
        iTermPreferences.setObject(savedHideTabBar, forKey: kPreferenceKeyHideTabBar)
        super.tearDown()
    }

    func testDragRefreshesWindowsWhenTabBarIsHiddenForSingleTab() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyHideTabBar)
        refreshCount = 0

        iTermPreferences.setHideTabBarSuppressedDuringDrag(true)
        XCTAssertFalse(iTermPreferences.bool(forKey: kPreferenceKeyHideTabBar))
        XCTAssertEqual(refreshCount, 1)

        iTermPreferences.setHideTabBarSuppressedDuringDrag(false)
        XCTAssertTrue(iTermPreferences.bool(forKey: kPreferenceKeyHideTabBar))
        XCTAssertEqual(refreshCount, 2)
    }

    func testDragDoesNotRefreshWindowsWhenTabBarIsAlwaysShown() {
        iTermPreferences.setBool(false, forKey: kPreferenceKeyHideTabBar)
        refreshCount = 0

        iTermPreferences.setHideTabBarSuppressedDuringDrag(true)
        XCTAssertFalse(iTermPreferences.bool(forKey: kPreferenceKeyHideTabBar))
        iTermPreferences.setHideTabBarSuppressedDuringDrag(false)
        XCTAssertFalse(iTermPreferences.bool(forKey: kPreferenceKeyHideTabBar))

        XCTAssertEqual(refreshCount, 0)
    }
}
