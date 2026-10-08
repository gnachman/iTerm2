//
//  FloatingPaneMaximizeTests.swift
//  ModernTests
//
//  Maximizing a float, and directional navigation, which floats take no part in.
//

import XCTest
@testable import iTerm2SharedARC

final class FloatingPaneMaximizeTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!
    private let floatFrame = NSRect(x: 60, y: 60, width: 300, height: 200)

    override func setUpWithError() throws {
        try super.setUpWithError()
        try OnscreenTestGate.skipUnlessEnabled()
        fixture = TerminalWindowTestFixture()
        var frame = fixture.window.frame
        frame.size = NSSize(width: 900, height: 650)
        fixture.window.setFrame(frame, display: true)
    }

    override func tearDown() {
        fixture?.close()
        fixture = nil
        super.tearDown()
    }

    private var tab: PTYTab {
        guard let tab = fixture.terminal.currentTab() else {
            it_fatalError("No tab")
        }
        return tab
    }

    private var container: NSView {
        guard let container = tab.realRootView else {
            it_fatalError("No container")
        }
        return container
    }

    private func pane(_ session: PTYSession) -> iTermFloatingPaneView {
        guard let pane = tab.floatingPane(for: session) else {
            it_fatalError("No pane")
        }
        return pane
    }

    private func assertFillsTheTab(_ session: PTYSession, file: StaticString = #filePath, line: UInt = #line) {
        guard let metrics = FloatingPaneLayout.metrics(for: session) else {
            XCTFail("No metrics", file: file, line: line)
            return
        }
        // Exactly, with the remainder of a cell in its margins, so nothing beneath shows at the edges.
        XCTAssertEqual(pane(session).outlineFrame, container.bounds, file: file, line: line)
        XCTAssertEqual(FloatingPaneGrid(columns: Int(session.columns), rows: Int(session.rows)),
                       FloatingPaneGeometry.maximumGrid(container: container.bounds.size, metrics: metrics),
                       "the largest grid that fits", file: file, line: line)
    }

    func testMaximizingAFloatFillsTheTabBehindTheOtherFloats() {
        let float = fixture.addFloat(frame: floatFrame)
        let other = fixture.addFloat(frame: floatFrame.offsetBy(dx: 40, dy: 40))
        let start = pane(float).outlineFrame
        tab.setActiveSession(float)

        fixture.terminal.toggleMaximizeActivePane()
        XCTAssertTrue(pane(float).isMaximized)
        assertFillsTheTab(float)
        XCTAssertTrue(float.textViewIsMaximized(), "it shows the maximized indicator")
        XCTAssertFalse(other.textViewIsMaximized())
        XCTAssertEqual(tab.floatingSessions(), [float, other], "a maximized float goes behind the others")
        XCTAssertFalse(tab.hasMaximizedPane(), "the tiled layout is not maximized")
        XCTAssertEqual(tab.tiledSessions()?.count, 1)

        fixture.terminal.toggleMaximizeActivePane()
        XCTAssertFalse(pane(float).isMaximized)
        XCTAssertFalse(float.textViewIsMaximized())
        XCTAssertEqual(pane(float).outlineFrame, start)
        XCTAssertEqual(tab.floatingSessions(), [other, float], "it comes back in front")
    }

    func testDoubleClickingTheTitleBarMaximizesTheFloat() {
        let float = fixture.addFloat(frame: floatFrame)
        guard let title = float.view?.title else {
            XCTFail("No title bar")
            return
        }
        let point = title.convert(NSPoint(x: title.bounds.width * 0.4, y: title.bounds.midY), to: nil)
        fixture.mouse.doubleClick(at: point)
        XCTAssertTrue(pane(float).isMaximized)
        assertFillsTheTab(float)
    }

    func testAMaximizedFloatKeepsFillingTheTabWhenTheWindowResizes() {
        let float = fixture.addFloat(frame: floatFrame)
        tab.setActiveSession(float)
        fixture.terminal.toggleMaximizeActivePane()

        var frame = fixture.window.frame
        frame.size.width += 120
        frame.size.height += 60
        fixture.window.setFrame(frame, display: true)
        assertFillsTheTab(float)

        frame.size.width -= 300
        frame.size.height -= 200
        fixture.window.setFrame(frame, display: true)
        assertFillsTheTab(float)
        XCTAssertTrue(pane(float).isMaximized)
    }

    func testAFloatShowsNoMaximizedIndicatorOverAMaximizedTiledPane() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let second = fixture.split(tiled, vertically: true)
        let float = fixture.addFloat(frame: floatFrame)
        tab.setActiveSession(second)
        tab.maximize()
        XCTAssertTrue(second.textViewIsMaximized())
        XCTAssertFalse(float.textViewIsMaximized())
        tab.perform(NSSelectorFromString("unmaximize"))
    }

    // MARK: - Directional navigation

    func testDirectionalNavigationFromAFloatDoesNothing() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let right = fixture.split(tiled, vertically: true)
        let float = fixture.addFloat(frame: floatFrame)
        XCTAssertNil(tab.sessionRight(of: float))
        XCTAssertNil(tab.sessionLeft(of: float))
        XCTAssertNil(tab.session(above: float))
        XCTAssertNil(tab.session(below: float))
        XCTAssertTrue(tab.sessionRight(of: tiled) === right, "floats are not neighbors of tiled panes")
    }

    // MARK: - Numbering

    func testFloatsAreNumberedAfterTiledPanes() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let second = fixture.split(tiled, vertically: true)
        let float = fixture.addFloat(frame: floatFrame)
        tab.updateSessionOrdinals()
        if iTermAdvancedSettingsModel.navigatePanesInReadingOrder() {
            XCTAssertEqual(tiled.view?.ordinal, 1)
            XCTAssertEqual(second.view?.ordinal, 2)
            XCTAssertEqual(float.view?.ordinal, 3, "floats come after the tiled panes")
        } else {
            XCTAssertEqual(Set([tiled.view?.ordinal, second.view?.ordinal, float.view?.ordinal]), Set([1, 2, 3]))
        }
    }
}
