//
//  TmuxFloatingPanePlacementTests.swift
//  ModernTests
//
//  Where a tmux float's first cell goes: over the same cell of the tiled pane that contains it, else
//  extended from the nearest tiled pane, else (only floats) a plain grid.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxFloatingPanePlacementTests: XCTestCase {
    private let cell = CGSize(width: 7, height: 17)

    /// Two side-by-side 40x20 panes. The right one starts at column 41 (column 40 is tmux's
    /// divider) but is drawn only one point after the left one ends.
    private var anchors: [TmuxFloatAnchor] {
        return [TmuxFloatAnchor(column: 0, row: 0, columns: 40, rows: 20,
                                origin: CGPoint(x: 5, y: 26), cellSize: cell),
                TmuxFloatAnchor(column: 41, row: 0, columns: 39, rows: 20,
                                origin: CGPoint(x: 296, y: 26), cellSize: cell)]
    }

    private func point(_ column: Int, _ row: Int, anchors: [TmuxFloatAnchor]) -> CGPoint {
        return TmuxFloatingPanePlacement.point(column: column,
                                               row: row,
                                               anchors: anchors,
                                               fallbackOrigin: CGPoint(x: 5, y: 2),
                                               fallbackCellSize: cell)
    }

    func testACellInATiledPaneMapsOntoThatPane() {
        XCTAssertEqual(point(4, 2, anchors: anchors), CGPoint(x: 5 + 4 * 7, y: 26 + 2 * 17))
        XCTAssertEqual(point(45, 3, anchors: anchors), CGPoint(x: 296 + 4 * 7, y: 26 + 3 * 17),
                       "anchored to the right pane, not counted across the divider")
    }

    func testADividerCellUsesTheNearestPane() {
        // Column 40 is the divider. Both panes are one cell away; the first found wins.
        XCTAssertEqual(point(40, 0, anchors: anchors), CGPoint(x: 5 + 40 * 7, y: 26))
    }

    func testANegativeOffsetExtendsTheNearestPane() {
        XCTAssertEqual(point(-2, -1, anchors: anchors), CGPoint(x: 5 - 2 * 7, y: 26 - 17))
    }

    func testWithOnlyFloatsAPlainGridIsUsed() {
        XCTAssertEqual(point(3, 2, anchors: []), CGPoint(x: 5 + 3 * 7, y: 2 + 2 * 17))
    }
}
