//
//  OpenQuicklyContentSearchTests.swift
//  iTerm2
//
//  Tests for Open Quickly's session contents search ("/g").
//

import XCTest
@testable import iTerm2SharedARC

final class OpenQuicklyContentMatchTallyTests: XCTestCase {
    func testCountsAccumulate() {
        var tally = iTermContentMatchTally<String, String>()
        tally.add(["a1", "a2"], for: "A")
        tally.add(["a3"], for: "A")
        XCTAssertEqual(tally.entries["A"]?.count, 3)
        XCTAssertEqual(tally.entries["A"]?.first, "a1")
    }

    func testOrdinalRecordsOrderOfFirstMatch() {
        var tally = iTermContentMatchTally<String, String>()
        tally.add(["b"], for: "B")
        tally.add(["a"], for: "A")
        tally.add(["b2"], for: "B")
        XCTAssertEqual(tally.entries["B"]?.ordinal, 0)
        XCTAssertEqual(tally.entries["A"]?.ordinal, 1)
    }

    func testEmptyResultsAreIgnored() {
        var tally = iTermContentMatchTally<String, String>()
        tally.add([], for: "A")
        XCTAssertNil(tally.entries["A"])
    }
}
