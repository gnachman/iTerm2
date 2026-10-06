//
//  ClaudeCodeTmuxProfileTriggerTests.swift
//  iTerm2 ModernTests
//
//  tmux Integration creates its “tmux” profile the first time it needs it, by copying the default
//  profile. If the Claude Code triggers were installed on other profiles but not the default one,
//  that new profile had none, so claude run in a tmux tab never entered the workgroup (and the
//  installed check started reporting the triggers missing). A profile created that way now gets
//  the triggers when any profile already has them.
//

import XCTest
@testable import iTerm2SharedARC

final class ClaudeCodeTmuxProfileTriggerTests: XCTestCase {
    private func profile(_ guid: String, triggers: [[String: Any]] = []) -> [AnyHashable: Any] {
        return [KEY_GUID: guid, KEY_NAME: guid, KEY_TRIGGERS: triggers]
    }

    private var claudeTriggers: [[String: Any]] {
        return ClaudeCodeOnboarding.claudeWorkgroupTriggerDictionaries()
    }

    private let unrelated: [String: Any] = [kTriggerActionKey: "BellTrigger", kTriggerRegexKey: "x"]

    func testGetsTheTriggersWhenAnotherProfileHasThem() {
        let tmux = profile("tmux", triggers: [unrelated])
        XCTAssertTrue(ClaudeCodeOnboarding.newTmuxProfileNeedsClaudeTriggers(
            tmux, otherProfiles: [profile("work", triggers: claudeTriggers), profile("default")]))
    }

    // Copied from a default profile that has them: nothing to add.
    func testInheritedTriggersAreEnough() {
        let tmux = profile("tmux", triggers: claudeTriggers)
        XCTAssertFalse(ClaudeCodeOnboarding.newTmuxProfileNeedsClaudeTriggers(
            tmux, otherProfiles: [profile("default", triggers: claudeTriggers)]))
    }

    // Someone who never installed them does not get them.
    func testNothingInstalledMeansNothingAdded() {
        XCTAssertFalse(ClaudeCodeOnboarding.newTmuxProfileNeedsClaudeTriggers(
            profile("tmux"), otherProfiles: [profile("default", triggers: [unrelated])]))
    }

    // Half an install (an Enter trigger without the Exit one) is not an install.
    func testPartialInstallElsewhereDoesNotCount() {
        let enterOnly = claudeTriggers.filter { ($0[kTriggerActionKey] as? String) == "iTermEnterWorkgroupTrigger" }
        XCTAssertEqual(enterOnly.count, 1)
        XCTAssertFalse(ClaudeCodeOnboarding.newTmuxProfileNeedsClaudeTriggers(
            profile("tmux"), otherProfiles: [profile("work", triggers: enterOnly)]))
    }

    // The dictionaries are the ones the installer writes, so a profile carrying them reads as installed.
    func testTriggerDictionariesReadAsInstalled() {
        XCTAssertTrue(ClaudeCodeOnboarding.profileHasClaudeWorkgroupTriggers(profile("p", triggers: claudeTriggers)))
        XCTAssertFalse(ClaudeCodeOnboarding.profileHasClaudeWorkgroupTriggers(profile("p")))
    }
}
