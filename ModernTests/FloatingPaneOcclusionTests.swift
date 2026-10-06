//
//  FloatingPaneOcclusionTests.swift
//  ModernTests
//
//  Tracking areas are not occlusion-aware, so a pane under a float gets entered and moved events
//  while the pointer is over the float. With focus follows mouse that would steal focus from the
//  float. SessionView ignores such events. Focus follows mouse needs a key window, which the test
//  host does not have, so these test the occlusion check itself; tests/floating_panes has a
//  check that drives the real pointer.
//

import XCTest
@testable import iTerm2SharedARC

final class FloatingPaneOcclusionTests: XCTestCase {
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

    /// A tiled session, a float over the middle of the tab, and points inside and outside it.
    private func setUpCoveredPane() -> (tiled: PTYSession, float: PTYSession, covered: NSPoint, uncovered: NSPoint) {
        guard let tiled = tab.tiledSessions()?.first, let container = tab.realRootView else {
            it_fatalError("No tiled session")
        }
        let float = fixture.addFloat(frame: NSRect(x: 200, y: 150, width: 400, height: 300))
        guard let pane = tab.floatingPane(for: float) else {
            it_fatalError("No pane")
        }
        let covered = pane.convert(NSPoint(x: pane.bounds.midX, y: pane.bounds.midY), to: nil)
        let uncovered = container.convert(NSPoint(x: 20, y: 20), to: nil)
        return (tiled, float, covered, uncovered)
    }

    /// Calls -[SessionView locationIsCoveredByAnotherView:].
    private func isCovered(_ view: SessionView, at point: NSPoint) -> Bool {
        let selector = NSSelectorFromString("locationIsCoveredByAnotherView:")
        typealias Fn = @convention(c) (AnyObject, Selector, NSPoint) -> Bool
        return unsafeBitCast(view.method(for: selector), to: Fn.self)(view, selector, point)
    }

    /// Calls -[SessionView sessionViewAtLocationInWindow:].
    private func sessionView(under view: SessionView, at point: NSPoint) -> SessionView? {
        let selector = NSSelectorFromString("sessionViewAtLocationInWindow:")
        typealias Fn = @convention(c) (AnyObject, Selector, NSPoint) -> SessionView?
        return unsafeBitCast(view.method(for: selector), to: Fn.self)(view, selector, point)
    }

    func testAPointUnderAFloatIsCoveredForTheTiledPane() {
        let (tiled, float, covered, uncovered) = setUpCoveredPane()
        guard let tiledView = tiled.view, let floatView = float.view else {
            XCTFail("No views")
            return
        }
        XCTAssertTrue(isCovered(tiledView, at: covered), "the float covers the tiled pane there")
        XCTAssertFalse(isCovered(tiledView, at: uncovered))
        XCTAssertFalse(isCovered(floatView, at: covered), "a float is not covered by itself")
        XCTAssertTrue(sessionView(under: tiledView, at: covered) === floatView)
        XCTAssertTrue(sessionView(under: floatView, at: uncovered) === tiledView,
                      "leaving the float finds the pane beneath it")
    }

    func testHiddenFloatsDoNotCover() {
        let (tiled, _, covered, _) = setUpCoveredPane()
        guard let tiledView = tiled.view else {
            XCTFail("No view")
            return
        }
        tab.floatingPanesHidden = true
        XCTAssertFalse(isCovered(tiledView, at: covered))
    }

    func testNothingIsCoveredWithoutFloats() {
        guard let tiled = tab.tiledSessions()?.first, let view = tiled.view else {
            XCTFail("No session")
            return
        }
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        XCTAssertFalse(isCovered(view, at: point))
    }
}
