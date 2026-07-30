//
//  UvDownloadTests.swift
//  ModernTests
//
//  Phase 1 of the uv Python-runtime migration. Pure pieces of the uv download:
//  parsing the download manifest JSON, and verifying a downloaded tarball against
//  a pinned SHA-256 (the trust mechanism for the dev source; RSA is added when
//  hosting moves to iterm2.com). See docs/uv-python-runtime-migration.md (Phase 1).
//

import XCTest
@testable import iTerm2SharedARC

final class UvDownloadTests: XCTestCase {
    // MARK: - Manifest parsing

    func testParsesManifestWithBracketsAndNullMax() {
        let json = """
        [
          { "uv_version": "0.12.0", "url": "https://x/uv-0.12.0.tar.gz",
            "signature": "aa", "size": 100,
            "minimum_macos_version": "13.0", "maximum_macos_version": null },
          { "uv_version": "0.11.0", "url": "https://x/uv-0.11.0.tar.gz",
            "signature": "bb", "size": 90,
            "minimum_macos_version": "12.0", "maximum_macos_version": "12.6" }
        ]
        """.data(using: .utf8)!
        let entries = iTermUvManifest.parse(json)
        XCTAssertEqual(entries?.count, 2)
        XCTAssertEqual(entries?[0].uvVersion, "0.12.0")
        XCTAssertEqual(entries?[0].size, 100)
        XCTAssertNil(entries?[0].maximumMacOSVersion)
        XCTAssertEqual(entries?[1].maximumMacOSVersion, "12.6")
    }

    func testAbsentMaxKeyDecodesToNil() {
        let json = """
        [ { "uv_version": "0.12.0", "url": "u", "signature": "s", "size": 1,
            "minimum_macos_version": "13.0" } ]
        """.data(using: .utf8)!
        XCTAssertEqual(iTermUvManifest.parse(json)?.first?.maximumMacOSVersion, nil)
        XCTAssertEqual(iTermUvManifest.parse(json)?.first?.uvVersion, "0.12.0")
    }

    func testMalformedManifestReturnsNil() {
        XCTAssertNil(iTermUvManifest.parse("{ not an array }".data(using: .utf8)!))
        XCTAssertNil(iTermUvManifest.parse(Data()))
    }

    // MARK: - SHA-256 verification

    func testMatchesKnownDigest() {
        // sha256("abc")
        let data = "abc".data(using: .utf8)!
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        XCTAssertTrue(iTermUvDownload.matchesSHA256(data: data, expectedHex: expected))
    }

    func testMatchIsCaseInsensitive() {
        let data = "abc".data(using: .utf8)!
        let expectedUpper = "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"
        XCTAssertTrue(iTermUvDownload.matchesSHA256(data: data, expectedHex: expectedUpper))
    }

    func testRejectsWrongDigest() {
        let data = "abc".data(using: .utf8)!
        XCTAssertFalse(iTermUvDownload.matchesSHA256(data: data, expectedHex: String(repeating: "0", count: 64)))
        // Tampered content must not match the digest of the original.
        let tampered = "abd".data(using: .utf8)!
        let abcDigest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        XCTAssertFalse(iTermUvDownload.matchesSHA256(data: tampered, expectedHex: abcDigest))
    }
}
