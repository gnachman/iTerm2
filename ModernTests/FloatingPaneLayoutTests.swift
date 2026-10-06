//
//  FloatingPaneLayoutTests.swift
//  ModernTests
//
//  Floats in a real terminal window: initial placement, the grid as the source of truth for the
//  frame, keyboard move and resize, and what happens when the window resizes.
//

import XCTest
@testable import iTerm2SharedARC

final class FloatingPaneLayoutTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!

    override func setUp() {
        super.setUp()
        fixture = TerminalWindowTestFixture()
        var frame = fixture.window.frame
        frame.size = NSSize(width: 900, height: 650)
        fixture.window.setFrame(frame, display: true)
    }

    override func tearDown() {
        fixture.close()
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

    /// A float placed the way New Floating Pane places one.
    private func newFloat() -> (PTYSession, iTermFloatingPaneView) {
        let session = fixture.addFloat(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        guard let pane = tab.floatingPane(for: session) else {
            it_fatalError("No pane")
        }
        FloatingPaneLayout.placeNew(pane, session: session)
        return (session, pane)
    }

    private func metrics(_ session: PTYSession) -> FloatingPaneMetrics {
        guard let metrics = FloatingPaneLayout.metrics(for: session) else {
            it_fatalError("No metrics")
        }
        return metrics
    }

    private func assertFrameMatchesGrid(_ session: PTYSession,
                                        _ pane: iTermFloatingPaneView,
                                        file: StaticString = #filePath,
                                        line: UInt = #line) {
        let grid = FloatingPaneGrid(columns: Int(session.columns), rows: Int(session.rows))
        XCTAssertEqual(pane.outlineFrame.size, metrics(session).frameSize(for: grid),
                       "the frame follows from the grid", file: file, line: line)
        XCTAssertTrue(container.bounds.contains(pane.outlineFrame), "the float is inside the tab", file: file, line: line)
    }

    func testNewFloatIsCenteredAndAbout80Percent() {
        let (session, pane) = newFloat()
        assertFrameMatchesGrid(session, pane)
        let bounds = container.bounds
        XCTAssertEqual(pane.outlineFrame.midX, bounds.midX, accuracy: 1)
        XCTAssertEqual(pane.outlineFrame.midY, bounds.midY, accuracy: 1)
        let m = metrics(session)
        XCTAssertLessThanOrEqual(pane.outlineFrame.width, bounds.width * 0.8)
        XCTAssertGreaterThan(pane.outlineFrame.width, bounds.width * 0.8 - m.cellSize.width)
        XCTAssertLessThanOrEqual(pane.outlineFrame.height, bounds.height * 0.8)
        XCTAssertGreaterThan(pane.outlineFrame.height, bounds.height * 0.8 - m.cellSize.height)
    }

    func testNewFloatHasATitleBar() {
        let (session, _) = newFloat()
        XCTAssertTrue(session.view?.showTitle() ?? false)
    }

    func testKeyboardResizeChangesTheGridByOneCell() {
        let (session, pane) = newFloat()
        let columns = session.columns
        let rows = session.rows
        FloatingPaneLayout.resize(pane, session: session, columns: -1, rows: 1)
        XCTAssertEqual(session.columns, columns - 1)
        XCTAssertEqual(session.rows, rows + 1)
        assertFrameMatchesGrid(session, pane)
    }

    func testKeyboardMoveMovesByWholeCellsAndStaysInside() {
        let (session, pane) = newFloat()
        let start = pane.outlineFrame
        let m = metrics(session)
        FloatingPaneLayout.move(pane, session: session, columns: 2, rows: 0)
        XCTAssertEqual(pane.outlineFrame.minX, start.minX + 2 * m.cellSize.width)
        XCTAssertEqual(pane.outlineFrame.size, start.size, "moving does not change the grid")

        FloatingPaneLayout.move(pane, session: session, columns: 10_000, rows: 10_000)
        XCTAssertTrue(container.bounds.contains(pane.outlineFrame))
        XCTAssertEqual(pane.outlineFrame.maxX, container.bounds.maxX)
    }

    func testShrinkingTheWindowKeepsTheFloatInsideAndRemembersItsGrid() {
        let (session, pane) = newFloat()
        let originalGrid = FloatingPaneGrid(columns: Int(session.columns), rows: Int(session.rows))

        var frame = fixture.window.frame
        frame.size = NSSize(width: 500, height: 400)
        fixture.window.setFrame(frame, display: true)
        assertFrameMatchesGrid(session, pane)
        XCTAssertLessThan(Int(session.columns), originalGrid.columns, "the float had to shrink")
        XCTAssertEqual(pane.desiredGrid, originalGrid)

        frame.size = NSSize(width: 900, height: 650)
        fixture.window.setFrame(frame, display: true)
        XCTAssertEqual(FloatingPaneGrid(columns: Int(session.columns), rows: Int(session.rows)), originalGrid,
                       "the float grows back when there is room")
        XCTAssertNil(pane.desiredGrid)
        assertFrameMatchesGrid(session, pane)
    }

    func testAFloatAtTheRightEdgeStaysThereWhenTheWindowGrows() {
        let (session, pane) = newFloat()
        FloatingPaneLayout.move(pane, session: session, columns: 10_000, rows: 0)
        XCTAssertEqual(pane.outlineFrame.maxX, container.bounds.maxX)

        var frame = fixture.window.frame
        frame.size.width += 150
        fixture.window.setFrame(frame, display: true)
        XCTAssertEqual(pane.outlineFrame.maxX, container.bounds.maxX)
    }

    func testWindowResizeDoesNotChangeAFittingFloatsGrid() {
        let (session, pane) = newFloat()
        let columns = session.columns
        let rows = session.rows
        let visualTop = container.bounds.height - pane.outlineFrame.maxY

        var frame = fixture.window.frame
        frame.size.width += 100
        frame.size.height += 80
        fixture.window.setFrame(frame, display: true)
        XCTAssertEqual(session.columns, columns)
        XCTAssertEqual(session.rows, rows)
        XCTAssertEqual(container.bounds.height - pane.outlineFrame.maxY, visualTop, accuracy: 0.5,
                       "the float keeps its distance from the top of the tab")
    }

    // MARK: - API

    func testOldPythonLibrariesAreNotToldAboutFloats() {
        XCTAssertFalse(iTermAPIHelper.libraryVersionUnderstandsFloatingPanes("python 2.25"))
        XCTAssertFalse(iTermAPIHelper.libraryVersionUnderstandsFloatingPanes("python 2.9"))
        XCTAssertTrue(iTermAPIHelper.libraryVersionUnderstandsFloatingPanes("python 2.26"))
        XCTAssertTrue(iTermAPIHelper.libraryVersionUnderstandsFloatingPanes("python 3.0"))
        XCTAssertTrue(iTermAPIHelper.libraryVersionUnderstandsFloatingPanes(""))
        XCTAssertTrue(iTermAPIHelper.libraryVersionUnderstandsFloatingPanes("swift 1.0"))
    }
}
