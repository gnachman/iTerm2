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
//  - mergeCCStatusHooks(intoSettingsURL:...) is Install's merge. It must never
//    rewrite a settings.json it can't read or parse as a JSON object, since
//    that would throw away the user's other settings.
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

    func testStripRemovesWrapperButKeepsCompoundCommand() {
        let wrapper = "[ -x \"$HOME/x/cc-status\" ] || exit 0; exec \"$HOME/x/cc-status\""
        let compound = "$HOME/x/cc-status && /usr/local/bin/notify"
        let redirect = "echo done > /tmp/cc-status"
        let settings: [String: Any] = [
            "hooks": [
                "Stop": [
                    ["hooks": [
                        ["type": "command", "command": wrapper],
                        ["type": "command", "command": compound],
                        ["type": "command", "command": redirect],
                    ]]
                ]
            ]
        ]
        let url = makeTempSettings(settings)
        XCTAssertEqual(ClaudeCodeOnboarding.stripCCStatusHooks(fromSettingsURL: url), .success)
        guard let hooks = readJSON(url)?["hooks"] as? [String: Any],
              let stop = hooks["Stop"] as? [[String: Any]],
              let group = stop.first,
              let entries = group["hooks"] as? [[String: Any]] else {
            XCTFail("expected surviving Stop hook group")
            return
        }
        let commands = entries.compactMap { $0["command"] as? String }
        XCTAssertEqual(commands, [compound, redirect])
    }

    // Uninstall sets the installed flag from hooksInstalled(atSettingsURL:),
    // which is also what the next launch's reconcile reads. After a strip it
    // must report exactly the commands left behind, or the menu flips back.
    func testInstalledStateAfterStrip() {
        let compound = "~/.config/iterm2/cc-status && say done"
        func settings(_ commands: [String]) -> [String: Any] {
            let entries = commands.map { ["type": "command", "command": $0] }
            return ["hooks": ["Stop": [["hooks": entries]], "Notification": [["hooks": entries]]]]
        }

        let removed = makeTempSettings(settings(["/x/y/cc-status", "/usr/local/bin/other-hook"]))
        XCTAssertTrue(ClaudeCodeOnboarding.hooksInstalled(atSettingsURL: removed))
        XCTAssertEqual(ClaudeCodeOnboarding.stripCCStatusHooks(fromSettingsURL: removed), .success)
        XCTAssertFalse(ClaudeCodeOnboarding.hooksInstalled(atSettingsURL: removed))

        let kept = makeTempSettings(settings(["/x/y/cc-status", compound]))
        XCTAssertEqual(ClaudeCodeOnboarding.stripCCStatusHooks(fromSettingsURL: kept), .success)
        XCTAssertTrue(ClaudeCodeOnboarding.hooksInstalled(atSettingsURL: kept))
        let remaining = readJSON(kept).map(ClaudeCodeOnboarding.ccStatusCommands(inSettings:))
        XCTAssertEqual(remaining, [compound, compound])
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

    // MARK: - mergeCCStatusHooks (Install / Reinstall)

    private func makeTempSettingsBytes(_ text: String) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cc-merge-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("settings.json")
        try! text.data(using: .utf8)!.write(to: url)
        return url
    }

    private let mergeCCStatusPath = "/Users/test/.config/iterm2/cc-status"

    private func merge(_ url: URL) -> ClaudeCodeInstallHooksResult {
        return ClaudeCodeOnboarding.mergeCCStatusHooks(intoSettingsURL: url,
                                                       ccStatusPath: mergeCCStatusPath,
                                                       environment: [:])
    }

    // A settings.json with a syntax error holds the user's other settings
    // (permissions, env, model). Install must refuse to touch it rather than
    // replace it with a file holding only our hooks.
    func testMergeLeavesUnparseableFileByteIdentical() {
        let original = "{ not json,\n  \"model\": \"opus\"\n"
        let url = makeTempSettingsBytes(original)
        XCTAssertEqual(merge(url), .malformed)
        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), original)
    }

    func testMergeLeavesNonObjectJSONByteIdentical() {
        let original = "[ {\"model\": \"opus\"} ]\n"
        let url = makeTempSettingsBytes(original)
        XCTAssertEqual(merge(url), .malformed)
        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), original)
    }

    // An empty settings.json (say, from `touch`) holds nothing to lose, so
    // Install treats it like a missing file rather than refusing.
    func testMergeIntoEmptyFileSucceeds() {
        let url = makeTempSettingsBytes(" \n")
        XCTAssertEqual(merge(url), .success)
        let commands = readJSON(url).map(ClaudeCodeOnboarding.ccStatusCommands(inSettings:)) ?? []
        XCTAssertEqual(commands.count, ClaudeCodeOnboarding.hookEventNames.count)
    }

    // Writing through a dangling symlink replaces the link with a regular
    // file. An atomic write over the link used to carry the link's own mode
    // (0755) to the new file, making settings.json executable. It must get
    // the mode any newly created file gets.
    func testMergeThroughDanglingSymlinkCreatesFileWithDefaultMode() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cc-merge-dangling-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let claudeDir = dir.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let link = claudeDir.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(atPath: link.path,
                                                   withDestinationPath: "../dotfiles/settings.json")
        let reference = claudeDir.appendingPathComponent("reference")
        try Data("{}".utf8).write(to: reference)

        XCTAssertEqual(merge(link), .success)

        let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeRegular)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue
        let expected = (try FileManager.default.attributesOfItem(atPath: reference.path)[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(mode, expected)
        XCTAssertEqual((mode ?? 0) & 0o111, 0, "settings.json is executable")
        let commands = readJSON(link).map(ClaudeCodeOnboarding.ccStatusCommands(inSettings:)) ?? []
        XCTAssertEqual(commands.count, ClaudeCodeOnboarding.hookEventNames.count)
        // No temporary file left behind.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: claudeDir.path).sorted(),
                       ["reference", "settings.json"])
    }

    // When the dangling link's directory isn't writable, the error shown to
    // the user must name settings.json, not the hidden temporary file the
    // write goes through.
    func testMergeThroughDanglingSymlinkInReadOnlyDirectoryNamesSettingsFile() throws {
        try XCTSkipIf(geteuid() == 0, "root can write to a mode 500 directory")
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cc-merge-dangling-ro-\(UUID().uuidString)")
        let claudeDir = dir.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: claudeDir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let link = claudeDir.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(atPath: link.path,
                                                   withDestinationPath: "../nowhere/settings.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: claudeDir.path)

        guard case .writeFailed(let description) = merge(link) else {
            XCTFail("Expected writeFailed")
            return
        }
        XCTAssertTrue(description.contains("\u{201C}settings.json\u{201D}"), description)
        XCTAssertFalse(description.contains(".settings.json."), description)
    }

    func testMergeLeavesUnreadableFileUntouched() throws {
        try XCTSkipIf(geteuid() == 0, "root can read a mode 000 file")
        let original = "{\"model\": \"opus\"}"
        let url = makeTempSettingsBytes(original)
        try! FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        XCTAssertEqual(merge(url), .unreadable)
        try! FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), original)
    }

    func testMergeIntoValidFileKeepsOtherSettings() {
        let url = makeTempSettingsBytes("""
            {"model": "opus", "permissions": {"allow": ["Bash(ls)"]},
             "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "/usr/local/bin/mine"}]}]}}
            """)
        XCTAssertEqual(merge(url), .success)
        let result = readJSON(url)
        XCTAssertEqual(result?["model"] as? String, "opus")
        XCTAssertEqual((result?["permissions"] as? [String: Any])?["allow"] as? [String], ["Bash(ls)"])
        let commands = result.map(ClaudeCodeOnboarding.ccStatusCommands(inSettings:)) ?? []
        XCTAssertEqual(commands.count, ClaudeCodeOnboarding.hookEventNames.count)
        XCTAssertTrue(commands.allSatisfy { $0 == mergeCCStatusPath })
        // The user's own Stop hook survives alongside ours.
        let stopGroups = (result?["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]] ?? []
        let stopCommands = stopGroups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        XCTAssertEqual(Set(stopCommands), Set(["/usr/local/bin/mine", mergeCCStatusPath]))
    }

    func testMergeCreatesMissingFile() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cc-merge-missing-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        XCTAssertEqual(merge(url), .success)
        let commands = readJSON(url).map(ClaudeCodeOnboarding.ccStatusCommands(inSettings:)) ?? []
        XCTAssertEqual(commands.count, ClaudeCodeOnboarding.hookEventNames.count)
    }

    // Uninstall's strip must likewise never rewrite a file it can't parse.
    func testStripLeavesNonObjectJSONByteIdentical() {
        let original = "[ {\"hooks\": {}} ]\n"
        let url = makeTempSettingsBytes(original)
        XCTAssertEqual(ClaudeCodeOnboarding.stripCCStatusHooks(fromSettingsURL: url), .malformed)
        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), original)
    }

    func testStripLeavesUnparseableFileByteIdentical() {
        let original = "{ not json,\n"
        let url = makeTempSettingsBytes(original)
        XCTAssertEqual(ClaudeCodeOnboarding.stripCCStatusHooks(fromSettingsURL: url), .malformed)
        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), original)
    }

    // An empty or whitespace-only settings.json has no hooks to remove, and
    // Install accepts it, so Uninstall must not call it unparseable. Nothing
    // to change means the file is left as it was.
    func testStripEmptyFileIsSuccessAndUntouched() {
        for original in ["", "  \n\t\n"] {
            let url = makeTempSettingsBytes(original)
            XCTAssertEqual(ClaudeCodeOnboarding.stripCCStatusHooks(fromSettingsURL: url), .success,
                           "for \(original.debugDescription)")
            XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), original)
        }
    }

    // MARK: - stripStaleCCStatusHooks (Install into a changed directory)

    // A real directory with Install's hooks already merged into its
    // settings.json, as installHookFilesOnBackgroundQueue leaves it right
    // before the stale-hook strip.
    private func makeInstalledConfigDirectory() -> (root: URL, configDir: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cc-stale-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let configDir = root.appendingPathComponent("claude")
        try! FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let settings = configDir.appendingPathComponent("settings.json")
        try! "{\"model\": \"x\"}".data(using: .utf8)!.write(to: settings)
        XCTAssertEqual(merge(settings), .success)
        return (root, configDir)
    }

    private func ccStatusCount(inConfigDirectory dir: URL) -> Int {
        let url = dir.appendingPathComponent("settings.json")
        return readJSON(url).map(ClaudeCodeOnboarding.ccStatusCommands(inSettings:))?.count ?? 0
    }

    private func volumeIsCaseSensitive(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        return values?.volumeSupportsCaseSensitiveNames ?? true
    }

    // F-274: ~/.claude -> ~/dotfiles/claude and CLAUDE_CONFIG_DIR names
    // ~/dotfiles/claude. Both paths are the same directory, so the strip must
    // not remove the hooks Install just wrote, whichever way round they are.
    func testStaleStripSkipsSymlinkedAliasOfNewDirectory() throws {
        let (root, configDir) = makeInstalledConfigDirectory()
        let alias = root.appendingPathComponent("dot-claude")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: configDir)

        XCTAssertFalse(ClaudeCodeOnboarding.stripStaleCCStatusHooks(previousDirectory: alias,
                                                                     newConfigDirectory: configDir))
        XCTAssertEqual(ccStatusCount(inConfigDirectory: configDir), ClaudeCodeOnboarding.hookEventNames.count)

        XCTAssertFalse(ClaudeCodeOnboarding.stripStaleCCStatusHooks(previousDirectory: configDir,
                                                                     newConfigDirectory: alias))
        XCTAssertEqual(ccStatusCount(inConfigDirectory: configDir), ClaudeCodeOnboarding.hookEventNames.count)
    }

    // F-274: real ~/.claude and CLAUDE_CONFIG_DIR=$HOME/.Claude on a
    // case-insensitive volume name the same directory.
    func testStaleStripSkipsCaseVariantOfNewDirectory() throws {
        let (root, configDir) = makeInstalledConfigDirectory()
        try XCTSkipIf(volumeIsCaseSensitive(root), "test volume is case-sensitive")
        let variant = root.appendingPathComponent("Claude")

        XCTAssertFalse(ClaudeCodeOnboarding.stripStaleCCStatusHooks(previousDirectory: configDir,
                                                                     newConfigDirectory: variant))
        XCTAssertEqual(ccStatusCount(inConfigDirectory: configDir), ClaudeCodeOnboarding.hookEventNames.count)

        XCTAssertFalse(ClaudeCodeOnboarding.stripStaleCCStatusHooks(previousDirectory: variant,
                                                                     newConfigDirectory: configDir))
        XCTAssertEqual(ccStatusCount(inConfigDirectory: configDir), ClaudeCodeOnboarding.hookEventNames.count)
    }

    // Two distinct directories whose settings.json files are links to one
    // file (a dotfiles manager linking the same settings into both). Stripping
    // the old one would strip the file Install just wrote.
    func testStaleStripSkipsOldSettingsThatIsTheNewFile() throws {
        let (root, configDir) = makeInstalledConfigDirectory()
        let otherDir = root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: otherDir.appendingPathComponent("settings.json"),
                                                   withDestinationURL: configDir.appendingPathComponent("settings.json"))

        XCTAssertFalse(ClaudeCodeOnboarding.stripStaleCCStatusHooks(previousDirectory: otherDir,
                                                                     newConfigDirectory: configDir))
        XCTAssertEqual(ccStatusCount(inConfigDirectory: configDir), ClaudeCodeOnboarding.hookEventNames.count)
    }

    // A genuinely different previous directory still loses its stale hook.
    func testStaleStripRemovesHookFromDifferentDirectory() throws {
        let (root, configDir) = makeInstalledConfigDirectory()
        let newDir = root.appendingPathComponent("work-claude")
        try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        XCTAssertEqual(merge(newDir.appendingPathComponent("settings.json")), .success)

        XCTAssertTrue(ClaudeCodeOnboarding.stripStaleCCStatusHooks(previousDirectory: configDir,
                                                                    newConfigDirectory: newDir))
        XCTAssertEqual(ccStatusCount(inConfigDirectory: configDir), 0)
        XCTAssertEqual(ccStatusCount(inConfigDirectory: newDir), ClaudeCodeOnboarding.hookEventNames.count)
    }

    // The same directory spelled with and without a trailing slash or a
    // redundant component is not a change.
    func testStaleStripSkipsSameDirectorySpelledDifferently() {
        let (root, configDir) = makeInstalledConfigDirectory()
        let spelled = URL(fileURLWithPath: root.path + "/./claude/")
        XCTAssertFalse(ClaudeCodeOnboarding.stripStaleCCStatusHooks(previousDirectory: spelled,
                                                                     newConfigDirectory: configDir))
        XCTAssertEqual(ccStatusCount(inConfigDirectory: configDir), ClaudeCodeOnboarding.hookEventNames.count)
    }
}
