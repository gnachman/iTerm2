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

    // The installer and the step's pre-check ask at once: one lookup answers both, so they can't
    // disagree about where the settings are.
    func testConcurrentRequestsShareOneLookup() {
        let memory = ClaudeCodeRemoteConnectionFacts()
        let connection = NSObject()
        var lookups = [(String?) -> Void]()
        var answers = [String?]()
        for _ in 0..<2 {
            memory.configDirectory(for: connection, lookUp: { lookups.append($0) }) { answers.append($0) }
        }
        XCTAssertEqual(lookups.count, 1)
        lookups[0]("/srv/claude")
        XCTAssertEqual(answers, ["/srv/claude", "/srv/claude"])
        memory.configDirectory(for: connection, lookUp: { lookups.append($0) }) { answers.append($0) }
        XCTAssertEqual(lookups.count, 1, "remembered for the connection")
        XCTAssertEqual(answers.last, "/srv/claude")
    }

    // A failure is not remembered: the next request looks again.
    func testAFailedLookupIsTriedAgain() {
        let memory = ClaudeCodeRemoteConnectionFacts()
        let connection = NSObject()
        var lookups = [(String?) -> Void]()
        var answers = [String?]()
        memory.configDirectory(for: connection, lookUp: { lookups.append($0) }) { answers.append($0) }
        lookups[0](nil)
        XCTAssertEqual(answers, [nil])
        memory.configDirectory(for: connection, lookUp: { lookups.append($0) }) { answers.append($0) }
        XCTAssertEqual(lookups.count, 2)
        lookups[1]("/home/u/.claude")
        XCTAssertEqual(answers, [nil, "/home/u/.claude"])
        XCTAssertNil(memory.configDirectory(for: NSObject()))
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

    // A host that is this Mac reached over ssh is not offered: Install refuses it, and its
    // settings belong to the local uninstall (QA finding F-606).
    @MainActor
    func testThisMacIsNotOffered() async {
        let hosts = await ClaudeCodeUninstallTargets.excludingThisMac(["u@a", "me@localhost", "u@b"]) { host in
            host == "me@localhost"
        }
        XCTAssertEqual(hosts, ["u@a", "u@b"])
    }
}
