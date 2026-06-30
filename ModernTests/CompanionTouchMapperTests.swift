//
//  CompanionTouchMapperTests.swift
//  iTerm2 ModernTests
//
//  The touch->cell transform must invert the live view's aspect-fit letterboxing
//  exactly, so a tap lands on the cell the user sees.
//

import XCTest
import CoreGraphics
@testable import iTerm2SharedARC

final class CompanionTouchMapperTests: XCTestCase {
    // 80x25 grid, 10x20 px cells, no margins => 800x500 image.
    private func mapper(liveTop: Int64 = 0) -> CompanionTouchMapper {
        CompanionTouchMapper(imageSize: CGSize(width: 800, height: 500),
                             cellGeometry: CompanionCellGeometry(cellWidth: 10, cellHeight: 20,
                                                                 leftMargin: 0, topMargin: 0),
                             columns: 80, rows: 25, liveTop: liveTop)
    }

    func testExactFitMapsDirectly() {
        // View == image size: pixel 25,40 -> column 2, row 2.
        let p = mapper().selectionPoint(viewPoint: CGPoint(x: 25, y: 40),
                                        viewSize: CGSize(width: 800, height: 500))
        XCTAssertEqual(p.column, 2)
        XCTAssertEqual(p.absLine, 2)
    }

    func testLiveTopOffsetsAbsoluteLine() {
        let p = mapper(liveTop: 1000).selectionPoint(viewPoint: CGPoint(x: 5, y: 60),
                                                     viewSize: CGSize(width: 800, height: 500))
        XCTAssertEqual(p.column, 0)
        XCTAssertEqual(p.absLine, 1003)  // row 3 + liveTop 1000
    }

    func testHorizontalLetterboxIsUndone() {
        // Image 800x500 (1.6) shown in a 1600x500 view: scale=1, centered with
        // 400px bars on each side. A tap 400px from the left edge is image x=0.
        let p = mapper().selectionPoint(viewPoint: CGPoint(x: 400, y: 0),
                                        viewSize: CGSize(width: 1600, height: 500))
        XCTAssertEqual(p.column, 0)
        XCTAssertEqual(p.absLine, 0)
        // 400 + 255 px from the left -> image x=255 -> column 25.
        let q = mapper().selectionPoint(viewPoint: CGPoint(x: 655, y: 0),
                                        viewSize: CGSize(width: 1600, height: 500))
        XCTAssertEqual(q.column, 25)
    }

    func testScaledViewMapsByRatio() {
        // View is half size (400x250): scale 0.5, no letterbox. Tap at 50,100 ->
        // image 100,200 -> column 10, row 10.
        let p = mapper().selectionPoint(viewPoint: CGPoint(x: 50, y: 100),
                                        viewSize: CGSize(width: 400, height: 250))
        XCTAssertEqual(p.column, 10)
        XCTAssertEqual(p.absLine, 10)
    }

    func testClampsOutOfBounds() {
        let m = mapper()
        let past = m.selectionPoint(viewPoint: CGPoint(x: 100_000, y: 100_000),
                                    viewSize: CGSize(width: 800, height: 500))
        XCTAssertEqual(past.column, 79)
        XCTAssertEqual(past.absLine, 24)
        let before = m.selectionPoint(viewPoint: CGPoint(x: -50, y: -50),
                                      viewSize: CGSize(width: 800, height: 500))
        XCTAssertEqual(before.column, 0)
        XCTAssertEqual(before.absLine, 0)
    }

    func testDegenerateGeometryReturnsOrigin() {
        let m = CompanionTouchMapper(imageSize: .zero,
                                     cellGeometry: CompanionCellGeometry(cellWidth: 0, cellHeight: 0,
                                                                         leftMargin: 0, topMargin: 0),
                                     columns: 0, rows: 0, liveTop: 77)
        let p = m.selectionPoint(viewPoint: CGPoint(x: 10, y: 10),
                                 viewSize: CGSize(width: 100, height: 100))
        XCTAssertEqual(p.column, 0)
        XCTAssertEqual(p.absLine, 77)
    }
}
