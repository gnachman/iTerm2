//
//  FloatingPaneGeometryTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class FloatingPaneGeometryTests: XCTestCase {
    // 10x20 cells; 22 points of horizontal chrome and 42 of vertical (margins, scroller, title bar,
    // outline).
    private let metrics = FloatingPaneMetrics(cellSize: CGSize(width: 10, height: 20),
                                              chrome: CGSize(width: 22, height: 42))
    private let container = CGSize(width: 1000, height: 800)

    private func grid(_ columns: Int, _ rows: Int) -> FloatingPaneGrid {
        return FloatingPaneGrid(columns: columns, rows: rows)
    }

    private func placement(_ columns: Int, _ rows: Int, x: CGFloat, y: CGFloat) -> FloatingPanePlacement {
        let g = grid(columns, rows)
        return FloatingPanePlacement(frame: CGRect(origin: CGPoint(x: x, y: y), size: metrics.frameSize(for: g)),
                                     grid: g)
    }

    // MARK: - Metrics

    func testFrameSizeAndGridAreInverses() {
        for columns in [2, 3, 80, 97] {
            for rows in [2, 5, 24] {
                let g = grid(columns, rows)
                XCTAssertEqual(metrics.grid(fitting: metrics.frameSize(for: g)), g)
            }
        }
    }

    func testGridFittingRoundsDown() {
        let size = metrics.frameSize(for: grid(10, 5))
        XCTAssertEqual(metrics.grid(fitting: CGSize(width: size.width + 9.9, height: size.height + 19.9)), grid(10, 5))
        XCTAssertEqual(metrics.grid(fitting: CGSize(width: size.width - 0.1, height: size.height - 0.1)), grid(9, 4))
    }

    func testGridFittingNeverNegative() {
        XCTAssertEqual(metrics.grid(fitting: .zero), grid(0, 0))
    }

    // MARK: - Coordinates

    func testVisualConversionFlipsUnflippedContainers() {
        let rect = CGRect(x: 10, y: 100, width: 50, height: 30)
        let visual = FloatingPaneGeometry.toVisual(rect, containerHeight: 800, containerIsFlipped: false)
        XCTAssertEqual(visual, CGRect(x: 10, y: 670, width: 50, height: 30))
        XCTAssertEqual(FloatingPaneGeometry.fromVisual(visual, containerHeight: 800, containerIsFlipped: false), rect)
        XCTAssertEqual(FloatingPaneGeometry.toVisual(rect, containerHeight: 800, containerIsFlipped: true), rect)
    }

    // MARK: - Creation

    func testInitialPlacementIs80PercentInWholeCellsAndCentered() {
        let p = FloatingPaneGeometry.initialPlacement(container: container, metrics: metrics)
        // 800 - 22 = 778 -> 77 columns; 640 - 42 = 598 -> 29 rows.
        XCTAssertEqual(p.grid, grid(77, 29))
        XCTAssertEqual(p.frame.size, metrics.frameSize(for: p.grid))
        XCTAssertEqual(p.frame.midX, container.width / 2, accuracy: 1)
        XCTAssertEqual(p.frame.midY, container.height / 2, accuracy: 1)
        XCTAssertEqual(p.frame.origin.x, p.frame.origin.x.rounded(.down), "origins are whole points")
    }

    func testInitialPlacementInATinyContainerIsTheMinimumAtTheTopLeft() {
        let p = FloatingPaneGeometry.initialPlacement(container: CGSize(width: 30, height: 40), metrics: metrics)
        XCTAssertEqual(p.grid, .minimum)
        XCTAssertEqual(p.frame.origin, .zero, "an oversize float keeps its title bar reachable")
    }

    // MARK: - Clamping and moving

    func testClampKeepsTheFloatInside() {
        let size = CGSize(width: 200, height: 100)
        XCTAssertEqual(FloatingPaneGeometry.clamp(CGRect(origin: CGPoint(x: -5, y: -7), size: size), in: container).origin,
                       .zero)
        XCTAssertEqual(FloatingPaneGeometry.clamp(CGRect(origin: CGPoint(x: 900, y: 750), size: size), in: container).origin,
                       CGPoint(x: 800, y: 700))
        let inside = CGRect(origin: CGPoint(x: 100, y: 100), size: size)
        XCTAssertEqual(FloatingPaneGeometry.clamp(inside, in: container), inside)
    }

    func testClampOfAnOversizeFloatPinsTheTopLeft() {
        let big = CGRect(x: 50, y: 50, width: 2000, height: 2000)
        XCTAssertEqual(FloatingPaneGeometry.clamp(big, in: container).origin, .zero)
    }

    func testMoveIsClampedAndKeepsSize() {
        let start = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(FloatingPaneGeometry.move(start, by: CGSize(width: 30, height: -20), in: container),
                       CGRect(x: 130, y: 80, width: 200, height: 100))
        XCTAssertEqual(FloatingPaneGeometry.move(start, by: CGSize(width: 5000, height: 5000), in: container),
                       CGRect(x: 800, y: 700, width: 200, height: 100))
        XCTAssertEqual(FloatingPaneGeometry.move(start, by: CGSize(width: -5000, height: -5000), in: container),
                       CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    // MARK: - Edge resizing

    func testRightEdgeDragSnapsToCells() {
        let start = placement(20, 10, x: 100, y: 100)
        let p = FloatingPaneGeometry.resize(start, edges: .right, by: CGSize(width: 35, height: 0),
                                            in: container, metrics: metrics)
        XCTAssertEqual(p.grid, grid(23, 10), "35 points is 3 whole columns")
        XCTAssertEqual(p.frame.origin, start.frame.origin, "the left edge does not move")
        XCTAssertEqual(p.frame.size, metrics.frameSize(for: p.grid))
    }

    func testLeftEdgeDragKeepsTheRightEdgeFixed() {
        let start = placement(20, 10, x: 100, y: 100)
        let p = FloatingPaneGeometry.resize(start, edges: .left, by: CGSize(width: -25, height: 0),
                                            in: container, metrics: metrics)
        XCTAssertEqual(p.grid, grid(22, 10))
        XCTAssertEqual(p.frame.maxX, start.frame.maxX)
        XCTAssertEqual(p.frame.minY, start.frame.minY)
    }

    func testTopLeftCornerDragKeepsTheBottomRightFixed() {
        let start = placement(20, 10, x: 100, y: 100)
        let p = FloatingPaneGeometry.resize(start, edges: [.top, .left], by: CGSize(width: 20, height: 40),
                                            in: container, metrics: metrics)
        XCTAssertEqual(p.grid, grid(18, 8))
        XCTAssertEqual(p.frame.maxX, start.frame.maxX)
        XCTAssertEqual(p.frame.maxY, start.frame.maxY)
    }

    func testBottomEdgeDragDoesNotChangeColumns() {
        let start = placement(20, 10, x: 100, y: 100)
        let p = FloatingPaneGeometry.resize(start, edges: .bottom, by: CGSize(width: 300, height: 60),
                                            in: container, metrics: metrics)
        XCTAssertEqual(p.grid, grid(20, 13))
    }

    func testResizeStopsAtTheMinimum() {
        let start = placement(20, 10, x: 100, y: 100)
        let p = FloatingPaneGeometry.resize(start, edges: [.right, .bottom], by: CGSize(width: -5000, height: -5000),
                                            in: container, metrics: metrics)
        XCTAssertEqual(p.grid, .minimum)
        XCTAssertEqual(p.frame.origin, start.frame.origin)
    }

    func testResizeStopsAtTheContainerEdge() {
        let start = placement(20, 10, x: 100, y: 100)
        let right = FloatingPaneGeometry.resize(start, edges: .right, by: CGSize(width: 5000, height: 0),
                                                in: container, metrics: metrics)
        XCTAssertLessThanOrEqual(right.frame.maxX, container.width)
        XCTAssertEqual(right.grid, grid(87, 10), "(1000 - 100 - 22) / 10 = 87.8")

        let left = FloatingPaneGeometry.resize(start, edges: .left, by: CGSize(width: -5000, height: 0),
                                               in: container, metrics: metrics)
        XCTAssertGreaterThanOrEqual(left.frame.minX, 0)
        XCTAssertEqual(left.frame.maxX, start.frame.maxX)

        let top = FloatingPaneGeometry.resize(start, edges: .top, by: CGSize(width: 0, height: -5000),
                                              in: container, metrics: metrics)
        XCTAssertGreaterThanOrEqual(top.frame.minY, 0)
        XCTAssertEqual(top.frame.maxY, start.frame.maxY)
    }

    // MARK: - Keyboard resizing

    func testKeyboardResizeChangesTheGridByOneCell() {
        let start = placement(20, 10, x: 100, y: 100)
        let wider = FloatingPaneGeometry.resize(start, byColumns: 1, rows: 0, in: container, metrics: metrics)
        XCTAssertEqual(wider.grid, grid(21, 10))
        XCTAssertEqual(wider.frame.origin, start.frame.origin)
        let shorter = FloatingPaneGeometry.resize(start, byColumns: 0, rows: -1, in: container, metrics: metrics)
        XCTAssertEqual(shorter.grid, grid(20, 9))
    }

    func testKeyboardResizeIsClampedAndStaysInside() {
        let start = placement(2, 2, x: 0, y: 0)
        XCTAssertEqual(FloatingPaneGeometry.resize(start, byColumns: -1, rows: -1, in: container, metrics: metrics).grid,
                       .minimum)
        let atRight = placement(20, 10, x: container.width - metrics.frameSize(for: grid(20, 10)).width, y: 0)
        let grown = FloatingPaneGeometry.resize(atRight, byColumns: 1, rows: 0, in: container, metrics: metrics)
        XCTAssertEqual(grown.grid, grid(21, 10))
        XCTAssertLessThanOrEqual(grown.frame.maxX, container.width, "growing at the right edge moves the float left")
    }

    // MARK: - Container changes

    func testGrowingTheContainerKeepsGridAndTopLeft() {
        let start = placement(20, 10, x: 100, y: 100)
        let p = FloatingPaneGeometry.placement(after: start, desiredGrid: nil, oldContainer: container,
                                               newContainer: CGSize(width: 1200, height: 900), metrics: metrics)
        XCTAssertEqual(p, start)
    }

    func testAFloatTouchingTheRightAndBottomEdgesStaysThere() {
        let size = metrics.frameSize(for: grid(20, 10))
        let start = placement(20, 10, x: container.width - size.width, y: container.height - size.height)
        let newContainer = CGSize(width: 1200, height: 900)
        let p = FloatingPaneGeometry.placement(after: start, desiredGrid: nil, oldContainer: container,
                                               newContainer: newContainer, metrics: metrics)
        XCTAssertEqual(p.grid, start.grid)
        XCTAssertEqual(p.frame.maxX, newContainer.width)
        XCTAssertEqual(p.frame.maxY, newContainer.height)
    }

    func testShrinkingTheContainerClampsPositionBeforeTheGrid() {
        let start = placement(20, 10, x: 700, y: 500)
        let newContainer = CGSize(width: 600, height: 400)
        let p = FloatingPaneGeometry.placement(after: start, desiredGrid: nil, oldContainer: container,
                                               newContainer: newContainer, metrics: metrics)
        XCTAssertEqual(p.grid, start.grid, "the float fits, so only its position changes")
        XCTAssertLessThanOrEqual(p.frame.maxX, newContainer.width)
        XCTAssertLessThanOrEqual(p.frame.maxY, newContainer.height)
    }

    func testShrinkAndRemember() {
        let start = placement(80, 30, x: 0, y: 0)
        let small = CGSize(width: 400, height: 300)
        let shrunk = FloatingPaneGeometry.placement(after: start, desiredGrid: nil, oldContainer: container,
                                                    newContainer: small, metrics: metrics)
        XCTAssertEqual(shrunk.grid, metrics.grid(fitting: small))
        let remembered = FloatingPaneGeometry.desiredGrid(wanted: start.grid, actual: shrunk.grid)
        XCTAssertEqual(remembered, start.grid)

        // When there is room again, the remembered grid comes back.
        let restored = FloatingPaneGeometry.placement(after: shrunk, desiredGrid: remembered, oldContainer: small,
                                                      newContainer: container, metrics: metrics)
        XCTAssertEqual(restored.grid, start.grid)
        XCTAssertNil(FloatingPaneGeometry.desiredGrid(wanted: start.grid, actual: restored.grid))
    }

    func testPartialRoomRestoresPartially() {
        let start = placement(80, 30, x: 0, y: 0)
        let medium = metrics.frameSize(for: grid(50, 20))
        let p = FloatingPaneGeometry.placement(after: start, desiredGrid: start.grid, oldContainer: container,
                                               newContainer: medium, metrics: metrics)
        XCTAssertEqual(p.grid, grid(50, 20))
    }

    func testNeverSmallerThanTheMinimum() {
        let start = placement(20, 10, x: 0, y: 0)
        let p = FloatingPaneGeometry.placement(after: start, desiredGrid: nil, oldContainer: container,
                                               newContainer: CGSize(width: 5, height: 5), metrics: metrics)
        XCTAssertEqual(p.grid, .minimum)
        XCTAssertEqual(p.frame.origin, .zero)
    }

    func testMetricsChangeKeepsTheGrid() {
        // A larger font: the grid is kept and the frame grows.
        let start = placement(20, 10, x: 100, y: 100)
        let bigger = FloatingPaneMetrics(cellSize: CGSize(width: 14, height: 28), chrome: metrics.chrome)
        let p = FloatingPaneGeometry.placement(after: start, desiredGrid: nil, oldContainer: container,
                                               newContainer: container, metrics: bigger)
        XCTAssertEqual(p.grid, start.grid)
        XCTAssertEqual(p.frame.size, bigger.frameSize(for: start.grid))
        XCTAssertEqual(p.frame.origin, start.frame.origin)
    }
}
