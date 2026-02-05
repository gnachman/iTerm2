//
//  PathTests.swift
//  iTerm2
//
//  Created by George Nachman on 2/4/26.
//

import XCTest
@testable import iTerm2SharedARC

/// Tests for path methods to verify correct behavior with and without custom suite names.
/// These tests establish baseline behavior and verify no regressions when --suite is not used.
final class PathTests: XCTestCase {

    // MARK: - Application Support Directory Tests

    func testApplicationSupportDirectory_DefaultSuite() {
        // Given: No custom suite is set (default behavior)
        // Note: We can't easily reset the suite in tests since it's set once at startup

        // When
        let path = FileManager.default.applicationSupportDirectory()

        // Then
        XCTAssertNotNil(path)
        XCTAssertTrue(path!.contains("Application Support"))
        // Default should use iTerm2 as the directory name
        XCTAssertTrue(path!.hasSuffix("/iTerm2") || path!.contains("iTerm2"))
    }

    func testApplicationSupportDirectoryWithoutCreating_DefaultSuite() {
        // When
        let path = FileManager.default.applicationSupportDirectoryWithoutCreating()

        // Then
        XCTAssertNotNil(path)
        XCTAssertTrue(path!.contains("Application Support"))
        XCTAssertTrue(path!.hasSuffix("/iTerm2") || path!.contains("iTerm2"))
    }

    // MARK: - Home Directory Dot-Dir Tests

    func testHomeDirectoryDotDir_DefaultSuite() {
        // When
        let path = FileManager.default.homeDirectoryDotDir()

        // Then
        XCTAssertNotNil(path)
        // Should be ~/.config/iterm2 or ~/.iterm2 (or custom preferredBaseDir)
        let homedir = NSHomeDirectory()
        XCTAssertTrue(
            path!.hasPrefix(homedir),
            "Path should be under home directory"
        )
        // Should contain iterm2 somewhere in the path
        let lowercasePath = path!.lowercased()
        XCTAssertTrue(
            lowercasePath.contains("iterm2") || lowercasePath.contains(".iterm2"),
            "Path should contain 'iterm2'"
        )
    }

    // MARK: - Custom Suite Name Accessor Tests

    func testCustomSuiteName_ReturnsNilOrSetValue() {
        // This test documents the behavior of customSuiteName accessor
        // The actual value depends on whether --suite was passed at startup
        let suiteName = iTermUserDefaults.customSuiteName()

        // The test passes regardless of value - we're just documenting that the method exists
        // and returns either nil (no suite) or a string (custom suite)
        if let name = suiteName {
            XCTAssertFalse(name.isEmpty, "If a suite name is set, it should not be empty")
        }
        // nil is also valid - means no custom suite
    }

    // MARK: - Integration Tests

    func testScriptsPath_UsesApplicationSupportDirectory() {
        // When
        let scriptsPath = FileManager.default.scriptsPath()

        // Then
        XCTAssertNotNil(scriptsPath)
        // Scripts path should be under Application Support (unless custom folder is set)
        let appSupport = FileManager.default.applicationSupportDirectory()
        if appSupport != nil {
            // Either it's under app support or it's a custom scripts folder
            let isUnderAppSupport = scriptsPath!.hasPrefix(appSupport!)
            let isCustomFolder = iTermPreferences.bool(forKey: kPreferenceKeyUseCustomScriptsFolder)
            XCTAssertTrue(isUnderAppSupport || isCustomFolder,
                          "Scripts path should be under app support or custom folder")
        }
    }
}
