//
//  ClaudeCodeOnboardingTests.swift
//  iTerm2 ModernTests
//
//  Offline coverage for the two pure helpers behind the Claude Code
//  integration's CLAUDE_CONFIG_DIR support:
//
//  - parseCLAUDE_CONFIG_DIR(from:) extracts the variable from `/usr/bin/env`
//    output. Returning nil for "absent" is load-bearing: the caller falls back
//    to the default directory only when the variable is genuinely unset.
//  - stripCCStatusHooks(fromSettingsURL:) removes our cc-status hook entries
//    from a settings.json, pruning emptied containers and leaving unrelated
//    hooks intact. It backs both Uninstall and the reinstall-into-a-new-dir
//    cleanup, so its result codes and pruning behavior matter. It also covers
//    the settings write that Install shares: a symlinked settings.json (a
//    dotfiles manager's link) must stay a link, with the change in its target.
//

import XCTest
@testable import iTerm2SharedARC

final class ClaudeCodeOnboardingTests: XCTestCase {

    // MARK: - parseCLAUDE_CONFIG_DIR

    func testParseValuePresent() {
        let out = "PATH=/usr/bin\nCLAUDE_CONFIG_DIR=/work/.claude\nHOME=/Users/x"
        XCTAssertEqual(ClaudeCodeOnboarding.parseCLAUDE_CONFIG_DIR(from: out), "/work/.claude")
    }

    func testParseValueAbsentReturnsNil() {
        let out = "PATH=/usr/bin\nHOME=/Users/x"
        XCTAssertNil(ClaudeCodeOnboarding.parseCLAUDE_CONFIG_DIR(from: out))
    }

    func testParseValueContainingEquals() {
        // Only the first '=' delimits key from value; the rest is value.
        let out = "CLAUDE_CONFIG_DIR=/a=b/c"
        XCTAssertEqual(ClaudeCodeOnboarding.parseCLAUDE_CONFIG_DIR(from: out), "/a=b/c")
    }

    func testParseDoesNotMatchPrefixedKey() {
        // A different variable that merely starts with the name must not match.
        let out = "CLAUDE_CONFIG_DIRX=/nope\nOTHER=1"
        XCTAssertNil(ClaudeCodeOnboarding.parseCLAUDE_CONFIG_DIR(from: out))
    }

    func testParseEmptyValue() {
        // Present but empty: parse returns "" (the caller treats empty as unset).
        let out = "CLAUDE_CONFIG_DIR=\nPATH=/usr/bin"
        XCTAssertEqual(ClaudeCodeOnboarding.parseCLAUDE_CONFIG_DIR(from: out), "")
    }

    // MARK: - stripCCStatusHooks

    private func makeTempSettings(_ json: Any) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cc-strip-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("settings.json")
        let data = try! JSONSerialization.data(withJSONObject: json, options: [])
        try! data.write(to: url)
        return url
    }

    private func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func testStripMissingFileIsSuccess() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cc-strip-missing-\(UUID().uuidString)")
            .appendingPathComponent("settings.json")
        XCTAssertEqual(ClaudeCodeOnboarding.stripCCStatusHooks(fromSettingsURL: url), .success)
    }

    func testStripMalformedJSON() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cc-strip-bad-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("settings.json")
        try! "{ not json".data(using: .utf8)!.write(to: url)
        XCTAssertEqual(ClaudeCodeOnboarding.stripCCStatusHooks(fromSettingsURL: url), .malformed)
    }

    func testStripNoHooksKeyIsSuccess() {
        let url = makeTempSettings(["model": "opus"])
        XCTAssertEqual(ClaudeCodeOnboarding.stripCCStatusHooks(fromSettingsURL: url), .success)
        // Unrelated content preserved.
        XCTAssertEqual(readJSON(url)?["model"] as? String, "opus")
    }

    func testStripRemovesCCStatusAndPrunesEmptyContainers() {
        let settings: [String: Any] = [
            "hooks": [
                "Stop": [
                    ["hooks": [["type": "command", "command": "/x/y/cc-status"]]]
                ]
            ]
        ]
        let url = makeTempSettings(settings)
        XCTAssertEqual(ClaudeCodeOnboarding.stripCCStatusHooks(fromSettingsURL: url), .success)
        // The only hook was ours: the emptied event group, the "Stop" event, and
        // the now-empty top-level "hooks" dict should all be pruned.
        let result = readJSON(url)
        XCTAssertNil(result?["hooks"], "empty hooks dict should be pruned; got \(String(describing: result))")
    }

    func testStripLeavesForeignHookUntouched() {
        let settings: [String: Any] = [
            "hooks": [
                "Stop": [
                    ["hooks": [
                        ["type": "command", "command": "/x/y/cc-status"],
                        ["type": "command", "command": "/usr/local/bin/other-hook"],
                    ]]
                ]
            ]
        ]
        let url = makeTempSettings(settings)
        XCTAssertEqual(ClaudeCodeOnboarding.stripCCStatusHooks(fromSettingsURL: url), .success)
        // The foreign hook survives; only cc-status is gone.
        guard let hooks = readJSON(url)?["hooks"] as? [String: Any],
              let stop = hooks["Stop"] as? [[String: Any]],
              let group = stop.first,
              let entries = group["hooks"] as? [[String: Any]] else {
            XCTFail("expected surviving Stop hook group")
            return
        }
        let commands = entries.compactMap { $0["command"] as? String }
        XCTAssertEqual(commands, ["/usr/local/bin/other-hook"])
    }

    // MARK: - Writing settings.json through a symlink

    // Lay out settings.json the way a dotfiles manager (GNU Stow, chezmoi)
    // does: the real file lives in dotfiles/ with mode 0600 and
    // .claude/settings.json is a symlink to it. Stow makes relative links.
    private func makeSymlinkedSettings(_ json: Any, relative: Bool) -> (link: URL, target: URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cc-strip-link-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let dotfiles = dir.appendingPathComponent("dotfiles")
        let claudeDir = dir.appendingPathComponent(".claude")
        try! FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let target = dotfiles.appendingPathComponent("settings.json")
        let data = try! JSONSerialization.data(withJSONObject: json, options: [])
        try! data.write(to: target)
        try! FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        let link = claudeDir.appendingPathComponent("settings.json")
        try! FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: relative ? "../dotfiles/settings.json" : target.path)
        return (link, target)
    }

    private func assertStripWritesThroughSymlink(relative: Bool,
                                                 file: StaticString = #filePath,
                                                 line: UInt = #line) {
        let settings: [String: Any] = [
            "model": "opus",
            "hooks": [
                "Stop": [
                    ["hooks": [["type": "command", "command": "/x/y/cc-status"]]]
                ]
            ]
        ]
        let (link, target) = makeSymlinkedSettings(settings, relative: relative)
        let destination = try! FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        XCTAssertEqual(ClaudeCodeOnboarding.stripCCStatusHooks(fromSettingsURL: link), .success,
                       file: file, line: line)

        // attributesOfItem doesn't follow a symlink in the last path component,
        // so this sees the link itself. It must still be a link, pointing where
        // it did before.
        let linkType = (try? FileManager.default.attributesOfItem(atPath: link.path))?[.type] as? FileAttributeType
        XCTAssertEqual(linkType, .typeSymbolicLink, "settings.json was replaced by a regular file",
                       file: file, line: line)
        XCTAssertEqual(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path), destination,
                       file: file, line: line)

        // The change landed in the link's target, and the target kept its mode.
        let result = readJSON(target)
        XCTAssertNil(result?["hooks"], "target still has hooks; got \(String(describing: result))",
                     file: file, line: line)
        XCTAssertEqual(result?["model"] as? String, "opus", file: file, line: line)
        let mode = (try? FileManager.default.attributesOfItem(atPath: target.path))?[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600, file: file, line: line)
    }

    func testStripThroughAbsoluteSymlinkKeepsLink() {
        assertStripWritesThroughSymlink(relative: false)
    }

    func testStripThroughRelativeSymlinkKeepsLink() {
        assertStripWritesThroughSymlink(relative: true)
    }
}
