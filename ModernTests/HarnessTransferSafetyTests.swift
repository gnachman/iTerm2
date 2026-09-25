import XCTest
@testable import iTerm2SharedARC

final class HarnessTransferSafetyTests: XCTestCase {
    private typealias Discovery = HarnessProcessDiscovery
    private let id = "01234567-89ab-4cde-8fab-0123456789ab"

    private func carried(_ harness: String, _ arguments: [String]) -> Result<[String], Discovery.TransferBlock> {
        Discovery.carriedArguments(harness: harness, arguments: arguments)
    }

    // MARK: - Launch options

    func testClaudeCarriesVerifiedOptionsAndReplacesConversationSelection() {
        XCTAssertEqual(carried("Claude", ["--model", "opus", "--permission-mode=plan", "--add-dir", "/a", "b",
                                          "--allowed-tools", "Read", "Bash(git:*)", "--verbose", "--continue",
                                          "-r", "old", "--session-id", id, "--fork-session"]),
                       .success(["--model", "opus", "--permission-mode=plan", "--add-dir", "/a", "b",
                                 "--allowed-tools", "Read", "Bash(git:*)", "--verbose"]))
        XCTAssertEqual(Discovery.resumeArguments(harness: "Claude", conversationID: id.uppercased(),
                                                 carried: ["--model", "opus"]),
                       ["--model", "opus", "--resume", id])
    }

    func testClaudeRefusesPromptsLaunchModesAndPermissionBypass() {
        XCTAssertEqual(carried("Claude", ["fix the bug"]), .failure(.unsupportedArguments([Discovery.promptArgument])))
        XCTAssertEqual(carried("Claude", ["--dangerously-skip-permissions"]),
                       .failure(.unsupportedArguments(["--dangerously-skip-permissions"])))
        XCTAssertEqual(carried("Claude", ["--permission-mode", "bypassPermissions"]),
                       .failure(.unsupportedArguments(["--permission-mode"])))
        XCTAssertEqual(carried("Claude", ["-p", "--worktree", "--tmux", "--unknown"]),
                       .failure(.unsupportedArguments(["-p", "--worktree", "--tmux", "--unknown"])))
        // A value-taking option at the end has no value to carry.
        XCTAssertEqual(carried("Claude", ["--model"]), .failure(.unsupportedArguments(["--model"])))
        // Everything after -- is a prompt.
        XCTAssertEqual(carried("Claude", ["--", "text"]), .failure(.unsupportedArguments([Discovery.promptArgument])))
    }

    func testRefusalsNameOptionsButNeverRevealValues() {
        let secret = "sk-secret-value"
        guard case .failure(.unsupportedArguments(let names)) = carried("Claude",
            ["--append-system-prompt", secret, "--permission-mode=" + secret, secret]) else {
            return XCTFail("Expected refusal")
        }
        XCTAssertFalse(names.contains { $0.contains(secret) })
        XCTAssertTrue(names.contains("--append-system-prompt"))
        XCTAssertTrue(names.contains("--permission-mode"))
    }

    func testCodexResumeSubcommandCarriesOptionsBeforeSessionID() {
        XCTAssertEqual(carried("Codex", ["-m", "gpt-5", "resume", "old-name", "--search", "-c", "model_reasoning_effort=\"high\"",
                                         "--sandbox", "workspace-write", "-a", "on-request", "--add-dir", "/repo", "--last"]),
                       .success(["-m", "gpt-5", "--search", "-c", "model_reasoning_effort=\"high\"",
                                 "--sandbox", "workspace-write", "-a", "on-request", "--add-dir", "/repo"]))
        XCTAssertEqual(Discovery.resumeArguments(harness: "Codex", conversationID: id, carried: ["-m", "gpt-5"]),
                       ["resume", "-m", "gpt-5", id])
    }

    func testCodexRefusesPermissionEscalationPromptsAndUnverifiedModes() {
        XCTAssertEqual(carried("Codex", ["--dangerously-bypass-approvals-and-sandbox"]),
                       .failure(.unsupportedArguments(["--dangerously-bypass-approvals-and-sandbox"])))
        XCTAssertEqual(carried("Codex", ["-s", "danger-full-access"]), .failure(.unsupportedArguments(["-s"])))
        XCTAssertEqual(carried("Codex", ["-a", "never"]), .failure(.unsupportedArguments(["-a"])))
        XCTAssertEqual(carried("Codex", ["-c", "sandbox_mode=\"danger-full-access\""]),
                       .failure(.unsupportedArguments(["-c"])))
        XCTAssertEqual(carried("Codex", ["-c", "approval_policy=never"]), .failure(.unsupportedArguments(["-c"])))
        XCTAssertEqual(carried("Codex", ["--add-dir", "relative"]), .failure(.unsupportedArguments(["--add-dir"])))
        XCTAssertEqual(carried("Codex", ["--worktree", "--remote", "ws://x", "--approve-for-me"]),
                       .failure(.unsupportedArguments(["--worktree", "--remote", Discovery.promptArgument, "--approve-for-me"])))
        XCTAssertEqual(carried("Codex", ["write tests"]), .failure(.unsupportedArguments([Discovery.promptArgument])))
        XCTAssertEqual(carried("Codex", ["resume", id, "and a prompt"]),
                       .failure(.unsupportedArguments([Discovery.promptArgument])))
        XCTAssertEqual(carried("Codex", ["fork", id]), .failure(.unsupportedArguments([Discovery.promptArgument])))
    }

    func testAntigravityAcceptsGoStyleFlags() {
        XCTAssertEqual(carried("Antigravity", ["-model", "m", "--mode=plan", "-sandbox", "-c", "--conversation", "old"]),
                       .success(["-model", "m", "--mode=plan", "-sandbox"]))
        XCTAssertEqual(carried("Antigravity", ["--dangerously-skip-permissions"]),
                       .failure(.unsupportedArguments(["--dangerously-skip-permissions"])))
        XCTAssertEqual(carried("Antigravity", ["--sandbox=false"]), .failure(.unsupportedArguments(["--sandbox"])))
        XCTAssertEqual(carried("Antigravity", ["-i", "prompt"]),
                       .failure(.unsupportedArguments(["-i", Discovery.promptArgument])))
        XCTAssertEqual(Discovery.resumeArguments(harness: "Antigravity", conversationID: id, carried: []),
                       ["--conversation", id])
    }

    func testResumeRequiresUUIDAndSupportedHarness() {
        XCTAssertNil(Discovery.resumeArguments(harness: "Codex", conversationID: "--last", carried: []))
        XCTAssertNil(Discovery.resumeArguments(harness: "Claude", conversationID: "", carried: []))
        XCTAssertNil(Discovery.resumeArguments(harness: "Aider", conversationID: id, carried: []))
        XCTAssertEqual(carried("Aider", []), .failure(.unsupportedHarness))
    }

    // MARK: - Environment

    func testEnvironmentReproducesRoutingAndNeverCopiesCredentials() {
        let result = Discovery.environmentArguments(
            original: ["ANTHROPIC_BASE_URL=https://proxy", "ANTHROPIC_API_KEY=same", "HOME=/x"],
            app: ["ANTHROPIC_API_KEY": "same", "OPENAI_API_KEY": "app-only", "AWS_PROFILE": "app"])
        XCTAssertEqual(result, .success(["-u", "OPENAI_API_KEY", "-u", "AWS_PROFILE", "ANTHROPIC_BASE_URL=https://proxy"]))
        if case .success(let arguments) = result {
            XCTAssertFalse(arguments.contains { $0.contains("same") || $0.contains("app-only") })
        }
    }

    func testEnvironmentRefusesCredentialsTheReplacementWouldNotHave() {
        XCTAssertEqual(Discovery.environmentArguments(original: ["ANTHROPIC_API_KEY=original", "AWS_SESSION_TOKEN=t"],
                                                      app: ["ANTHROPIC_API_KEY": "different"]),
                       .failure(.credentialEnvironment(["ANTHROPIC_API_KEY", "AWS_SESSION_TOKEN"])))
    }

    // MARK: - Multiplexers

    func testMultiplexerEvidenceIncludesClearedEnvironmentAndServerNames() {
        XCTAssertTrue(Discovery.multiplexerEvident(ancestorNames: ["/bin/zsh", "/opt/homebrew/bin/tmux\u{1f}tmux"], environment: []))
        XCTAssertTrue(Discovery.multiplexerEvident(ancestorNames: ["\u{1f}tmux: server"], environment: []))
        XCTAssertTrue(Discovery.multiplexerEvident(ancestorNames: ["SCREEN"], environment: []))
        XCTAssertTrue(Discovery.multiplexerEvident(ancestorNames: ["-zsh"], environment: ["TMUX_PANE=%1"]))
        XCTAssertTrue(Discovery.multiplexerEvident(ancestorNames: [], environment: ["STY=123.pts"]))
        XCTAssertFalse(Discovery.multiplexerEvident(ancestorNames: ["-zsh", "/usr/bin/login", "/Applications/iTerm.app/x/iTermServer"],
                                                    environment: ["TMUXINATOR_CONFIG=/x", "TERM=xterm"]))
    }

    func testUninspectableEnvironmentFailsClosed() {
        XCTAssertNil(Discovery.inspectableEnvironment(nil))
        XCTAssertNil(Discovery.inspectableEnvironment([]), "an empty or truncated read proves nothing")
        XCTAssertEqual(Discovery.inspectableEnvironment(["HOME=/x"]), ["HOME=/x"])
        // Discovery marks the harness tmux-unverified rather than native.
        XCTAssertTrue(Discovery.multiplexerEvident(ancestorNames: ["-zsh"], environment: nil))
    }

    func testUnverifiedMultiplexerHarnessIsNeverNative() {
        let harness = Discovery.Harness(pid: 10, started: Date(), name: "Claude", directory: "/w", ancestors: [],
                                        tty: 1, tmuxSocket: nil, tmuxPane: nil, tmuxUnverified: true)
        XCTAssertFalse(harness.isNative)
    }

    // MARK: - Claude record

    func testClaudeRecordRequiresLiveCorroboration() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let socket = "/tmp/cc-socks/42.sock"
        let record: [String: Any] = ["pid": 42, "sessionId": id.uppercased(), "startedAt": 1_000_000_500,
                                     "updatedAt": 1_000_100_000, "messagingSocketPath": socket, "status": "idle"]
        func check(_ changes: [String: Any?], sockets: Set<String> = [socket]) -> Result<String, Discovery.TransferBlock> {
            var copy = record
            for (key, value) in changes { copy[key] = value }
            return Discovery.claudeRecordSessionID(copy, pid: 42, processStart: start, heldSockets: sockets)
        }
        XCTAssertEqual(check([:]), .success(id))
        XCTAssertEqual(check([:], sockets: []), .failure(.identityUnavailable), "record not held by the live process")
        XCTAssertEqual(check(["pid": 43]), .failure(.identityUnavailable))
        XCTAssertEqual(check(["startedAt": 900_000_000]), .failure(.identityUnavailable), "record from a reused PID")
        XCTAssertEqual(check(["updatedAt": 900_000_000]), .failure(.identityUnavailable), "record not updated this run")
        XCTAssertEqual(check(["messagingSocketPath": nil]), .failure(.identityUnavailable))
        XCTAssertEqual(check(["sessionId": "not-a-uuid"]), .failure(.identityUnavailable))
        XCTAssertEqual(check(["status": "busy"]), .failure(.busy))
        XCTAssertEqual(check(["status": "waiting"]), .failure(.busy))
    }

    // MARK: - Live transfer guards

    // macOS hides the environment of platform binaries such as /bin/sleep, while real harnesses
    // expose theirs. An ad-hoc signed copy behaves like a real harness; the original does not.
    private func withExternalHarness(readableEnvironment: Bool = true,
                                     _ body: (Discovery.Harness, Process) throws -> Void) throws {
        var sleep = "/bin/sleep"
        if readableEnvironment {
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("harness-sleep-" + UUID().uuidString)
            try FileManager.default.copyItem(atPath: sleep, toPath: copy.path)
            sleep = copy.path
            // A copied platform binary is killed at launch unless it is re-signed.
            let sign = Process()
            sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            sign.arguments = ["-s", "-", "-f", copy.path]
            sign.standardOutput = FileHandle.nullDevice
            sign.standardError = FileHandle.nullDevice
            try sign.run()
            sign.waitUntilExit()
            XCTAssertEqual(sign.terminationStatus, 0)
        }
        defer { if readableEnvironment { try? FileManager.default.removeItem(atPath: sleep) } }
        // A harmless process with a harness argv[0], in an independent PTY. No actual agent runs.
        // The subshell exits so the fake harness is reparented away from this (iTerm2-hosted) test process.
        let marker = String(format: "30.%06d", Int.random(in: 0..<1_000_000))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", "/bin/zsh", "-c",
                             "( exec -a claude \(sleep) \(marker) & ); exec /bin/sleep 30"]
        process.standardInput = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        for name in ["TMUX", "TMUX_PANE", "STY", "ZELLIJ", "ZELLIJ_SESSION_NAME"] { environment.removeValue(forKey: name) }
        process.environment = environment
        try process.run()
        var discovered: Discovery.Harness?
        defer {
            if let discovered { kill(discovered.pid, SIGTERM) }
            if process.isRunning { process.terminate() }
        }
        let found = expectation(description: "external harness discovered")
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if let item = Discovery.scan().first(where: {
                iTermLSOF.rawCommandLineArguments(forProcess: $0.pid, execName: nil)?.contains(marker) == true
            }) {
                discovered = item
                timer.invalidate()
                found.fulfill()
            }
        }
        defer { timer.invalidate() }
        wait(for: [found], timeout: 10)
        try body(try XCTUnwrap(discovered), process)
    }

    func testTransferRefusesHarnessOnProtectedTerminal() throws {
        try withExternalHarness { harness, _ in
            XCTAssertTrue(harness.isNative)
            XCTAssertEqual(Discovery.resumeTarget(for: harness, protectedTTYs: [harness.tty]), .failure(.hostedByITerm))
            // The fixture's own argv is a positional argument, so it is never transferable either.
            XCTAssertEqual(Discovery.resumeTarget(for: harness, protectedTTYs: []),
                           .failure(.unsupportedArguments([Discovery.promptArgument])))
        }
    }

    func testUnreadableEnvironmentIsNeverTreatedAsNative() throws {
        try withExternalHarness(readableEnvironment: false) { harness, _ in
            XCTAssertTrue(harness.tmuxUnverified)
            XCTAssertFalse(harness.isNative)
            XCTAssertEqual(Discovery.resumeTarget(for: harness, protectedTTYs: []), .failure(.insideMultiplexer))
        }
    }

    func testStopRefusesUnverifiedMultiplexerWithoutSignaling() throws {
        try withExternalHarness { found, _ in
            let harness = Discovery.Harness(pid: found.pid, started: found.started, name: found.name,
                directory: found.directory, ancestors: found.ancestors, tty: found.tty,
                tmuxSocket: nil, tmuxPane: nil, tmuxUnverified: true)
            let target = Discovery.ResumeTarget(conversationID: id, transcript: "/nonexistent", command: ["/bin/true"])
            let refused = expectation(description: "stop refused")
            Discovery.stopForTransfer(harness, target: target, protectedTTYs: []) { result in
                XCTAssertEqual(result.failureValue, .insideMultiplexer)
                refused.fulfill()
            }
            wait(for: [refused], timeout: 10)
            XCTAssertEqual(iTermLSOF.startTime(forProcess: harness.pid), harness.started, "harness must still be running")
        }
    }

    func testTerminalDevicePathMatchesProcessTerminal() throws {
        try withExternalHarness { harness, _ in
            let paths = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
            let match = paths.filter { $0.hasPrefix("ttys") }.first {
                Discovery.ttyRdev(path: "/dev/" + $0) == harness.tty
            }
            XCTAssertNotNil(match)
            XCTAssertNil(Discovery.ttyRdev(path: "/etc/hosts"))
        }
    }

    // MARK: - Additional Transfer Safety Tests

    func testCodexRefusesDangerousConfigValues() {
        XCTAssertEqual(carried("Codex", ["-c", "override_policy=\"danger-full-access\""]),
                       .failure(.unsupportedArguments(["-c"])))
        XCTAssertEqual(carried("Codex", ["-c", "execution_mode=bypass"]),
                       .failure(.unsupportedArguments(["-c"])))
        XCTAssertEqual(carried("Codex", ["-c", "grant_permission=always"]),
                       .failure(.unsupportedArguments(["-c"])))
        XCTAssertEqual(carried("Codex", ["-c", "trust_mode=all"]),
                       .failure(.unsupportedArguments(["-c"])))

        XCTAssertFalse(Discovery.codexConfigAllowed("override_policy=danger-full-access"))
        XCTAssertFalse(Discovery.codexConfigAllowed("execution=bypass"))
        XCTAssertFalse(Discovery.codexConfigAllowed("permission_level=unrestricted"))
        XCTAssertFalse(Discovery.codexConfigAllowed("trust_mode=all"))
        XCTAssertTrue(Discovery.codexConfigAllowed("model_reasoning_effort=high"))
        XCTAssertTrue(Discovery.codexConfigAllowed("profile=production"))
    }

    func testTmuxProbeExecutableValidation() {
        XCTAssertFalse(HarnessTmuxProbe.isValidExecutable("tmux"), "Relative executable must be rejected")
        XCTAssertFalse(HarnessTmuxProbe.isValidExecutable("/nonexistent/bin/tmux"), "Nonexistent path must be rejected")
        XCTAssertFalse(HarnessTmuxProbe.isValidExecutable("/bin/sh"), "Path not ending in tmux must be rejected")

        let tempDir = FileManager.default.temporaryDirectory
        let fakeTmuxDir = tempDir.appendingPathComponent("fake-tmux-dir-" + UUID().uuidString + "/tmux")
        try? FileManager.default.createDirectory(at: fakeTmuxDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fakeTmuxDir.deletingLastPathComponent()) }
        XCTAssertFalse(HarnessTmuxProbe.isValidExecutable(fakeTmuxDir.path), "Directory named tmux must be rejected")

        let nonExecDir = tempDir.appendingPathComponent("non-exec-tmux-" + UUID().uuidString)
        let nonExecTmux = nonExecDir.appendingPathComponent("tmux")
        try? FileManager.default.createDirectory(at: nonExecDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: nonExecTmux.path, contents: Data(), attributes: [.posixPermissions: 0o644])
        defer { try? FileManager.default.removeItem(at: nonExecDir) }
        XCTAssertFalse(HarnessTmuxProbe.isValidExecutable(nonExecTmux.path), "Non-executable file must be rejected")

        for standard in ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"] {
            if FileManager.default.isExecutableFile(atPath: standard) {
                XCTAssertTrue(HarnessTmuxProbe.isValidExecutable(standard))
            }
        }
    }

    func testCommandLineArgumentsPreservesEmptyItems() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 10; :", "--", "", "final-arg"]
        try process.run()
        defer {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        var execName: NSString?
        let args = iTermLSOF.rawCommandLineArguments(forProcess: process.processIdentifier, execName: &execName)
        XCTAssertNotNil(args)
        guard let args else { return }
        // Arguments should include: ["sh", "-c", "sleep 10; :", "--", "", "final-arg"]
        XCTAssertTrue(args.contains(""), "rawCommandLineArguments must not drop empty string argv items")
        XCTAssertEqual(args.last, "final-arg")
        XCTAssertEqual(iTermLSOF.strictRawCommandLineArguments(forProcess: process.processIdentifier,
                                                               execName: nil), args)

        let escaped = iTermLSOF.commandLineArguments(forProcess: process.processIdentifier, execName: nil)
        XCTAssertNotNil(escaped)
        XCTAssertTrue(escaped?.contains("\"\"") == true, "Empty argv item must be escaped as empty quotes")
    }

    func testProcessExitedDetection() {
        let currentPid = getpid()
        let startTime = iTermLSOF.startTime(forProcess: currentPid) ?? Date()
        // A live process with matching start time has not exited.
        XCTAssertFalse(Discovery.hasProcessExited(pid: currentPid, started: startTime))
        // A different start time indicates exit/reuse.
        XCTAssertTrue(Discovery.hasProcessExited(pid: currentPid, started: Date(timeIntervalSince1970: 0)))
        // A nonexistent PID (e.g. 999999) has exited (ESRCH).
        XCTAssertTrue(Discovery.hasProcessExited(pid: 999_999, started: Date()))
    }

}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
