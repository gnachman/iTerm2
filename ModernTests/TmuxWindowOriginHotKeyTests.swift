//
//  TmuxWindowOriginHotKeyTests.swift
//  ModernTests
//
//  With tmux windows set to open as tabs in the attaching window, running `tmux -CC attach` in a
//  hotkey window moved the hotkey window to the tmux window's saved position, often mostly off
//  screen (QA finding F-273). A hotkey window's position belongs to its profile, so the saved
//  origin of a tmux window is not applied to it.
//
//  The opener needs a live tmux session to reach the code that moves the window, so this pins
//  the decision it makes there.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxWindowOriginHotKeyTests: XCTestCase {
    private func shouldApply(useOriginalWindow: Bool,
                             initialTabs: Int,
                             initial: Bool,
                             isHotKeyWindow: Bool) -> Bool {
        return TmuxWindowOpener.shouldApplySavedOrigin(usingOriginalWindow: useOriginalWindow,
                                                       initialTabs: initialTabs,
                                                       initial: initial,
                                                       isHotKeyWindow: isHotKeyWindow)
    }

    func testHotKeyWindowIsNotMovedWhenTmuxTabsOpenInIt() {
        XCTAssertFalse(shouldApply(useOriginalWindow: true, initialTabs: 1, initial: true, isHotKeyWindow: true))
    }

    func testHotKeyWindowIsNeverMoved() {
        XCTAssertFalse(shouldApply(useOriginalWindow: false, initialTabs: 1, initial: false, isHotKeyWindow: true))
    }

    func testOrdinaryWindowsKeepTheirBehavior() {
        // The attaching window holds only the gateway, so it effectively becomes the tmux window.
        XCTAssertTrue(shouldApply(useOriginalWindow: true, initialTabs: 1, initial: true, isHotKeyWindow: false))
        // The attaching window has other tabs, so it keeps its place.
        XCTAssertFalse(shouldApply(useOriginalWindow: true, initialTabs: 2, initial: true, isHotKeyWindow: false))
        // A window of its own goes where tmux last had it.
        XCTAssertTrue(shouldApply(useOriginalWindow: false, initialTabs: 0, initial: true, isHotKeyWindow: false))
        XCTAssertTrue(shouldApply(useOriginalWindow: true, initialTabs: 3, initial: false, isHotKeyWindow: false))
    }
}
