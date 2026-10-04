//
//  ClaudeCodeRemoteHostStateTests.swift
//  iTerm2 ModernTests
//
//  Per-host Claude Code integration state for hosts reached through SSH Integration (Phase 4a).
//  The existing local settings stay the record for this Mac; this covers every other host,
//  keyed by SSHIdentity.stringIdentifier.
//

import XCTest
@testable import iTerm2SharedARC

private final class MemoryHostStateBacking: ClaudeCodeRemoteHostStateBacking {
    var configDirPathByHost: [String: String] = [:]
    var hooksInstalledHosts: [String] = []
}

final class ClaudeCodeRemoteHostStateTests: XCTestCase {
    // MARK: - Config directory

    // Nothing resolved yet: Claude Code's own default, under that host's home.
    func testSettingsPathDefaultsToDotClaudeUnderTheRemoteHome() {
        let state = ClaudeCodeRemoteHostState(backing: MemoryHostStateBacking())
        XCTAssertNil(state.configDirectoryPath(forHost: "u@h"))
        XCTAssertEqual(state.settingsPath(forHost: "u@h", home: "/home/u"),
                       "/home/u/.claude/settings.json")
    }

    func testRecordedConfigDirectoryIsUsed() {
        let backing = MemoryHostStateBacking()
        let state = ClaudeCodeRemoteHostState(backing: backing)
        state.recordConfigDirectory("/srv/claude-work", forHost: "u@h")
        XCTAssertEqual(state.settingsPath(forHost: "u@h", home: "/home/u"),
                       "/srv/claude-work/settings.json")
        XCTAssertEqual(ClaudeCodeRemoteHostState(backing: backing).configDirectoryPath(forHost: "u@h"),
                       "/srv/claude-work", "persisted, not just held in memory")
    }

    // Each host resolves its own CLAUDE_CONFIG_DIR; one host's must never leak to another.
    func testConfigDirectoriesAreKeptPerHost() {
        let state = ClaudeCodeRemoteHostState(backing: MemoryHostStateBacking())
        state.recordConfigDirectory("/a/claude", forHost: "u@a")
        XCTAssertNil(state.configDirectoryPath(forHost: "u@b"))
        XCTAssertEqual(state.settingsPath(forHost: "u@b", home: "/home/u"),
                       "/home/u/.claude/settings.json")
    }

    // A trailing slash from a user's CLAUDE_CONFIG_DIR must not produce "//settings.json".
    func testTrailingSlashIsTolerated() {
        let state = ClaudeCodeRemoteHostState(backing: MemoryHostStateBacking())
        state.recordConfigDirectory("/srv/claude/", forHost: "u@h")
        XCTAssertEqual(state.settingsPath(forHost: "u@h", home: "/home/u"), "/srv/claude/settings.json")
        XCTAssertEqual(state.settingsPath(forHost: "u@x", home: "/home/u/"), "/home/u/.claude/settings.json")
    }

    // An empty value is "not resolved", not a directory named "".
    func testEmptyRecordedDirectoryFallsBackToTheDefault() {
        let backing = MemoryHostStateBacking()
        backing.configDirPathByHost = ["u@h": ""]
        let state = ClaudeCodeRemoteHostState(backing: backing)
        XCTAssertNil(state.configDirectoryPath(forHost: "u@h"))
        XCTAssertEqual(state.settingsPath(forHost: "u@h", home: "/home/u"), "/home/u/.claude/settings.json")
    }

    // MARK: - Installed hosts

    func testInstalledHostsRoundTrip() {
        let backing = MemoryHostStateBacking()
        let state = ClaudeCodeRemoteHostState(backing: backing)
        XCTAssertFalse(state.hooksInstalled(onHost: "u@h"))
        state.setHooksInstalled(true, onHost: "u@h")
        XCTAssertTrue(ClaudeCodeRemoteHostState(backing: backing).hooksInstalled(onHost: "u@h"))
        state.setHooksInstalled(false, onHost: "u@h")
        XCTAssertFalse(state.hooksInstalled(onHost: "u@h"))
    }

    // Marking a host twice must not list it twice, or uninstall would offer it twice.
    func testInstallingTwiceListsTheHostOnce() {
        let state = ClaudeCodeRemoteHostState(backing: MemoryHostStateBacking())
        state.setHooksInstalled(true, onHost: "u@h")
        state.setHooksInstalled(true, onHost: "u@h")
        XCTAssertEqual(state.hostsWithHooksInstalled, ["u@h"])
    }

    // Sorted so menus and uninstall offer hosts in a stable order.
    func testInstalledHostsAreSorted() {
        let state = ClaudeCodeRemoteHostState(backing: MemoryHostStateBacking())
        for host in ["u@zeta", "u@alpha", "u@host10", "u@host9"] {
            state.setHooksInstalled(true, onHost: host)
        }
        XCTAssertEqual(state.hostsWithHooksInstalled, ["u@alpha", "u@host9", "u@host10", "u@zeta"])
    }

    // Uninstalling keeps the resolved directory, as the local scalar does: a reinstall should go
    // back to the same place without asking the host again.
    func testUninstallKeepsTheConfigDirectory() {
        let state = ClaudeCodeRemoteHostState(backing: MemoryHostStateBacking())
        state.recordConfigDirectory("/srv/claude", forHost: "u@h")
        state.setHooksInstalled(true, onHost: "u@h")
        state.setHooksInstalled(false, onHost: "u@h")
        XCTAssertEqual(state.configDirectoryPath(forHost: "u@h"), "/srv/claude")
    }
}

final class ClaudeCodeUninstallTargetsTests: XCTestCase {
    // Uninstalling on a host means editing its file, which needs a live connection. A host without
    // one is reported, not dropped: its install stays recorded until it can really be removed.
    func testHostsSplitByWhetherTheyCanBeReachedNow() {
        let targets = ClaudeCodeUninstallTargets(installedHosts: ["u@a", "u@b", "u@c"],
                                                 isReachable: { $0 != "u@b" })
        XCTAssertEqual(targets.reachable, ["u@a", "u@c"])
        XCTAssertEqual(targets.unreachable, ["u@b"])
    }

    func testOrderIsKept() {
        let targets = ClaudeCodeUninstallTargets(installedHosts: ["u@z", "u@a"], isReachable: { _ in true })
        XCTAssertEqual(targets.reachable, ["u@z", "u@a"])
        XCTAssertEqual(targets.unreachable, [])
    }
}
