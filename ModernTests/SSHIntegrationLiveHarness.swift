//
//  SSHIntegrationLiveHarness.swift
//  iTerm2 ModernTests
//
//  Live end-to-end harness for it2 over ssh integration, against `ssh localhost`. NOT a unit
//  test: it opens real windows in the test host, runs the real conductor bootstrap and framer
//  over a real ssh connection, and runs the uploaded it2 on the "remote" host, which is this Mac.
//  Because it opens windows it also needs ITERM2_ONSCREEN_TESTS=1 (see OnscreenTestGate): run it
//  with ITERM2_ONSCREEN_TESTS=1 tools/run_ssh_integration_live.sh; otherwise every test skips.
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
//  grants in ~/.iterm2/it2-grants, which are removed afterwards, leaving the ones that were
//  there. Grants on the Mac side go to an in-memory store, never the user's defaults.
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
    private let grantDirectory = NSHomeDirectory() + "/" + IT2GrantToken.remoteDirectoryRelativePath
    private var grantsBefore = Set<String>()

    // Generous: the bootstrap uploads files and starts a framer before it2 can work. Waiting on a
    // condition rather than a fixed delay, so a slow run is slow, not a failure.
    private let connectTimeout: TimeInterval = 90
    private let commandTimeout: TimeInterval = 30

    /// Workgroups this harness adds are saved like any others. A run killed before its tear-down
    /// leaves them behind, where a later run (or the tmux harness) could adopt with them.
    private static let workgroupIDPrefix = "ssh-live-"

    @MainActor
    private static func removeLeftoverWorkgroups() {
        for workgroup in iTermWorkgroupModel.instance.workgroups
        where workgroup.uniqueIdentifier.hasPrefix(workgroupIDPrefix) {
            iTermWorkgroupModel.instance.remove(uniqueIdentifier: workgroup.uniqueIdentifier)
        }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard ProcessInfo.processInfo.environment["ITERM2_SSH_LIVE"] != nil else {
            throw XCTSkip("Live ssh integration harness; run tools/run_ssh_integration_live.sh")
        }
        // It launches real sessions, in windows.
        try OnscreenTestGate.skipUnlessEnabled()
        MainActor.assumeIsolated {
            Self.removeLeftoverWorkgroups()
        }
        MainActor.assumeIsolated {
            grantsBefore = Set((try? FileManager.default.contentsOfDirectory(atPath: grantDirectory)) ?? [])
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
            let grants = (try? FileManager.default.contentsOfDirectory(atPath: grantDirectory)) ?? []
            for name in grants where !grantsBefore.contains(name) {
                try? FileManager.default.removeItem(atPath: grantDirectory + "/" + name)
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
    private func connect(host: String = "localhost",
                         forwardAgent: Bool = false,
                         loadShellIntegration: Bool = true,
                         sshOptions: String = "",
                         command: String? = nil,
                         file: StaticString = #filePath, line: UInt = #line) -> PTYSession? {
        var profile = baseProfile()
        profile[KEY_CUSTOM_COMMAND] = kProfilePreferenceCommandTypeSSHValue
        profile[KEY_COMMAND_LINE] = sshOptions + (forwardAgent ? "-A " : "") + host + (command.map { " " + $0 } ?? "")
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
        // Find the window first: a terminated session no longer knows it.
        let window = session.delegate?.realParentWindow()?.window
        session.terminate()
        window?.close()
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

    // MARK: - Flow control

    // A flood over a slow link, then Ctrl-C. Without flow control the output already in ssh's
    // buffers (its 2 MB channel window, at 20 KB/s about 100 s of it) must arrive before the
    // prompt can. With it, the framer holds the flood in the remote pty, where Ctrl-C discards
    // it, so only about a round trip and twice the target delay of output is in flight.
    func testCtrlCAfterAFloodOnASlowLinkIsPrompt() throws {
        Conductor.flowControlAvailableForTesting = true
        addTeardownBlock { @MainActor in Conductor.flowControlAvailableForTesting = nil }
        let proxy = URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tests/throttle_proxy.py").path
        let session = try XCTUnwrap(connect(
            sshOptions: "-o 'ProxyCommand=/usr/bin/env python3 \(proxy) %h %p 20480' "))
        let conductor = try XCTUnwrap(session.conductor)
        waitUntil("flow control to start", timeout: commandTimeout) {
            conductor.flowController != nil
        }
        XCTAssertEqual(conductor.flowVersion, 2, "the framer gives each flow credit of its own")
        session.writeTask("yes flood\r")
        addTeardownBlock { @MainActor in session.writeTask("\u{3}") }
        // Long enough for the flood to fill whatever buffers it can: 100 KB is 5 s at 20 KB/s.
        waitUntil("the flood to get going", timeout: 60) {
            (conductor.flowController?.consumed ?? 0) > 100_000
        }
        let interrupted = Date()
        session.writeTask("\u{3}")
        session.writeTask("echo after-$((6*7))\r")
        waitUntil("the prompt after Ctrl-C", timeout: 120) {
            screenText(session).contains("after-42")
        }
        let elapsed = Date().timeIntervalSince(interrupted)
        XCTAssertLessThan(elapsed, 10, "Ctrl-C took \(elapsed) s to take effect")
        let stats = try XCTUnwrap(conductor.flowController?.statistics)
        NSLog("Flow control live test: Ctrl-C took %.2f s; statistics %@", elapsed, "\(stats)")
    }

    private func throttledOptions(bytesPerSecond: Int) -> String {
        let proxy = URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tests/throttle_proxy.py").path
        return "-o 'ProxyCommand=/usr/bin/env python3 \(proxy) %h %p \(bytesPerSecond)' "
    }

    /// A link whose rate is read from `rateFile` (bytes per second; 0 is unlimited), so a test can
    /// slow it down and speed it up, with `delay` seconds each way.
    private func throttledOptions(rateFile: String, delay: TimeInterval) -> String {
        let proxy = URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tests/throttle_proxy.py").path
        return "-o 'ProxyCommand=/usr/bin/env python3 \(proxy) %h %p 0 --rate-file \(rateFile) --delay \(delay)' "
    }

    /// What `conductor`'s controller knows now, for a failure message.
    private func flowState(_ conductor: Conductor) -> String {
        guard let s = conductor.flowController?.snapshot(now: conductor.flowClock()) else {
            return "no controller"
        }
        return "W=\(Int(s.window)) outstanding=\(s.outstanding) floor=\(Int(s.floor)) "
            + "rttMin=\(s.rttMin) target=\(s.target) dq=\(s.queueingDelay.map { "\($0)" } ?? "nil") "
            + "rate=\(s.deliveryRate.map { "\(Int($0))" } ?? "nil") slowStart=\(s.slowStart) "
            + "drain=\(s.drain) stats=\(s.statistics)"
    }

    // Diagnostic, not a check: a flood through ITERM2_SSH_FAR_HOST, a host reached over a path
    // that can be throttled (Network Link Conditioner does not shape loopback), printing the
    // controller's state every second to see where it settles and why. Skips without the variable:
    //   ITERM2_SSH_FAR_HOST=nlc-far ITERM2_ONSCREEN_TESTS=1 tools/run_tests_vm.sh --host vm2 \
    //       -e ITERM2_SSH_FAR_HOST -- tools/run_ssh_integration_live.sh testAFloodThroughAFarHost
    func testAFloodThroughAFarHost() throws {
        guard let far = ProcessInfo.processInfo.environment["ITERM2_SSH_FAR_HOST"] else {
            throw XCTSkip("Set ITERM2_SSH_FAR_HOST to a host reached over a throttled path")
        }
        Conductor.flowControlAvailableForTesting = true
        addTeardownBlock { @MainActor in Conductor.flowControlAvailableForTesting = nil }
        let session = try XCTUnwrap(connect(host: far))
        let conductor = try XCTUnwrap(session.conductor)
        waitUntil("flow control", timeout: commandTimeout) { conductor.flowController != nil }
        session.writeTask("yes far-flood\r")
        addTeardownBlock { @MainActor in session.writeTask("\u{3}") }
        let ms = { (v: TimeInterval?) in v.map { String(format: "%.0f", $0 * 1000) } ?? "-" }
        var lastConsumed = conductor.flowController?.consumed ?? 0
        for second in 1...60 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
            guard let s = conductor.flowController?.snapshot(now: conductor.flowClock()) else {
                print("FAR t=\(second) no controller")
                continue
            }
            let rate = s.consumed >= lastConsumed ? s.consumed - lastConsumed : s.consumed
            lastConsumed = s.consumed
            print("FAR t=\(second) wall=\(String(format: "%.2f", Date().timeIntervalSince1970)) consumed/s=\(rate) W=\(Int(s.window)) notArrived=\(s.granted - s.arrived) "
                  + "dq=\(ms(s.queueingDelay)) target=\(ms(s.target)) rttMin=\(ms(s.rttMin)) "
                  + "costKB=\(ms(s.delayBaseline.costPerKilobyte)) rate=\(s.deliveryRate.map { Int($0) } ?? -1) "
                  + "floor=\(Int(s.floor)) slowStart=\(s.slowStart) drain=\(s.drain) "
                  + "decreases=\(s.statistics.decreases) drains=\(s.statistics.drains) recalls=\(s.statistics.creditRecalls) "
                  + "busy=\(s.flows.first?.busy ?? false) waits=\(ms(s.flows.first?.consumptionDelay)) cap=\(s.flows.first?.cap.map { Int($0) } ?? -1)")
        }
        if let events = conductor.flowController?.events {
            for event in events {
                print(String(format: "FAR event %.2f ", event.time) + event.description)
            }
        }
        print("FAR ctrl-c \(interrupt(session)) s")
    }

    // A flood over a fast link that is slowed down and then sped up again, as with Network Link
    // Conditioner turned on and off: the window grows back to what the fast link carries.
    func testTheWindowRecoversWhenTheLinkSpeedsUpAgain() throws {
        Conductor.flowControlAvailableForTesting = true
        addTeardownBlock { @MainActor in Conductor.flowControlAvailableForTesting = nil }
        let rateFile = try makeRateFile()
        let session = try XCTUnwrap(connect(sshOptions: throttledOptions(rateFile: rateFile, delay: 0.015)))
        let conductor = try XCTUnwrap(session.conductor)
        waitUntil("flow control", timeout: commandTimeout) { conductor.flowController != nil }
        try slowDownAndSpeedUp(session, rateFile: rateFile, watching: [conductor])
    }

    // The same through two hops, with the outer one's link slowed and sped up, and the flood in
    // the inner shell.
    func testNestedWindowsRecoverWhenTheLinkSpeedsUpAgain() throws {
        let rateFile = try makeRateFile()
        let (session, outer, inner) = try connectTwoHops(outerOptions: throttledOptions(rateFile: rateFile,
                                                                                        delay: 0.015))
        try slowDownAndSpeedUp(session, rateFile: rateFile, watching: [outer, inner])
    }

    /// A rate file for throttledOptions(rateFile:delay:), unlimited for now.
    private func makeRateFile() throws -> String {
        let rateFile = (NSTemporaryDirectory() as NSString).appendingPathComponent("rate-\(UUID().uuidString)")
        try "0".write(toFile: rateFile, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: rateFile) }
        return rateFile
    }

    /// Floods `session` over a fast link, slows the link to 500 Kbit/s, speeds it up again, and
    /// expects each conductor in `watching` to get back at least half its rate from before.
    private func slowDownAndSpeedUp(_ session: PTYSession, rateFile: String, watching conductors: [Conductor],
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        session.writeTask("yes link-speeds-up\r")
        addTeardownBlock { @MainActor in session.writeTask("\u{3}") }
        func rates() -> [Double] {
            let before = conductors.map { $0.flowController?.consumed ?? 0 }
            let start = Date()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 5))
            let elapsed = Date().timeIntervalSince(start)
            return zip(conductors, before).map { conductor, before in
                let after = conductor.flowController?.consumed ?? 0
                return Double(after >= before ? after - before : after) / elapsed
            }
        }
        func states() -> String {
            conductors.map { "depth \($0.depth): \(flowState($0))" }.joined(separator: "; ")
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 10))
        let before = rates()
        let statesBefore = states()

        // 500 Kbit/s.
        try "62500".write(toFile: rateFile, atomically: true, encoding: .utf8)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 15))
        let slow = rates()

        try "0".write(toFile: rateFile, atomically: true, encoding: .utf8)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 30))
        let after = rates()
        print("before \(before.map(Int.init)) B/s, throttled \(slow.map(Int.init)) B/s, after \(after.map(Int.init)) B/s")
        for (index, conductor) in conductors.enumerated() {
            XCTAssertLessThan(slow[index], 80_000, "depth \(conductor.depth): the throttle held: \(states())",
                              file: file, line: line)
            XCTAssertGreaterThan(after[index], before[index] / 2,
                                 "depth \(conductor.depth): before \(Int(before[index])) B/s (\(statesBefore)), "
                                 + "throttled \(Int(slow[index])) B/s, after \(Int(after[index])) B/s: \(states())",
                                 file: file, line: line)
        }
    }

    /// Presses Ctrl-C in `session` and returns how long its prompt took to come back.
    private func interrupt(_ session: PTYSession) -> TimeInterval {
        // A marker of its own, so a second Ctrl-C in a test is not answered by the first's.
        let marker = "after-\(UUID().uuidString.prefix(8))"
        let interrupted = Date()
        session.writeTask("\u{3}")
        session.writeTask("echo \(marker)-$((6*7))\r")
        waitUntil("the prompt after Ctrl-C", timeout: 120) {
            screenText(session).contains("\(marker)-42")
        }
        return Date().timeIntervalSince(interrupted)
    }

    // A workgroup peer flooding the same slow link does not hold up the leader: each has credit
    // of its own, so Ctrl-C after the leader's own flood still brings its prompt back promptly,
    // and the peer's output keeps flowing meanwhile.
    func testAFloodingPeerLeavesCtrlCInTheLeaderPrompt() throws {
        Conductor.flowControlAvailableForTesting = true
        addTeardownBlock { @MainActor in Conductor.flowControlAvailableForTesting = nil }
        let session = try XCTUnwrap(connect(sshOptions: throttledOptions(bytesPerSecond: 20480)))
        let conductor = try XCTUnwrap(session.conductor)
        waitUntil("flow control to start", timeout: commandTimeout) {
            conductor.flowController != nil
        }
        XCTAssertEqual(conductor.flowVersion, 2)
        let root = WGFix.makeRoot()
        let peer = WGFix.makePeer(parentID: root.uniqueIdentifier, command: "exec yes pane-flood")
        let workgroup = WGFix.wrap(name: "flooding peer", sessions: [root, peer], uniqueIdentifier: Self.workgroupIDPrefix + UUID().uuidString)
        iTermWorkgroupModel.instance.add(workgroup)
        addTeardownBlock { @MainActor in
            iTermWorkgroupController.instance.exit(on: session)
            iTermWorkgroupModel.instance.remove(uniqueIdentifier: workgroup.uniqueIdentifier)
        }
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: session,
                                                              mechanism: .menu))
        let port = try XCTUnwrap(session.peerPort as? iTermWorkgroupPeerPort)
        var pid: Int32?
        waitUntil("the peer to start as a pane", timeout: connectTimeout) {
            pid = port.session(forIdentifier: peer.uniqueIdentifier)?.shell.framerPaneJobManager?.remotePID
            return pid != nil
        }
        let pane = FramerFlowController.Flow.pane(try XCTUnwrap(pid))
        let peerSession = try XCTUnwrap(port.session(forIdentifier: peer.uniqueIdentifier))
        let controller = try XCTUnwrap(conductor.flowController)
        waitUntil("the peer's flood to get going", timeout: 60) {
            (controller.granted(to: pane) ?? 0) > 30_000
        }

        let leaderBefore = controller.granted(to: .leader) ?? 0
        session.writeTask("yes leader-flood\r")
        addTeardownBlock { @MainActor in session.writeTask("\u{3}") }
        waitUntil("the leader's flood to get going beside it", timeout: 60) {
            (controller.granted(to: .leader) ?? 0) > leaderBefore + 30_000
        }
        let elapsed = interrupt(session)
        XCTAssertLessThan(elapsed, 3, "Ctrl-C took \(elapsed) s to take effect")
        let paneAfter = controller.granted(to: pane) ?? 0
        func state() -> String {
            let now = conductor.flowClock()
            return "granted \(controller.granted(to: pane) ?? -1) backlog \(controller.backlog(of: pane) ?? -1) " +
                "window \(controller.window(of: pane) ?? -1) of \(controller.window) " +
                "waited \(controller.consumptionDelay(of: pane, now: now) ?? -1) " +
                "peer lines \(Int64(peerSession.screen.numberOfLines()) + peerSession.screen.totalScrollbackOverflow())"
        }
        // Long enough that output stuck unconsumed (a byte its session ran but did not report)
        // would show: the pane's credit would stop coming back.
        waitUntil("the peer's output to keep flowing", timeout: 60) {
            (controller.granted(to: pane) ?? 0) > paneAfter + 30_000
        }
        let waited = controller.consumptionDelay(of: pane, now: conductor.flowClock()) ?? 0
        XCTAssertLessThan(waited, 2, "the peer's output is waiting to be consumed: \(state())")
        NSLog("Flow control live test with a flooding peer: Ctrl-C took %.2f s; statistics %@",
              elapsed, "\(controller.statistics)")
    }

    /// Takes a pane's output and never lets its session consume it, like a peer whose session
    /// has stopped reading.
    private final class StalledPaneClient: NSObject, ConductorPaneClient {
        private(set) var received = 0
        func conductorPaneDidOutput(_ data: Data) { received += data.count }
        func conductorPaneDidExit(code: Int32) {}
        func conductorPaneDidLoseConnection() {}
    }

    // A pane whose session stops consuming holds back only itself: the framer stops at the
    // pane's window, so nothing piles up in iTerm2, while the leader keeps the connection.
    func testAStalledPaneHoldsBackOnlyItself() throws {
        Conductor.flowControlAvailableForTesting = true
        addTeardownBlock { @MainActor in Conductor.flowControlAvailableForTesting = nil }
        let session = try XCTUnwrap(connect())
        let conductor = try XCTUnwrap(session.conductor)
        waitUntil("flow control to start", timeout: commandTimeout) {
            conductor.flowController != nil
        }
        XCTAssertEqual(conductor.flowVersion, 2)
        let client = StalledPaneClient()
        var started: Int32?
        conductor.startPane(rows: 24, cols: 80, directory: "~", command: "exec yes stalled-pane",
                            client: client) { started = $0 }
        waitUntil("the pane to start", timeout: commandTimeout) { started != nil }
        let pid = try XCTUnwrap(started)
        addTeardownBlock { @MainActor in conductor.killPane(pid) }
        let controller = try XCTUnwrap(conductor.flowController)
        waitUntil("the pane to use up its credit", timeout: commandTimeout) {
            client.received > 0 && client.received >= (controller.granted(to: .pane(pid)) ?? 0)
        }

        let leaderBefore = controller.granted(to: .leader) ?? 0
        session.writeTask("yes leader-flood\r")
        addTeardownBlock { @MainActor in session.writeTask("\u{3}") }
        waitUntil("the leader to flood well past anything the pane could take", timeout: 60) {
            (controller.granted(to: .leader) ?? 0) > leaderBefore + 4 * 1024 * 1024
        }
        XCTAssertLessThan(client.received, 512 * 1024,
                          "the pane's output stopped at its window instead of piling up")
        // A frame counts as arrived when it is parsed and reaches the client a moment later.
        waitUntil("all that arrived to reach the pane's client, none of it consumed", timeout: commandTimeout) {
            client.received == controller.backlog(of: .pane(pid))
        }
        let elapsed = interrupt(session)
        XCTAssertLessThan(elapsed, 3, "Ctrl-C took \(elapsed) s to take effect")
        NSLog("Flow control live test with a stalled pane: it holds %d bytes; Ctrl-C took %.2f s",
              client.received, elapsed)
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
    // leader's directory there. IT2_SOCK is what tells it apart from a
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
            command: #"printf '%s\n%s\n%s\n' "$PWD" "$IT2_SOCK" "$TERM_SESSION_ID" > "# + shellQuote(output) + "; sleep 60")
        let diffOutput = directory + "/diff-report"
        let diffPeer = WGFix.makePeer(parentID: root.uniqueIdentifier,
                                      displayName: "Diff",
                                      command: "pwd > " + shellQuote(diffOutput) + "; sleep 60",
                                      mode: .diff)
        let workgroup = WGFix.wrap(name: "remote peer", sessions: [root, peer, diffPeer], uniqueIdentifier: Self.workgroupIDPrefix + UUID().uuidString)
        iTermWorkgroupModel.instance.add(workgroup)
        addTeardownBlock { @MainActor in
            iTermWorkgroupController.instance.exit(on: session)
            iTermWorkgroupModel.instance.remove(uniqueIdentifier: workgroup.uniqueIdentifier)
        }
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: session,
                                                              mechanism: .menu))
        waitUntil("the peer to report", timeout: connectTimeout) {
            ((try? String(contentsOfFile: output, encoding: .utf8)) ?? "").split(separator: "\n").count == 3
        }
        let lines = try XCTUnwrap(try? String(contentsOfFile: output, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual((lines[0] as NSString).resolvingSymlinksInPath, realDirectory, "the leader's directory")
        XCTAssertFalse(lines[1].isEmpty, "started over SSH Integration, so it has it2")
        let port = try XCTUnwrap(session.peerPort as? iTermWorkgroupPeerPort)
        // The program can report before the pane's reply reaches iTerm2 and the workgroup
        // gets its session.
        waitUntil("the workgroup to get the peer's session", timeout: commandTimeout) {
            port.session(forIdentifier: peer.uniqueIdentifier) != nil
        }
        let peerSession = try XCTUnwrap(port.session(forIdentifier: peer.uniqueIdentifier))
        XCTAssertNotNil(peerSession.shell.framerPaneJobManager,
                        "a pane of the leader's framer, not a connection of its own")
        XCTAssertNil(peerSession.conductor)
        XCTAssertTrue(lines[2].hasSuffix(peerSession.guid), "the peer's own session id: \(lines[2])")
        // A diff peer starts when it is shown and the poller has seen a change, so its diff is of
        // the tree as it is then.
        XCTAssertTrue(port.activate(identifier: diffPeer.uniqueIdentifier))
        waitUntil("the diff peer to launch once shown", timeout: connectTimeout) {
            let reported = (try? String(contentsOfFile: diffOutput, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return reported.map { ($0 as NSString).resolvingSymlinksInPath } == realDirectory
        }
    }

    // A pane peer takes input, ends when its program does, and relaunches as a new pane.
    func testAPanePeerTakesInputEndsAndRelaunches() throws {
        let session = try XCTUnwrap(connect())
        let directory = (NSTemporaryDirectory() as NSString).appendingPathComponent("wg-pane-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: directory) }
        let typed = directory + "/typed"
        let relaunched = directory + "/relaunched"
        let root = WGFix.makeRoot()
        let peer = WGFix.makePeer(parentID: root.uniqueIdentifier,
                                  command: "IFS= read -r line; printf '%s' \"$line\" > " + shellQuote(typed))
        let workgroup = WGFix.wrap(name: "pane peer", sessions: [root, peer], uniqueIdentifier: Self.workgroupIDPrefix + UUID().uuidString)
        iTermWorkgroupModel.instance.add(workgroup)
        addTeardownBlock { @MainActor in
            iTermWorkgroupController.instance.exit(on: session)
            iTermWorkgroupModel.instance.remove(uniqueIdentifier: workgroup.uniqueIdentifier)
        }
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: session,
                                                              mechanism: .menu))
        let port = try XCTUnwrap(session.peerPort as? iTermWorkgroupPeerPort)
        var peerSession: PTYSession?
        waitUntil("the peer to start as a pane", timeout: connectTimeout) {
            peerSession = port.session(forIdentifier: peer.uniqueIdentifier)
            return peerSession?.shell.framerPaneJobManager?.remotePID != nil
        }
        let pane = try XCTUnwrap(peerSession)
        pane.writeTask("typed into the pane\r")
        waitUntil("the pane to read the input", timeout: commandTimeout) {
            (try? String(contentsOfFile: typed, encoding: .utf8)) == "typed into the pane"
        }
        waitUntil("the session to end with its program", timeout: commandTimeout) {
            pane.exited
        }
        pane.relaunchWorkgroupMember(command: "echo again > " + shellQuote(relaunched) + "; sleep 60")
        waitUntil("the relaunched pane to run", timeout: commandTimeout) {
            (try? String(contentsOfFile: relaunched, encoding: .utf8)) == "again\n"
        }
        XCTAssertNotNil(pane.shell.framerPaneJobManager, "still a pane after relaunching")
    }

    // When the leader's connection is recovered in place, its conductor is replaced while the
    // pane keeps running on the host. The peer reattaches to the new conductor and keeps
    // working. Recovery starts here the way it does when the parser loses the conductor's
    // hook (a terminal reset, say): framer's next output arrives unframed.
    func testAPanePeerSurvivesRecoveringTheLeadersConnection() throws {
        let session = try XCTUnwrap(connect())
        let directory = (NSTemporaryDirectory() as NSString).appendingPathComponent("wg-recover-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: directory) }
        let heard = directory + "/heard"
        let root = WGFix.makeRoot()
        let peer = WGFix.makePeer(
            parentID: root.uniqueIdentifier,
            command: "while IFS= read -r line; do printf '%s\\n' \"$line\" >> " + shellQuote(heard)
                + "; echo \"pane-said-$line\"; done")
        let workgroup = WGFix.wrap(name: "recovered pane peer", sessions: [root, peer], uniqueIdentifier: Self.workgroupIDPrefix + UUID().uuidString)
        iTermWorkgroupModel.instance.add(workgroup)
        addTeardownBlock { @MainActor in
            iTermWorkgroupController.instance.exit(on: session)
            iTermWorkgroupModel.instance.remove(uniqueIdentifier: workgroup.uniqueIdentifier)
        }
        XCTAssertTrue(iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroup.uniqueIdentifier,
                                                              on: session,
                                                              mechanism: .menu))
        let port = try XCTUnwrap(session.peerPort as? iTermWorkgroupPeerPort)
        var peerSession: PTYSession?
        waitUntil("the peer to start as a pane", timeout: connectTimeout) {
            peerSession = port.session(forIdentifier: peer.uniqueIdentifier)
            return peerSession?.shell.framerPaneJobManager?.remotePID != nil
        }
        let pane = try XCTUnwrap(peerSession)
        let panePID = try XCTUnwrap(pane.shell.framerPaneJobManager?.remotePID)
        pane.writeTask("before\r")
        waitUntil("the pane to answer", timeout: commandTimeout) {
            self.screenText(pane).contains("pane-said-before")
        }

        // The pane's echo of this is framer output, which starts recovery. Its own echo may be
        // lost to recovery, but whatever the pane prints after is not.
        try recoverConnection(of: session) {
            pane.writeTask("during\r")
        }
        pane.writeTask("after\r")
        waitUntil("the reattached pane to take input", timeout: commandTimeout) {
            ((try? String(contentsOfFile: heard, encoding: .utf8)) ?? "").contains("after\n")
        }
        waitUntil("its output to reach the session", timeout: commandTimeout) {
            self.screenText(pane).contains("pane-said-after")
        }
        XCTAssertFalse(pane.exited)
        XCTAssertEqual(pane.shell.framerPaneJobManager?.remotePID, panePID, "the same pane")
        // What a restart restores it from.
        XCTAssertEqual((pane.framerPaneArrangement?["pid"] as? NSNumber)?.int32Value, panePID)
    }

    /// Recovers `session`'s connection in place, the way it happens when the parser loses the
    /// conductor's hook (a terminal reset, say): framer's next output, which `provokeOutput`
    /// causes, arrives unframed.
    private func recoverConnection(of session: PTYSession, provokeOutput: () -> Void,
                                   file: StaticString = #filePath, line: UInt = #line) throws {
        let original = try XCTUnwrap(session.conductor, file: file, line: line)
        session.screen.performBlock(joinedThreads: { terminal, _, _ in
            terminal?.parser.forceUnhookDCS(nil)
        })
        provokeOutput()
        waitUntil("the connection to be recovered", timeout: connectTimeout, file: file, line: line) {
            guard let conductor = session.conductor else {
                return false
            }
            return conductor !== original && conductor.framing && !conductor.awaitingResynchronization
        }
    }

    // MARK: - Stranded panes

    private final class HarnessPaneClient: NSObject, ConductorPaneClient {
        func conductorPaneDidOutput(_ data: Data) {}
        func conductorPaneDidExit(code: Int32) {}
        func conductorPaneDidLoseConnection() {}
    }

    /// A pane on `session`'s connection with no session for it, as when iTerm2 restarts without
    /// restoring a peer's session. It has written "early-go", which the conductor keeps. The
    /// connection is then recovered, after which iTerm2 looks for such panes.
    private func strandPane(on session: PTYSession) throws -> Int32 {
        FramerPaneStrandedFinder.shared.restorationDidSettle()
        let conductor = try XCTUnwrap(session.conductor)
        let client = HarnessPaneClient()
        var started: Int32?
        conductor.startPane(rows: 24, cols: 80, directory: "~",
                            command: "IFS= read -r x; echo \"early-$x\"; while IFS= read -r line; do echo \"pane-said-$line\"; done",
                            client: client) { started = $0 }
        waitUntil("the pane to start", timeout: commandTimeout) { started != nil }
        let pid = try XCTUnwrap(started)
        conductor.panes[pid] = nil
        conductor.sendToPane(pid, data: Data("go\n".utf8))
        waitUntil("the conductor to keep the pane's output", timeout: commandTimeout) {
            String(decoding: conductor.unclaimedPanes[pid]?.output ?? Data(), as: UTF8.self).contains("early-go")
        }
        try recoverConnection(of: session) {
            session.writeTask("\r")
        }
        return pid
    }

    private func strandedAnnouncementIdentifier(_ session: PTYSession) -> String? {
        return StrandedFramerPaneAnnouncer.announcementIdentifier(for: session)
    }

    private func sessionShowingPane(_ pid: Int32) -> PTYSession? {
        return iTermController.sharedInstance()?.allSessions().first {
            $0.shell.framerPaneJobManager?.remotePID == pid
        }
    }

    // The user is told, and opening it puts it in a tab with what it wrote meanwhile. It works
    // like any pane session, and after a restart it reattaches through the leader's session.
    func testAStrandedPaneOpensInATab() throws {
        let session = try XCTUnwrap(connect())
        let pid = try strandPane(on: session)
        waitUntil("the user to be told", timeout: commandTimeout) {
            strandedAnnouncementIdentifier(session).map { session.hasAnnouncement(withIdentifier: $0) } ?? false
        }
        XCTAssertNil(sessionShowingPane(pid), "nothing is opened before the user decides")
        XCTAssertTrue(session.debugSelectAction(0, ofAnnouncementWithIdentifier: try XCTUnwrap(strandedAnnouncementIdentifier(session))))
        var adopted: PTYSession?
        waitUntil("the pane to open in a tab", timeout: commandTimeout) {
            adopted = sessionShowingPane(pid)
            return adopted?.delegate?.realParentWindow() != nil
        }
        let tab = try XCTUnwrap(adopted)
        addTeardownBlock { @MainActor in
            self.close(tab)
        }
        waitUntil("what it wrote without a session to be shown", timeout: commandTimeout) {
            self.screenText(tab).contains("early-go")
        }
        tab.writeTask("later\r")
        waitUntil("it to take input", timeout: commandTimeout) {
            self.screenText(tab).contains("pane-said-later")
        }
        XCTAssertEqual(tab.framerPaneArrangement?["owner"] as? String, session.guid)
        XCTAssertNil(session.conductor?.unclaimedPanes[pid], "claimed, so nothing is kept for it")
    }

    // Stopping kills it on the host, and no session is opened for it.
    func testAStrandedPaneCanBeStopped() throws {
        let session = try XCTUnwrap(connect())
        let pid = try strandPane(on: session)
        waitUntil("the user to be told", timeout: commandTimeout) {
            strandedAnnouncementIdentifier(session).map { session.hasAnnouncement(withIdentifier: $0) } ?? false
        }
        XCTAssertTrue(session.debugSelectAction(1, ofAnnouncementWithIdentifier: try XCTUnwrap(strandedAnnouncementIdentifier(session))))
        // The host is this Mac.
        waitUntil("the pane to be stopped", timeout: commandTimeout) {
            kill(pid, 0) != 0 && errno == ESRCH
        }
        waitUntil("its exit to be heard", timeout: commandTimeout) {
            session.conductor?.stoppingPanes.isEmpty == true
        }
        XCTAssertNil(sessionShowingPane(pid))
        XCTAssertNil(session.conductor?.unclaimedPanes[pid])
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
        let grantID = try XCTUnwrap(store.grant(forHost: host)).id
        let attributes = try FileManager.default.attributesOfItem(atPath: grantDirectory + "/" + grantID)
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
    // MARK: - tmux Integration over SSH Integration

    // A pane whose shell doesn't run shell integration never reports its host. On a tmux server
    // reached through SSH Integration it takes the connection's, so its git status is read on
    // that host. Its directory comes from tmux.
    func testATmuxPaneWithoutShellIntegrationTakesTheConnectionsHost() throws {
        let tmux = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        let tmuxPath = try XCTUnwrap(tmux, "no tmux on this machine")
        let socket = "it2live-\(UUID().uuidString.prefix(8))"
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent("it2live-repo-\(UUID().uuidString)")
            .resolvingSymlinksInPath().path
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["init", "-q", repo]
        try git.run()
        git.waitUntilExit()
        addTeardownBlock {
            let kill = Process()
            kill.executableURL = URL(fileURLWithPath: tmuxPath)
            kill.arguments = ["-L", socket, "kill-server"]
            try? kill.run()
            kill.waitUntilExit()
            try? FileManager.default.removeItem(atPath: repo)
        }
        let gateway = try XCTUnwrap(connect(loadShellIntegration: false,
                                            command: "\(tmuxPath) -L \(socket) -f /dev/null -CC new-session -c \(repo) /bin/sh"))
        waitUntil("the tmux pane's session", timeout: connectTimeout) {
            gateway.tmuxController?.session(forWindowPane: 0) != nil
        }
        let pane = try XCTUnwrap(gateway.tmuxController?.session(forWindowPane: 0))
        XCTAssertNil(pane.currentHost, "the pane's shell reports nothing")
        let conductor = try XCTUnwrap(gateway.conductor)
        waitUntil("the pane to take the connection's host", timeout: commandTimeout) {
            let host = pane.genericScope.value(forVariableName: iTermVariableKeySessionHostname) as? String
            return host != nil && (host == conductor.discoveredHostname || host == conductor.sshIdentity.hostname)
        }
        waitUntil("the pane to be known as remote", timeout: commandTimeout) {
            pane.genericScope.value(forVariableName: iTermVariableKeySessionIsLocalhost) as? Bool == false
        }
        XCTAssertEqual(pane.genericScope.value(forVariableName: iTermVariableKeySessionIsLocalhost) as? Bool, false,
                       "gateway job \(String(describing: gateway.genericScope.value(forVariableName: iTermVariableKeySessionJob)))")
        // The directory is polled from tmux as output arrives, as it does when the user types.
        pane.writeTask("\n")
        // Compared resolved: tmux reports the physical path, /private/var for /var.
        let resolved = { (path: String?) in path.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } }
        waitUntil("the pane's directory from tmux", timeout: commandTimeout) {
            resolved(pane.genericScope.value(forVariableName: iTermVariableKeySessionPath) as? String) == resolved(repo)
        }
        XCTAssertNotNil(iTermRemoteGitPollWorker.worker(forScope: pane.genericScope),
                        "its git status is read through the connection")
    }

    // A plain ssh from the connected host to another runs tmux there, which isn't the
    // connection's host, so the panes are not said to be on it. (Here both are this machine, but
    // nothing tells the connection that.)
    func testATmuxPaneBeyondAPlainSSHIsNotGivenTheConnectionsHost() throws {
        let tmux = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        let tmuxPath = try XCTUnwrap(tmux, "no tmux on this machine")
        let socket = "it2live-\(UUID().uuidString.prefix(8))"
        addTeardownBlock {
            let kill = Process()
            kill.executableURL = URL(fileURLWithPath: tmuxPath)
            kill.arguments = ["-L", socket, "kill-server"]
            try? kill.run()
            kill.waitUntilExit()
        }
        let gateway = try XCTUnwrap(connect(loadShellIntegration: false,
                                            command: "ssh -o BatchMode=yes -tt localhost \(tmuxPath) -L \(socket) -f /dev/null -CC new-session /bin/sh"))
        waitUntil("the tmux pane's session", timeout: connectTimeout) {
            gateway.tmuxController?.session(forWindowPane: 0) != nil
        }
        let pane = try XCTUnwrap(gateway.tmuxController?.session(forWindowPane: 0))
        waitUntil("the gateway's job to be known", timeout: commandTimeout) {
            (gateway.genericScope.value(forVariableName: iTermVariableKeySessionJob) as? String) != nil
        }
        XCTAssertEqual(gateway.genericScope.value(forVariableName: iTermVariableKeySessionJob) as? String, "ssh")
        XCTAssertNil(pane.genericScope.value(forVariableName: iTermVariableKeySessionIsLocalhost),
                     "no host is inferred for a pane on another host")
    }

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

    // MARK: - Flow control over two hops

    /// `it2ssh localhost` inside an ssh integration session to localhost, each with the given
    /// ssh options, once both conductors run flow control version 2.
    private func connectTwoHops(outerOptions: String = "", innerOptions: String = "",
                                file: StaticString = #filePath,
                                line: UInt = #line) throws -> (PTYSession, Conductor, Conductor) {
        let it2ssh = NSHomeDirectory() + "/.iterm2/it2ssh"
        guard FileManager.default.isExecutableFile(atPath: it2ssh) else {
            throw XCTSkip("\(it2ssh) is not installed (Install Shell Integration with utilities)")
        }
        Conductor.flowControlAvailableForTesting = true
        addTeardownBlock { @MainActor in Conductor.flowControlAvailableForTesting = nil }
        let session = try XCTUnwrap(connect(forwardAgent: true, sshOptions: outerOptions), file: file, line: line)
        let outer = try XCTUnwrap(session.conductor, file: file, line: line)
        waitUntil("the outer conductor's flow control", timeout: commandTimeout, file: file, line: line) {
            outer.flowController != nil
        }
        session.writeTask("\(shellQuote(it2ssh)) \(innerOptions)localhost\r")
        waitUntil("the inner connection's flow control", timeout: connectTimeout, file: file, line: line) {
            guard let current = session.conductor, current !== outer, current.parent === outer else {
                return false
            }
            return current.it2ProxyActive && current.flowController != nil
        }
        let inner = try XCTUnwrap(session.conductor, file: file, line: line)
        XCTAssertEqual(outer.flowVersion, 2, file: file, line: line)
        XCTAssertEqual(inner.flowVersion, 2, "the inner framer is controlled too", file: file, line: line)
        return (session, outer, inner)
    }

    private func flowSummary(_ outer: Conductor, _ inner: Conductor) -> String {
        let now = outer.flowClock()
        func describe(_ c: Conductor) -> String {
            guard let f = c.flowController else {
                return "off"
            }
            return "window \(Int(f.window)) granted \(f.granted) consumed \(f.consumed) "
                + "dq \(f.queueingDelay(now: now) ?? -1) feedback \(f.feedbackDelay(now: now)) "
                + "carrier window \(f.carrierWindow.map { String(Int($0)) } ?? "none") \(f.statistics)"
        }
        return "outer: \(describe(outer)); inner: \(describe(inner))"
    }

    /// Floods the inner host's shell until its controller has seen `bytes`, then presses Ctrl-C
    /// and returns how long the inner prompt took to come back.
    private func floodThenInterrupt(_ session: PTYSession, _ outer: Conductor, _ inner: Conductor,
                                    bytes: Int = 100_000) -> TimeInterval {
        session.writeTask("yes inner-flood\r")
        addTeardownBlock { @MainActor in session.writeTask("\u{3}") }
        waitUntil("the inner flood to get going", timeout: 90) {
            (inner.flowController?.consumed ?? 0) > bytes
        }
        let elapsed = interrupt(session)
        NSLog("Two-hop flow control: Ctrl-C took %.2f s; %@", elapsed, flowSummary(outer, inner))
        return elapsed
    }

    // host1 far away, host2 near it, as with a bastion. The inner flood waits on host2, where
    // Ctrl-C discards it, rather than in host1's pty and the slow hop's buffers. Half a second
    // to a second.
    func testCtrlCAtTheInnerPromptBehindASlowOuterHop() throws {
        let (session, outer, inner) = try connectTwoHops(outerOptions: throttledOptions(bytesPerSecond: 20480))
        let elapsed = floodThenInterrupt(session, outer, inner)
        XCTAssertLessThan(elapsed, 3, "Ctrl-C took \(elapsed) s: \(flowSummary(outer, inner))")
        XCTAssertNotNil(inner.flowController?.carrierWindow, "the inner window follows the outer leader's")
    }

    // What the inner framer's flow control is for: with only the outer framer controlled, the
    // inner flood fills host1's pty and the slow hop's buffers, and Ctrl-C waits for all of it
    // (88 s when measured).
    func testWithoutInnerFlowControlCtrlCWaitsBehindASlowOuterHop() throws {
        Conductor.nestedFlowControlAvailableForTesting = false
        addTeardownBlock { @MainActor in Conductor.nestedFlowControlAvailableForTesting = nil }
        let it2ssh = NSHomeDirectory() + "/.iterm2/it2ssh"
        guard FileManager.default.isExecutableFile(atPath: it2ssh) else {
            throw XCTSkip("\(it2ssh) is not installed (Install Shell Integration with utilities)")
        }
        Conductor.flowControlAvailableForTesting = true
        addTeardownBlock { @MainActor in Conductor.flowControlAvailableForTesting = nil }
        let session = try XCTUnwrap(connect(forwardAgent: true, sshOptions: throttledOptions(bytesPerSecond: 20480)))
        let outer = try XCTUnwrap(session.conductor)
        waitUntil("the outer conductor's flow control", timeout: commandTimeout) { outer.flowController != nil }
        session.writeTask("\(shellQuote(it2ssh)) localhost\r")
        waitUntil("the inner connection", timeout: connectTimeout) {
            guard let c = session.conductor, c !== outer else { return false }
            return c.it2ProxyActive
        }
        let inner = try XCTUnwrap(session.conductor)
        XCTAssertNil(inner.flowController)
        session.writeTask("yes inner-flood\r")
        addTeardownBlock { @MainActor in
            session.writeTask("\u{3}")
        }
        let before = outer.flowController?.consumed ?? 0
        waitUntil("the inner flood to get going", timeout: 90) {
            (outer.flowController?.consumed ?? 0) > before + 100_000
        }
        let marker = "after-\(UUID().uuidString.prefix(8))"
        session.writeTask("\u{3}")
        session.writeTask("echo \(marker)-$((6*7))\r")
        let deadline = Date(timeIntervalSinceNow: 15)
        while Date() < deadline && !screenText(session).contains("\(marker)-42") {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        }
        XCTAssertFalse(screenText(session).contains("\(marker)-42"),
                       "Ctrl-C took effect within 15 s without the inner framer controlled")
    }

    // host1 near, host2 far away.
    func testCtrlCAtTheInnerPromptBehindASlowInnerHop() throws {
        let (session, outer, inner) = try connectTwoHops(innerOptions: throttledOptions(bytesPerSecond: 20480))
        let elapsed = floodThenInterrupt(session, outer, inner)
        XCTAssertLessThan(elapsed, 3, "Ctrl-C took \(elapsed) s: \(flowSummary(outer, inner))")
    }

    // A pane on the inner host whose session stops consuming holds back only itself, while the
    // inner leader floods through both hops.
    func testAStalledInnerPaneHoldsBackOnlyItself() throws {
        let (session, outer, inner) = try connectTwoHops()
        let client = StalledPaneClient()
        var started: Int32?
        inner.startPane(rows: 24, cols: 80, directory: "~", command: "exec yes stalled-inner-pane",
                        client: client) { started = $0 }
        waitUntil("the inner pane to start", timeout: commandTimeout) { started != nil }
        let pid = try XCTUnwrap(started)
        addTeardownBlock { @MainActor in inner.killPane(pid) }
        let controller = try XCTUnwrap(inner.flowController)
        waitUntil("the pane to use up its credit", timeout: commandTimeout) {
            client.received > 0 && client.received >= (controller.granted(to: .pane(pid)) ?? 0)
        }
        let leaderBefore = controller.granted(to: .leader) ?? 0
        session.writeTask("yes inner-flood\r")
        addTeardownBlock { @MainActor in session.writeTask("\u{3}") }
        waitUntil("the inner leader to flood well past anything the pane could take", timeout: 90) {
            (controller.granted(to: .leader) ?? 0) > leaderBefore + 4 * 1024 * 1024
        }
        XCTAssertLessThan(client.received, 512 * 1024,
                          "the pane's output stopped at its window instead of piling up")
        // A frame counts as arrived when it is parsed and reaches the client a moment later.
        waitUntil("all that arrived to reach the pane's client, none of it consumed", timeout: commandTimeout) {
            client.received == controller.backlog(of: .pane(pid))
        }
        let elapsed = interrupt(session)
        XCTAssertLessThan(elapsed, 3, "Ctrl-C took \(elapsed) s: \(flowSummary(outer, inner))")
    }

    // Ending the inner connection mid-flood leaves the outer one controlled, and the next inner
    // connection is controlled again.
    func testTheInnerConnectionEndsAndStartsAgainUnderFlowControl() throws {
        let (session, outer, inner) = try connectTwoHops(outerOptions: throttledOptions(bytesPerSecond: 40960))
        _ = floodThenInterrupt(session, outer, inner, bytes: 50_000)
        session.writeTask("exit\r")
        waitUntil("the outer conductor to be current again", timeout: commandTimeout) {
            session.conductor === outer
        }
        XCTAssertNil(inner.flowController, "the ended conductor stopped its controller")
        XCTAssertNotNil(outer.flowController)
        var sessionLedger: FramerFlowLedger?
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            sessionLedger = mutableState.flowLedger
        })
        let ledger = try XCTUnwrap(sessionLedger)
        XCTAssertTrue(ledger.isActive(depth: 0))
        XCTAssertFalse(ledger.isActive(depth: 1))

        // The outer host still floods and stops at once.
        session.writeTask("yes outer-flood\r")
        let before = outer.flowController?.consumed ?? 0
        waitUntil("the outer flood to get going", timeout: 60) {
            (outer.flowController?.consumed ?? 0) > before + 50_000
        }
        let outerElapsed = interrupt(session)
        XCTAssertLessThan(outerElapsed, 3, "Ctrl-C at the outer prompt took \(outerElapsed) s")

        let it2ssh = NSHomeDirectory() + "/.iterm2/it2ssh"
        session.writeTask("\(shellQuote(it2ssh)) localhost\r")
        waitUntil("a new inner connection's flow control", timeout: connectTimeout) {
            guard let current = session.conductor, current !== outer, current !== inner else {
                return false
            }
            return current.it2ProxyActive && current.flowController != nil
        }
        let second = try XCTUnwrap(session.conductor)
        XCTAssertTrue(ledger.isActive(depth: 1), "the successor listens at depth 1")
        let elapsed = floodThenInterrupt(session, outer, second, bytes: 50_000)
        XCTAssertLessThan(elapsed, 3, "Ctrl-C took \(elapsed) s: \(flowSummary(outer, second))")
    }

    /// Recovers the connection as when the parser loses the conductor's hook (a terminal reset,
    /// say), with no input to provoke output, and waits for a conductor at `depth` again.
    private func recoverNested(_ session: PTYSession, toDepth depth: Int32, typing: String? = nil,
                               timeout: TimeInterval = 30,
                               file: StaticString = #filePath, line: UInt = #line) -> Conductor? {
        let before = session.conductor
        session.screen.performBlock(joinedThreads: { terminal, _, _ in
            terminal?.parser.forceUnhookDCS(nil)
        })
        if let typing {
            // Once recovery is under way: the session talks to a conductor that does not frame.
            waitUntil("recovery to begin", timeout: timeout, file: file, line: line) {
                session.conductor !== before && session.conductor?.framing == false
            }
            session.writeTask(typing)
        }
        var recovered: Conductor?
        waitUntil("a recovered conductor at depth \(depth)", timeout: timeout, file: file, line: line) {
            guard let c = session.conductor, c !== before, c.depth == depth, c.framing,
                  !c.awaitingResynchronization else {
                return false
            }
            recovered = c
            return true
        }
        return recovered
    }

    // The flow control monitor (an advanced setting) shows the current session's connections,
    // outermost first, sampled while a flood runs through both, and watching does not slow
    // Ctrl-C. Closing its window turns the setting off. What the window drew is saved to a PNG
    // named in the output, for a person to look at.
    func testTheFlowControlMonitorShowsBothHops() throws {
        let (session, outer, inner) = try connectTwoHops()
        iTermAdvancedSettingsModel.setShowSSHFlowControlMonitor(true)
        addTeardownBlock { @MainActor in iTermAdvancedSettingsModel.setShowSSHFlowControlMonitor(false) }
        let monitor = FlowControlMonitor.instance
        waitUntil("the monitor's window", timeout: commandTimeout) { monitor.isWindowVisible }
        session.writeTask("yes inner-flood\r")
        addTeardownBlock { @MainActor in session.writeTask("\u{3}") }
        waitUntil("both hops to be sampled while the flood runs through them", timeout: 90) {
            let connections = monitor.connections
            return connections.map(\.guid) == [outer.guid, inner.guid]
                && connections.allSatisfy { ($0.history.samples.last?.snapshot?.consumed ?? 0) > 200_000 }
        }
        let connections = monitor.connections
        XCTAssertEqual(connections.map(\.depth), [outer.depth, inner.depth])
        XCTAssertEqual(connections.map(\.reasonOff), [nil, nil])
        let innerLatest = try XCTUnwrap(connections[1].history.samples.last?.snapshot)
        XCTAssertNotNil(innerLatest.carrierWindow, "the inner hop shows what its carrier carries")
        XCTAssertGreaterThan(connections[1].history.rate { $0.consumed }.compactMap(\.value).max() ?? 0, 0)

        let view = try XCTUnwrap(monitor.monitorView)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("FlowControlMonitor-live.png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        print("Wrote \(path)")

        let elapsed = interrupt(session)
        XCTAssertLessThan(elapsed, 3, "Ctrl-C took \(elapsed) s with the monitor open: \(flowSummary(outer, inner))")

        view.window?.performClose(nil)
        waitUntil("closing the window to turn the setting off", timeout: commandTimeout) {
            !iTermAdvancedSettingsModel.showSSHFlowControlMonitor() && !monitor.isWindowVisible
        }
        XCTAssertTrue(monitor.connections.isEmpty, "it stopped sampling")
    }

    // The outer framer's recovery knows nothing of a framer nested in it, and an idle inner
    // framer says nothing to start its own. iTerm2 remembers how deep the connection was and
    // recovers each depth in turn, every time, with flow control at each.
    func testANestedConnectionIsRecoveredEveryTime() throws {
        for round in 0..<5 {
            let (session, _, _) = try connectTwoHops()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 2))
            let inner = try XCTUnwrap(recoverNested(session, toDepth: 1), "round \(round)")
            let outer = try XCTUnwrap(inner.parent)
            waitUntil("flow control at both depths", timeout: commandTimeout) {
                inner.flowController != nil && outer.flowController != nil
            }
            let elapsed = interrupt(session)
            XCTAssertLessThan(elapsed, 5, "round \(round): the inner shell answers")
            if round == 4 {
                let floodElapsed = floodThenInterrupt(session, outer, inner, bytes: 50_000)
                XCTAssertLessThan(floodElapsed, 10, "Ctrl-C took \(floodElapsed) s: \(flowSummary(outer, inner))")
            }
            close(session)
        }
    }

    // Keys typed while the connection recovers belong to the inner shell. They wait for it
    // rather than going to the outer framer's login, which is the inner framer.
    func testKeysTypedDuringANestedRecoveryReachTheInnerShell() throws {
        let (session, _, _) = try connectTwoHops()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 2))
        let marker = "typed-\(UUID().uuidString.prefix(6))"
        _ = try XCTUnwrap(recoverNested(session, toDepth: 1, typing: "echo \(marker)-$((6*7))\r"))
        waitUntil("the typed command to run in the inner shell", timeout: commandTimeout) {
            self.screenText(session).contains("\(marker)-42")
        }
    }

    // If the inner connection is gone, its recovery gets no answer; iTerm2 gives up on it and
    // the session is left at the outer host, working.
    func testANestedRecoveryGivesUpWhenTheInnerConnectionIsGone() throws {
        let (session, outer, inner) = try connectTwoHops()
        // localhost: the inner login shell's parent is the inner framer, on this Mac.
        let login = try XCTUnwrap(inner.framedPID)
        let framer = try XCTUnwrap(parentPID(of: login))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
        session.screen.performBlock(joinedThreads: { terminal, _, _ in
            terminal?.parser.forceUnhookDCS(nil)
        })
        kill(framer, SIGKILL)
        waitUntil("the session to settle at the outer host", timeout: 60) {
            guard let c = session.conductor, c !== outer, c.depth == 0, c.framing,
                  !c.awaitingResynchronization, !session.isRecoveringNestedSSHConnection else {
                return false
            }
            return true
        }
        let elapsed = interrupt(session)
        XCTAssertLessThan(elapsed, 5, "the outer host's shell answers")
    }

    private func parentPID(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        return info.kp_eproc.e_ppid
    }
}
