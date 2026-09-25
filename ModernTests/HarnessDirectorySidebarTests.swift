import XCTest
@testable import iTerm2SharedARC

final class HarnessDirectorySidebarTests: XCTestCase {
    func testTransferRejectsReusedPIDAndCurrentProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        let started = try XCTUnwrap(iTermLSOF.startTime(forProcess: process.processIdentifier))
        XCTAssertFalse(HarnessProcessDiscovery.signalTransferProcesses([
            (process.processIdentifier, started.addingTimeInterval(-1))]))
        XCTAssertTrue(process.isRunning)
        let ownStarted = try XCTUnwrap(iTermLSOF.startTime(forProcess: getpid()))
        XCTAssertFalse(HarnessProcessDiscovery.signalTransferProcesses([(getpid(), ownStarted)]))
    }

    func testTransferWaitsForExitAndDoesNotForceKillOnTimeout() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        let started = try XCTUnwrap(iTermLSOF.startTime(forProcess: process.processIdentifier))
        let targets = [(process.processIdentifier, started)]
        let timeout = expectation(description: "Running original blocks replacement")
        HarnessProcessDiscovery.waitForTransferExit(targets, deadline: .now()) { exited in
            XCTAssertFalse(exited)
            timeout.fulfill()
        }
        wait(for: [timeout], timeout: 5)
        XCTAssertTrue(process.isRunning)
        XCTAssertTrue(HarnessProcessDiscovery.signalTransferProcesses(targets))
        let stopped = expectation(description: "Replacement allowed only after original exits")
        HarnessProcessDiscovery.waitForTransferExit(targets, deadline: .now() + 5) { exited in
            XCTAssertTrue(exited)
            stopped.fulfill()
        }
        wait(for: [stopped], timeout: 10)
    }

    func testDiscoveryFindsTmuxPaneWithClearedEnvironment() throws {
        guard let tmux = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"].first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else { throw XCTSkip("tmux is not installed") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("harness-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Keep the UNIX socket below macOS's path-length limit, including long TMPDIRs.
        let socket = "/tmp/iterm-harness-" + UUID().uuidString
        func command(_ arguments: [String]) throws -> String {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: tmux)
            process.arguments = ["-N", "-S", socket, "-f", "/dev/null"] + arguments
            // The first command must be allowed to start this isolated fixture server.
            if arguments.first == "new-session" { process.arguments?.removeFirst() }
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        }
        defer {
            _ = try? command(["kill-server"])
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(atPath: socket)
        }
        _ = try command(["new-session", "-d", "-s", "fixture", "-c", directory.path,
                         "/usr/bin/env -i /bin/zsh -c 'exec -a claude /bin/sleep 30'"])
        let panePID = Int32(try command(["list-panes", "-a", "-F", "#{pane_pid}"]).trimmingCharacters(in: .whitespacesAndNewlines))
        let found = expectation(description: "tmux identity recovered without environment markers")
        var discovered: HarnessProcessDiscovery.Harness?
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if let item = HarnessProcessDiscovery.scan().first(where: { $0.pid == panePID }) {
                discovered = item
                timer.invalidate()
                found.fulfill()
            }
        }
        defer { timer.invalidate() }
        wait(for: [found], timeout: 10)
        XCTAssertEqual(discovered?.tmuxSocket, socket)
        XCTAssertEqual(discovered?.tmuxPane, "%0")
        XCTAssertEqual(discovered?.name, "Claude")
        if let discovered {
            XCTAssertFalse((iTermLSOF.environment(forProcess: discovered.pid) ?? []).contains { $0.hasPrefix("TMUX=") })
        }
    }

    func testServerPaneMetadataParsing() {
        let panes = HarnessTmuxProbe.parseServerPanes("123\u{1f}%4\u{1f}/tmp/server with spaces\nbad\n")
        XCTAssertEqual(panes.count, 1)
        XCTAssertEqual(panes.first?.pid, 123)
        XCTAssertEqual(panes.first?.socket, "/tmp/server with spaces")
    }

    func testResumeIdentityUsesProviderConversationPaths() {
        let id = "01234567-89ab-4cde-8fab-0123456789ab"
        XCTAssertEqual(HarnessProcessDiscovery.conversationID(harness: "Codex",
            path: "/home/.codex/sessions/2026/rollout-date-" + id + ".jsonl"), id)
        XCTAssertEqual(HarnessProcessDiscovery.conversationID(harness: "Claude",
            path: "/home/.claude/projects/work/" + id + ".jsonl"), id)
        XCTAssertEqual(HarnessProcessDiscovery.conversationID(harness: "Antigravity",
            path: "/home/.gemini/antigravity-cli/conversations/" + id + ".db"), id)
        XCTAssertNil(HarnessProcessDiscovery.conversationID(harness: "Codex", path: "/tmp/" + id + ".jsonl"))
        XCTAssertNil(HarnessProcessDiscovery.conversationID(harness: "Claude", path: "/projects/work/not-an-id.jsonl"))
    }

    func testResumeTargetUsesOpenTranscriptAndRejectsAmbiguousIdentity() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let id = UUID().uuidString.lowercased()
        let first = folder.appendingPathComponent("rollout-date-" + id + ".jsonl")
        try Data("{}\n".utf8).write(to: first)
        let handle = try FileHandle(forReadingFrom: first)
        defer { try? handle.close() }
        let pid = ProcessInfo.processInfo.processIdentifier
        let harness = HarnessProcessDiscovery.Harness(pid: pid, started: iTermLSOF.startTime(forProcess: pid)!,
            name: "Codex", directory: folder.path, ancestors: [], tty: 0, tmuxSocket: nil, tmuxPane: nil)
        guard case .success(let identity) = HarnessProcessDiscovery.conversationIdentity(for: harness) else {
            return XCTFail("Expected the open transcript to identify the conversation")
        }
        XCTAssertEqual(identity.conversationID, id)
        XCTAssertEqual(URL(fileURLWithPath: identity.transcript).lastPathComponent, first.lastPathComponent)
        let second = folder.appendingPathComponent("rollout-date-" + UUID().uuidString + ".jsonl")
        try Data("{}\n".utf8).write(to: second)
        let other = try FileHandle(forReadingFrom: second)
        defer { try? other.close() }
        XCTAssertEqual(HarnessProcessDiscovery.conversationIdentity(for: harness),
                       .failure(.identityUnavailable))
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

    func testProjectShortcutsRespectConfiguredModifiersAndAvailableProjects() {
        let projectMask: NSEvent.ModifierFlags = [.command, .option]
        let tabMask: NSEvent.ModifierFlags = [.command]
        func action(_ flags: NSEvent.ModifierFlags, _ digit: Int, _ projectCount: Int = 2,
                    _ filterActive: Bool = true) -> SessionDirectorySidebar.ShortcutAction {
            SessionDirectorySidebar.shortcutAction(flags: flags, digit: digit,
                projectMask: projectMask, tabMask: tabMask,
                projectCount: projectCount, filterActive: filterActive)
        }
        XCTAssertEqual(action(projectMask, 1), .project(0))
        XCTAssertEqual(action(projectMask, 3), .pass)
        XCTAssertEqual(action(tabMask, 1), .tab(0))
        XCTAssertEqual(action(tabMask, 9), .tab(8))
        XCTAssertEqual(action(tabMask, 1, 2, false), .pass)
        XCTAssertEqual(action([.command, .option, .shift], 1), .pass)
        XCTAssertEqual(action(projectMask, 0), .pass)
        XCTAssertEqual(SessionDirectorySidebar.shortcutAction(flags: tabMask, digit: 1,
            projectMask: projectMask, tabMask: nil, projectCount: 2, filterActive: true), .pass)
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

    func testProjectFilterReselectsOnlyForIntentionalProjectChanges() {
        XCTAssertFalse(SessionDirectorySidebar.projectFilterReselects(.refresh))
        XCTAssertTrue(SessionDirectorySidebar.projectFilterReselects(.projectChange))
        XCTAssertFalse(SessionDirectorySidebar.projectFilterReselects(.selectedTab))
    }

    func testWindowLocalArrivalAdoptsSelectedProjectWithoutStealingExistingKeys() {
        let project = SessionDirectoryKey(host: nil, user: nil, path: "/work", sessionID: "p")
        let other = SessionDirectoryKey(host: nil, user: nil, path: "/other", sessionID: "o")
        let keys = ["kept": other]
        XCTAssertEqual(SessionDirectorySidebar.adoptingWindowArrivals(
            keys: keys, previousWindowSessionIDs: nil, windowSessionIDs: ["moved"], selectedProject: project), keys)
        XCTAssertEqual(SessionDirectorySidebar.adoptingWindowArrivals(
            keys: keys, previousWindowSessionIDs: [], windowSessionIDs: ["moved"], selectedProject: nil), keys)
        let adopted = SessionDirectorySidebar.adoptingWindowArrivals(
            keys: keys,
            previousWindowSessionIDs: ["kept"],
            windowSessionIDs: ["kept", "moved"],
            selectedProject: project)
        XCTAssertEqual(adopted["kept"], other)
        XCTAssertEqual(adopted["moved"], project)
        let stable = SessionDirectorySidebar.adoptingWindowArrivals(
            keys: adopted,
            previousWindowSessionIDs: ["kept", "moved"],
            windowSessionIDs: ["kept", "moved"],
            selectedProject: project)
        XCTAssertEqual(stable, adopted)
    }

    func testHarnessOperationReservationIsAppWide() {
        let id = "harness-reservation-" + UUID().uuidString
        defer { SessionDirectorySidebar.releaseHarnessOperation(id) }
        XCTAssertTrue(SessionDirectorySidebar.reserveHarnessOperation(id))
        XCTAssertFalse(SessionDirectorySidebar.reserveHarnessOperation(id),
                       "a second window must not stop or attach a harness that is already reserved")
        SessionDirectorySidebar.releaseHarnessOperation(id)
        XCTAssertTrue(SessionDirectorySidebar.reserveHarnessOperation(id))
    }

    func testReplacementLaunchFailureNamesSavedHandoff() {
        let path = "/tmp/handoff dir/token.json"
        let message = SessionDirectorySidebar.replacementLaunchFailureMessage(handoffPath: path)
        XCTAssertTrue(message.contains(path))
    }

    func testTransferTimeoutNamesSavedHandoff() {
        let path = "/tmp/handoff dir/token.json"
        let message = SessionDirectorySidebar.transferFailureMessage(.didNotExit, handoffPath: path)
        XCTAssertTrue(message.contains(path))
    }
}
