//
//  PSMTabBarAccessoryClipTests.swift
//  iTerm2XCTests
//
//  Geometry behind clipping a per-cell accessory (the activity indicator, a tab
//  progress bar) to the scrollable region of the tab bar.
//
//  Two rules are under test. First, an accessory that deliberately overhangs its
//  own cell -- the Tahoe progress ring is outset past the pill so it can draw
//  around it -- is allowed to reach that far past the margin, so a fully visible
//  first or last tab keeps its whole ring. Second, a cell that really is partly
//  scrolled under the decorations gets its accessory cut off at the margin
//  rather than hidden outright.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabBarAccessoryClipTests: XCTestCase {
    // Stand-ins for -scrollLeadingMargin and -scrollViewportLength.
    private let leading: CGFloat = 100
    private let trailing: CGFloat = 800

    // The Tahoe ring's outset (progressRingWidth).
    private let ringOutset: CGFloat = 2

    private struct Interval {
        var min: CGFloat
        var max: CGFloat
    }

    /// The visible part of `accessory` for a cell occupying `cell`, or nil if none of it is visible.
    private func visiblePart(accessory: Interval, cell: Interval) -> Interval? {
        var visibleMin: CGFloat = .nan
        var visibleMax: CGFloat = .nan
        guard PSMVisibleAccessoryInterval(accessory.min,
                                          accessory.max,
                                          cell.min,
                                          cell.max,
                                          leading,
                                          trailing,
                                          &visibleMin,
                                          &visibleMax) else {
            return nil
        }
        return Interval(min: visibleMin, max: visibleMax)
    }

    private func ring(around cell: Interval) -> Interval {
        return Interval(min: cell.min - ringOutset, max: cell.max + ringOutset)
    }

    private func assertVisible(_ visible: Interval?,
                               _ expected: Interval,
                               _ message: String,
                               file: StaticString = #filePath,
                               line: UInt = #line) {
        guard let visible else {
            XCTFail("\(message): nothing visible", file: file, line: line)
            return
        }
        XCTAssertEqual(visible.min, expected.min, accuracy: 0.001, message, file: file, line: line)
        XCTAssertEqual(visible.max, expected.max, accuracy: 0.001, message, file: file, line: line)
    }

    // MARK: - An overhanging accessory on a fully visible edge tab

    func testFirstTabRingIsNotClipped() {
        // The leftmost cell starts exactly at the leading margin, so its ring reaches into the margin
        // the style reserved for it. All of it stays.
        let cell = Interval(min: leading, max: leading + 100)
        assertVisible(visiblePart(accessory: ring(around: cell), cell: cell),
                      ring(around: cell),
                      "first tab's ring")
    }

    func testLastTabRingIsNotClipped() {
        let cell = Interval(min: trailing - 100, max: trailing)
        assertVisible(visiblePart(accessory: ring(around: cell), cell: cell),
                      ring(around: cell),
                      "last tab's ring")
    }

    func testInteriorAccessoryIsNotClipped() {
        let cell = Interval(min: 300, max: 400)
        let indicator = Interval(min: 380, max: 396)
        assertVisible(visiblePart(accessory: indicator, cell: cell),
                      indicator,
                      "interior indicator")
    }

    // MARK: - A partly scrolled cell

    func testPartlyScrolledCellKeepsThePartInsideTheRegion() {
        // 60pt of the cell has scrolled under the decorations. The ring survives from the margin to
        // its trailing end rather than vanishing.
        let cell = Interval(min: leading - 60, max: leading + 40)
        assertVisible(visiblePart(accessory: ring(around: cell), cell: cell),
                      Interval(min: leading, max: cell.max + ringOutset),
                      "partly scrolled ring")
    }

    func testAScrolledCellGetsNoOverhangAllowance() {
        // The gutter past the margin is kept for a ring whose tab is fully in view. A cell that has
        // really crossed the margin is cut off at it, exactly where -drawRect: cuts the cell, rather
        // than painting its ring into the band beyond.
        let cell = Interval(min: leading - 2, max: leading + 98)
        assertVisible(visiblePart(accessory: ring(around: cell), cell: cell),
                      Interval(min: leading, max: cell.max + ringOutset),
                      "ring of a cell past the margin")
    }

    func testPartlyScrolledCellClipsAnAccessoryWithNoOverhangAtTheMargin() {
        // An indicator sits inside its cell, so it gets no allowance past the margin.
        let cell = Interval(min: leading - 60, max: leading + 40)
        let indicator = Interval(min: leading - 10, max: leading + 6)
        assertVisible(visiblePart(accessory: indicator, cell: cell),
                      Interval(min: leading, max: indicator.max),
                      "partly scrolled indicator")
    }

    func testCellRunningPastTheTrailingEdgeIsClippedThere() {
        // Same rule at the other end: the cell crosses the trailing edge, so it gets no allowance
        // there. Its leading end is well inside, so nothing is clipped from that side.
        let cell = Interval(min: trailing - 50, max: trailing + 50)
        assertVisible(visiblePart(accessory: ring(around: cell), cell: cell),
                      Interval(min: cell.min - ringOutset, max: trailing),
                      "ring past the trailing edge")
    }

    func testLastTabOvershootingTheEdgeByAFractionKeepsItsRing() {
        // Cell widths are divided per tab, rounded to device pixels, and accumulated through Float, so
        // the last cell's edge lands near the viewport rather than on it. A cell that fits is still a
        // cell that fits, and its ring keeps the cap it would lose if the comparison were exact.
        for overshoot in [0.0, 0.01, 0.25, 0.5] {
            let cell = Interval(min: trailing - 100, max: trailing + overshoot)
            assertVisible(visiblePart(accessory: ring(around: cell), cell: cell),
                          ring(around: cell),
                          "last tab overshooting by \(overshoot)")
        }
    }

    func testLeadingEdgeUndershootByAFractionKeepsItsRing() {
        for undershoot in [0.0, 0.01, 0.25, 0.5] {
            let cell = Interval(min: leading - undershoot, max: leading + 100)
            assertVisible(visiblePart(accessory: ring(around: cell), cell: cell),
                          ring(around: cell),
                          "first tab undershooting by \(undershoot)")
        }
    }

    // MARK: - Nothing visible

    func testFullyScrolledOutAccessoryIsNotVisible() {
        let cell = Interval(min: 10, max: 50)
        XCTAssertNil(visiblePart(accessory: ring(around: cell), cell: cell))
    }

    func testAccessoryEndingExactlyAtTheMarginIsNotVisible() {
        // Touching the margin leaves a zero-width sliver, which is nothing to draw.
        let cell = Interval(min: leading - 40, max: leading)
        XCTAssertNil(visiblePart(accessory: cell, cell: cell))
    }

    func testAccessoryStartingExactlyAtTheTrailingEdgeIsNotVisible() {
        let cell = Interval(min: trailing, max: trailing + 40)
        XCTAssertNil(visiblePart(accessory: cell, cell: cell))
    }

    // MARK: - Flipped-to-layer conversion

    func testLayerCoordinatesOfTheWholeSubviewIsItsBounds() {
        let frame = NSRect(x: 100, y: 10, width: 40, height: 20)
        XCTAssertEqual(PSMRectInLayerCoordinates(frame, frame),
                       NSRect(x: 0, y: 0, width: 40, height: 20))
    }

    func testLayerCoordinatesFlipY() {
        let frame = NSRect(x: 100, y: 10, width: 40, height: 20)
        // The top half in the bar's flipped coordinates is the top half in the layer's too, which is
        // the upper 10pt of a 20pt-tall, y-up box.
        XCTAssertEqual(PSMRectInLayerCoordinates(NSRect(x: 100, y: 10, width: 40, height: 10), frame),
                       NSRect(x: 0, y: 10, width: 40, height: 10))
        XCTAssertEqual(PSMRectInLayerCoordinates(NSRect(x: 100, y: 20, width: 40, height: 10), frame),
                       NSRect(x: 0, y: 0, width: 40, height: 10))
    }

    func testLayerCoordinatesOfALeadingClip() {
        // What the leading edge of a partly scrolled accessory looks like once converted: the visible
        // part is the trailing portion of the view, so it starts partway along x and keeps its height.
        let frame = NSRect(x: 100, y: 10, width: 40, height: 20)
        let visible = NSRect(x: 115, y: 10, width: 25, height: 20)
        XCTAssertEqual(PSMRectInLayerCoordinates(visible, frame),
                       NSRect(x: 15, y: 0, width: 25, height: 20))
    }
}
