//
//  UvManifestSelectionTests.swift
//  ModernTests
//
//  Phase 1 of the uv Python-runtime migration. The uv download manifest lists
//  multiple pinned uv builds, each bracketed by a min/max macOS version. The app
//  must select the newest uv build compatible with the running OS and never pick
//  an incompatible one, so a future uv that raises its macOS floor cannot strand
//  users on an older macOS. See docs/uv-python-runtime-migration.md (Phase 1).
//

import XCTest
@testable import iTerm2SharedARC

final class UvDottedVersionTests: XCTestCase {
    func testNumericNotLexicalOrdering() {
        // Lexical string order would wrongly say "0.12.0" < "0.9.17".
        XCTAssertEqual(iTermDottedVersion.compare("0.12.0", "0.9.17"), .orderedDescending)
        XCTAssertEqual(iTermDottedVersion.compare("0.9.17", "0.12.0"), .orderedAscending)
    }

    func testEqualityAndMissingComponents() {
        XCTAssertEqual(iTermDottedVersion.compare("13", "13.0"), .orderedSame)
        XCTAssertEqual(iTermDottedVersion.compare("13.0.0", "13"), .orderedSame)
        XCTAssertEqual(iTermDottedVersion.compare("13.4", "13.0"), .orderedDescending)
    }

    func testMajorDominates() {
        XCTAssertEqual(iTermDottedVersion.compare("12.9", "13.0"), .orderedAscending)
    }
}

final class UvManifestSelectionTests: XCTestCase {
    private func entry(_ uv: String, min: String, max: String? = nil) -> iTermUvManifestEntry {
        return iTermUvManifestEntry(uvVersion: uv,
                                    url: "https://example.com/uv-\(uv).tar.gz",
                                    signature: "sig-\(uv)",
                                    size: 1000,
                                    minimumMacOSVersion: min,
                                    maximumMacOSVersion: max)
    }

    func testPicksNewestCompatibleUv() {
        let entries = [entry("0.11.0", min: "13.0"),
                       entry("0.12.0", min: "13.0"),
                       entry("0.10.0", min: "13.0")]
        let chosen = iTermUvManifest.select(entries: entries, runningMacOSVersion: "13.4")
        XCTAssertEqual(chosen?.uvVersion, "0.12.0")
    }

    func testExcludesEntriesRequiringNewerMacOS() {
        let entries = [entry("0.12.0", min: "14.0"),
                       entry("0.11.0", min: "13.0")]
        let chosen = iTermUvManifest.select(entries: entries, runningMacOSVersion: "13.4")
        XCTAssertEqual(chosen?.uvVersion, "0.11.0")
    }

    func testExcludesEntriesWithMaxBelowRunning() {
        let entries = [entry("0.9.0", min: "12.0", max: "12.6"),
                       entry("0.11.0", min: "13.0")]
        let chosen = iTermUvManifest.select(entries: entries, runningMacOSVersion: "13.4")
        XCTAssertEqual(chosen?.uvVersion, "0.11.0")
    }

    func testNilMaxIsUnbounded() {
        let entries = [entry("0.12.0", min: "13.0", max: nil)]
        XCTAssertEqual(iTermUvManifest.select(entries: entries, runningMacOSVersion: "26.0")?.uvVersion,
                       "0.12.0")
    }

    func testReturnsNilWhenNoneCompatible() {
        let entries = [entry("0.12.0", min: "14.0"),
                       entry("0.13.0", min: "15.0")]
        XCTAssertNil(iTermUvManifest.select(entries: entries, runningMacOSVersion: "13.4"))
    }

    func testFutureUvFloorDoesNotStrandOlderMacOS() {
        // The key scenario: a newer uv raises its floor to macOS 14, but a macOS 13
        // user must still get the last uv that supports 13, not nothing and not the
        // incompatible newer build.
        let entries = [entry("0.20.0", min: "14.0"),
                       entry("0.12.0", min: "13.0", max: nil)]
        let chosen = iTermUvManifest.select(entries: entries, runningMacOSVersion: "13.4")
        XCTAssertEqual(chosen?.uvVersion, "0.12.0")
    }

    func testInclusiveBoundaries() {
        let entries = [entry("0.12.0", min: "13.0", max: "13.4")]
        XCTAssertEqual(iTermUvManifest.select(entries: entries, runningMacOSVersion: "13.0")?.uvVersion, "0.12.0")
        XCTAssertEqual(iTermUvManifest.select(entries: entries, runningMacOSVersion: "13.4")?.uvVersion, "0.12.0")
        XCTAssertNil(iTermUvManifest.select(entries: entries, runningMacOSVersion: "12.9"))
        XCTAssertNil(iTermUvManifest.select(entries: entries, runningMacOSVersion: "13.5"))
    }
}
