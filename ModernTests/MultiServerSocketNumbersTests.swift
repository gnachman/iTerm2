//
//  MultiServerSocketNumbersTests.swift
//  ModernTests
//
//  Created by George Nachman on 9/23/26.
//

import XCTest
@testable import iTerm2SharedARC

class MultiServerSocketNumbersTests: XCTestCase {
    private func firstUnused(from start: Int, inUse: [Int]) -> Int {
        return MultiServerSocketNumbers.firstUnusedNumber(from: start,
                                                          inUse: inUse.map { NSNumber(value: $0) })
    }

    func testNothingInUseReturnsStart() {
        XCTAssertEqual(firstUnused(from: 1, inUse: []), 1)
    }

    func testSkipsASingleAdoptedOrphan() {
        XCTAssertEqual(firstUnused(from: 1, inUse: [1]), 2)
    }

    func testSkipsARunOfAdoptedOrphans() {
        XCTAssertEqual(firstUnused(from: 1, inUse: [1, 2, 3]), 4)
    }

    func testFillsAGapRatherThanAppending() {
        XCTAssertEqual(firstUnused(from: 1, inUse: [1, 3]), 2)
    }

    func testIgnoresNumbersBelowStart() {
        XCTAssertEqual(firstUnused(from: 1, inUse: [2]), 1)
    }

    func testStartBelowOneIsClampedBecauseSocketNumbersAreOneBased() {
        XCTAssertEqual(firstUnused(from: 0, inUse: []), 1)
        XCTAssertEqual(firstUnused(from: -5, inUse: [1]), 2)
    }

    func testResumesFromAFailedAttempt() {
        // tryCreatingConnectionStartingAtNumber: retries at number + 1.
        XCTAssertEqual(firstUnused(from: 4, inUse: [1, 2, 3]), 4)
        XCTAssertEqual(firstUnused(from: 4, inUse: [1, 4, 5]), 6)
    }

    func testUnsortedAndDuplicateInputs() {
        XCTAssertEqual(firstUnused(from: 1, inUse: [3, 1, 2, 1, 3]), 4)
    }
}
