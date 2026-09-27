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
//    cleanup, so its result codes and pruning behavior matter.
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
}
