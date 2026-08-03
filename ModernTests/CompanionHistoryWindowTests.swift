//
//  CompanionHistoryWindowTests.swift
//  iTerm2 ModernTests
//
//  Absolute-line addressing for scrollback browsing: requests clamp to the
//  available window and translate to/from buffer-relative indices, so eviction
//  races resolve deterministically.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionHistoryWindowTests: XCTestCase {
    func testRelativeAndAbsoluteTranslation() {
        // 100 lines have scrolled off; 50 are available: abs [100, 150).
        let window = CompanionHistoryWindow(firstAbsLine: 100, lineCount: 50)
        XCTAssertEqual(window.endAbsLine, 150)
        XCTAssertEqual(window.relativeLine(forAbs: 100), 0)
        XCTAssertEqual(window.relativeLine(forAbs: 149), 49)
        XCTAssertEqual(window.absLine(forRelative: 10), 110)
    }

    func testContainsAndEvicted() {
        let window = CompanionHistoryWindow(firstAbsLine: 100, lineCount: 50)
        XCTAssertFalse(window.contains(absLine: 99))    // evicted off the top
        XCTAssertTrue(window.contains(absLine: 100))
        XCTAssertTrue(window.contains(absLine: 149))
        XCTAssertFalse(window.contains(absLine: 150))   // past the end
        XCTAssertNil(window.relativeLine(forAbs: 99))
        XCTAssertNil(window.relativeLine(forAbs: 150))
    }

    func testClampWithinWindow() {
        let window = CompanionHistoryWindow(firstAbsLine: 100, lineCount: 50)
        let r = window.clamped(absLine: 110, count: 20)
        XCTAssertEqual(r?.absLine, 110)
        XCTAssertEqual(r?.count, 20)
    }

    func testClampTrimsEvictedHead() {
        // Asked for [80, 120) but [80,100) is evicted -> covered [100, 120).
        let window = CompanionHistoryWindow(firstAbsLine: 100, lineCount: 50)
        let r = window.clamped(absLine: 80, count: 40)
        XCTAssertEqual(r?.absLine, 100)
        XCTAssertEqual(r?.count, 20)
    }

    func testClampTrimsBeyondEnd() {
        // Asked for [140, 170) but only up to 150 -> covered [140, 150).
        let window = CompanionHistoryWindow(firstAbsLine: 100, lineCount: 50)
        let r = window.clamped(absLine: 140, count: 30)
        XCTAssertEqual(r?.absLine, 140)
        XCTAssertEqual(r?.count, 10)
    }

    func testClampFullyEvictedReturnsNil() {
        let window = CompanionHistoryWindow(firstAbsLine: 100, lineCount: 50)
        XCTAssertNil(window.clamped(absLine: 0, count: 50))    // all below firstAbs
        XCTAssertNil(window.clamped(absLine: 200, count: 50))  // all beyond end
        XCTAssertNil(window.clamped(absLine: 110, count: 0))   // empty request
    }

    func testEmptyWindow() {
        let window = CompanionHistoryWindow(firstAbsLine: 0, lineCount: 0)
        XCTAssertEqual(window.endAbsLine, 0)
        XCTAssertFalse(window.contains(absLine: 0))
        XCTAssertNil(window.clamped(absLine: 0, count: 10))
    }
}
