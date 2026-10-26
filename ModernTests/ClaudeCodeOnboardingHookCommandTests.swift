//
//  ClaudeCodeOnboardingHookCommandTests.swift
//  ModernTests
//
//  The installer, the health check and the uninstaller all have to recognize the hook entries
//  iTerm2 wrote into settings.json. Historically that ran cc-status; new installs write
//  `"<dotdir>/it2" handle-agent-hook`, a quoted executable plus a subcommand, and both forms must
//  be recognized for as long as old installs exist, including the ways users rewrite them
//  (CCStatusHookCommand, issue 13099).
//

import XCTest
@testable import iTerm2SharedARC

final class ClaudeCodeOnboardingHookCommandTests: XCTestCase {
    // Ownership is scoped to THIS instance's dot dir, so the commands under test have to be
    // built from the real one rather than a fictional path: a hook in someone else's dot dir is
    // deliberately not ours (see ClaudeCodeHookOwnershipTests).
    private var dotDir: String {
        return FileManager.default.homeDirectoryDotDir() ?? "/tmp/no-dot-dir"
    }

    func testNewFormIsBuiltFromTheIt2Path() {
        XCTAssertEqual(ClaudeCodeOnboarding.hookCommand(it2Path: "\(dotDir)/it2"),
                       "\"\(dotDir)/it2\" handle-agent-hook")
    }

    private typealias H = CCStatusHookCommand

    func testRecognizesBothForms() {
        XCTAssertTrue(H.refersToCCStatus("/Users/x/.config/iterm2/cc-status"))
        XCTAssertTrue(H.refersToCCStatus("\"/Users/x/.config/iterm2/it2\" handle-agent-hook"))
        XCTAssertTrue(H.refersToCCStatus("\"/Users/x/.config/iterm2/it2\" handle-agent-hook --agent codex"))
        XCTAssertTrue(H.refersToCCStatus("$HOME/.config/iterm2/it2 handle-agent-hook"))
        XCTAssertTrue(H.refersToCCStatus("it2 handle-agent-hook"))
        XCTAssertTrue(ClaudeCodeOnboarding.isOurHookCommand("\(dotDir)/cc-status"))
        XCTAssertTrue(ClaudeCodeOnboarding.isOurHookCommand("\"\(dotDir)/it2\" handle-agent-hook"))
        XCTAssertTrue(ClaudeCodeOnboarding.isOurHookCommand("\"\(dotDir)/it2\" handle-agent-hook --agent codex"))
    }

    func testDoesNotClaimForeignCommands() {
        XCTAssertFalse(H.refersToCCStatus("/usr/local/bin/some-other-hook"))
        XCTAssertFalse(H.refersToCCStatus("\"/Users/x/.config/iterm2/it2\" session list"))
        XCTAssertFalse(H.refersToCCStatus("/Users/x/bin/cc-status-wrapper"))
        // it2 as an argument, or handle-agent-hook as something else's argument, is just text.
        XCTAssertFalse(H.refersToCCStatus("echo it2 handle-agent-hook"))
        XCTAssertFalse(H.refersToCCStatus("notify handle-agent-hook"))
        XCTAssertFalse(H.refersToCCStatus("it2 > handle-agent-hook"))
        XCTAssertFalse(ClaudeCodeOnboarding.isOurHookCommand("/usr/local/bin/some-other-hook"))
        XCTAssertFalse(ClaudeCodeOnboarding.isOurHookCommand("\"\(dotDir)/it2\" session list"))
        XCTAssertFalse(ClaudeCodeOnboarding.isOurHookCommand("/Users/x/bin/cc-status-wrapper"))
    }

    // The health check tests the program the hook runs, which for the new form is the quoted
    // path, not the whole command string.
    func testResolvesTheProgramOfEitherForm() {
        let executable: (String) -> Bool = { $0.hasPrefix("/Users/x") }
        XCTAssertEqual(H.resolutions(of: "/Users/x/.config/iterm2/cc-status", environment: [:], isExecutable: executable),
                       [.executable("/Users/x/.config/iterm2/cc-status")])
        XCTAssertEqual(H.resolutions(of: "\"/Users/x y/.config/iterm2/it2\" handle-agent-hook", environment: [:],
                                     isExecutable: executable),
                       [.executable("/Users/x y/.config/iterm2/it2")])
        XCTAssertEqual(H.resolutions(of: "\"/gone/it2\" handle-agent-hook", environment: [:], isExecutable: executable),
                       [.notExecutable("/gone/it2")])
        XCTAssertEqual(H.resolutions(of: "it2 handle-agent-hook", environment: ["PATH": "/Users/x/bin"],
                                     isExecutable: executable),
                       [.executable("/Users/x/bin/it2")])
        XCTAssertTrue(H.needsEnvironment("it2 handle-agent-hook"))
        XCTAssertFalse(H.needsEnvironment("\"/Users/x/.config/iterm2/it2\" handle-agent-hook"))
    }

    // What an installer writes, which a reinstall may point somewhere else. A command the user
    // wrote is kept unless it can't run.
    func testInstallerForm() {
        XCTAssertTrue(H.isInstallerForm("/Users/x/.config/iterm2/cc-status"))
        XCTAssertTrue(H.isInstallerForm("\"/Users/x/.config/iterm2-alt4/it2\" handle-agent-hook"))
        XCTAssertTrue(H.isInstallerForm("\"/Users/x y/.config/iterm2/it2\" handle-agent-hook --agent codex"))
        XCTAssertFalse(H.isInstallerForm("$HOME/.config/iterm2/it2 handle-agent-hook"))
        XCTAssertFalse(H.isInstallerForm("/Users/x/.config/iterm2/it2 handle-agent-hook"), "unquoted: the user's")
        XCTAssertFalse(H.isInstallerForm("\"/Users/x/.config/iterm2/it2\" handle-agent-hook; say done"))
        XCTAssertFalse(H.isInstallerForm("\"/Users/x/.config/iterm2/it2\" handle-agent-hook --verbose"))
    }

    // A wrapper around the new form is recognized like one around cc-status (issue 13099), and
    // one that also runs something of the user's is left alone.
    func testWrappersOfTheNewForm() {
        let wrapper = "[ -x \"$HOME/.config/iterm2/it2\" ] || exit 0; exec \"$HOME/.config/iterm2/it2\" handle-agent-hook"
        XCTAssertTrue(H.refersToCCStatus(wrapper))
        XCTAssertTrue(H.runsOnlyCCStatus(wrapper))
        XCTAssertFalse(H.runsOnlyCCStatus("\"/Users/x/.config/iterm2/it2\" handle-agent-hook && say done"))
        XCTAssertTrue(H.runsOnlyCCStatus("\"/Users/x/.config/iterm2/it2\" handle-agent-hook --agent codex"))
    }

    // Uninstall strips the new form the same way it strips the old one.
    func testStripRemovesNewFormEntries() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cc-strip-new-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("settings.json")
        let json: [String: Any] = [
            "hooks": [
                "Stop": [
                    ["hooks": [["type": "command", "command": "\"\(dotDir)/it2\" handle-agent-hook"]]],
                    ["hooks": [["type": "command", "command": "/usr/local/bin/other"]]],
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        XCTAssertEqual(ClaudeCodeOnboarding.stripCCStatusHooks(fromSettingsURL: url), .success)

        let after = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let hooks = try XCTUnwrap(after["hooks"] as? [String: Any])
        let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stop.count, 1)
        let remaining = try XCTUnwrap((stop[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String)
        XCTAssertEqual(remaining, "/usr/local/bin/other")
    }

    // MARK: - Merging our entries into a settings.json hooks dictionary

    private func commands(_ hooks: [String: Any], _ event: String) -> [String] {
        let groups = hooks[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    private var it2: String { return "\"\(dotDir)/it2\" handle-agent-hook" }

    func testMergeAddsEveryEventToAnEmptyFile() {
        let merged = ClaudeCodeOnboarding.mergedHooks([:], command: it2)
        XCTAssertEqual(merged.count, 10)
        for event in merged.keys {
            XCTAssertEqual(commands(merged, event), [it2], event)
        }
    }

    func testMergeRewritesAStaleEntryOfOursInPlace() {
        // The old cc-status form, in OUR dot dir: that is what "stale entry of ours" means now.
        // The same entry under another instance's dot dir is that instance's business, covered
        // by ClaudeCodeHookOwnershipTests.
        let hooks: [String: Any] = ["Stop": [["hooks": [["type": "command", "command": "\(dotDir)/cc-status"]]]]]
        let merged = ClaudeCodeOnboarding.mergedHooks(hooks, command: it2)
        XCTAssertEqual(commands(merged, "Stop"), [it2])
    }

    func testMergeLeavesForeignEntriesAlone() {
        let hooks: [String: Any] = ["Stop": [["hooks": [["type": "command", "command": "/usr/local/bin/other-hook"]]]]]
        let merged = ClaudeCodeOnboarding.mergedHooks(hooks, command: it2)
        XCTAssertEqual(commands(merged, "Stop"), ["/usr/local/bin/other-hook", it2])
    }

    // Two installs from different instances can leave several entries of ours per
    // event (seen 2026-09-28: two identical it2 entries plus a cc-status one).
    // Claude Code would run the hook three times per event. One survives.
    func testMergeCollapsesDuplicateEntriesOfOurs() {
        let hooks: [String: Any] = ["Stop": [
            ["hooks": [["type": "command", "command": it2], ["type": "command", "command": it2]]],
            ["hooks": [["type": "command", "command": "\(dotDir)/cc-status"],
                       ["type": "command", "command": "/usr/local/bin/other-hook"]]],
        ]]
        let merged = ClaudeCodeOnboarding.mergedHooks(hooks, command: it2)
        XCTAssertEqual(commands(merged, "Stop"), [it2, "/usr/local/bin/other-hook"])
        // A group emptied by the cleanup is dropped rather than left as an empty list.
        let groups = merged["Stop"] as? [[String: Any]] ?? []
        XCTAssertTrue(groups.allSatisfy { !(($0["hooks"] as? [[String: Any]]) ?? []).isEmpty })
    }

    // MARK: - Health of a settings.json

    // The installer pre-marks its hook step from the directory the lookups resolved,
    // not from the one recorded by an earlier install, so the check is given the
    // settings themselves (checkHooksHealth reads them from a URL).
    func testHealthyWhenEveryEventRunsAnExecutableOfOurs() {
        let ours = "/Users/x/.config/iterm2"
        let it2Path = ours + "/it2"
        let command = ClaudeCodeOnboarding.hookCommand(it2Path: it2Path)
        let healthy: [String: Any] = ["hooks": ClaudeCodeOnboarding.mergedHooks([:], command: command)]
        let executable: (String) -> Bool = { $0 == it2Path }
        XCTAssertTrue(ClaudeCodeOnboarding.hooksHealthy(inSettings: healthy, environment: [:], dotDir: ours,
                                                        isExecutable: executable))

        var partial = ClaudeCodeOnboarding.mergedHooks([:], command: command)
        partial["Stop"] = nil
        XCTAssertFalse(ClaudeCodeOnboarding.hooksHealthy(inSettings: ["hooks": partial], environment: [:], dotDir: ours,
                                                         isExecutable: executable),
                       "a missing event is unhealthy")
        XCTAssertFalse(ClaudeCodeOnboarding.hooksHealthy(inSettings: healthy, environment: [:], dotDir: ours,
                                                         isExecutable: { _ in false }),
                       "a non-executable program is unhealthy")
        XCTAssertFalse(ClaudeCodeOnboarding.hooksHealthy(inSettings: healthy, environment: [:],
                                                         dotDir: "/Users/x/.config/iterm2-alt4", isExecutable: executable),
                       "another instance's hook is not this one's")
    }

    // An entry the user wrote that also runs their own program is never removed as a duplicate.
    func testMergeKeepsAnEntryThatAlsoRunsTheUsersProgram() {
        let mine = "\"/Users/x/.config/iterm2/it2\" handle-agent-hook && say done"
        let hooks: [String: Any] = ["Stop": [["hooks": [["type": "command", "command": it2],
                                                        ["type": "command", "command": mine]]]]]
        let merged = ClaudeCodeOnboarding.mergedHooks(hooks, command: it2, isExecutable: { _ in true })
        XCTAssertEqual(commands(merged, "Stop"), [it2, mine])
    }
}
