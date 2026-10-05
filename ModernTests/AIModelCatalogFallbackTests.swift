//
//  AIModelCatalogFallbackTests.swift
//  ModernTests
//
//  AIModelCatalog loads the bundled ai-models.json and the downloaded cache in Application
//  Support. When neither can be read it asserted, crashing at launch. That happens when the app's
//  bundle is moved or deleted while it launches (for example, an installer such as Jamf removing
//  its staged copy while the “Move to Applications folder?” prompt holds up launch). Then the app
//  is damaged and the user needs to reinstall, so iTerm2 says so (AppSignatureValidator) rather
//  than asserting. These tests cover deciding that the catalog is unavailable.
//

import XCTest
@testable import iTerm2SharedARC

final class AIModelCatalogFallbackTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIModelCatalogFallbackTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    private var missingURL: URL {
        tempDir.appendingPathComponent("missing.json")
    }

    private func corruptURL() throws -> URL {
        let url = tempDir.appendingPathComponent("corrupt.json")
        try Data("not json".utf8).write(to: url)
        return url
    }

    private func bundledURL() throws -> URL {
        return try XCTUnwrap(AIModelCatalog.bundledCatalogURL)
    }

    // The launch crash: no bundle (it moved) and no cache (fresh install).
    func testMissingBundleAndCacheIsUnavailable() {
        XCTAssertNil(AIModelCatalog(bundledURL: nil, cachedURL: missingURL))
    }

    func testUnreadableBundleAndCorruptCacheIsUnavailable() throws {
        XCTAssertNil(AIModelCatalog(bundledURL: missingURL, cachedURL: try corruptURL()))
    }

    // One good source is enough.
    func testCorruptCacheFallsBackToBundle() throws {
        let catalog = try XCTUnwrap(AIModelCatalog(bundledURL: try bundledURL(), cachedURL: try corruptURL()))
        XCTAssertEqual(catalog.models.map(\.name),
                       try XCTUnwrap(AIModelCatalog.bundledForTesting).models.map(\.name))
    }

    func testMissingBundleUsesCache() throws {
        let catalog = try XCTUnwrap(AIModelCatalog(bundledURL: missingURL, cachedURL: try bundledURL()))
        XCTAssertFalse(catalog.models.isEmpty)
    }
}

final class AppSignatureValidatorMessageTests: XCTestCase {
    private let officialTeamID = "H7V7XYVQ7D"

    func testUnverifiableSignatureSaysToReinstall() {
        let message = AppSignatureValidator.corruptionMessage(teamID: nil)
        XCTAssertTrue(message.contains("could not be verified"), message)
    }

    func testOfficialSignatureSaysToFileABug() {
        let message = AppSignatureValidator.corruptionMessage(teamID: officialTeamID)
        XCTAssertTrue(message.contains("against all odds"), message)
    }

    func testOtherTeamSaysItIsNotTheOfficialDistribution() {
        let message = AppSignatureValidator.corruptionMessage(teamID: "ABCDE12345")
        XCTAssertTrue(message.contains("did not match that of the official distribution"), message)
    }
}
