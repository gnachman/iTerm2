//
//  PTYSessionTheoreticalGridSizeTests.swift
//  ModernTests
//
//  -[PTYSession theoreticalGridSize] answers CSI 19 t (and DECST8C's width):
//  the grid the session would have if its window filled the screen. It adds
//  the room left on the screen, divided by the cell size, to the current
//  grid. A session with no font metrics has a zero cell size, which made the
//  quotient NaN (0/0) or infinite, and converting that to int is undefined
//  in C (0 on arm64, INT_MIN on x86_64, a saturated value for infinity). A
//  dimension whose growth is not finite now contributes no growth, so the
//  answer is the current grid size. See
//  docs/swift-migration/integer-findings.md section 4.1.
//

import XCTest
@testable import iTerm2SharedARC

private final class SizedSession: PTYSession {
    var cellSize = NSSize.zero
    var windowFrame = NSRect.zero
    var screenFrame = NSRect.zero

    override func screenCellSize() -> NSSize {
        return cellSize
    }

    override func screenWindowFrame() -> NSRect {
        return windowFrame
    }

    override func screenWindowScreenFrame() -> NSRect {
        return screenFrame
    }
}

final class PTYSessionTheoreticalGridSizeTests: XCTestCase {
    /// Calls -[PTYSession theoreticalGridSize], which is private.
    private func theoreticalGridSize(_ session: PTYSession) -> VT100GridSize {
        let selector = NSSelectorFromString("theoreticalGridSize")
        typealias Fn = @convention(c) (AnyObject, Selector) -> VT100GridSize
        return unsafeBitCast(session.method(for: selector), to: Fn.self)(session, selector)
    }

    private func makeSession(cellSize: NSSize,
                             window: NSSize,
                             screen: NSSize) -> SizedSession {
        let session = SizedSession(synthetic: false)!
        session.cellSize = cellSize
        session.windowFrame = NSRect(origin: NSPoint(x: 10, y: 20), size: window)
        session.screenFrame = NSRect(origin: .zero, size: screen)
        return session
    }

    private func currentGridSize(_ session: PTYSession) -> VT100GridSize {
        return VT100GridSize(width: session.screen.width(), height: session.screen.height())
    }

    private func assertSize(_ actual: VT100GridSize,
                            width: Int32,
                            height: Int32,
                            file: StaticString = #filePath,
                            line: UInt = #line) {
        XCTAssertEqual(actual.width, width, "width", file: file, line: line)
        XCTAssertEqual(actual.height, height, "height", file: file, line: line)
    }

    // MARK: - Ordinary cell sizes: unchanged

    func testGrowthIsRoomOverCellSizeAddedToTheGrid() {
        let session = makeSession(cellSize: NSSize(width: 10, height: 20),
                                  window: NSSize(width: 500, height: 400),
                                  screen: NSSize(width: 1000, height: 800))
        let grid = currentGridSize(session)
        assertSize(theoreticalGridSize(session), width: grid.width + 50, height: grid.height + 20)
    }

    func testFractionalGrowthTruncatesTowardZero() {
        let session = makeSession(cellSize: NSSize(width: 10, height: 20),
                                  window: NSSize(width: 500, height: 400),
                                  screen: NSSize(width: 1009, height: 815))
        let grid = currentGridSize(session)
        // 509 / 10 = 50.9 and 415 / 20 = 20.75: the fractions are dropped.
        assertSize(theoreticalGridSize(session), width: grid.width + 50, height: grid.height + 20)
    }

    func testWindowLargerThanTheScreenShrinksTheGrid() {
        let session = makeSession(cellSize: NSSize(width: 10, height: 20),
                                  window: NSSize(width: 600, height: 500),
                                  screen: NSSize(width: 500, height: 400))
        let grid = currentGridSize(session)
        assertSize(theoreticalGridSize(session), width: grid.width - 10, height: grid.height - 5)
    }

    func testInfiniteCellSizeGivesNoGrowth() {
        // room / infinity is 0, a finite quotient: this was already defined.
        let session = makeSession(cellSize: NSSize(width: CGFloat.infinity, height: CGFloat.infinity),
                                  window: NSSize(width: 500, height: 400),
                                  screen: NSSize(width: 1000, height: 800))
        let grid = currentGridSize(session)
        assertSize(theoreticalGridSize(session), width: grid.width, height: grid.height)
    }

    // MARK: - Zero or non-finite cell sizes

    func testZeroCellSizeWithNoRoomGivesTheCurrentGrid() {
        // 0 / 0 is NaN. arm64 converted it to 0, reporting a 0x0 screen.
        let session = makeSession(cellSize: .zero,
                                  window: NSSize(width: 500, height: 400),
                                  screen: NSSize(width: 500, height: 400))
        let grid = currentGridSize(session)
        XCTAssertGreaterThan(grid.width, 0)
        XCTAssertGreaterThan(grid.height, 0)
        assertSize(theoreticalGridSize(session), width: grid.width, height: grid.height)
    }

    func testZeroCellSizeWithRoomGivesTheCurrentGrid() {
        // room / 0 is infinite. arm64 saturated it to INT_MAX.
        let session = makeSession(cellSize: .zero,
                                  window: NSSize(width: 500, height: 400),
                                  screen: NSSize(width: 1000, height: 800))
        let grid = currentGridSize(session)
        assertSize(theoreticalGridSize(session), width: grid.width, height: grid.height)
    }

    func testZeroCellSizeWithNegativeRoomGivesTheCurrentGrid() {
        // -room / 0 is negative infinity. arm64 saturated it to INT_MIN.
        let session = makeSession(cellSize: .zero,
                                  window: NSSize(width: 600, height: 500),
                                  screen: NSSize(width: 500, height: 400))
        let grid = currentGridSize(session)
        assertSize(theoreticalGridSize(session), width: grid.width, height: grid.height)
    }

    func testNaNCellSizeGivesTheCurrentGrid() {
        let session = makeSession(cellSize: NSSize(width: CGFloat.nan, height: CGFloat.nan),
                                  window: NSSize(width: 500, height: 400),
                                  screen: NSSize(width: 1000, height: 800))
        let grid = currentGridSize(session)
        assertSize(theoreticalGridSize(session), width: grid.width, height: grid.height)
    }

    func testOnlyTheZeroDimensionLosesItsGrowth() {
        let session = makeSession(cellSize: NSSize(width: 10, height: 0),
                                  window: NSSize(width: 500, height: 400),
                                  screen: NSSize(width: 1000, height: 800))
        let grid = currentGridSize(session)
        assertSize(theoreticalGridSize(session), width: grid.width + 50, height: grid.height)
    }
}
