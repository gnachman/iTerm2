//
//  ProgressBarRingGeometryTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class ProgressBarRingGeometryTests: XCTestCase {
    private func assertIncreasingInUnitInterval(_ locations: [CGFloat],
                                                file: StaticString = #filePath,
                                                line: UInt = #line) {
        XCTAssertFalse(locations.isEmpty, file: file, line: line)
        for (a, b) in zip(locations, locations.dropFirst()) {
            XCTAssertLessThan(a, b, file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(locations.first ?? -1, 0, file: file, line: line)
        XCTAssertLessThan(locations.last ?? 2, 1, file: file, line: line)
    }

    func testWidePillLocationsIncrease() {
        let locations = iTermProgressBarView.stadiumConicLocations(width: 760, height: 40, count: 72)
        XCTAssertEqual(locations.count, 72)
        assertIncreasingInUnitInterval(locations)
        XCTAssertEqual(locations[0], 0, accuracy: 1e-9)
    }

    func testWidePillCapGetsArcLengthShareOfStops() {
        // The right cap spans ±atan(r / halfStraight) from the center: about
        // ±3.2° here. Its 63pt of arc gets about 3 of the 72 stops.
        let locations = iTermProgressBarView.stadiumConicLocations(width: 760, height: 40, count: 72)
        let capHalfAngle = atan(20.0 / 360.0) / (2.0 * .pi)
        let onRightCap = locations.filter { $0 <= capHalfAngle || $0 >= 1.0 - capHalfAngle }
        XCTAssertEqual(onRightCap.count, 3)
    }

    func testTallPillLocationsIncrease() {
        let locations = iTermProgressBarView.stadiumConicLocations(width: 40, height: 300, count: 72)
        XCTAssertEqual(locations.count, 72)
        assertIncreasingInUnitInterval(locations)
        // The walk starts on the +x axis so the closing stop at 1.0 covers the
        // same arc as every other stop instead of leaving a flat wedge at 0.
        XCTAssertEqual(locations[0], 0, accuracy: 1e-9)
    }

    func testTallPillWrapStopMatchesStraightEdgeSpacing() {
        // 40 x 300: the right edge is straight from y = -130 to 130, so the
        // stops on either side of angle 0 lie on it and the wrap-around gap
        // (from the last location to 1.0) equals the first gap.
        let locations = iTermProgressBarView.stadiumConicLocations(width: 40, height: 300, count: 72)
        let firstGap = locations[1] - locations[0]
        let wrapGap = 1.0 - locations[locations.count - 1]
        XCTAssertEqual(wrapGap, firstGap, accuracy: 1e-9)
    }

    func testCircleIsUniform() {
        let locations = iTermProgressBarView.stadiumConicLocations(width: 50, height: 50, count: 8)
        for (i, location) in locations.enumerated() {
            XCTAssertEqual(location, CGFloat(i) / 8.0, accuracy: 1e-9)
        }
    }

    func testDegenerateSizeIsEmpty() {
        XCTAssertTrue(iTermProgressBarView.stadiumConicLocations(width: 0, height: 0, count: 72).isEmpty)
        XCTAssertTrue(iTermProgressBarView.stadiumConicLocations(width: 100, height: 40, count: 0).isEmpty)
    }
}
