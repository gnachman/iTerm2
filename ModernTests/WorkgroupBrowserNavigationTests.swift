//
//  WorkgroupBrowserNavigationTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class WorkgroupBrowserNavigationTests: XCTestCase {
    private typealias Nav = WorkgroupBrowserNavigation

    private func config(id: String = UUID().uuidString,
                        parentID: String? = nil,
                        kind: iTermWorkgroupSessionConfig.Kind,
                        url: String = "",
                        name: String = "") -> iTermWorkgroupSessionConfig {
        return iTermWorkgroupSessionConfig(uniqueIdentifier: id,
                                           parentID: parentID,
                                           kind: kind,
                                           profileGUID: nil,
                                           command: "",
                                           urlString: url,
                                           toolbarItems: [],
                                           displayName: name)
    }

    func testShellQuoting() {
        XCTAssertEqual(Nav.shellQuoted("Browser"), "Browser")
        XCTAssertEqual(Nav.shellQuoted("Navigateur"), "Navigateur")
        XCTAssertEqual(Nav.shellQuoted("ブラウザ"), "ブラウザ")
        XCTAssertEqual(Nav.shellQuoted("Navegador-2"), "Navegador-2")
        XCTAssertEqual(Nav.shellQuoted("My Browser"), "'My Browser'")
        XCTAssertEqual(Nav.shellQuoted("George’s"), "'George’s'")
        XCTAssertEqual(Nav.shellQuoted("it's"), #"'it'\''s'"#)
        XCTAssertEqual(Nav.shellQuoted("$HOME"), "'$HOME'")
        XCTAssertEqual(Nav.shellQuoted(""), "''")
    }

    func testCommandAndAllowRuleUseStoredName() {
        let target = Nav.Target(peerName: "Mon navigateur", variablePath: "user.browserURL")
        XCTAssertEqual(Nav.command(for: target, url: "https://x/"),
                       "it2 session set-var --peer-name 'Mon navigateur' user.browserURL https://x/")
        XCTAssertEqual(Nav.claudeAllowRule(for: target),
                       "Bash(it2 session set-var --peer-name 'Mon navigateur' user.browserURL:*)")
    }

    func testCommandsCanNameIt2ByPath() {
        let target = Nav.Target(peerName: "Browser", variablePath: "user.browserURL")
        let it2 = "~/.config/iterm2/it2"
        XCTAssertEqual(Nav.claudeAllowRule(for: target, it2: it2),
                       "Bash(~/.config/iterm2/it2 session set-var --peer-name Browser user.browserURL:*)")
        XCTAssertTrue(Nav.agentInstructions(for: target, it2: it2)
            .hasSuffix("\n~/.config/iterm2/it2 session set-var --peer-name Browser user.browserURL '<URL>'"))
    }

    func testClaudeCodeIt2IsWrittenWithATilde() {
        let home = NSHomeDirectory()
        XCTAssertEqual(ClaudeCodeBrowserNavigation.it2(path: home + "/.config/iterm2/it2"),
                       "~/.config/iterm2/it2")
        XCTAssertEqual(ClaudeCodeBrowserNavigation.it2(path: home + "/.config/iterm2.suite/it2"),
                       "~/.config/iterm2.suite/it2")
        // A component that needs quoting can't follow an unquoted ~.
        XCTAssertEqual(ClaudeCodeBrowserNavigation.it2(path: home + "/My Config/it2"),
                       "'" + home + "/My Config/it2'")
        XCTAssertEqual(ClaudeCodeBrowserNavigation.it2(path: nil), "it2")
    }

    // Claude on a host reached through SSH Integration runs the wrapper there,
    // and the paths shown are that host's, with ~ for its home.
    func testRemoteLocation() {
        let location = ClaudeCodeConfigLocation.remote(.init(conductor: nil,
                                                             host: "u@example.com",
                                                             home: "/home/u/",
                                                             directory: "/home/u/.claude/"))
        XCTAssertTrue(location.isRemote)
        XCTAssertEqual(location.settingsPath, "/home/u/.claude/settings.json")
        XCTAssertEqual(location.claudeMDPath, "/home/u/.claude/CLAUDE.md")
        XCTAssertEqual(location.displayPath(location.claudeMDPath), "~/.claude/CLAUDE.md")
        XCTAssertEqual(location.displayPath("/etc/claude/CLAUDE.md"), "/etc/claude/CLAUDE.md")
        XCTAssertEqual(location.displayPath("/home/user2/x"), "/home/user2/x")
        XCTAssertNil(location.localSkillsURL)
        let target = Nav.Target(peerName: "Browser", variablePath: "user.browserURL")
        XCTAssertEqual(Nav.claudeAllowRule(for: target, it2: location.it2),
                       "Bash(~/.iterm2/bin/it2 session set-var --peer-name Browser user.browserURL:*)")
    }

    func testRemoteLocationAtTheRoot() {
        let location = ClaudeCodeConfigLocation.remote(.init(conductor: nil,
                                                             host: "u@example.com",
                                                             home: "/home/u",
                                                             directory: "/"))
        XCTAssertEqual(location.settingsPath, "/settings.json")
        XCTAssertEqual(location.claudeMDPath, "/CLAUDE.md")
        XCTAssertEqual(ClaudeCodeRemoteConnectionFacts.settingsPath(configDirectory: "/", home: "/home/u"),
                       "/settings.json")
    }

    func testLocalLocation() {
        let directory = URL(fileURLWithPath: NSHomeDirectory() + "/.claude")
        let location = ClaudeCodeConfigLocation.local(directory)
        XCTAssertFalse(location.isRemote)
        XCTAssertEqual(location.displayPath(location.settingsPath), "~/.claude/settings.json")
        XCTAssertEqual(location.localSkillsURL, directory.appendingPathComponent("skills"))
        XCTAssertEqual(location.it2, ClaudeCodeBrowserNavigation.it2)
    }

    // What was appended on a remote host is remembered by host, so a new
    // connection to it doesn't offer to append again, and not on disk.
    func testAppendedInstructionsAreRememberedPerHost() {
        func location(_ host: String) -> ClaudeCodeConfigLocation {
            return .remote(.init(conductor: nil, host: host, home: "/home/u", directory: "/home/u/.claude"))
        }
        let host = "u@\(UUID().uuidString).example.com"
        let defaults = UserDefaults(suiteName: "WorkgroupBrowserNavigationTests-\(UUID().uuidString)")!
        XCTAssertFalse(ClaudeCodeBrowserNavigation.instructionsAppended("text", in: location(host), defaults: defaults))
        ClaudeCodeBrowserNavigation.noteInstructionsAppended("text", in: location(host), defaults: defaults)
        XCTAssertTrue(ClaudeCodeBrowserNavigation.instructionsAppended("text", in: location(host), defaults: defaults))
        XCTAssertFalse(ClaudeCodeBrowserNavigation.instructionsAppended("text", in: location("other." + host), defaults: defaults))
        XCTAssertNil(defaults.dictionary(forKey: ClaudeCodeBrowserNavigation.appendedInstructionsKey))
    }

    func testInstructionsEndWithJustTheCommand() {
        let target = Nav.Target(peerName: "Browser", variablePath: "user.browserURL")
        let text = Nav.agentInstructions(for: target)
        // A bare command, so the allow rule covers all of it.
        XCTAssertTrue(text.hasSuffix("\nit2 session set-var --peer-name Browser user.browserURL '<URL>'"))
        XCTAssertTrue(text.contains("ignore any failure"))
    }

    func testTargetRequiresNameAndVariable() {
        XCTAssertEqual(Nav.target(for: config(kind: .peer, url: "\\(user.a)", name: "B"), isBrowser: { _ in true }),
                       Nav.Target(peerName: "B", variablePath: "user.a"))
        XCTAssertNil(Nav.target(for: config(kind: .peer, url: "\\(user.a)", name: ""), isBrowser: { _ in true }))
        XCTAssertNil(Nav.target(for: config(kind: .peer, url: "https://x/", name: "B"), isBrowser: { _ in true }))
        XCTAssertNil(Nav.target(for: config(kind: .peer, url: "\\(path)", name: "B"), isBrowser: { _ in true }))
        // The generated command sets one variable, so a URL needing two never forms.
        XCTAssertNil(Nav.target(for: config(kind: .peer, url: "https://x/\\(user.a)/\\(user.b)", name: "B"), isBrowser: { _ in true }))
        // The agent passes a whole URL, so text around the variable would
        // mangle it.
        XCTAssertNil(Nav.target(for: config(kind: .peer, url: "https://x/\\(user.a)/\\(user.a)", name: "B"), isBrowser: { _ in true }))
        XCTAssertNil(Nav.target(for: config(kind: .peer, url: "https://github.com/\\(user.a)", name: "B"), isBrowser: { _ in true }))
        // A terminal member keeps its URL after a profile change, but nothing would navigate.
        XCTAssertNil(Nav.target(for: config(kind: .peer, url: "\\(user.a)", name: "B"), isBrowser: { _ in false }))
    }

    func testAddingBrowserPeer() {
        let root = config(id: "root", kind: .root, name: "Chat")
        let workgroup = iTermWorkgroup(uniqueIdentifier: "w", name: "W", sessions: [root])
        let updated = Nav.addingBrowserPeer(to: workgroup, profileGUID: "guid")
        let peer = updated?.sessions.last
        XCTAssertEqual(updated?.sessions.count, 2)
        XCTAssertEqual(peer?.parentID, "root")
        XCTAssertEqual(peer?.kind, .peer)
        XCTAssertEqual(peer?.profileGUID, "guid")
        XCTAssertEqual(peer?.urlString, "\\(user.browserURL)")
        XCTAssertEqual(peer?.displayName, Nav.defaultPeerName)
        XCTAssertEqual(updated.map { Nav.targets(in: $0, isBrowser: { _ in true }) },
                       [Nav.Target(peerName: Nav.defaultPeerName, variablePath: "user.browserURL")])
    }

    func testAddingBrowserPeerKeepsNamesUnique() {
        let root = config(id: "root", kind: .root, name: "Chat")
        let taken = config(parentID: "root", kind: .peer, name: Nav.defaultPeerName.uppercased())
        let workgroup = iTermWorkgroup(uniqueIdentifier: "w", name: "W", sessions: [root, taken])
        let peer = Nav.addingBrowserPeer(to: workgroup, profileGUID: "guid")?.sessions.last
        XCTAssertEqual(peer?.displayName, "\(Nav.defaultPeerName) 2")
    }

    func testAddingBrowserPeerNeedsRoot() {
        let workgroup = iTermWorkgroup(uniqueIdentifier: "w", name: "W", sessions: [])
        XCTAssertNil(Nav.addingBrowserPeer(to: workgroup, profileGUID: "guid"))
    }

    func testAddingAllowRuleKeepsExistingSettings() throws {
        let settings: [String: Any] = [
            "model": "opus",
            "permissions": ["allow": ["Bash(ls:*)"], "deny": ["Bash(rm:*)"]],
        ]
        let result = try XCTUnwrap(ClaudeCodeBrowserNavigation.adding(allowRule: "Bash(x:*)", to: settings))
        XCTAssertEqual(result["model"] as? String, "opus")
        let permissions = result["permissions"] as? [String: Any]
        XCTAssertEqual(permissions?["allow"] as? [String], ["Bash(ls:*)", "Bash(x:*)"])
        XCTAssertEqual(permissions?["deny"] as? [String], ["Bash(rm:*)"])

        let again = try XCTUnwrap(ClaudeCodeBrowserNavigation.adding(allowRule: "Bash(x:*)", to: result))
        XCTAssertEqual((again["permissions"] as? [String: Any])?["allow"] as? [String], ["Bash(ls:*)", "Bash(x:*)"])
    }

    func testAddingAllowRuleToEmptySettings() throws {
        let result = try XCTUnwrap(ClaudeCodeBrowserNavigation.adding(allowRule: "Bash(x:*)", to: [:]))
        XCTAssertEqual((result["permissions"] as? [String: Any])?["allow"] as? [String], ["Bash(x:*)"])
    }

    // One entry that isn't a string mustn't hide the rest.
    func testAllowRulesSkipsEntriesThatAreNotStrings() {
        let settings: [String: Any] = ["permissions": ["allow": ["Bash(x:*)", 7, ["odd": true]]]]
        XCTAssertEqual(ClaudeCodeBrowserNavigation.allowRules(in: settings), ["Bash(x:*)"])
    }

    // Replacing a value of the wrong type would lose the user's entries.
    func testAddingAllowRuleRefusesPermissionsOfTheWrongType() {
        XCTAssertNil(ClaudeCodeBrowserNavigation.adding(allowRule: "Bash(x:*)",
                                                        to: ["permissions": ["allow": "Bash(git:*)"]]))
        XCTAssertNil(ClaudeCodeBrowserNavigation.adding(allowRule: "Bash(x:*)",
                                                        to: ["permissions": ["Bash(git:*)"]]))
    }
}
