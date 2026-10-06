//
//  ClaudeCodeRemoteConnectionFactsTests.swift
//  iTerm2 ModernTests
//
//  Nothing about remote hosts is written to disk. What iTerm2 learns about a host while connected
//  (where Claude Code keeps its settings there, whether iTerm2's hook is in them) is kept per
//  connection, in memory, and goes away with the connection.
//

import XCTest
@testable import iTerm2SharedARC

final class ClaudeCodeRemoteConnectionFactsTests: XCTestCase {
    func testFactsBelongToTheConnection() {
        let memory = ClaudeCodeRemoteConnectionFacts()
        let a = NSObject()
        let b = NSObject()
        memory.setConfigDirectory("/srv/claude", for: a)
        memory.setHookPresent(true, for: a)
        XCTAssertEqual(memory.configDirectory(for: a), "/srv/claude")
        XCTAssertEqual(memory.hookPresent(for: a), true)
        XCTAssertNil(memory.configDirectory(for: b))
        XCTAssertNil(memory.hookPresent(for: b))
    }

    // Gone with the connection: nothing outlives it.
    func testFactsGoAwayWithTheConnection() {
        let memory = ClaudeCodeRemoteConnectionFacts()
        autoreleasepool {
            let connection = NSObject()
            memory.setHookPresent(true, for: connection)
            XCTAssertTrue(memory.anyHookPresent)
        }
        XCTAssertFalse(memory.anyHookPresent)
    }

    // The default matches Claude Code's own when CLAUDE_CONFIG_DIR is unset; trailing slashes
    // do not double up.
    func testSettingsPath() {
        XCTAssertEqual(ClaudeCodeRemoteConnectionFacts.settingsPath(configDirectory: nil, home: "/home/u/"),
                       "/home/u/.claude/settings.json")
        XCTAssertEqual(ClaudeCodeRemoteConnectionFacts.settingsPath(configDirectory: "/srv/claude/", home: "/home/u"),
                       "/srv/claude/settings.json")
    }
}

// Uninstall can only edit a host it is connected to, so it offers the connected ones.
final class ClaudeCodeUninstallTargetsTests: XCTestCase {
    func testOneEntryPerConnectedHostInOrder() {
        let hosts = ClaudeCodeUninstallTargets.hosts(connections: [("u@b", true), ("u@a", true), ("u@b", true), ("u@c", false)])
        XCTAssertEqual(hosts, ["u@a", "u@b"])
    }
}
