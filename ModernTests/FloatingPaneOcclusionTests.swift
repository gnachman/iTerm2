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

    /// Entering a float crosses its outline, which belongs to the float's wrapper. That must not
    /// count as covering the float, or the float would ignore the pointer coming in. The resize band
    /// does count, for the float too, so its content doesn't take the pointer from a resize.
    func testAFloatsOutlineDoesNotCoverItButItsResizeBandDoes() {
        let (tiled, float, _, _) = setUpCoveredPane()
        guard let tiledView = tiled.view, let floatView = float.view, let pane = tab.floatingPane(for: float) else {
            XCTFail("No views")
            return
        }
        let band = iTermFloatingPaneView.resizeBandWidth
        let onOutline = pane.convert(NSPoint(x: band + iTermFloatingPaneView.outlineWidth / 2, y: pane.bounds.midY), to: nil)
        XCTAssertFalse(isCovered(floatView, at: onOutline))
        let inBand = pane.convert(NSPoint(x: band / 2, y: pane.bounds.midY), to: nil)
        XCTAssertTrue(isCovered(floatView, at: inBand))
        XCTAssertTrue(isCovered(tiledView, at: inBand), "the band is over the tiled pane")
    }

    func testPanesTrackMouseMovementWhileTheTabHasFloats() {
        guard let tiledView = tab.tiledSessions()?.first?.view else {
            XCTFail("No view")
            return
        }
        _ = setUpCoveredPane()
        XCTAssertTrue(tiledView.trackingAreas.first?.options.contains(.mouseMoved) ?? false)
    }

    /// The pointer comes out from under a float without leaving the tiled pane's tracking area, so
    /// only a moved event says it entered the tiled pane.
    func testMovingOutFromUnderAFloatEntersTheTiledPane() {
        let (tiled, _, covered, uncovered) = setUpCoveredPane()
        guard let tiledView = tiled.view else {
            XCTFail("No view")
            return
        }
        func moved(to point: NSPoint) {
            guard let event = NSEvent.mouseEvent(with: .mouseMoved,
                                                 location: point,
                                                 modifierFlags: [],
                                                 timestamp: 0,
                                                 windowNumber: fixture.window.windowNumber,
                                                 context: nil,
                                                 eventNumber: 0,
                                                 clickCount: 0,
                                                 pressure: 0) else {
                it_fatalError("No event")
            }
            tiledView.mouseMoved(with: event)
        }
        let entered = { (tiledView.value(forKey: "_pointerIsOverUncoveredPart") as? Bool) ?? false }
        moved(to: covered)
        XCTAssertFalse(entered(), "under the float")
        moved(to: uncovered)
        XCTAssertTrue(entered(), "out from under it")
    }

    /// QA finding F-051: with Swap With Session picking a target, a tiled pane under a float is not
    /// highlighted while the pointer is over the float; only the float is.
    func testSwapPickerHighlightsOnlyTheFloatWhereItCoversATiledPane() {
        guard let first = tab.tiledSessions()?.first, let controller = MovePaneController.sharedInstance() else {
            XCTFail("No tiled session")
            return
        }
        let second = fixture.split(first, vertically: true)
        let float = fixture.addFloat(frame: NSRect(x: 200, y: 150, width: 400, height: 300))
        guard let pane = tab.floatingPane(for: float), let secondView = second.view, let floatView = float.view else {
            XCTFail("No views")
            return
        }
        let overSecond = pane.convert(NSPoint(x: pane.bounds.maxX - 40, y: pane.bounds.midY), to: nil)
        XCTAssertTrue(secondView.bounds.contains(secondView.convert(overSecond, from: nil)),
                      "test setup: the point is over the float where it covers the second tiled pane")
        let uncovered = secondView.convert(NSPoint(x: secondView.bounds.maxX - 20, y: 20), to: nil)

        controller.swapPane(first)
        defer {
            controller.exitMovePaneMode()
        }
        let tiledPicker = picker(secondView)
        let floatPicker = picker(floatView)
        move(tiledPicker, to: uncovered)
        XCTAssertEqual(tiledPicker.half(), .fullPane, "test setup: the tiled pane starts highlighted")
        move(floatPicker, to: overSecond)
        move(tiledPicker, to: overSecond)
        XCTAssertEqual(floatPicker.half(), .fullPane, "the float is the target")
        XCTAssertEqual(tiledPicker.half(), .noHalf, "the pane under the float is not")

        move(tiledPicker, to: uncovered)
        XCTAssertEqual(tiledPicker.half(), .fullPane, "the tiled pane is a target where nothing covers it")
    }

    /// Only a float hides a pane from the picker. Another view over the pane leaves it a target.
    func testSwapPickerIgnoresViewsOtherThanFloats() {
        guard let first = tab.tiledSessions()?.first, let controller = MovePaneController.sharedInstance() else {
            XCTFail("No tiled session")
            return
        }
        let second = fixture.split(first, vertically: true)
        guard let secondView = second.view else {
            XCTFail("No view")
            return
        }
        controller.swapPane(first)
        defer {
            controller.exitMovePaneMode()
        }
        let point = secondView.convert(NSPoint(x: 50, y: 50), to: nil)
        guard let contentView = fixture.window.contentView else {
            XCTFail("No content view")
            return
        }
        let center = contentView.convert(point, from: nil)
        let cover = NSView(frame: NSRect(x: center.x - 20, y: center.y - 20, width: 40, height: 40))
        contentView.addSubview(cover, positioned: .above, relativeTo: nil)
        defer {
            cover.removeFromSuperview()
        }
        guard contentView.hitTest(contentView.superview?.convert(point, from: nil) ?? point) === cover else {
            XCTFail("test setup: the view covers the picker")
            return
        }
        let tiledPicker = picker(secondView)
        move(tiledPicker, to: point)
        XCTAssertEqual(tiledPicker.half(), .fullPane)
    }

    private func picker(_ view: SessionView) -> SplitSelectionView {
        guard let picker = view.subviews.compactMap({ $0 as? SplitSelectionView }).first else {
            it_fatalError("No picker")
        }
        return picker
    }

    private func move(_ picker: SplitSelectionView, to point: NSPoint) {
        guard let event = NSEvent.mouseEvent(with: .mouseMoved,
                                             location: point,
                                             modifierFlags: [],
                                             timestamp: 0,
                                             windowNumber: fixture.window.windowNumber,
                                             context: nil,
                                             eventNumber: 0,
                                             clickCount: 0,
                                             pressure: 0) else {
            it_fatalError("No event")
        }
        picker.mouseMoved(with: event)
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
