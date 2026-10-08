//
//  FloatingPaneDropTests.swift
//  ModernTests
//
//  Dropping a dragged session as a float: into another window's tab, back into its own tab at a
//  new place, or a tiled pane dropped on a float. AppKit's drag session cannot run in the test
//  host, so these call the drop directly, as SessionView does when the drag ends over a pane.
//

import XCTest
@testable import iTerm2SharedARC

final class FloatingPaneDropTests: XCTestCase {
    private var source: TerminalWindowTestFixture!
    private var destination: TerminalWindowTestFixture!
    private let floatFrame = NSRect(x: 60, y: 60, width: 300, height: 200)

    override func setUpWithError() throws {
        try super.setUpWithError()
        try OnscreenTestGate.skipUnlessEnabled()
        source = TerminalWindowTestFixture()
        destination = TerminalWindowTestFixture()
        for fixture in [source!, destination!] {
            var frame = fixture.window.frame
            frame.size = NSSize(width: 900, height: 650)
            fixture.window.setFrame(frame, display: true)
        }
    }

    override func tearDown() {
        MovePaneController.sharedInstance()?.session = nil
        source?.close()
        destination?.close()
        source = nil
        destination = nil
        super.tearDown()
    }

    private func tab(_ fixture: TerminalWindowTestFixture) -> PTYTab {
        guard let tab = fixture.terminal.currentTab() else {
            it_fatalError("No tab")
        }
        return tab
    }

    /// A point in window coordinates at the given visual (top left, y down) point of the tab.
    private func windowPoint(_ fixture: TerminalWindowTestFixture, visual: NSPoint) -> NSPoint {
        guard let container = tab(fixture).realRootView else {
            it_fatalError("No container")
        }
        let y = container.isFlipped ? visual.y : container.bounds.height - visual.y
        return container.convert(NSPoint(x: visual.x, y: y), to: nil)
    }

    private func drop(_ session: PTYSession, in fixture: TerminalWindowTestFixture, visual: NSPoint) -> Bool {
        guard let controller = MovePaneController.sharedInstance() else {
            it_fatalError("No controller")
        }
        controller.session = session
        defer {
            controller.session = nil
        }
        return controller.dropFloatingPane(in: tab(fixture), atWindowPoint: windowPoint(fixture, visual: visual))
    }

    /// The destination's tab bar is shown during a drag and may hide again afterward, which moves
    /// its content. The dropped float is placed again so it stays where it was dropped on screen.
    func testADroppedFloatStaysWhereItWasDroppedWhenTheContentMoves() {
        let float = source.addFloat(frame: floatFrame)
        guard let controller = MovePaneController.sharedInstance() else {
            XCTFail("No controller")
            return
        }
        XCTAssertTrue(drop(float, in: destination, visual: NSPoint(x: 100, y: 120)))
        guard let pane = tab(destination).floatingPane(for: float) else {
            XCTFail("No pane")
            return
        }
        func screenTopLeft() -> NSPoint {
            let frame = pane.convert(pane.bounds, to: nil)
            let band = iTermFloatingPaneView.resizeBandWidth
            return destination.window.convertPoint(toScreen: NSPoint(x: frame.minX + band, y: frame.maxY - band))
        }
        let dropped = screenTopLeft()

        // Move the content on screen, as a tab bar hiding does. The float moves with it.
        destination.window.setFrameOrigin(NSPoint(x: destination.window.frame.minX,
                                                  y: destination.window.frame.minY - 35))
        XCTAssertNotEqual(screenTopLeft().y, dropped.y, accuracy: 1, "test setup: the content moved")

        controller.perform(NSSelectorFromString("placeDroppedFloatingPaneAgain"))
        XCTAssertEqual(screenTopLeft().x, dropped.x, accuracy: 1)
        XCTAssertEqual(screenTopLeft().y, dropped.y, accuracy: 1)
    }

    func testAFloatDroppedInAnotherWindowStaysAFloatWithItsGrid() {
        let float = source.addFloat(frame: floatFrame)
        let grid = (float.columns, float.rows)
        XCTAssertTrue(drop(float, in: destination, visual: NSPoint(x: 100, y: 120)))

        XCTAssertEqual(tab(destination).floatingSessions(), [float])
        XCTAssertTrue(tab(source).floatingSessions()?.isEmpty ?? false)
        XCTAssertEqual(float.columns, grid.0)
        XCTAssertEqual(float.rows, grid.1)
        XCTAssertTrue(tab(destination).activeSession === float)
        guard let pane = tab(destination).floatingPane(for: float) else {
            XCTFail("No pane")
            return
        }
        let visual = FloatingPaneLayout.visualOutlineFrame(of: pane)
        XCTAssertEqual(visual.origin.x, 100 - iTermFloatingPaneView.outlineWidth, accuracy: 1)
        XCTAssertEqual(visual.origin.y, 120 - iTermFloatingPaneView.outlineWidth, accuracy: 1)
    }

    func testAFloatDroppedInItsOwnTabMoves() {
        let float = source.addFloat(frame: floatFrame)
        guard let pane = tab(source).floatingPane(for: float) else {
            XCTFail("No pane")
            return
        }
        XCTAssertTrue(drop(float, in: source, visual: NSPoint(x: 200, y: 50)))
        XCTAssertTrue(tab(source).floatingPane(for: float) === pane, "the same float, moved")
        XCTAssertEqual(FloatingPaneLayout.visualOutlineFrame(of: pane).origin.x,
                       200 - iTermFloatingPaneView.outlineWidth, accuracy: 1)
    }

    func testADropIsClampedAndShrinksOnlyIfTheTabIsTooSmall() {
        let float = source.addFloat(frame: floatFrame)
        var frame = destination.window.frame
        frame.size = NSSize(width: 400, height: 300)
        destination.window.setFrame(frame, display: true)
        XCTAssertTrue(drop(float, in: destination, visual: NSPoint(x: 350, y: 250)))
        guard let pane = tab(destination).floatingPane(for: float),
              let container = tab(destination).realRootView else {
            XCTFail("No pane")
            return
        }
        XCTAssertTrue(container.bounds.contains(pane.outlineFrame), "kept inside the tab")
    }

    func testATiledPaneDroppedOnAnotherTabBecomesAFloat() {
        guard let first = tab(source).tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let second = source.split(first, vertically: true)
        XCTAssertTrue(drop(second, in: destination, visual: NSPoint(x: 40, y: 40)))
        XCTAssertEqual(tab(destination).floatingSessions(), [second])
        XCTAssertEqual(tab(source).sessions(), [first])
    }

    func testATiledPaneIsNotFloatedInItsOwnTab() {
        guard let first = tab(source).tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let second = source.split(first, vertically: true)
        XCTAssertFalse(drop(second, in: source, visual: NSPoint(x: 40, y: 40)))
        XCTAssertEqual(tab(source).tiledSessions(), [first, second])
    }

    func testDropIsRefusedWhenTheDestinationLayoutIsLocked() {
        let float = source.addFloat(frame: floatFrame)
        destination.terminal.perform(NSSelectorFromString("toggleLayoutLocked:"), with: nil)
        defer {
            destination.terminal.perform(NSSelectorFromString("toggleLayoutLocked:"), with: nil)
        }
        XCTAssertFalse(drop(float, in: destination, visual: NSPoint(x: 40, y: 40)))
        XCTAssertEqual(tab(source).floatingSessions(), [float])
    }
}
