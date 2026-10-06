//
//  FloatingPaneWindowOperationTests.swift
//  ModernTests
//
//  Window operations from escape sequences (CSI t and friends) with a float as the session. The
//  pane is the window: size requests and reports describe the float, raise and lower restack the
//  tab's floats, and moving or miniaturizing the window is ignored.
//

import XCTest
@testable import iTerm2SharedARC

final class FloatingPaneWindowOperationTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!
    private let floatFrame = NSRect(x: 60, y: 60, width: 300, height: 200)

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

    /// Calls a private PTYSession method that takes an NSSize.
    private func call(_ name: String, on session: PTYSession, size: NSSize) {
        let selector = NSSelectorFromString(name)
        typealias Fn = @convention(c) (AnyObject, Selector, NSSize) -> Void
        unsafeBitCast(session.method(for: selector), to: Fn.self)(session, selector, size)
    }

    /// Calls -[PTYSession windowFrame], which is private.
    private func reportedWindowFrame(_ session: PTYSession) -> NSRect {
        let selector = NSSelectorFromString("windowFrame")
        typealias Fn = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(session.method(for: selector), to: Fn.self)(session, selector)
    }

    /// Calls -[PTYSession theoreticalGridSize], which is private.
    private func theoreticalGridSize(_ session: PTYSession) -> VT100GridSize {
        let selector = NSSelectorFromString("theoreticalGridSize")
        typealias Fn = @convention(c) (AnyObject, Selector) -> VT100GridSize
        return unsafeBitCast(session.method(for: selector), to: Fn.self)(session, selector)
    }

    func testRaiseAndLowerRestackTheFloats() {
        let back = fixture.addFloat(frame: floatFrame)
        let front = fixture.addFloat(frame: floatFrame.offsetBy(dx: 40, dy: 40))
        let windowFrame = fixture.window.frame

        back.screenRaise(true)
        XCTAssertEqual(tab.floatingSessions(), [front, back])
        back.screenRaise(false)
        XCTAssertEqual(tab.floatingSessions(), [back, front])
        XCTAssertEqual(fixture.window.frame, windowFrame)
    }

    func testMovingAndMiniaturizingTheWindowAreIgnored() {
        let float = fixture.addFloat(frame: floatFrame)
        let windowFrame = fixture.window.frame

        float.screenMoveWindowTopLeftPoint(to: NSPoint(x: 10, y: 10))
        float.screenSetWindowFrame(NSRect(x: 0, y: 0, width: 400, height: 300))
        float.screenMiniaturizeWindow(true)
        XCTAssertEqual(fixture.window.frame, windowFrame)
        XCTAssertFalse(fixture.window.isMiniaturized)
    }

    func testAPointSizeResizesTheFloatInWholeCells() {
        let float = fixture.addFloat(frame: floatFrame)
        guard let metrics = FloatingPaneLayout.metrics(for: float) else {
            XCTFail("No metrics")
            return
        }
        let windowFrame = fixture.window.frame
        let size = NSSize(width: metrics.cellSize.width * 30.4, height: metrics.cellSize.height * 9.6)

        call("setFloatingPanePointSize:", on: float, size: size)
        XCTAssertEqual(float.columns, 30)
        XCTAssertEqual(float.rows, 10)
        XCTAssertEqual(fixture.window.frame, windowFrame)

        // Negative leaves a dimension alone; zero makes it as large as the tab allows.
        call("setFloatingPanePointSize:", on: float, size: NSSize(width: -1, height: 0))
        XCTAssertEqual(float.columns, 30)
        XCTAssertEqual(CGFloat(float.rows), tab.sessionMaximumFloatingGridSize(float).height)
    }

    func testReportsDescribeTheFloat() {
        guard let tiled = tab.tiledSessions()?.first else {
            XCTFail("No tiled session")
            return
        }
        let float = fixture.addFloat(frame: floatFrame)
        guard let view = float.view else {
            XCTFail("No view")
            return
        }
        XCTAssertEqual(reportedWindowFrame(float).size, view.frame.size, "14 t gives the float's size")
        XCTAssertEqual(reportedWindowFrame(tiled).size, fixture.window.frame.size)

        let maximum = tab.sessionMaximumFloatingGridSize(float)
        let theoretical = theoreticalGridSize(float)
        XCTAssertEqual(CGFloat(theoretical.width), maximum.width, "19 t gives the grid that fills the tab")
        XCTAssertEqual(CGFloat(theoretical.height), maximum.height)
        XCTAssertFalse(float.screenWindowIsFullscreen())
    }
}
