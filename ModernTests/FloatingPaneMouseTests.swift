//
//  FloatingPaneMouseTests.swift
//  ModernTests
//
//  Moving, resizing and raising floats with the mouse, driven by synthesized events through a real
//  terminal window.
//

import XCTest
@testable import iTerm2SharedARC

final class FloatingPaneMouseTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!

    override func setUp() {
        super.setUp()
        fixture = TerminalWindowTestFixture()
        var frame = fixture.window.frame
        frame.size = NSSize(width: 900, height: 650)
        fixture.window.setFrame(frame, display: true)
    }

    override func tearDown() {
        if fixture.terminal.layoutLocked {
            fixture.terminal.perform(NSSelectorFromString("toggleLayoutLocked:"), with: nil)
        }
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

    /// A float of a fixed grid at a fixed place, so tests are independent of the window size.
    private func addFloat(columns: Int = 30, rows: Int = 8, at origin: NSPoint = NSPoint(x: 60, y: 60)) -> (PTYSession, iTermFloatingPaneView) {
        let session = fixture.addFloat(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        guard let pane = tab.floatingPane(for: session),
              let metrics = FloatingPaneLayout.metrics(for: session) else {
            it_fatalError("No pane")
        }
        let grid = FloatingPaneGrid(columns: columns, rows: rows)
        let visual = CGRect(origin: origin, size: metrics.frameSize(for: grid))
        FloatingPaneLayout.apply(FloatingPanePlacement(frame: visual, grid: grid), to: pane, session: session)
        return (session, pane)
    }

    private func metrics(_ session: PTYSession) -> FloatingPaneMetrics {
        guard let metrics = FloatingPaneLayout.metrics(for: session) else {
            it_fatalError("No metrics")
        }
        return metrics
    }

    /// A point in the middle of the float's title bar, in window coordinates.
    private func titleBarPoint(_ session: PTYSession) -> NSPoint {
        guard let title = session.view?.title else {
            it_fatalError("No title bar")
        }
        // Left of center, clear of the close and menu buttons.
        return title.convert(NSPoint(x: title.bounds.width * 0.4, y: title.bounds.midY), to: nil)
    }

    /// A point in the middle of the float's right resize band, in window coordinates.
    private func rightBandPoint(_ pane: iTermFloatingPaneView) -> NSPoint {
        let band = iTermFloatingPaneView.resizeBandWidth
        return pane.convert(NSPoint(x: pane.bounds.maxX - band / 2, y: pane.bounds.midY), to: nil)
    }

    private func grid(_ session: PTYSession) -> FloatingPaneGrid {
        return FloatingPaneGrid(columns: Int(session.columns), rows: Int(session.rows))
    }

    // MARK: - Raising

    func testClickingACoveredFloatRaisesIt() {
        let (back, backPane) = addFloat(at: NSPoint(x: 40, y: 40))
        let (_, frontPane) = addFloat(at: NSPoint(x: 120, y: 120))
        XCTAssertTrue(container.subviews.last === frontPane)

        // Click a part of the back float that the front one does not cover.
        guard let textview = back.textview else {
            XCTFail("No text view")
            return
        }
        let point = textview.convert(NSPoint(x: 10, y: 10), to: nil)
        XCTAssertTrue(backPane.convert(backPane.bounds, to: nil).contains(point))
        XCTAssertFalse(frontPane.convert(frontPane.bounds, to: nil).contains(point))
        fixture.mouse.click(at: point)

        XCTAssertTrue(container.subviews.last === backPane, "a click raises the float")
        XCTAssertEqual(tab.floatingPanes.last, backPane)
        XCTAssertTrue(tab.activeSession === back)
    }

    func testClickingATiledPaneDoesNotChangeFloatOrder() {
        let (_, firstPane) = addFloat(at: NSPoint(x: 40, y: 40))
        let (_, secondPane) = addFloat(at: NSPoint(x: 120, y: 120))
        guard let tiled = tab.tiledSessions()?.first, let textview = tiled.textview else {
            XCTFail("No tiled session")
            return
        }
        // The bottom right of the tiled pane is clear of both floats.
        let point = textview.convert(NSPoint(x: textview.visibleRect.maxX - 5, y: textview.visibleRect.maxY - 5), to: nil)
        fixture.mouse.click(at: point)
        XCTAssertEqual(tab.floatingPanes, [firstPane, secondPane])
    }

    // MARK: - Moving

    func testDraggingTheTitleBarMovesTheFloatWithoutResizingIt() {
        let (session, pane) = addFloat()
        let start = pane.outlineFrame
        let startGrid = grid(session)
        let point = titleBarPoint(session)

        fixture.mouse.down(at: point)
        fixture.mouse.dragged(to: NSPoint(x: point.x + 25, y: point.y - 15))
        XCTAssertTrue(pane.isDragging)
        fixture.mouse.dragged(to: NSPoint(x: point.x + 50, y: point.y - 30))
        fixture.mouse.up(at: NSPoint(x: point.x + 50, y: point.y - 30))

        XCTAssertFalse(pane.isDragging)
        XCTAssertEqual(pane.outlineFrame.origin.x, start.origin.x + 50)
        XCTAssertEqual(pane.outlineFrame.origin.y, start.origin.y - 30, "window y is up, like the container's")
        XCTAssertEqual(pane.outlineFrame.size, start.size)
        XCTAssertEqual(grid(session), startGrid, "moving never resizes the PTY")
    }

    func testMoveIsClampedToTheTab() {
        let (session, pane) = addFloat()
        let point = titleBarPoint(session)
        // Keep the pointer inside the tab (leaving it would start a pane drag), but move far enough
        // that the float would cross the tab's top right corner.
        let topRight = container.convert(NSPoint(x: container.bounds.maxX - 2, y: container.bounds.maxY - 2), to: nil)
        fixture.mouse.drag(from: point, to: topRight, steps: 3)
        XCTAssertTrue(container.bounds.contains(pane.outlineFrame))
        XCTAssertEqual(pane.outlineFrame.maxX, container.bounds.maxX)
        XCTAssertEqual(pane.outlineFrame.maxY, container.bounds.maxY)
        XCTAssertFalse(pane.isDragging)
    }

    func testClickingTheTitleBarDoesNotMoveTheFloat() {
        let (session, pane) = addFloat()
        let start = pane.outlineFrame
        fixture.mouse.click(at: titleBarPoint(session))
        XCTAssertEqual(pane.outlineFrame, start)
        XCTAssertFalse(pane.isDragging)
    }

    func testLockLayoutPreventsMoving() {
        let (session, pane) = addFloat()
        fixture.terminal.perform(NSSelectorFromString("toggleLayoutLocked:"), with: nil)
        XCTAssertTrue(fixture.terminal.layoutLocked)
        let start = pane.outlineFrame
        let point = titleBarPoint(session)
        fixture.mouse.drag(from: point, to: NSPoint(x: point.x + 50, y: point.y - 30), steps: 3)
        XCTAssertEqual(pane.outlineFrame, start)
    }

    // MARK: - Resizing

    func testDraggingTheRightEdgeResizesInWholeCells() {
        let (session, pane) = addFloat()
        let start = pane.outlineFrame
        let cell = metrics(session).cellSize
        let point = rightBandPoint(pane)
        let end = NSPoint(x: point.x + cell.width * 3 + cell.width / 2, y: point.y)

        fixture.mouse.down(at: point)
        fixture.mouse.dragged(to: end)
        XCTAssertEqual(pane.sizeReadoutText, "33×8", "a readout shows the grid while resizing")
        fixture.mouse.up(at: end)

        XCTAssertNil(pane.sizeReadoutText)
        XCTAssertEqual(grid(session), FloatingPaneGrid(columns: 33, rows: 8))
        XCTAssertEqual(pane.outlineFrame.minX, start.minX, "the left edge stays put")
        XCTAssertEqual(pane.outlineFrame.size, metrics(session).frameSize(for: grid(session)))
    }

    func testDraggingTheBottomLeftCornerResizesBothWays() {
        let (session, pane) = addFloat(at: NSPoint(x: 200, y: 60))
        let start = pane.outlineFrame
        let cell = metrics(session).cellSize
        let band = iTermFloatingPaneView.resizeBandWidth
        // The bottom-left corner in window coordinates (window y is up).
        let point = pane.convert(NSPoint(x: band / 2, y: pane.isFlipped ? pane.bounds.maxY - band / 2 : band / 2),
                                 to: nil)
        let end = NSPoint(x: point.x - cell.width * 2, y: point.y - cell.height * 2)
        fixture.mouse.drag(from: point, to: end, steps: 4)

        XCTAssertEqual(grid(session), FloatingPaneGrid(columns: 32, rows: 10))
        XCTAssertEqual(pane.outlineFrame.maxX, start.maxX, "the right edge stays put")
        // In the unflipped container, the visual top is maxY.
        XCTAssertEqual(pane.outlineFrame.maxY, start.maxY, "the top edge stays put")
    }

    func testResizeStopsAtTheMinimumGrid() {
        let (session, pane) = addFloat()
        let point = rightBandPoint(pane)
        fixture.mouse.drag(from: point, to: NSPoint(x: point.x - 5000, y: point.y), steps: 3)
        XCTAssertEqual(grid(session).columns, FloatingPaneGrid.minimum.columns)
    }

    func testLockLayoutPreventsResizing() {
        let (session, pane) = addFloat()
        fixture.terminal.perform(NSSelectorFromString("toggleLayoutLocked:"), with: nil)
        let startGrid = grid(session)
        let point = rightBandPoint(pane)
        fixture.mouse.drag(from: point, to: NSPoint(x: point.x + 200, y: point.y), steps: 3)
        XCTAssertEqual(grid(session), startGrid)
    }

    func testBandIsOnlyOutsideTheOutline() {
        let (_, pane) = addFloat()
        let band = iTermFloatingPaneView.resizeBandWidth
        let b = pane.bounds
        XCTAssertEqual(pane.edges(at: NSPoint(x: b.minX + band / 2, y: b.midY)), .left)
        XCTAssertEqual(pane.edges(at: NSPoint(x: b.maxX - band / 2, y: b.midY)), .right)
        XCTAssertEqual(pane.edges(at: NSPoint(x: b.midX, y: b.midY)), [], "the inside is the terminal's")
        XCTAssertEqual(pane.edges(at: NSPoint(x: b.minX + band + 1, y: b.midY)), [], "the outline is not a grab zone")
        XCTAssertEqual(pane.edges(at: NSPoint(x: b.minX + band / 2, y: b.minY + band * 2)),
                       [.left, pane.isFlipped ? .top : .bottom],
                       "near a corner both edges move")
    }
}
