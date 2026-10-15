//
//  SwapSessionPaneTitleTests.swift
//  ModernTests
//
//  Swap With Session between a one-pane tab and a split tab used to carry each pane's title bar
//  state with it: the session swapped into the split tab had no title bar while its neighbors did,
//  and the one-pane tab gained one (QA finding F-317). Each tab refreshed its pane titles before
//  its view-to-session map knew about the session it had just received, so that session was
//  skipped.
//

import XCTest
@testable import iTerm2SharedARC

final class SwapSessionPaneTitleTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!
    private var savedShowPaneTitles = true
    private var savedShowPaneTitlesEvenIfOnlyOnePane = false

    override func setUp() {
        super.setUp()
        savedShowPaneTitles = iTermPreferences.bool(forKey: kPreferenceKeyShowPaneTitles)
        savedShowPaneTitlesEvenIfOnlyOnePane = iTermPreferences.bool(forKey: kPreferenceKeyShowPaneTitlesEvenIfOnlyOnePane)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyShowPaneTitles)
        iTermPreferences.setBool(false, forKey: kPreferenceKeyShowPaneTitlesEvenIfOnlyOnePane)
        fixture = TerminalWindowTestFixture()
    }

    override func tearDown() {
        fixture.close()
        fixture = nil
        iTermPreferences.setBool(savedShowPaneTitles, forKey: kPreferenceKeyShowPaneTitles)
        iTermPreferences.setBool(savedShowPaneTitlesEvenIfOnlyOnePane,
                                 forKey: kPreferenceKeyShowPaneTitlesEvenIfOnlyOnePane)
        super.tearDown()
    }

    func testSwappingFromAOnePaneTabIntoASplitTabUpdatesTitleBars() throws {
        let terminal = fixture.terminal
        let a = try XCTUnwrap(terminal.currentSession())
        let b = fixture.split(a, vertically: true)
        let t = fixture.split(b, vertically: false)
        let u = fixture.addTab()
        let splitTab = try XCTUnwrap(a.delegate as? PTYTab)
        let onePaneTab = try XCTUnwrap(u.delegate as? PTYTab)
        XCTAssertFalse(splitTab === onePaneTab)
        XCTAssertTrue(t.view?.showTitle() ?? false, "Precondition: panes in a split tab have title bars")
        XCTAssertFalse(u.view?.showTitle() ?? false, "Precondition: a lone pane has no title bar")

        // Swap With Session started on U, with a pane in the split tab chosen as the destination.
        splitTab.swapSession(t, with: u)

        XCTAssertTrue((u.delegate as? PTYTab) === splitTab)
        XCTAssertTrue((t.delegate as? PTYTab) === onePaneTab)
        for session in [a, b, u] {
            XCTAssertTrue(session.view?.showTitle() ?? false, "A pane in the split tab has no title bar")
        }
        XCTAssertFalse(t.view?.showTitle() ?? false, "The lone pane has a title bar")
    }
}
