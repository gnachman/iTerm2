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

private final class LiveHostStateBacking: ClaudeCodeRemoteHostStateBacking {
    var configDirPathByHost: [String: String] = [:]
    var hooksInstalledHosts: [String] = []
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
                         file: StaticString = #filePath, line: UInt = #line) -> PTYSession? {
        var profile = baseProfile()
        profile[KEY_CUSTOM_COMMAND] = kProfilePreferenceCommandTypeSSHValue
        profile[KEY_COMMAND_LINE] = forwardAgent ? "-A localhost" : "localhost"
        profile[KEY_LOAD_SHELL_INTEGRATION_AUTOMATICALLY] = true
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
        let state = ClaudeCodeRemoteHostState(backing: LiveHostStateBacking())
        var result: ClaudeCodeRemoteHooks.InstallResult?
        ClaudeCodeOnboarding.installHooksRemotely(conductor: conductor, configDirectory: directory,
                                                  grantAlwaysAllow: true, state: state) { result = $0 }
        waitUntil("the install to finish", timeout: connectTimeout) { result != nil }
        XCTAssertEqual(result, .thisMac)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory))
        XCTAssertFalse(state.hooksInstalled(onHost: conductor.sshIdentity.stringIdentifier))
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
        let state = ClaudeCodeRemoteHostState(backing: LiveHostStateBacking())
        let files = NotThisMacFiles(ConductorClaudeCodeRemoteFiles(conductor: conductor))

        var installed: ClaudeCodeRemoteHooks.InstallResult?
        ClaudeCodeOnboarding.installHooksRemotely(conductor: conductor, configDirectory: directory,
                                                  grantAlwaysAllow: true,
                                                  files: files, state: state) { installed = $0 }
        waitUntil("the install to finish", timeout: connectTimeout) { installed != nil }
        XCTAssertEqual(installed, .installed)
        let data = try XCTUnwrap(FileManager.default.contents(atPath: settingsPath))
        let settings = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(ClaudeCodeHookSettings.ourCommandsCoveringEveryEvent(
            settings, descriptor: .claudeCode,
            isOurs: { ClaudeCodeHookSettings.isRemoteHookCommand($0, home: home) }))
        XCTAssertEqual(state.configDirectoryPath(forHost: host), directory)
        XCTAssertTrue(state.hooksInstalled(onHost: host))
        waitUntil("the grant to be minted", timeout: commandTimeout) {
            store.grant(forHost: host) != nil
        }

        var healthy: Bool?
        ClaudeCodeOnboarding.remoteHooksHealthy(conductor: conductor, files: files, state: state) { healthy = $0 }
        waitUntil("the health check", timeout: connectTimeout) { healthy != nil }
        XCTAssertEqual(healthy, true)

        var uninstalled: ClaudeCodeUninstallHooksResult?
        ClaudeCodeOnboarding.uninstallHooksRemotely(conductor: conductor, revokeAlwaysAllow: true,
                                                    files: files, state: state) { uninstalled = $0 }
        waitUntil("the uninstall to finish", timeout: connectTimeout) { uninstalled != nil }
        XCTAssertEqual(uninstalled, .success)
        let after = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try XCTUnwrap(FileManager.default.contents(atPath: settingsPath))) as? [String: Any])
        XCTAssertNil(after["hooks"], "nothing of ours left, and nothing else was there")
        XCTAssertFalse(state.hooksInstalled(onHost: host))
        XCTAssertEqual(state.configDirectoryPath(forHost: host), directory, "kept for a reinstall")
        XCTAssertNil(store.grant(forHost: host), "revoked, as the user chose")
    }

    // The user declined both: installing mints no grant, and uninstalling leaves alone a grant the
    // host already had from the authorization prompt.
    func testRemoteHookInstallAndUninstallWithoutGrantChanges() throws {
        let session = try XCTUnwrap(connect())
        let conductor = try XCTUnwrap(session.conductor)
        let host = conductor.sshIdentity.stringIdentifier
        let directory = scratchConfigDirectory()
        let state = ClaudeCodeRemoteHostState(backing: LiveHostStateBacking())
        let files = NotThisMacFiles(ConductorClaudeCodeRemoteFiles(conductor: conductor))

        var installed: ClaudeCodeRemoteHooks.InstallResult?
        ClaudeCodeOnboarding.installHooksRemotely(conductor: conductor, configDirectory: directory,
                                                  grantAlwaysAllow: false,
                                                  files: files, state: state) { installed = $0 }
        waitUntil("the install to finish", timeout: connectTimeout) { installed != nil }
        XCTAssertEqual(installed, .installed)
        XCTAssertNil(store.grant(forHost: host), "no grant unless the user agreed to one")

        let earlier = IT2HostGrant(host: host, id: "earlier", secretSHA256: "hash", granted: Date())
        store.add(earlier)
        var uninstalled: ClaudeCodeUninstallHooksResult?
        ClaudeCodeOnboarding.uninstallHooksRemotely(conductor: conductor, revokeAlwaysAllow: false,
                                                    files: files, state: state) { uninstalled = $0 }
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
