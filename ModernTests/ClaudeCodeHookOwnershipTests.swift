//
//  ClaudeCodeHookOwnershipTests.swift
//  iTerm2 ModernTests
//
//  Which hook entries in a settings.json belong to THIS iTerm2, and which
//  directory an install may strip.
//
//  Both questions were answered too loosely. Ownership was decided by the
//  shape of the command alone ("ends in /cc-status", or a quoted path ending
//  in /it2 followed by handle-agent-hook), so every instance considered every
//  other instance's hooks its own. And when nothing had been recorded yet, the
//  "previous" directory was assumed to be ~/.claude. Installing from a second
//  instance into its own directory therefore stripped all ten entries belonging
//  to the main install out of ~/.claude/settings.json (2026-09-27, restored by
//  hand).
//
//  A hook entry is ours only when its executable lives in THIS instance's dot
//  dir, which is per-suite, and a strip only ever targets a directory this
//  instance actually recorded.
//

import XCTest
@testable import iTerm2SharedARC

final class ClaudeCodeHookOwnershipTests: XCTestCase {
    private let ours = "/Users/gnachman/.config/iterm2-alt7"
    private let theirs = "/Users/gnachman/.config/iterm2"

    // MARK: - Whose hook is this?

    func testCurrentFormInOurDotDirIsOurs() {
        let command = "\"\(ours)/it2\" handle-agent-hook"
        XCTAssertTrue(ClaudeCodeOnboarding.hookCommand(command, belongsToDotDir: ours))
    }

    func testCurrentFormWithArgumentsIsOurs() {
        let command = "\"\(ours)/it2\" handle-agent-hook --agent codex"
        XCTAssertTrue(ClaudeCodeOnboarding.hookCommand(command, belongsToDotDir: ours))
    }

    // The upgrade path: an install predating `it2 handle-agent-hook` still has
    // the cc-status shim, and it is still ours when it is in our dot dir.
    func testLegacyShimInOurDotDirIsOurs() {
        XCTAssertTrue(ClaudeCodeOnboarding.hookCommand("\(ours)/cc-status", belongsToDotDir: ours))
    }

    // The defect, both forms: another instance's entries are not ours to touch.
    func testCurrentFormInAnotherDotDirIsNotOurs() {
        let command = "\"\(theirs)/it2\" handle-agent-hook"
        XCTAssertFalse(ClaudeCodeOnboarding.hookCommand(command, belongsToDotDir: ours))
    }

    func testLegacyShimInAnotherDotDirIsNotOurs() {
        XCTAssertFalse(ClaudeCodeOnboarding.hookCommand("\(theirs)/cc-status", belongsToDotDir: ours))
    }

    // A path that merely starts with the same characters is a different directory.
    func testASiblingDirectoryWithASharedPrefixIsNotOurs() {
        let command = "\"\(ours)-2/it2\" handle-agent-hook"
        XCTAssertFalse(ClaudeCodeOnboarding.hookCommand(command, belongsToDotDir: ours))
    }

    func testSomeoneElsesHookIsNotOurs() {
        XCTAssertFalse(ClaudeCodeOnboarding.hookCommand("/usr/local/bin/notify", belongsToDotDir: ours))
        XCTAssertFalse(ClaudeCodeOnboarding.hookCommand("", belongsToDotDir: ours))
    }

    // MARK: - Commands the user wrote (issue 13099)

    private let home = ["HOME": "/Users/gnachman"]

    // A path through $HOME or ~ is judged by where it expands to.
    func testAPathThroughHomeIsJudgedByWhereItLeads() {
        XCTAssertTrue(ClaudeCodeOnboarding.hookCommand("$HOME/.config/iterm2-alt7/cc-status",
                                                       belongsToDotDir: ours, environment: home))
        XCTAssertTrue(ClaudeCodeOnboarding.hookCommand("~/.config/iterm2-alt7/it2 handle-agent-hook",
                                                       belongsToDotDir: ours, environment: home))
        XCTAssertFalse(ClaudeCodeOnboarding.hookCommand("$HOME/.config/iterm2/it2 handle-agent-hook",
                                                        belongsToDotDir: ours, environment: home))
    }

    // A wrapper is ours when the hook it runs is in our dot dir, even though it also names it
    // in a test.
    func testAWrapperAroundOurHookIsOurs() {
        let wrapper = "[ -x \"$HOME/.config/iterm2-alt7/it2\" ] || exit 0; " +
            "exec \"$HOME/.config/iterm2-alt7/it2\" handle-agent-hook"
        XCTAssertTrue(ClaudeCodeOnboarding.hookCommand(wrapper, belongsToDotDir: ours, environment: home))
    }

    // Nothing in these names a path anywhere else, so they count as this instance's, as they
    // count as working: a bare name found through PATH, or one that needs the shell to resolve.
    func testAReferenceWithNoExplicitPathElsewhereIsOurs() {
        XCTAssertTrue(ClaudeCodeOnboarding.hookCommand("it2 handle-agent-hook", belongsToDotDir: ours))
        XCTAssertTrue(ClaudeCodeOnboarding.hookCommand("cc-status", belongsToDotDir: ours))
        XCTAssertTrue(ClaudeCodeOnboarding.hookCommand("$(brew --prefix)/bin/cc-status", belongsToDotDir: ours))
        XCTAssertTrue(ClaudeCodeOnboarding.hookCommand("$UNSET/cc-status", belongsToDotDir: ours, environment: home))
    }

    // MARK: - Which directory may an install strip?

    // The core of the 2026-09-27 data loss: with nothing recorded, the default
    // was assumed to be the previous location and stripped. A directory this
    // instance never wrote to may hold another instance's install.
    func testNothingRecordedMeansNothingToStrip() {
        XCTAssertNil(ClaudeCodeOnboarding.directoryToStrip(
            afterInstallingInto: URL(fileURLWithPath: "/Users/gnachman/.config/iterm2-alt7/claude"),
            recorded: nil))
        XCTAssertNil(ClaudeCodeOnboarding.directoryToStrip(
            afterInstallingInto: URL(fileURLWithPath: "/Users/gnachman/.config/iterm2-alt7/claude"),
            recorded: ""))
    }

    func testUnchangedDirectoryIsNotStripped() {
        let dir = "/Users/gnachman/.claude"
        XCTAssertNil(ClaudeCodeOnboarding.directoryToStrip(
            afterInstallingInto: URL(fileURLWithPath: dir),
            recorded: dir))
    }

    // Trailing-slash and normalization differences are the same directory. URL
    // equality would call these different and strip the file just written.
    func testTrailingSlashIsTheSameDirectory() {
        XCTAssertNil(ClaudeCodeOnboarding.directoryToStrip(
            afterInstallingInto: URL(fileURLWithPath: "/Users/gnachman/.claude"),
            recorded: "/Users/gnachman/.claude/"))
    }

    // The legitimate case this exists for: we really did move, so our hook must
    // stop firing from a file nothing will read again.
    // MARK: - Health on disk, which is what Try It Now now consults

    /// A settings.json whose hook entries all run `command`, for every event the health check
    /// requires.
    private func writeSettings(hookCommand command: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hookhealth-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        var hooks: [String: Any] = [:]
        for event in ClaudeCodeOnboarding.hookEventNames {
            hooks[event] = [["hooks": [["type": "command", "command": command]]]]
        }
        let url = dir.appendingPathComponent("settings.json")
        try JSONSerialization.data(withJSONObject: ["hooks": hooks]).write(to: url)
        return url
    }

    // The 2026-09-27 shape: ~/.claude full of a DIFFERENT instance's entries. It must read as not
    // installed here, so Try It Now opens the installer instead of assuming all is well.
    func testAnotherInstancesHooksAreNotHealthyForUs() throws {
        let url = try writeSettings(hookCommand: "\(theirs)/cc-status")
        XCTAssertFalse(ClaudeCodeOnboarding.hooksHealthyOnDisk(settingsURL: url))
    }

    func testAMissingSettingsFileIsNotHealthy() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("definitely-absent-\(UUID().uuidString)/settings.json")
        XCTAssertFalse(ClaudeCodeOnboarding.hooksHealthyOnDisk(settingsURL: url))
    }

    func testARecordedMoveIsStripped() {
        let old = "/Users/gnachman/.claude"
        let stripped = ClaudeCodeOnboarding.directoryToStrip(
            afterInstallingInto: URL(fileURLWithPath: "/Users/gnachman/.config/iterm2-alt7/claude"),
            recorded: old)
        XCTAssertEqual(stripped?.standardizedFileURL.path, old)
    }
}
