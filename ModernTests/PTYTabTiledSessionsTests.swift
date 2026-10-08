//
//  PTYTabTiledSessionsTests.swift
//  ModernTests
//
//  Callers that are about the tiled layout use -tiledSessions; floating panes must not change what
//  they see. These use a real terminal window.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYTabTiledSessionsTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!
    private var savedShowPaneTitles = false
    private var savedShowPaneTitlesForOnePane = false
    private let floatFrame = NSRect(x: 40, y: 30, width: 300, height: 200)

    override func setUpWithError() throws {
        try super.setUpWithError()
        try OnscreenTestGate.skipUnlessEnabled()
        savedShowPaneTitles = iTermPreferences.bool(forKey: kPreferenceKeyShowPaneTitles)
        savedShowPaneTitlesForOnePane = iTermPreferences.bool(forKey: kPreferenceKeyShowPaneTitlesEvenIfOnlyOnePane)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyShowPaneTitles)
        iTermPreferences.setBool(false, forKey: kPreferenceKeyShowPaneTitlesEvenIfOnlyOnePane)
        fixture = TerminalWindowTestFixture()
    }

    override func tearDown() {
        // When setUp was skipped nothing was saved, so there is nothing to restore.
        if let fixture {
            fixture.close()
            self.fixture = nil
            iTermPreferences.setBool(savedShowPaneTitles, forKey: kPreferenceKeyShowPaneTitles)
            iTermPreferences.setBool(savedShowPaneTitlesForOnePane, forKey: kPreferenceKeyShowPaneTitlesEvenIfOnlyOnePane)
        }
        super.tearDown()
    }

    private var tab: PTYTab {
        guard let tab = fixture.terminal.currentTab() else {
            it_fatalError("No tab")
        }
        return tab
    }

    func testFloatHasTitleBarButDoesNotTurnOnTheTiledPanesTitleBar() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No session")
            return
        }
        let float = fixture.addFloat(frame: floatFrame)
        tab.updatePaneTitles()

        XCTAssertTrue(float.view?.showTitle() ?? false, "a float always has a title bar")
        XCTAssertFalse(tiled.view?.showTitle() ?? true,
                       "one tiled pane plus a float is still one tiled pane, which has no title bar")
    }

    func testTwoTiledPanesStillGetTitleBars() {
        guard let first = tab.tiledSessions()?.first else {
            XCTFail("No session")
            return
        }
        let second = fixture.split(first, vertically: true)
        tab.updatePaneTitles()
        XCTAssertTrue(first.view?.showTitle() ?? false)
        XCTAssertTrue(second.view?.showTitle() ?? false)
    }

    func testOrderedSessionsPutFloatsAfterTiledPanes() {
        guard let first = tab.tiledSessions()?.first else {
            XCTFail("No session")
            return
        }
        let second = fixture.split(first, vertically: true)
        let back = fixture.addFloat(frame: floatFrame)
        let front = fixture.addFloat(frame: floatFrame.offsetBy(dx: 10, dy: 10))
        guard let ordered = tab.orderedSessions as? [PTYSession] else {
            XCTFail("No ordered sessions")
            return
        }
        XCTAssertEqual(Set(ordered), Set([first, second, back, front]))
        if iTermAdvancedSettingsModel.navigatePanesInReadingOrder() {
            XCTAssertEqual(ordered, [first, second, back, front],
                           "reading order puts tiled panes first, then floats back to front")
        }
    }

    func testSplitPaneWidthCannotBeLockedOnAFloat() {
        guard let first = tab.tiledSessions()?.first else {
            XCTFail("No session")
            return
        }
        fixture.split(first, vertically: true)
        let float = fixture.addFloat(frame: floatFrame)
        var allowed: ObjCBool = true
        _ = float.textViewSplitPaneWidthIsLocked(&allowed)
        XCTAssertFalse(allowed.boolValue)
    }

    func testSplitPaneWidthCannotBeLockedOnTheOnlyTiledPaneEvenWithAFloat() {
        guard let only = tab.tiledSessions()?.first else {
            XCTFail("No session")
            return
        }
        fixture.addFloat(frame: floatFrame)
        var allowed: ObjCBool = true
        _ = only.textViewSplitPaneWidthIsLocked(&allowed)
        XCTAssertFalse(allowed.boolValue)
    }

    func testMinimizedSessionsExcludeFloats() {
        guard let first = tab.tiledSessions()?.first else {
            XCTFail("No session")
            return
        }
        let second = fixture.split(first, vertically: true)
        let float = fixture.addFloat(frame: floatFrame)
        tab.setActiveSession(second)
        tab.maximize()
        let minimized = tab.minimizedSessions ?? []
        XCTAssertEqual(minimized, [first], "a float over a maximized pane is not minimized")
        XCTAssertFalse(minimized.contains(float))
        tab.perform(NSSelectorFromString("unmaximize"))
    }
}
