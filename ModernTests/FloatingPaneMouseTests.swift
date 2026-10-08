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

    override func setUpWithError() throws {
        try super.setUpWithError()
        try OnscreenTestGate.skipUnlessEnabled()
        fixture = TerminalWindowTestFixture()
        var frame = fixture.window.frame
        frame.size = NSSize(width: 900, height: 650)
        fixture.window.setFrame(frame, display: true)
    }

    override func tearDown() {
        if fixture?.terminal.layoutLocked == true {
            fixture.terminal.perform(NSSelectorFromString("toggleLayoutLocked:"), with: nil)
        }
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

    func testCommandOptionShiftDragInTheTextMovesTheFloat() {
        let (session, pane) = addFloat()
        guard let textview = session.textview else {
            XCTFail("No text view")
            return
        }
        let start = pane.outlineFrame
        let startGrid = grid(session)
        let point = textview.convert(NSPoint(x: 30, y: 30), to: nil)
        let modifiers: NSEvent.ModifierFlags = [.command, .option, .shift]

        fixture.mouse.drag(from: point, to: NSPoint(x: point.x + 40, y: point.y - 20), steps: 3, modifiers: modifiers)

        XCTAssertFalse(pane.isDragging)
        XCTAssertEqual(pane.outlineFrame.origin.x, start.origin.x + 40)
        XCTAssertEqual(pane.outlineFrame.origin.y, start.origin.y - 20)
        XCTAssertEqual(grid(session), startGrid)
        XCTAssertFalse(textview.selection.hasSelection, "the drag did not select text")
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

    /// Shrinking a float from its top-left corner when the tab gets its split view's resizes. Setting
    /// the frame used to make the tab refit the float to its old grid at its old top left, so the
    /// corner didn't follow the mouse.
    func testDraggingTheTopLeftCornerOfAShrunkFloatShrinksIt() {
        let session = fixture.addFloat(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        guard let pane = tab.floatingPane(for: session) else {
            XCTFail("No pane")
            return
        }
        let m = metrics(session)
        // Clear of the window's own resize area at its corner, and not touching any of the tab's
        // edges, as after full screen left it a fraction of a point off.
        let maximum = FloatingPaneGeometry.maximumGrid(container: container.bounds.size, metrics: m)
        let full = FloatingPaneGrid(columns: maximum.columns - 6, rows: maximum.rows - 6)
        let size = m.frameSize(for: full)
        let origin = CGPoint(x: container.bounds.width - size.width - 20.5,
                             y: container.bounds.height - size.height - 20.5)
        FloatingPaneLayout.apply(FloatingPanePlacement(frame: CGRect(origin: origin, size: size), grid: full),
                                 to: pane,
                                 session: session)
        XCTAssertEqual(grid(session), full)
        // As in a window seen after leaving full screen: the float remembers a larger grid it wants
        // back, and the tab handles its split view's resizes as it does the tiled ones.
        pane.desiredGrid = maximum
        pane.splitView.delegate = tab
        let start = pane.outlineFrame
        let band = iTermFloatingPaneView.resizeBandWidth
        // The top-left corner in window coordinates (window y is up).
        let point = pane.convert(NSPoint(x: band / 2, y: pane.isFlipped ? band / 2 : pane.bounds.maxY - band / 2),
                                 to: nil)
        let cell = m.cellSize
        let end = NSPoint(x: point.x + cell.width * 3, y: point.y - cell.height * 2)
        fixture.mouse.drag(from: point, to: end, steps: 4)

        XCTAssertEqual(grid(session), FloatingPaneGrid(columns: full.columns - 3, rows: full.rows - 2))
        XCTAssertEqual(pane.outlineFrame.size, m.frameSize(for: grid(session)), "the frame follows the grid")
        XCTAssertEqual(pane.outlineFrame.maxX, start.maxX, "the right edge stays put")
        // In the unflipped container, the visual bottom is minY.
        XCTAssertEqual(pane.outlineFrame.minY, start.minY, "the bottom edge stays put")
    }

    /// Applying a placement gives the float exactly that frame and grid, even when the tab gets its
    /// split view's resizes and the float remembers a larger grid. The resize used to refit the float
    /// to its old grid partway through.
    func testApplyingAPlacementIsNotUndoneByTheSplitViewResize() {
        let (session, pane) = addFloat(columns: 40, rows: 12, at: NSPoint(x: 60, y: 60))
        let m = metrics(session)
        pane.desiredGrid = FloatingPaneGeometry.maximumGrid(container: container.bounds.size, metrics: m)
        pane.splitView.delegate = tab
        let grid = FloatingPaneGrid(columns: 30, rows: 9)
        let frame = CGRect(origin: CGPoint(x: 130.5, y: 111.5), size: m.frameSize(for: grid))
        FloatingPaneLayout.apply(FloatingPanePlacement(frame: frame, grid: grid), to: pane, session: session)
        XCTAssertEqual(self.grid(session), grid)
        XCTAssertEqual(FloatingPaneLayout.visualOutlineFrame(of: pane), frame)
    }

    func testCornersHaveDiagonalCursors() {
        for corner: FloatingPaneEdges in [[.top, .left], [.top, .right], [.bottom, .left], [.bottom, .right]] {
            XCTAssertNotEqual(iTermFloatingPaneView.cursor(for: corner), NSCursor.crosshair)
        }
        XCTAssertNotEqual(iTermFloatingPaneView.cursor(for: [.top, .left]),
                          iTermFloatingPaneView.cursor(for: [.top, .right]))
    }

    /// The corner's target reaches along both edges, well past the band's width.
    func testTheCornerTargetReachesAlongTheEdges() {
        let (_, pane) = addFloat()
        let band = iTermFloatingPaneView.resizeBandWidth
        let reach = iTermFloatingPaneView.cornerLength - 1
        let lowY: FloatingPaneEdges = pane.isFlipped ? .top : .bottom
        XCTAssertEqual(pane.edges(at: NSPoint(x: reach, y: band / 2)), [.left, lowY])
        XCTAssertEqual(pane.edges(at: NSPoint(x: band / 2, y: reach)), [.left, lowY])
        XCTAssertEqual(pane.edges(at: NSPoint(x: iTermFloatingPaneView.cornerLength + 1, y: band / 2)), [lowY],
                       "past the corner it is just the edge")
    }

    /// The outline marks the active float only when the profile asks for a border around the
    /// active pane, in that border's color.
    func testTheOutlineMarksTheActiveFloatOnlyWithAnActivePaneBorder() {
        let (session, pane) = addFloat()
        tab.setActiveSession(session)
        XCTAssertTrue(pane.isActive)
        XCTAssertNil(pane.activeOutlineColor)

        // The profile may have separate light and dark mode colors; set both.
        func border(_ on: Bool) -> [String: Any] {
            var values = [String: Any]()
            for suffix in ["", COLORS_LIGHT_MODE_SUFFIX, COLORS_DARK_MODE_SUFFIX] {
                values[KEY_USE_ACTIVE_PANE_BORDER + suffix] = on
                values[KEY_ACTIVE_PANE_BORDER_COLOR + suffix] = NSColor.systemRed.dictionaryValue
            }
            return values
        }
        session.setSessionSpecificProfileValues(border(true))
        XCTAssertNotNil(pane.activeOutlineColor)
        session.setSessionSpecificProfileValues(border(false))
        XCTAssertNil(pane.activeOutlineColor)
    }

    /// A float flush with the tab's right edge has its band there just inside the outline, since
    /// the usual band would be outside the window.
    func testAFloatFlushWithTheTabsEdgeCanBeResizedFromThatEdge() {
        let (session, pane) = addFloat()
        let m = metrics(session)
        let size = m.frameSize(for: grid(session))
        let visual = CGRect(x: container.bounds.width - size.width, y: 60, width: size.width, height: size.height)
        FloatingPaneLayout.apply(FloatingPanePlacement(frame: visual, grid: grid(session)), to: pane, session: session)
        let start = pane.outlineFrame
        XCTAssertEqual(start.maxX, container.bounds.maxX, "test setup: flush with the right edge")

        let band = iTermFloatingPaneView.resizeBandWidth
        // Past the window's own resize area, which is just inside its edge.
        let inside = NSPoint(x: pane.bounds.maxX - band - iTermFloatingPaneView.flushBandInset - band / 2,
                             y: pane.bounds.midY)
        XCTAssertEqual(pane.edges(at: inside), .right)
        let point = pane.convert(inside, to: nil)
        let cell = m.cellSize
        fixture.mouse.drag(from: point, to: NSPoint(x: point.x - cell.width * 3, y: point.y), steps: 3)
        XCTAssertEqual(grid(session).columns, 27, "the right edge moved in")
        XCTAssertEqual(pane.outlineFrame.minX, start.minX, "the left edge stays put")

        XCTAssertTrue(pane.edges(at: inside).isEmpty,
                      "once it isn't flush, the band is outside the outline again")
    }

    /// A float whose program ends during a resize can't close then, as the drag would lose its
    /// view. It closes when the drag ends.
    func testAFloatWhoseProgramEndsDuringADragClosesWhenTheDragEnds() {
        let (session, pane) = addFloat()
        session.endAction = .close
        // A session that ends right after it starts gets a warning about its command.
        session.setValue(Date.distantPast, forKey: "creationDate")
        let point = rightBandPoint(pane)
        fixture.mouse.down(at: point)
        fixture.mouse.dragged(to: NSPoint(x: point.x + 20, y: point.y))
        XCTAssertTrue(pane.isDragging)

        session.perform(NSSelectorFromString("brokenPipe"))
        XCTAssertTrue(tab.floatingSessions()?.contains(session) ?? false, "not during the drag")

        fixture.mouse.up(at: NSPoint(x: point.x + 20, y: point.y))
        let closed = expectation(description: "closed")
        DispatchQueue.main.async {
            closed.fulfill()
        }
        wait(for: [closed], timeout: 5)
        XCTAssertFalse(tab.floatingSessions()?.contains(session) ?? true, "after the drag")
    }

    /// The band inside the outline on a flush edge stays out of the title bar, which is the grab
    /// handle. A float flush with the top of the tab moves when dragged by the middle of its title
    /// bar.
    func testAFloatFlushWithTheTopMovesByItsTitleBar() {
        let (session, pane) = addFloat()
        let m = metrics(session)
        let size = m.frameSize(for: grid(session))
        FloatingPaneLayout.apply(FloatingPanePlacement(frame: CGRect(x: 100, y: 0, width: size.width, height: size.height),
                                                       grid: grid(session)),
                                 to: pane,
                                 session: session)
        XCTAssertEqual(pane.outlineFrame.maxY, container.bounds.maxY, "test setup: flush with the top")
        let startGrid = grid(session)
        let start = pane.outlineFrame
        let title = titleBarPoint(session)
        XCTAssertTrue(pane.edges(at: pane.convert(title, from: nil)).isEmpty)
        fixture.mouse.drag(from: title, to: NSPoint(x: title.x + 50, y: title.y - 40), steps: 3)
        XCTAssertEqual(grid(session), startGrid, "moved, not resized")
        XCTAssertEqual(pane.outlineFrame.size, start.size)
        XCTAssertNotEqual(pane.outlineFrame.origin, start.origin)
    }

    /// The top couple of points of the title bar of a float flush with the top resize its top edge.
    func testTheTopOfTheTitleBarResizesAFloatFlushWithTheTop() {
        let (session, pane) = addFloat()
        let m = metrics(session)
        let size = m.frameSize(for: grid(session))
        FloatingPaneLayout.apply(FloatingPanePlacement(frame: CGRect(x: 100, y: 0, width: size.width, height: size.height),
                                                       grid: grid(session)),
                                 to: pane,
                                 session: session)
        let start = pane.outlineFrame
        let startGrid = grid(session)
        let band = iTermFloatingPaneView.resizeBandWidth
        // One point inside the outline's top, in the middle of its width.
        let top = NSPoint(x: pane.bounds.midX, y: pane.isFlipped ? band + 1 : pane.bounds.maxY - band - 1)
        XCTAssertEqual(pane.edges(at: top), pane.isFlipped ? .bottom : .top)
        let point = pane.convert(top, to: nil)
        fixture.mouse.drag(from: point, to: NSPoint(x: point.x, y: point.y - m.cellSize.height * 2), steps: 3)
        XCTAssertEqual(grid(session).rows, startGrid.rows - 2, "the top edge moved down")
        XCTAssertEqual(pane.outlineFrame.minY, start.minY, "the bottom edge stays put")
    }

    func testDoubleClickingAMaximizedFloatsTitleBarRestoresIt() {
        let (session, pane) = addFloat()
        tab.setActiveSession(session)
        fixture.terminal.toggleMaximizeActivePane()
        XCTAssertTrue(pane.isMaximized)
        fixture.mouse.doubleClick(at: titleBarPoint(session))
        XCTAssertFalse(pane.isMaximized)
    }

    /// On a float flush with the left edge, the band inside the outline stops at the title bar, so
    /// its close button isn't under a resize cursor.
    func testTheTitleBarOfAFloatFlushWithTheLeftIsNotPartOfTheBand() {
        let (session, pane) = addFloat(at: NSPoint(x: 0, y: 60))
        guard let title = session.view?.title else {
            XCTFail("No title bar")
            return
        }
        XCTAssertEqual(pane.outlineFrame.minX, container.bounds.minX, "test setup: flush with the left")
        let band = iTermFloatingPaneView.resizeBandWidth
        let x = band + iTermFloatingPaneView.flushBandInset + band / 2
        let inTitle = NSPoint(x: x, y: pane.convert(NSPoint(x: 0, y: title.bounds.midY), from: title).y)
        XCTAssertTrue(pane.edges(at: inTitle).isEmpty)
        XCTAssertEqual(pane.edges(at: NSPoint(x: x, y: pane.bounds.midY)), .left, "below the title bar it is band")
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

    /// A float that can't move must not start a pane drag instead, which would offer to dock it.
    /// tmux 3.7's floats take this path; so does Lock Layout.
    func testAFloatThatCannotMoveDoesNotStartAPaneDrag() {
        let (_, pane) = addFloat()
        XCTAssertTrue(pane.allowsPaneDrag)
        fixture.terminal.perform(NSSelectorFromString("toggleLayoutLocked:"), with: nil)
        XCTAssertFalse(pane.allowsPaneDrag)
    }

    /// Lock Pane keeps a float from being moved, resized or docked, as Lock Layout does.
    func testALockedFloatCannotBeMovedResizedOrDocked() {
        let (session, pane) = addFloat()
        session.locked = true
        let frame = pane.outlineFrame
        let startGrid = grid(session)

        let title = titleBarPoint(session)
        fixture.mouse.drag(from: title, to: NSPoint(x: title.x + 100, y: title.y - 60), steps: 3)
        XCTAssertEqual(pane.outlineFrame, frame, "not moved")
        let edge = rightBandPoint(pane)
        fixture.mouse.drag(from: edge, to: NSPoint(x: edge.x + 100, y: edge.y), steps: 3)
        XCTAssertEqual(grid(session), startGrid, "not resized")
        XCTAssertFalse(fixture.terminal.canDockFloating(session))
        XCTAssertFalse(pane.allowsPaneDrag)
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
