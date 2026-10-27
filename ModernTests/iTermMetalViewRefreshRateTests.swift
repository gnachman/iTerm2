//
//  iTermMetalViewRefreshRateTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

final class iTermMetalViewRefreshRateTests: XCTestCase {
    // QA finding F-726: a screen reporting 0 frames per second must not stop drawing or crash.
    func testZeroMaximumUsesTheFloor() {
        XCTAssertEqual(iTermMetalView.refreshesPerSecond(screenMaximum: 0), 15)
    }

    func testNegativeMaximumUsesTheFloor() {
        XCTAssertEqual(iTermMetalView.refreshesPerSecond(screenMaximum: -1), 15)
    }

    func testNormalMaximumIsKept() {
        XCTAssertEqual(iTermMetalView.refreshesPerSecond(screenMaximum: 60), 60)
        XCTAssertEqual(iTermMetalView.refreshesPerSecond(screenMaximum: 120), 120)
    }
}
