//
//  UvPythonVersionResolveTests.swift
//  ModernTests
//
//  Phase 2 of the uv Python-runtime migration. A script pins a Python version in
//  setup.cfg. python-build-standalone offers 3.8+, so we preserve the pinned minor
//  whenever it is available and only bump versions it cannot provide (in practice
//  3.7) to a safe target (3.9, the last release before the 3.10 collections.abc
//  alias removal). A forced minor bump is surfaced to the user; a preserved version
//  is silent. See docs/uv-python-runtime-migration.md (Phase 2/3).
//

import XCTest
@testable import iTerm2SharedARC

final class UvPythonVersionResolveTests: XCTestCase {
    private let available = ["3.8", "3.9", "3.10", "3.11", "3.12", "3.13", "3.14"]

    func testTwoPartExtraction() {
        XCTAssertEqual(iTermUvPythonVersion.twoPartVersion("3.10.4"), "3.10")
        XCTAssertEqual(iTermUvPythonVersion.twoPartVersion("3.9"), "3.9")
        XCTAssertEqual(iTermUvPythonVersion.twoPartVersion("3"), "3")
    }

    func testPreservesAvailablePinnedMinor() {
        let r = iTermUvPythonVersion.resolve(requested: "3.9", available: available)
        XCTAssertEqual(r.version, "3.9")
        XCTAssertNil(r.remappedFrom)
    }

    func testPreservesMinorFromThreePartPin() {
        let r = iTermUvPythonVersion.resolve(requested: "3.10.2", available: available)
        XCTAssertEqual(r.version, "3.10")
        XCTAssertNil(r.remappedFrom)
    }

    func testBumps37To39() {
        let r = iTermUvPythonVersion.resolve(requested: "3.7", available: available)
        XCTAssertEqual(r.version, "3.9")
        XCTAssertEqual(r.remappedFrom, "3.7")
    }

    func testBumpsUnavailable38To39() {
        // If pbs ever drops 3.8, a 3.8-pinned script lands on 3.9 too.
        let without38 = available.filter { $0 != "3.8" }
        let r = iTermUvPythonVersion.resolve(requested: "3.8", available: without38)
        XCTAssertEqual(r.version, "3.9")
        XCTAssertEqual(r.remappedFrom, "3.8")
    }

    func testFallsBackToNearestForwardWhenSafeTargetUnavailable() {
        // Contrived: 3.9 not offered. A 3.7 pin lands on the smallest available >= 3.7.
        let r = iTermUvPythonVersion.resolve(requested: "3.7", available: ["3.10", "3.11"])
        XCTAssertEqual(r.version, "3.10")
        XCTAssertEqual(r.remappedFrom, "3.7")
    }

    func testRequestNewerThanAllLandsOnNewest() {
        let r = iTermUvPythonVersion.resolve(requested: "3.99", available: available)
        XCTAssertEqual(r.version, "3.14")
        XCTAssertEqual(r.remappedFrom, "3.99")
    }

    func testEmptyAvailableReturnsRequestedUnchanged() {
        // Degenerate (uv python list failed): don't invent a version.
        let r = iTermUvPythonVersion.resolve(requested: "3.7", available: [])
        XCTAssertEqual(r.version, "3.7")
        XCTAssertNil(r.remappedFrom)
    }

    // MARK: - Parsing `uv python list --output-format json`

    func testAvailableMinorsFiltersToStableCPythonDefault() {
        let json = """
        [
          {"version":"3.14.0","implementation":"cpython","variant":"default"},
          {"version":"3.14.1","implementation":"cpython","variant":"default"},
          {"version":"3.9.20","implementation":"cpython","variant":"default"},
          {"version":"3.15.0a2","implementation":"cpython","variant":"default"},
          {"version":"3.13.0","implementation":"cpython","variant":"freethreaded"},
          {"version":"7.3.16","implementation":"pypy","variant":"default"}
        ]
        """.data(using: .utf8)!
        // Alpha (3.15.0a2), freethreaded variant, and pypy are excluded; patches dedupe.
        XCTAssertEqual(iTermUvPythonVersion.availableMinors(fromListJSON: json), ["3.9", "3.14"])
    }

    func testAvailableMinorsOnMalformedJSONIsEmpty() {
        XCTAssertEqual(iTermUvPythonVersion.availableMinors(fromListJSON: Data("nope".utf8)), [])
    }
}
