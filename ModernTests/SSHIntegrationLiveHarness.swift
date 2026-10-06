//
//  SSHIntegrationLiveHarness.swift
//  iTerm2 ModernTests
//
//  Live end-to-end harness for it2 over ssh integration, against `ssh localhost`. NOT a unit
//  test: it opens real windows in the test host, runs the real conductor bootstrap and framer
//  over a real ssh connection, and runs the uploaded it2 on the "remote" host, which is this Mac.
//  Run it with tools/run_ssh_integration_live.sh; without ITERM2_SSH_LIVE every test skips.
//
//  Needs Remote Login on and `ssh -o BatchMode=yes localhost true` to succeed.
//
//  The remote it2 is run over a SEPARATE `ssh localhost` carrying the connection's IT2_SOCK,
//  IT2_NONCE and IT2_PY, rather than typed into the session, so its stdout, stderr and exit status
//  are captured exactly instead of scraped off the screen. The authorization announcement is
//  answered through a Development-only hook that presses its button as a click would.
//
//  Side effects on this Mac, because it is also the remote host: ssh integration uploads it2 and
//  its interpreter under ~/.iterm2 as it does on any host, and the always-allow tests write
//  ~/.iterm2/it2-grant. That file is backed up and restored. Grants on the Mac side go to an
//  in-memory store, never the user's defaults.
//

import XCTest
@testable import iTerm2SharedARC

private final class LiveGrantBacking: IT2HostGrantBacking {
    var data: Data?
    func loadGrantData() -> Data? { data }
    func saveGrantData(_ data: Data?) { self.data = data }
}

/// The real framer-backed file access, except that the host claims not to be this Mac, so the
/// install path can run against localhost. Only the token is overridden; every read and write is
/// real.
@MainActor
private final class NotThisMacFiles: ClaudeCodeRemoteFiles {
    private let inner: ClaudeCodeRemoteFiles
    init(_ inner: ClaudeCodeRemoteFiles) { self.inner = inner }
    func read(_ path: String) async -> ClaudeCodeRemoteRead { await inner.read(path) }
    func write(_ path: String, _ data: Data) async -> Bool { await inner.write(path, data) }
    func isExecutable(_ path: String) async -> Bool { await inner.isExecutable(path) }
    func machineToken() async -> String? { "1:" }
}

private struct RemoteResult: CustomStringConvertible {
    var status: Int32
    var stdout: String
    var stderr: String
    var description: String { "exit \(status) stdout=\(stdout.debugDescription) stderr=\(stderr.debugDescription)" }
}

@MainActor
final class SSHIntegrationLiveHarness: XCTestCase {
    private var sessions = [PTYSession]()
    private var store: IT2HostGrantStore!
    private var savedGrantFile: Data?
    private let grantFilePath = NSHomeDirectory() + "/.iterm2/it2-grant"

    // Generous: the bootstrap uploads files and starts a framer before it2 can work. Waiting on a
    // condition rather than a fixed delay, so a slow run is slow, not a failure.
    private let connectTimeout: TimeInterval = 90
    private let commandTimeout: TimeInterval = 30

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard ProcessInfo.processInfo.environment["ITERM2_SSH_LIVE"] != nil else {
            throw XCTSkip("Live ssh integration harness; run tools/run_ssh_integration_live.sh")
        }
        MainActor.assumeIsolated {
            savedGrantFile = FileManager.default.contents(atPath: grantFilePath)
            store = IT2HostGrantStore(backing: LiveGrantBacking())
            Conductor.hostGrantStoreForTesting = store
            Conductor.it2APIEnabledForTesting = true
            iTermAPIHelper.debugStartInProcessOnlyServer()
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            for session in sessions {
                close(session)
            }
            sessions = []
            Conductor.hostGrantStoreForTesting = nil
            Conductor.it2APIEnabledForTesting = nil
            if let savedGrantFile {
                FileManager.default.createFile(atPath: grantFilePath, contents: savedGrantFile,
                                               attributes: [.posixPermissions: 0o600])
            } else {
                try? FileManager.default.removeItem(atPath: grantFilePath)
            }
        }
        super.tearDown()
    }

    // MARK: - Helpers

    private func waitUntil(_ what: String, timeout: TimeInterval,
                           file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for \(what)", file: file, line: line)
                return
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }

    private func launch(profile: [AnyHashable: Any]) -> PTYSession? {
        var launched: PTYSession?
        iTermSessionLauncher.launchBookmark(profile, in: nil, respectTabbingMode: false) { session in
            launched = session
        }
        waitUntil("the session to launch", timeout: commandTimeout) { launched != nil }
        if let launched {
            sessions.append(launched)
        }
        return launched
    }

    private func baseProfile() -> [AnyHashable: Any] {
        var profile = (ProfileModel.sharedInstance()?.defaultProfile() as? [AnyHashable: Any]) ?? [:]
        profile[KEY_GUID] = UUID().uuidString
        profile[KEY_NAME] = "ssh live harness"
        return profile
    }

    /// A session running ssh integration to localhost, once its it2 proxy is live.
    /// `forwardAgent` lets an ssh started on the remote host authenticate with this Mac's agent,
    /// which a second hop needs: the remote shell has no agent of its own.
    private func connect(forwardAgent: Bool = false,
                         loadShellIntegration: Bool = true,
                         command: String? = nil,
                         file: StaticString = #filePath, line: UInt = #line) -> PTYSession? {
        var profile = baseProfile()
        profile[KEY_CUSTOM_COMMAND] = kProfilePreferenceCommandTypeSSHValue
        profile[KEY_COMMAND_LINE] = (forwardAgent ? "-A localhost" : "localhost") + (command.map { " " + $0 } ?? "")
        profile[KEY_LOAD_SHELL_INTEGRATION_AUTOMATICALLY] = loadShellIntegration
        guard let session = launch(profile: profile) else {
            XCTFail("could not launch", file: file, line: line)
            return nil
        }
        waitUntil("the it2 proxy to come up", timeout: connectTimeout, file: file, line: line) {
            session.conductor?.it2ProxyActive == true
        }
        return session
    }

    /// A local session that becomes the focused one, so a test can tell "the session the call
    /// came from" apart from "whatever is focused".
    private func openDecoy() -> PTYSession? {
        return launch(profile: baseProfile())
    }

    private func close(_ session: PTYSession) {
        session.terminate()
        session.delegate?.realParentWindow()?.window?.close()
    }

    private func screenText(_ session: PTYSession) -> String {
        var result = ""
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            result = mutableState.currentGrid.compactLineDump()
        })
        return result
    }

    /// What the shell in `session` actually has for IT2_SOCK and IT2_NONCE. Asked of the shell
    /// itself, because the conductor knowing its socket proves nothing about whether the shell
    /// received it. The "remote" host is this Mac, so the shell can answer through a file.
    private func shellIT2Environment(_ session: PTYSession,
                                     file: StaticString = #filePath,
                                     line: UInt = #line) -> (sock: String, nonce: String)? {
        let path = NSTemporaryDirectory() + "it2-harness-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let partial = path + ".partial"
        session.writeTask("printf '%s\\n%s\\n' \"$IT2_SOCK\" \"$IT2_NONCE\" > \(shellQuote(partial)) && mv \(shellQuote(partial)) \(shellQuote(path))\r")
        waitUntil("the shell to report its environment", timeout: commandTimeout, file: file, line: line) {
            FileManager.default.fileExists(atPath: path)
        }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 2 else {
            return nil
        }
        return (lines[0], lines[1])
    }

    /// This process's environment without the test runner's debugging variables (malloc stack
    /// logging, zombies, sanitizers), which make every child print noise on stderr.
    private nonisolated func sshEnvironment() -> [String: String] {
        let noisy = ["Malloc", "NSZombie", "NSDeallocate", "DYLD_", "ASAN_", "OBJC_DEBUG"]
        return ProcessInfo.processInfo.environment.filter { entry in
            !noisy.contains { entry.key.hasPrefix($0) }
        }
    }

    private func shellQuote(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Starts the uploaded it2 on the remote host with `conductor`'s connection environment.
    /// Asynchronous, because the app must keep running its main loop to serve the call.
    private func startRemoteIt2(_ conductor: Conductor, _ arguments: [String],
                                stdin: String? = nil) -> () -> RemoteResult? {
        let env = ["IT2_SOCK": conductor.it2SocketPath ?? "",
                   "IT2_NONCE": conductor.it2Nonce ?? "",
                   "IT2_PY": conductor.it2Proxy.pyPath ?? ""]
        let remote = ["env"] + env.sorted { $0.key < $1.key }.map { "\($0.key)=\(shellQuote($0.value))" }
            + [shellQuote(NSHomeDirectory() + "/.iterm2/bin/it2")] + arguments.map(shellQuote)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-o", "BatchMode=yes", "-T", "localhost", remote.joined(separator: " ")]
        process.environment = sshEnvironment()
        let out = Pipe()
        let err = Pipe()
        let input = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = input
        let lock = NSLock()
        var stdoutData = Data()
        var stderrData = Data()
        out.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            lock.lock(); stdoutData.append(chunk); lock.unlock()
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            lock.lock(); stderrData.append(chunk); lock.unlock()
        }
        do {
            try process.run()
        } catch {
            XCTFail("could not run ssh: \(error)")
            return { RemoteResult(status: -1, stdout: "", stderr: "\(error)") }
        }
        if let stdin {
            input.fileHandleForWriting.write(Data(stdin.utf8))
        }
        try? input.fileHandleForWriting.close()
        return {
            guard !process.isRunning else {
                return nil
            }
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            let restOut = out.fileHandleForReading.readDataToEndOfFile()
            let restErr = err.fileHandleForReading.readDataToEndOfFile()
            lock.lock(); defer { lock.unlock() }
            return RemoteResult(status: process.terminationStatus,
                                stdout: String(decoding: stdoutData + restOut, as: UTF8.self),
                                stderr: String(decoding: stderrData + restErr, as: UTF8.self))
        }
    }

    private func finished(_ poll: () -> RemoteResult?, file: StaticString = #filePath,
                          line: UInt = #line) -> RemoteResult? {
        var result: RemoteResult?
        waitUntil("the remote it2 to finish", timeout: commandTimeout, file: file, line: line) {
            result = poll()
            return result != nil
        }
        return result
    }

    private func runRemoteIt2(_ conductor: Conductor, _ arguments: [String], stdin: String? = nil,
                              file: StaticString = #filePath, line: UInt = #line) -> RemoteResult? {
        return finished(startRemoteIt2(conductor, arguments, stdin: stdin), file: file, line: line)
    }

    private func hasPrompt(_ session: PTYSession, _ conductor: Conductor) -> Bool {
        return session.hasAnnouncement(
            withIdentifier: PTYSession.it2AuthorizationAnnouncementIdentifier(forGUID: conductor.guid))
    }

    private func answerPrompt(_ session: PTYSession, _ conductor: Conductor, selection: Int,
                              file: StaticString = #filePath, line: UInt = #line) {
        waitUntil("the authorization prompt", timeout: commandTimeout, file: file, line: line) {
            hasPrompt(session, conductor)
        }
        XCTAssertTrue(session.debugAnswerIT2Authorization(forConductorGUID: conductor.guid,
                                                          selection: Int32(selection)),
                      file: file, line: line)
    }

    // MARK: - The prompt

    func testAllowRunsTheCommand() throws {
        let session = try XCTUnwrap(connect())
        let conductor = try XCTUnwrap(session.conductor)
        let shellEnv = try XCTUnwrap(shellIT2Environment(session))
        XCTAssertEqual(shellEnv.sock, conductor.it2SocketPath, "the shell itself got IT2_SOCK")
        XCTAssertEqual(shellEnv.nonce, conductor.it2Nonce, "the shell itself got IT2_NONCE")
        let poll = startRemoteIt2(conductor, ["session", "list"])
        answerPrompt(session, conductor, selection: IT2AuthorizationOutcome.allowIndex)
        let result = try XCTUnwrap(finished(poll))
        XCTAssertEqual(result.status, 0, "\(result)")
        XCTAssertFalse(result.stdout.isEmpty)

        // Remembered for the connection: the next call does not ask.
        let again = try XCTUnwrap(runRemoteIt2(conductor, ["session", "list"]))
        XCTAssertEqual(again.status, 0, "\(again)")
        XCTAssertFalse(hasPrompt(session, conductor))
    }

    func testDenyRefusesTheCommand() throws {
        let session = try XCTUnwrap(connect())
        let conductor = try XCTUnwrap(session.conductor)
        let poll = startRemoteIt2(conductor, ["session", "list"])
        answerPrompt(session, conductor, selection: IT2AuthorizationOutcome.denyIndex)
        let result = try XCTUnwrap(finished(poll))
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.stderr.contains("Permission denied"), result.stderr)
    }

    // MARK: - Hooks

    // A hook must finish while the prompt is still up, and the next one, after the user answers,
    // must actually run.
    func testHookNeverWaitsForThePrompt() throws {
        let session = try XCTUnwrap(connect())
        let conductor = try XCTUnwrap(session.conductor)
        let result = try XCTUnwrap(runRemoteIt2(conductor, ["handle-agent-hook"], stdin: "{}"))
        XCTAssertEqual(result.status, 0, "\(result)")
        XCTAssertTrue(result.stderr.isEmpty, result.stderr)
        XCTAssertTrue(hasPrompt(session, conductor), "the hook still raised the prompt")
        XCTAssertNil(conductor.it2Authorized, "and nobody has answered it")
        answerPrompt(session, conductor, selection: IT2AuthorizationOutcome.allowIndex)
        XCTAssertEqual(conductor.it2Authorized, true)
    }

    // A real Claude Code event, sent through the remote hook the way Claude Code runs it, must
    // change the status of the session the agent is in. The shell there has neither tmux nor
    // TERM_SESSION_ID, so the hook can only address the session it arrived on. Sending "{}" (as
    // above) proved the plumbing but not this, which is how a hook that reported nothing at all
    // got past the harness.
    func testRealHookEventSetsTheSessionStatus() throws {
        let session = try XCTUnwrap(connect())
        let conductor = try XCTUnwrap(session.conductor)
        let allow = startRemoteIt2(conductor, ["session", "list"])
        answerPrompt(session, conductor, selection: IT2AuthorizationOutcome.allowIndex)
        XCTAssertEqual(try XCTUnwrap(finished(allow)).status, 0)

        let event = #"{"hook_event_name": "UserPromptSubmit", "session_id": "harness", "cwd": "/tmp", "prompt": "hi"}"#
        let result = try XCTUnwrap(runRemoteIt2(conductor, ["handle-agent-hook"], stdin: event))
        XCTAssertEqual(result.status, 0, "\(result)")
        waitUntil("the session status to change", timeout: commandTimeout) {
            session.tabStatus?.statusText?.localizedCaseInsensitiveContains("working") == true
        }
    }

    // MARK: - Jobs

    // What the Jobs toolbelt tool shows for an ssh session: the processes under the session's
    // effective root pid, read from the session's process provider. Both must describe the remote
    // host for a remote job to appear.
    func testJobsToolSeesARemoteJob() throws {
        let session = try XCTUnwrap(connect())
        let conductor = try XCTUnwrap(session.conductor)
        session.writeTask("sleep 120\r")
        addTeardownBlock { @MainActor in session.writeTask("\u{3}") }
        waitUntil("the remote job to appear in the session's process tree", timeout: commandTimeout) {
            guard let root = session.genericScope.value(forVariableName: iTermVariableKeySessionEffectiveSessionRootPid) as? NSNumber,
                  root.int32Value == conductor.framedPID,
                  let info = session.processInfoProvider?.processInfo(for: root.int32Value) else {
                return false
            }
            return info.descendants(skipping: 0).contains { $0.name == "sleep" }
        }
    }

    // MARK: - Without injection

    // it2's socket used to come only with shell-integration injection. With "Load shell
    // integration automatically" off there was no socket and no IT2_SOCK, so every remote it2
    // feature failed silently. Now the connection always has one; the setting decides only what
    // is uploaded.
    func testSettingOffStillGivesTheShellASocket() throws {
        let session = try XCTUnwrap(connect(loadShellIntegration: false))
        let conductor = try XCTUnwrap(session.conductor)
        // The profile passed it2ssh --no-shell-integration, which reported si=0.
        XCTAssertFalse(conductor.shouldInjectShellIntegration)
        let environment = try XCTUnwrap(shellIT2Environment(session))
        XCTAssertEqual(environment.sock, conductor.it2SocketPath)
        XCTAssertEqual(environment.nonce, conductor.it2Nonce)
    }

    // tcsh cannot be injected, so it got no socket even with the setting on. It still cannot be
    // injected, but it gets the socket and its variables.
    func testShellThatCannotBeInjectedGetsASocket() throws {
        guard FileManager.default.isExecutableFile(atPath: "/bin/tcsh") else {
            throw XCTSkip("no /bin/tcsh")
        }
        let session = try XCTUnwrap(connect(command: "/bin/tcsh"))
        let conductor = try XCTUnwrap(session.conductor)
        XCTAssertTrue(conductor.shouldInjectShellIntegration)
        let environment = try XCTUnwrap(shellIT2Environment(session))
        XCTAssertEqual(environment.sock, conductor.it2SocketPath)
        XCTAssertEqual(environment.nonce, conductor.it2Nonce)
    }

    // MARK: - Shell integration too old for Claude Code's it2

    // The session keeps the version its remote shell reports. Injected scripts are current, so the
    // check passes; a shell reporting an older version (a stale install, as on a host where the
    // scripts are sourced by hand) is too old for Claude Code to find it2 on PATH.
    func testReportedShellIntegrationVersionDecidesTheIt2Check() throws {
        let session = try XCTUnwrap(connect())
        waitUntil("the remote shell to report its shell integration", timeout: commandTimeout) {
            session.reportedShellIntegration != nil
        }
        XCTAssertEqual(ClaudeIntegrationHealthMonitor.it2Verdict(for: session), .current,
                       "\(String(describing: session.reportedShellIntegration))")

        session.writeTask("printf '\\033]1337;ShellIntegrationVersion=19;shell=zsh\\007'\r")
        waitUntil("the older version to be recorded", timeout: commandTimeout) {
            session.reportedShellIntegration?.version == 19
        }
        XCTAssertEqual(ClaudeIntegrationHealthMonitor.it2Verdict(for: session),
                       .tooOld(shell: "zsh", version: 19, minimum: 20))
    }

    // MARK: - Git status

    /// A repository on branch trunk with one commit, a modified tracked.txt (one line changed)
    /// and an untracked file.
    private func makeDirtyRepository(at directory: String) throws {
        func git(_ args: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
            var environment = sshEnvironment()
            environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
            process.environment = environment
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "git \(args)")
        }
        try git(["init", "-q", "-b", "trunk"])
        try git(["config", "user.email", "t@example.com"])
        try git(["config", "user.name", "T"])
        try "one\n".write(toFile: directory + "/tracked.txt", atomically: false, encoding: .utf8)
        try git(["add", "-A"])
        try git(["commit", "-q", "-m", "one"])
        try "two\n".write(toFile: directory + "/tracked.txt", atomically: false, encoding: .utf8)
        try "new\n".write(toFile: directory + "/untracked.txt", atomically: false, encoding: .utf8)
    }

    private final class AlwaysPoll: NSObject, iTermGitPollerDelegate {
        func gitPollerShouldPoll(_ poller: iTermGitPoller, after lastPoll: Date?) -> Bool { true }
    }

    // The status bar's git component and the workgroup toolbar read a repository on the host
    // through the connection, the way they read one on this Mac. Before, off this Mac they only
    // had the it2git user variables, which a host has to be set up to send, and no file list.
    func testGitStatusComesFromTheRemoteHost() throws {
        let session = try XCTUnwrap(connect())
        let directory = (NSTemporaryDirectory() as NSString).appendingPathComponent("git-remote-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: directory) }
        let realDirectory = (directory as NSString).resolvingSymlinksInPath
        try makeDirtyRepository(at: directory)

        session.writeTask("cd \(shellQuote(directory))\r")
        waitUntil("the session's directory to be known", timeout: commandTimeout) {
            guard let path = session.genericScope.value(forVariableName: iTermVariableKeySessionPath) as? String else {
                return false
            }
            return (path as NSString).resolvingSymlinksInPath == realDirectory
        }

        // The loopback host is this Mac, so a session there rightly reads git locally. Resolve the
        // worker the way a real remote session does, and read through it.
        let conductor = try XCTUnwrap(session.conductor)
        let worker = try XCTUnwrap(iTermRemoteGitPollWorker.worker(forScope: session.genericScope))
        XCTAssertTrue(worker === conductor.remoteGitPollWorker)
        let poller = iTermGitPoller(cadence: 1) {}
        let delegate = AlwaysPoll()
        poller.delegate = delegate
        poller.includeDiffStats = true
        poller.worker = worker
        poller.enabled = true
        poller.currentDirectory = directory
        // state is declared nonnull but is nil until the first answer; KVC reads it safely.
        func state() -> iTermGitState? { poller.value(forKey: "state") as? iTermGitState }
        waitUntil("the git state of the remote repository", timeout: commandTimeout) {
            state()?.branch == "trunk"
        }
        withExtendedLifetime(delegate) {}
        let state = try XCTUnwrap(state())
        XCTAssertTrue(state.dirty)
        XCTAssertEqual(state.adds, 1)
        XCTAssertEqual(state.filesModified, 1)
        XCTAssertEqual(state.linesInserted, 1)
        XCTAssertEqual(state.linesDeleted, 1)
        XCTAssertEqual(state.fileStatuses?.map(\.path), ["tracked.txt"])
        XCTAssertEqual(state.fileStatuses?.first?.workdirStatus, .modified)
    }

    // MARK: - Remote commands

    // `it2ssh host <command>` runs <command> as ssh would: the remote shell gets it intact, quotes
    // and all. Before, the words were split and rejoined, so the double space and the semicolon
    // inside the quotes below were lost.
    func testRemoteCommandKeepsItsQuoting() throws {
        let output = NSTemporaryDirectory() + "it2ssh-quoting-\(UUID().uuidString)"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: output) }
        // The sleep keeps the session up past setup, as an interactive use of a command would.
        let command = "printf '%s\\n' 'a  b;c' > " + shellQuote(output) + "; sleep 5"
        var profile = baseProfile()
        profile[KEY_CUSTOM_COMMAND] = kProfilePreferenceCommandTypeSSHValue
        profile[KEY_COMMAND_LINE] = "localhost " + shellQuote(command)
        profile[KEY_LOAD_SHELL_INTEGRATION_AUTOMATICALLY] = true
        var computed: String?
        ITAddressBookMgr.computeCommand(forProfile: profile, objectType: .windowObject,
                                        scope: iTermVariableScope()) { command, _ in computed = command }
        waitUntil("the command to be computed", timeout: commandTimeout) { computed != nil }
        let session = try XCTUnwrap(launch(profile: profile))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 4))
        let early = screenText(session)
        let deadline = Date(timeIntervalSinceNow: connectTimeout)
        while (try? String(contentsOfFile: output, encoding: .utf8)) != "a  b;c\n" && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        let written = try? String(contentsOfFile: output, encoding: .utf8)
        XCTAssertEqual(written, "a  b;c\n", "Command:\n\(computed ?? "nil")\nScreen after 4s:\n\(early)\nScreen at the end:\n\(screenText(session))")
    }

    // A command run with `it2ssh host <command>` gets it2 too: IT2_SOCK and IT2_NONCE in its
    // environment, and `it2` on PATH. Before, the command's first word was taken to be the shell,
    // and shell integration skipped anything it did not recognize, so a remote `claude` could not
    // report; then it had the environment but not PATH, so `it2` was not found.
    // The conductor's shell is the real login shell, not the command.
    func testRemoteCommandGetsIt2() throws {
        let output = NSTemporaryDirectory() + "it2ssh-env-\(UUID().uuidString)"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: output) }
        // printf rather than printenv, which takes one name on macOS.
        let command = #"printf '%s\n%s\n%s\n' "$IT2_SOCK" "$IT2_NONCE" "$(command -v it2)" > "# + shellQuote(output) + "; sleep 30"
        var profile = baseProfile()
        profile[KEY_CUSTOM_COMMAND] = kProfilePreferenceCommandTypeSSHValue
        profile[KEY_COMMAND_LINE] = "localhost " + shellQuote(command)
        profile[KEY_LOAD_SHELL_INTEGRATION_AUTOMATICALLY] = true
        let session = try XCTUnwrap(launch(profile: profile))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 8))
        let early = "file=\((try? String(contentsOfFile: output, encoding: .utf8)).debugDescription) conductor=\(session.conductor.debugDescription)\nScreen:\n\(screenText(session))"
        waitUntil("the remote command to report its environment: \(early)", timeout: connectTimeout) {
            // Three lines, the last possibly empty (it2 not found), each ending in a newline.
            ((try? String(contentsOfFile: output, encoding: .utf8)) ?? "").components(separatedBy: "\n").count == 4
        }
        let lines = Array(try XCTUnwrap(try? String(contentsOfFile: output, encoding: .utf8)).components(separatedBy: "\n").dropLast())
        let conductor = try XCTUnwrap(session.conductor)
        XCTAssertEqual(lines.first, conductor.it2SocketPath)
        XCTAssertEqual(lines[1], conductor.it2Nonce)
        XCTAssertEqual(lines.last, NSHomeDirectory() + "/.iterm2/bin/it2")
        let loginShell = try XCTUnwrap(conductor.shell)
        XCTAssertNotEqual((loginShell as NSString).lastPathComponent, "printenv")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: loginShell), loginShell)
    }

    // MARK: - Workgroup peers

    // A peer of a leader on a host reached through SSH Integration runs on that host, in the
    // leader's directory there, with the workgroup's ID. IT2_SOCK is what tells it apart from a
    // peer run on this Mac, which on localhost would otherwise see the same directory.
    func testWorkgroupPeerRunsOnTheLeadersHost() throws {
        let session = try XCTUnwrap(connect())
        let directory = (NSTemporaryDirectory() as NSString).appendingPathComponent("wg-remote-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let output = directory + "/peer-report"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: directory) }
        // A diff peer waits until the git poller sees a change, so give it one.
        try makeDirtyRepository(at: directory)
        let realDirectory = (directory as NSString).resolvingSymlinksInPath
        session.writeTask("cd \(shellQuote(directory))\r")
        waitUntil("the leader's directory to be known", timeout: commandTimeout) {
            guard let path = session.genericScope.value(forVariableName: iTermVariableKeySessionPath) as? String else {
                return false
            }
            return (path as NSString).resolvingSymlinksInPath == realDirectory
        }

        let root = WGFix.makeRoot()
        let peer = WGFix.makePeer(
            parentID: root.uniqueIdentifier,
            command: #"printf '%s\n%s\n%s\n' "$PWD" "$ITERM_WORKGROUP_ID" "$IT2_SOCK" > "# + shellQuote(output) + "; sleep 60")
        let diffOutput = directory + "/diff-report"
        let diffPeer = WGFix.makePeer(parentID: root.uniqueIdentifier,
                                      displayName: "Diff",
                                      command: "pwd > " + shellQuote(diffOutput) + "; sleep 60",
                                      mode: .diff)
        let workgroup = WGFix.wrap(name: "remote peer", sessions: [root, peer, diffPeer])
        iTermWorkgroupModel.instance.add(workgroup)
        addTeardownBlock { @MainActor in
            iTermWorkgroupController.instance.exit(on: session)
            iTermWorkgroupModel.instance.remove(uniqueIdentifier: workgroup.uniqueIdentifier)
        }
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: session,
                                                              mechanism: .menu))
        let instanceID = try XCTUnwrap(iTermWorkgroupController.instance.workgroupInstance(on: session)?.instanceUniqueIdentifier)
        waitUntil("the peer to report", timeout: connectTimeout) {
            ((try? String(contentsOfFile: output, encoding: .utf8)) ?? "").split(separator: "\n").count == 3
        }
        let lines = try XCTUnwrap(try? String(contentsOfFile: output, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual((lines[0] as NSString).resolvingSymlinksInPath, realDirectory, "the leader's directory")
        XCTAssertEqual(lines[1], instanceID, "the workgroup's ID")
        XCTAssertFalse(lines[2].isEmpty, "started over SSH Integration, so it has it2")
        // A diff peer starts when it is shown and the poller has seen a change, so its diff is of
        // the tree as it is then.
        let port = try XCTUnwrap(session.peerPort as? iTermWorkgroupPeerPort)
        XCTAssertTrue(port.activate(identifier: diffPeer.uniqueIdentifier))
        waitUntil("the diff peer to launch once shown", timeout: connectTimeout) {
            let reported = (try? String(contentsOfFile: diffOutput, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return reported.map { ($0 as NSString).resolvingSymlinksInPath } == realDirectory
        }
    }

    // MARK: - Default target

    // With no target, a remote it2 addresses the session the call arrived on, not the focused one.
    func testNoTargetMeansTheSessionTheCallCameFrom() throws {
        let session = try XCTUnwrap(connect())
        let conductor = try XCTUnwrap(session.conductor)
        let decoy = try XCTUnwrap(openDecoy())
        let marker = UUID().uuidString
        // set-var takes a JSON value.
        let poll = startRemoteIt2(conductor, ["session", "set-var", "user.harness", "\"\(marker)\""])
        answerPrompt(session, conductor, selection: IT2AuthorizationOutcome.allowIndex)
        let result = try XCTUnwrap(finished(poll))
        XCTAssertEqual(result.status, 0, "\(result)")
        XCTAssertEqual(session.genericScope.value(forVariableName: "user.harness") as? String, marker)
        XCTAssertNil(decoy.genericScope.value(forVariableName: "user.harness"), "not the focused session")
    }

    // MARK: - Always Allow This Host

    // Minting writes the host's half, a later connection is let in without asking, and revoking
    // makes the next connection ask again.
    func testAlwaysAllowSurvivesReconnectUntilRevoked() throws {
        let first = try XCTUnwrap(connect())
        let firstConductor = try XCTUnwrap(first.conductor)
        let host = firstConductor.sshIdentity.stringIdentifier
        let poll = startRemoteIt2(firstConductor, ["session", "list"])
        answerPrompt(first, firstConductor, selection: IT2AuthorizationOutcome.alwaysAllowThisHostIndex)
        XCTAssertEqual(try XCTUnwrap(finished(poll)).status, 0)
        waitUntil("the grant to be recorded", timeout: commandTimeout) {
            store.grant(forHost: host) != nil
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: grantFilePath)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        close(first)

        let second = try XCTUnwrap(connect())
        let secondConductor = try XCTUnwrap(second.conductor)
        let granted = try XCTUnwrap(runRemoteIt2(secondConductor, ["session", "list"]))
        XCTAssertEqual(granted.status, 0, "\(granted)")
        XCTAssertFalse(hasPrompt(second, secondConductor), "a granted host is not asked")
        close(second)

        store.revoke(host: host)
        let third = try XCTUnwrap(connect())
        let thirdConductor = try XCTUnwrap(third.conductor)
        let afterRevoke = startRemoteIt2(thirdConductor, ["session", "list"])
        answerPrompt(third, thirdConductor, selection: IT2AuthorizationOutcome.denyIndex)
        XCTAssertEqual(try XCTUnwrap(finished(afterRevoke)).status, 1)
    }

    // MARK: - Claude Code config directory

    // The real lookup through framer's pty: the login shell starts, its rc files run, and the
    // markers come back intact around /usr/bin/env. Compared with what ssh reports for the same
    // login shell run the same way, which is what Claude Code started from that shell would see.
    func testRemoteConfigDirectoryLookup() throws {
        let session = try XCTUnwrap(connect())
        let conductor = try XCTUnwrap(session.conductor)
        var result: String??
        ClaudeCodeOnboarding.resolveRemoteConfigDirectory(conductor: conductor) { result = .some($0) }
        waitUntil("the config directory lookup", timeout: ClaudeCodeRemoteConfigDirResolver.deadline + 5) {
            result != nil
        }
        let directory = try XCTUnwrap(try XCTUnwrap(result), "the lookup failed")
        let shell = try XCTUnwrap(conductor.shell)
        let home = try XCTUnwrap(conductor.homeDirectory)
        let probe = ClaudeCodeRemoteConfigDirResolver.commandLine(shell: shell, sentinel: "harness")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-o", "BatchMode=yes", "-T", "localhost", probe]
        process.environment = sshEnvironment()
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let expected = ClaudeCodeRemoteConfigDirResolver.directory(fromOutput: String(decoding: data, as: UTF8.self),
                                                                   sentinel: "harness",
                                                                   home: home)
        XCTAssertEqual(directory, try XCTUnwrap(expected))
    }

    // MARK: - Claude Code hook install

    private func scratchConfigDirectory() -> String {
        let path = NSTemporaryDirectory() + "claude-harness-\(UUID().uuidString)"
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return path
    }

    // localhost is this Mac: the local install owns its settings, so the remote one refuses and
    // writes nothing. Uses the real machine token from the host.
    func testRemoteHookInstallRefusesThisMac() throws {
        try XCTSkipUnless((iTermAdvancedSettingsModel.fakeBootSessionUUID() ?? "").isEmpty,
                          "FakeBootSessionUUID override is set")
        let session = try XCTUnwrap(connect())
        let conductor = try XCTUnwrap(session.conductor)
        let directory = scratchConfigDirectory()
        let facts = ClaudeCodeRemoteConnectionFacts()
        var result: ClaudeCodeRemoteHooks.InstallResult?
        ClaudeCodeOnboarding.installHooksRemotely(conductor: conductor, configDirectory: directory,
                                                  grantAlwaysAllow: true, facts: facts) { result = $0 }
        waitUntil("the install to finish", timeout: connectTimeout) { result != nil }
        XCTAssertEqual(result, .thisMac)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory))
        XCTAssertNil(facts.hookPresent(for: conductor))
        XCTAssertNil(store.grant(forHost: conductor.sshIdentity.stringIdentifier), "no grant for a refused install")

        // The same answer the health monitor uses to leave localhost alone.
        var isThisMac: Bool?
        ClaudeCodeOnboarding.remoteHostIsThisMac(conductor: conductor) { isThisMac = $0 }
        waitUntil("the machine check", timeout: connectTimeout) { isThisMac != nil }
        XCTAssertEqual(isThisMac, true)
    }

    // Install, check and remove through the real framer, into a scratch directory, with the user
    // agreeing to always allow the host and then to revoke that on uninstall.
    func testRemoteHookInstallHealthAndUninstall() throws {
        let session = try XCTUnwrap(connect())
        let conductor = try XCTUnwrap(session.conductor)
        let host = conductor.sshIdentity.stringIdentifier
        let home = try XCTUnwrap(conductor.homeDirectory)
        let directory = scratchConfigDirectory()
        let settingsPath = directory + "/settings.json"
        let facts = ClaudeCodeRemoteConnectionFacts()
        let files = NotThisMacFiles(ConductorClaudeCodeRemoteFiles(conductor: conductor))

        var installed: ClaudeCodeRemoteHooks.InstallResult?
        ClaudeCodeOnboarding.installHooksRemotely(conductor: conductor, configDirectory: directory,
                                                  grantAlwaysAllow: true,
                                                  files: files, facts: facts) { installed = $0 }
        waitUntil("the install to finish", timeout: connectTimeout) { installed != nil }
        XCTAssertEqual(installed, .installed)
        let data = try XCTUnwrap(FileManager.default.contents(atPath: settingsPath))
        let settings = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(ClaudeCodeHookSettings.ourCommandsCoveringEveryEvent(
            settings, descriptor: .claudeCode,
            isOurs: { ClaudeCodeHookSettings.isRemoteHookCommand($0, home: home) }))
        // Known for this connection only; nothing about the host is written to disk.
        XCTAssertEqual(facts.configDirectory(for: conductor), directory)
        XCTAssertEqual(facts.hookPresent(for: conductor), true)
        XCTAssertNil(iTermUserDefaults.userDefaults().object(forKey: "NoSyncClaudeCodeHooksInstalledHosts"))
        XCTAssertNil(iTermUserDefaults.userDefaults().object(forKey: "NoSyncClaudeCodeConfigDirPathByHost"))
        waitUntil("the grant to be minted", timeout: commandTimeout) {
            store.grant(forHost: host) != nil
        }

        // Read from the host, in the directory found for this connection.
        var status: ClaudeCodeRemoteHooks.HookStatus?
        ClaudeCodeOnboarding.remoteHookStatus(conductor: conductor, files: files, facts: facts) { status = $0 }
        waitUntil("the health check", timeout: connectTimeout) { status != nil }
        XCTAssertEqual(status, .healthy)

        var uninstalled: ClaudeCodeUninstallHooksResult?
        ClaudeCodeOnboarding.uninstallHooksRemotely(conductor: conductor, revokeAlwaysAllow: true,
                                                    files: files, facts: facts) { uninstalled = $0 }
        waitUntil("the uninstall to finish", timeout: connectTimeout) { uninstalled != nil }
        XCTAssertEqual(uninstalled, .success)
        let after = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try XCTUnwrap(FileManager.default.contents(atPath: settingsPath))) as? [String: Any])
        XCTAssertNil(after["hooks"], "nothing of ours left, and nothing else was there")
        XCTAssertEqual(facts.hookPresent(for: conductor), false)
        XCTAssertNil(store.grant(forHost: host), "revoked, as the user chose")
    }

    // The user declined both: installing mints no grant, and uninstalling leaves alone a grant the
    // host already had from the authorization prompt.
    func testRemoteHookInstallAndUninstallWithoutGrantChanges() throws {
        let session = try XCTUnwrap(connect())
        let conductor = try XCTUnwrap(session.conductor)
        let host = conductor.sshIdentity.stringIdentifier
        let directory = scratchConfigDirectory()
        let facts = ClaudeCodeRemoteConnectionFacts()
        let files = NotThisMacFiles(ConductorClaudeCodeRemoteFiles(conductor: conductor))

        var installed: ClaudeCodeRemoteHooks.InstallResult?
        ClaudeCodeOnboarding.installHooksRemotely(conductor: conductor, configDirectory: directory,
                                                  grantAlwaysAllow: false,
                                                  files: files, facts: facts) { installed = $0 }
        waitUntil("the install to finish", timeout: connectTimeout) { installed != nil }
        XCTAssertEqual(installed, .installed)
        XCTAssertNil(store.grant(forHost: host), "no grant unless the user agreed to one")

        let earlier = IT2HostGrant(host: host, id: "earlier", secretSHA256: "hash", granted: Date())
        store.add(earlier)
        var uninstalled: ClaudeCodeUninstallHooksResult?
        ClaudeCodeOnboarding.uninstallHooksRemotely(conductor: conductor, revokeAlwaysAllow: false,
                                                    files: files, facts: facts) { uninstalled = $0 }
        waitUntil("the uninstall to finish", timeout: connectTimeout) { uninstalled != nil }
        XCTAssertEqual(uninstalled, .success)
        XCTAssertEqual(store.grant(forHost: host), earlier, "kept, as the user chose")
    }

    // MARK: - Two hops

    // ssh integration inside ssh integration: the inner connection has its own socket, nonce and
    // prompt, and a command from the inner host is served by the inner conductor.
    func testTwoHops() throws {
        // By path: the shell that ssh integration injects does not put the utilities on PATH.
        let it2ssh = NSHomeDirectory() + "/.iterm2/it2ssh"
        guard FileManager.default.isExecutableFile(atPath: it2ssh) else {
            throw XCTSkip("\(it2ssh) is not installed (Install Shell Integration with utilities)")
        }
        let session = try XCTUnwrap(connect(forwardAgent: true))
        let outer = try XCTUnwrap(session.conductor)
        session.writeTask("\(shellQuote(it2ssh)) localhost\r")
        waitUntil("the inner connection's it2 proxy", timeout: connectTimeout) {
            guard let current = session.conductor else {
                return false
            }
            return current !== outer && current.parent === outer && current.it2ProxyActive
        }
        let inner = try XCTUnwrap(session.conductor)
        guard inner !== outer else {
            XCTFail("no inner connection. Screen:\n\(screenText(session))")
            return
        }
        XCTAssertNotEqual(inner.it2Nonce, outer.it2Nonce)
        XCTAssertNotEqual(inner.it2SocketPath, outer.it2SocketPath)
        let shellEnv = try XCTUnwrap(shellIT2Environment(session))
        XCTAssertEqual(shellEnv.sock, inner.it2SocketPath, "the inner shell got the inner IT2_SOCK")
        XCTAssertEqual(shellEnv.nonce, inner.it2Nonce, "the inner shell got the inner IT2_NONCE")

        let poll = startRemoteIt2(inner, ["session", "list"])
        answerPrompt(session, inner, selection: IT2AuthorizationOutcome.allowIndex)
        XCTAssertEqual(try XCTUnwrap(finished(poll)).status, 0)
        XCTAssertEqual(inner.it2Authorized, true)
        XCTAssertNil(outer.it2Authorized, "each hop decides for itself")
    }
}
