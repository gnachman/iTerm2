import XCTest
@testable import iTerm2SharedARC

final class HarnessDirectorySidebarTests: XCTestCase {
    func testResumeRequiresExplicitIdentityAndSupportedHarness() {
        XCTAssertEqual(SessionDirectorySidebar.resumeArguments(harness: "Codex", conversationID: "abc"), ["resume", "abc"])
        XCTAssertEqual(SessionDirectorySidebar.resumeArguments(harness: "Claude", conversationID: "abc"), ["--resume", "abc"])
        XCTAssertNil(SessionDirectorySidebar.resumeArguments(harness: "Codex", conversationID: "--last"))
        XCTAssertNil(SessionDirectorySidebar.resumeArguments(harness: "Codex", conversationID: ""))
        XCTAssertNil(SessionDirectorySidebar.resumeArguments(harness: "Aider", conversationID: "abc"))
    }

    func testAttachmentCommandPreservesSocketAndPaneArguments() {
        let arguments = ["/opt/bin/tmux", "-N", "-S", "/tmp/a b;$(echo unsafe)'socket", "attach-session", "-t", "%42"]
        XCTAssertEqual((SessionDirectorySidebar.shellCommand(arguments) as NSString).componentsInShellCommand(), arguments)
    }

    func testMachineWideDiscoveryFindsExternalTerminalHarness() throws {
        // A harmless process with a harness argv[0], in an independent PTY. No actual agent runs.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", "/bin/zsh", "-c", "exec -a claude /bin/sleep 30"]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "TMUX")
        environment.removeValue(forKey: "TMUX_PANE")
        process.environment = environment
        try process.run()
        var discovered: HarnessProcessDiscovery.Harness?
        defer {
            if let discovered { kill(discovered.pid, SIGTERM) }
            if process.isRunning { process.terminate() }
        }
        let found = expectation(description: "external harness discovered without an iTerm session")
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if let item = HarnessProcessDiscovery.scan().first(where: { $0.ancestors.contains(process.processIdentifier) }) {
                discovered = item
                timer.invalidate()
                found.fulfill()
            }
        }
        defer { timer.invalidate() }
        wait(for: [found], timeout: 10)
        XCTAssertEqual(discovered?.name, "Claude")
        XCTAssertNil(discovered?.tmuxSocket)
        XCTAssertNotNil(discovered?.directory)
    }

    func testDiscoveryCollapsesOnlySameTerminalLauncherChildren() {
        func item(_ pid: Int32, ancestors: [Int32], tty: UInt64) -> HarnessProcessDiscovery.Harness {
            .init(pid: pid, started: Date(timeIntervalSince1970: 1), name: "Codex", directory: "/work",
                  ancestors: ancestors, tty: tty, tmuxSocket: nil, tmuxPane: nil)
        }
        let parent = item(10, ancestors: [1], tty: 100)
        let wrapperChild = item(11, ancestors: [10, 1], tty: 100)
        let separateTerminal = item(12, ancestors: [10, 1], tty: 200)
        XCTAssertEqual(HarnessProcessDiscovery.deduplicated([parent, wrapperChild, separateTerminal]).map { $0.pid }, [10, 12])
        XCTAssertEqual(HarnessProcessDiscovery.socketPath("/tmp/with,comma/server,123,0"), "/tmp/with,comma/server")
        XCTAssertNil(HarnessProcessDiscovery.socketPath("invalid"))
    }

    func testSidebarShortcutRequiresCommandOption() {
        func event(_ flags: NSEvent.ModifierFlags, character: String, code: UInt16 = 18) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                            windowNumber: 0, context: nil, characters: character,
                            charactersIgnoringModifiers: character, isARepeat: false, keyCode: code)!
        }
        XCTAssertEqual(SessionDirectorySidebar.shortcutIndex(event([.command, .option], character: "1")), 0)
        XCTAssertNil(SessionDirectorySidebar.shortcutIndex(event([.command], character: "1")))
        XCTAssertNil(SessionDirectorySidebar.shortcutIndex(event([.option], character: "1")))
        XCTAssertNil(SessionDirectorySidebar.shortcutIndex(event([.command, .option, .shift], character: "1")))
    }

    func testDirectoryIdentity() {
        func key(_ host: String?, _ user: String?, _ path: String?, _ id: String = "a") -> SessionDirectoryKey {
            SessionDirectoryKey(host: host, user: user, path: path, sessionID: id)
        }
        XCTAssertEqual(key("host", "user", "/work/"), key("host", "user", "/work", "b"))
        XCTAssertNotEqual(key("host", "user", "/work"), key("other", "user", "/work"))
        XCTAssertNotEqual(key("host", "user", "/work"), key("host", "other", "/work"))
        XCTAssertNotEqual(key(nil, nil, nil), key(nil, nil, nil, "b"))
        XCTAssertNil(key(nil, nil, "~/work").path)
        XCTAssertEqual(key(nil, nil, "/").path, "/")
        XCTAssertEqual(key(nil, nil, "///").path, "/")
        XCTAssertEqual(key(nil, nil, "/work//").path, "/work")
    }

    func testHarnessExecutableDetectionRejectsTitlesAndArguments() {
        XCTAssertEqual(SessionDirectoryKey.harnessName(executable: "/opt/bin/codex"), "Codex")
        XCTAssertEqual(SessionDirectoryKey.harnessName(executable: "claude"), "Claude")
        XCTAssertEqual(SessionDirectoryKey.harnessName(executable: "agy"), "Antigravity")
        XCTAssertEqual(SessionDirectoryKey.harnessName(executable: "node", arguments: ["node", "/tools/node_modules/@openai/codex/bin/codex.js"]), "Codex")
        XCTAssertNil(SessionDirectoryKey.harnessName(executable: "node", arguments: ["node", "/app.js", "codex"]))
        for executable in ["vim", "tmux", "echo codex", "codex project", "not-claude", "zsh"] {
            XCTAssertNil(SessionDirectoryKey.harnessName(executable: executable))
        }
    }

    func testTmuxSocketArgumentsPreserveSpacesAndExcludeConfigAndCommands() {
        XCTAssertEqual(HarnessTmuxProbe.socketArguments([
            "tmux", "-S", "/tmp/server with spaces", "-f", "/tmp/config", "-u", "attach-session", "-t", "work"
        ]), ["-S", "/tmp/server with spaces"])
        XCTAssertEqual(HarnessTmuxProbe.socketArguments(["tmux", "-Lnamed", "attach"]), ["-L", "named"])
        XCTAssertEqual(HarnessTmuxProbe.socketArguments(["tmux", "attach"]), [])
        XCTAssertNil(HarnessTmuxProbe.socketArguments(["tmux", "-S"]))
    }

    func testTmuxSelectsOnlyMatchingClientMetadata() {
        let text = "10\u{1f}%1\u{1f}vim\u{1f}/elsewhere\u{1f}101\n20\u{1f}%3\u{1f}codex\u{1f}/work with spaces\u{1f}202\n"
        let pane = HarnessTmuxProbe.parse(text, clientPID: 20)
        XCTAssertEqual(pane?.command, "codex")
        XCTAssertEqual(pane?.path, "/work with spaces")
        XCTAssertEqual(pane?.id, "%3")
        XCTAssertEqual(pane?.pid, 202)
        XCTAssertNil(HarnessTmuxProbe.parse(text, clientPID: 99))
        XCTAssertNil(HarnessTmuxProbe.parse("broken", clientPID: 20))
    }
}
