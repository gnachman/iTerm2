//
//  CompanionSelectionRangeTests.swift
//  iTerm2 ModernTests
//
//  iTermSelection uses a half-open (exclusive) end x, but the Companion wire and
//  the phone treat the selection end as the inclusive last cell. The bridge
//  converts on the way out; these cover the conversion, including the wrap when
//  the exclusive end sits at column 0 (previous line selected through its end).
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionSelectionRangeTests: XCTestCase {
    func testMidLineEndSubtractsOne() {
        let end = CompanionHostBridge.inclusiveSelectionEnd(exclusiveColumn: 10, absLine: 42, gridWidth: 80)
        XCTAssertEqual(end.column, 9)
        XCTAssertEqual(end.absLine, 42)
    }

    func testSelectAllEndMapsToLastColumn() {
        // Select all yields an exclusive end at the grid width; the inclusive last
        // cell is gridWidth - 1 on the same line.
        let end = CompanionHostBridge.inclusiveSelectionEnd(exclusiveColumn: 80, absLine: 42, gridWidth: 80)
        XCTAssertEqual(end.column, 79)
        XCTAssertEqual(end.absLine, 42)
    }

    func testEndAtColumnZeroWrapsToPreviousLineEnd() {
        let end = CompanionHostBridge.inclusiveSelectionEnd(exclusiveColumn: 0, absLine: 42, gridWidth: 80)
        XCTAssertEqual(end.column, 79)
        XCTAssertEqual(end.absLine, 41)
    }

    func testEndAtColumnZeroWithUnknownWidthDoesNotGoNegative() {
        let end = CompanionHostBridge.inclusiveSelectionEnd(exclusiveColumn: 0, absLine: 42, gridWidth: 0)
        XCTAssertEqual(end.column, 0)
        XCTAssertEqual(end.absLine, 41)
    }
}
