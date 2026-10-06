//
//  CodeReviewSettingsMigrationTests.swift
//  iTerm2 ModernTests
//
//  The code review command's --settings argument becomes the codeReviewSettingsFile variable
//  rather than a path inside the app bundle, so a review peer on a remote host can point it at a
//  copy written there (Phase 6, part 2). Saved commands are rewritten once.
//

import XCTest
@testable import iTerm2SharedARC

final class CodeReviewSettingsMigrationTests: XCTestCase {
    private let migrated = #"--settings '\(codeReviewSettingsFile)'"#

    func testTemplatedBundlePathIsRewritten() {
        let old = #"claude \(codeReviewPrompt) --append-system-prompt-file '\(codeReviewSystemPromptFile)' --settings '\(iterm2.appBundlePath)/Contents/Resources/code-review-settings.txt'"#
        XCTAssertEqual(iTermWorkgroupModel.commandUsingCodeReviewSettingsVariable(old),
                       #"claude \(codeReviewPrompt) --append-system-prompt-file '\(codeReviewSystemPromptFile)' "# + migrated)
    }

    // Older builds persisted the resolved path, unquoted.
    func testResolvedBundlePathIsRewritten() {
        let old = "claude x --settings /Applications/iTerm.app/Contents/Resources/code-review-settings.txt --verbose"
        XCTAssertEqual(iTermWorkgroupModel.commandUsingCodeReviewSettingsVariable(old),
                       "claude x " + migrated + " --verbose")
    }

    // A user's own settings file is theirs.
    func testOtherSettingsAreLeftAlone() {
        XCTAssertNil(iTermWorkgroupModel.commandUsingCodeReviewSettingsVariable("claude x --settings '~/my.json'"))
        XCTAssertNil(iTermWorkgroupModel.commandUsingCodeReviewSettingsVariable("claude x"))
    }

    func testAlreadyMigratedIsLeftAlone() {
        XCTAssertNil(iTermWorkgroupModel.commandUsingCodeReviewSettingsVariable("claude x " + migrated))
    }
}
