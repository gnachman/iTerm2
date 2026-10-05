//
//  GridSizeFromContentSizeTests.swift
//  ModernTests
//
//  Adding a tab to a window sizes the new session from the existing view's size divided by the
//  profile's cell size. A zero cell size (a font that measures as zero) made that infinite, which
//  Int32(clamping:) turned into Int32.max columns, and allocating the grid's lines threw
//  "-[NSConcreteMutableData initWithLength:]: absurd length". A grid size must be finite and
//  positive whatever the inputs.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class GridSizeFromContentSizeTests: XCTestCase {
    func testZeroCellSizeGivesSaneGrid() {
        let size = TerminalWindowSizeHelper.gridSize(forContentSize: NSSize(width: 800, height: 600),
                                                     cellSize: .zero)
        XCTAssertGreaterThanOrEqual(size.width, 1)
        XCTAssertLessThanOrEqual(size.width, 800)
        XCTAssertGreaterThanOrEqual(size.height, 1)
        XCTAssertLessThanOrEqual(size.height, 600)
    }

    func testTinyContentSizeGivesAtLeastOneCell() {
        let size = TerminalWindowSizeHelper.gridSize(forContentSize: .zero,
                                                     cellSize: NSSize(width: 7, height: 14))
        XCTAssertGreaterThanOrEqual(size.width, 1)
        XCTAssertGreaterThanOrEqual(size.height, 1)
    }

    func testNormalSize() {
        let margins = 2.0 * Double(iTermPreferences.sideMargins())
        let vmargins = 2.0 * Double(iTermPreferences.topBottomMargins())
        let size = TerminalWindowSizeHelper.gridSize(forContentSize: NSSize(width: 800 + margins,
                                                                            height: 280 + vmargins),
                                                     cellSize: NSSize(width: 10, height: 14))
        XCTAssertEqual(size.width, 80)
        XCTAssertEqual(size.height, 20)
    }

    // Int32(clamping: CGFloat) compared against Int.max, so values between Int32.max and Int.max
    // reached Int32(value), which traps.
    func testInt32ClampingOfLargeValue() {
        XCTAssertEqual(Int32(clamping: CGFloat(3_000_000_000)), Int32.max)
        XCTAssertEqual(Int32(clamping: CGFloat(-3_000_000_000)), Int32.min)
    }
}
