//
//  UvDownloadTests.swift
//  ModernTests
//
//  Phase 1 of the uv Python-runtime migration. Pure pieces of the uv download:
//  parsing the download manifest JSON. Tarball trust is an RSA signature verified
//  against the bundled public key (see UvProvisionerTests); there is no SHA-256
//  path. See docs/uv-python-runtime-migration.md (Phase 1).
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
}
