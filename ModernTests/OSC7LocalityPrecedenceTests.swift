//
//  OSC7LocalityPrecedenceTests.swift
//  iTerm2
//
//  Issue 13117. Shell integration sends a verified OSC 7 (one with a matching
//  ?machineID token) from precmd, and a third-party hook such as oh-my-zsh's
//  omz_termsupport_cwd may send its own tokenless OSC 7 from the same precmd. If
//  the shell's $HOST is stale, the tokenless report names a host we don't
//  recognize and used to flip a local session to remote.
//
//  The rule under test: a tokenless OSC 7 doesn't override a verified report for
//  the same prompt. The window opens at the verified report and closes at the
//  first of 133;B (prompt end), 133;C (command start), or input written to the
//  pty. A tokenless report outside the window (e.g. from a remote shell reached by
//  plain ssh) is honored as before.
//
//  Also covers locality-only host changes (same user@host, different verdict),
//  which must still reach the session.
//

import XCTest
@testable import iTerm2SharedARC

final class OSC7LocalityPrecedenceTests: XCTestCase {
    // Not a name this machine answers to, standing in for a stale $HOST (the
    // reporter's "Mac.main") or a remote machine's name.
    private let staleName = "stale-name-not-this-mac.main"
    private let remoteName = "remotebox-not-this-mac.example"
    private let sideEffectTimeout: TimeInterval = 30.0

    private var localMachineIDToken: String {
        return iTermMachineIdentity.localVersion1TokenForTesting()!
    }

    override func setUp() {
        super.setUp()
        Host.it_resetRememberedLocalHostnamesForTesting()
    }

    override func tearDown() {
        Host.it_resetRememberedLocalHostnamesForTesting()
        super.tearDown()
    }

    // MARK: - Wire format

    private func bytes(_ s: String) -> [UInt8] {
        return Array(s.utf8)
    }

    // What iTerm2's zsh integration sends (BEL-terminated, with a machineID token).
    private func verifiedOSC7(user: String = "user",
                              host: String = "my-mac",
                              path: String = "/Users/user") -> [UInt8] {
        return bytes("\u{1b}]7;file://\(user)@\(host)\(path)?machineID=\(localMachineIDToken)\u{07}")
    }

    // What oh-my-zsh's omz_termsupport_cwd sends: ST-terminated, no user, no token.
    private func tokenlessOSC7(host: String, path: String = "/Users/user") -> [UInt8] {
        return bytes("\u{1b}]7;file://\(host)\(path)\u{1b}\\")
    }

    private func ftcs(_ code: String) -> [UInt8] {
        return bytes("\u{1b}]133;\(code)\u{07}")
    }

    // Runs every side effect already dispatched to the main queue. Host changes
    // reach the session on an unmanaged paused side effect, which
    // performBlock(joinedThreads:) doesn't drain; the main queue is FIFO, so a
    // block enqueued now runs after them.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: sideEffectTimeout)
    }

    // The host the session ends up with, which is what nonTextPasteHelperDestination
    // consults. Not -lastRemoteHost: two host marks on the same line (both reports
    // from one precmd) share an interval, and the tree doesn't return them in
    // insertion order.
    private func sessionHost(_ harness: TerminalTestHarness) -> (any VT100RemoteHostReading)? {
        harness.sync()
        drainMainQueue()
        return harness.delegate.currentHostDidChangeCalls.last
    }

    private func inputWasWrittenToTask(_ harness: TerminalTestHarness) {
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.inputWasWrittenToTask()
        })
    }

    // The precmd of an integrated zsh: 133;D for the previous command, then the
    // verified OSC 7, then (optionally) a third-party hook's report, then the
    // prompt itself (133;A ... 133;B).
    private func feedPrecmd(_ harness: TerminalTestHarness,
                            thirdPartyHost: String?,
                            drawPrompt: Bool = true) {
        harness.feedEscapeSequence(ftcs("D;0"))
        harness.feedEscapeSequence(verifiedOSC7())
        if let thirdPartyHost {
            harness.feedEscapeSequence(tokenlessOSC7(host: thirdPartyHost))
        }
        if drawPrompt {
            harness.feedEscapeSequence(ftcs("A"))
            harness.appendText("% ")
            harness.feedEscapeSequence(ftcs("B"))
        }
        harness.sync()
    }

    // MARK: - Same prompt: the verified report wins

    // The reported bug: a stale-$HOST tokenless report right after the verified one
    // must not turn the session remote.
    func testTokenlessReportAtSamePromptDoesNotOverrideVerifiedLocalhost() {
        let harness = TerminalTestHarness()
        feedPrecmd(harness, thirdPartyHost: staleName)
        XCTAssertEqual(sessionHost(harness)?.localityState, .localhost)
    }

    // The reporter's log shows this at every prompt. The window reopens with each
    // verified report, so it holds across prompt cycles, not just the first.
    func testTokenlessReportAtEveryPromptKeepsLocalhost() {
        let harness = TerminalTestHarness()
        for _ in 0..<3 {
            feedPrecmd(harness, thirdPartyHost: staleName)
            harness.appendText("ls")
            harness.feedEscapeSequence(ftcs("C"))
            harness.newline()
        }
        feedPrecmd(harness, thirdPartyHost: staleName)
        XCTAssertEqual(sessionHost(harness)?.localityState, .localhost)
    }

    // starship and other prompt frameworks can drop iTerm2's 133;B decoration. The
    // window then stays open until the command starts, so the duplicate is still
    // ignored.
    func testTokenlessReportAtSamePromptWithoutPromptEndKeepsLocalhost() {
        let harness = TerminalTestHarness()
        feedPrecmd(harness, thirdPartyHost: staleName, drawPrompt: false)
        XCTAssertEqual(sessionHost(harness)?.localityState, .localhost)
    }

    // If the third-party hook runs first, the verified report already wins by
    // arriving last. Guards against the fix getting this order wrong.
    func testTokenlessReportBeforeVerifiedReportIsLocalhost() {
        let harness = TerminalTestHarness()
        harness.feedEscapeSequence(tokenlessOSC7(host: staleName))
        harness.feedEscapeSequence(verifiedOSC7())
        harness.sync()
        XCTAssertEqual(sessionHost(harness)?.localityState, .localhost)
    }

    // MARK: - ssh to a host without shell integration: the tokenless report wins

    // The common case: user types `ssh remotebox` at an integrated prompt. preexec
    // sends 133;C before ssh runs, and the remote oh-my-zsh reports its host.
    func testSSHAfterPromptAndCommandStartIsRemote() {
        let harness = TerminalTestHarness()
        feedPrecmd(harness, thirdPartyHost: nil)
        harness.appendText("ssh \(remoteName)")
        inputWasWrittenToTask(harness)
        harness.feedEscapeSequence(ftcs("C"))
        harness.newline()
        harness.feedEscapeSequence(tokenlessOSC7(host: remoteName, path: "/home/user"))
        harness.sync()
        let host = sessionHost(harness)
        XCTAssertEqual(host?.hostname, remoteName)
        XCTAssertEqual(host?.localityState, .remote)
    }

    // 133;B alone (prompt drawn, no preexec, e.g. ssh started by a zle widget)
    // closes the window.
    func testTokenlessReportAfterPromptEndIsRemote() {
        let harness = TerminalTestHarness()
        feedPrecmd(harness, thirdPartyHost: nil)
        harness.feedEscapeSequence(tokenlessOSC7(host: remoteName, path: "/home/user"))
        harness.sync()
        XCTAssertEqual(sessionHost(harness)?.localityState, .remote)
    }

    // No 133;B (a prompt framework stripped it). VT100Terminal drops a 133;C that
    // doesn't follow a 133;B, so preexec's 133;C closes nothing here; the typed
    // command, written to the pty first, is what closes the window.
    func testTokenlessReportAfterCommandWithoutPromptEndIsRemote() {
        let harness = TerminalTestHarness()
        feedPrecmd(harness, thirdPartyHost: nil, drawPrompt: false)
        harness.appendText("ssh \(remoteName)")
        inputWasWrittenToTask(harness)
        harness.feedEscapeSequence(ftcs("C"))
        harness.newline()
        harness.feedEscapeSequence(tokenlessOSC7(host: remoteName, path: "/home/user"))
        harness.sync()
        XCTAssertEqual(sessionHost(harness)?.localityState, .remote)
    }

    // The hole in a "until the next command starts" rule: no 133;B and no 133;C
    // (PS1 rewritten, and ssh launched from a zle widget so preexec never ran).
    // Something still had to write to the pty to start ssh, and that closes the
    // window.
    func testTokenlessReportAfterInputWithoutAnyPromptMarksIsRemote() {
        let harness = TerminalTestHarness()
        feedPrecmd(harness, thirdPartyHost: nil, drawPrompt: false)
        inputWasWrittenToTask(harness)
        harness.newline()
        harness.feedEscapeSequence(tokenlessOSC7(host: remoteName, path: "/home/user"))
        harness.sync()
        XCTAssertEqual(sessionHost(harness)?.localityState, .remote)
    }

    // Every later prompt of the remote shell is also outside the window, so the
    // session stays remote for the whole ssh session rather than just one report.
    func testLaterRemotePromptsStayRemote() {
        let harness = TerminalTestHarness()
        feedPrecmd(harness, thirdPartyHost: nil)
        inputWasWrittenToTask(harness)
        harness.feedEscapeSequence(ftcs("C"))
        harness.newline()
        for dir in ["/home/user", "/tmp", "/var/log"] {
            harness.feedEscapeSequence(tokenlessOSC7(host: remoteName, path: dir))
            harness.appendText("$ cd somewhere")
            inputWasWrittenToTask(harness)
            harness.newline()
        }
        harness.sync()
        XCTAssertEqual(sessionHost(harness)?.localityState, .remote)
    }

    // Leaving ssh lands back at an integrated prompt, whose verified report makes
    // the session local again.
    func testVerifiedReportAfterSSHExitsRestoresLocalhost() {
        let harness = TerminalTestHarness()
        feedPrecmd(harness, thirdPartyHost: nil)
        inputWasWrittenToTask(harness)
        harness.feedEscapeSequence(ftcs("C"))
        harness.newline()
        harness.feedEscapeSequence(tokenlessOSC7(host: remoteName, path: "/home/user"))
        harness.sync()
        XCTAssertEqual(sessionHost(harness)?.localityState, .remote)

        harness.newline()
        feedPrecmd(harness, thirdPartyHost: nil)
        XCTAssertEqual(sessionHost(harness)?.localityState, .localhost)
    }

    // Without shell integration there is no verified report and no window: a
    // tokenless report for an unknown host is remote, as before.
    func testTokenlessReportWithoutShellIntegrationIsRemote() {
        let harness = TerminalTestHarness()
        harness.feedEscapeSequence(tokenlessOSC7(host: remoteName))
        harness.sync()
        XCTAssertEqual(sessionHost(harness)?.localityState, .remote)
    }

    // MARK: - Locality-only changes reach the session

    private func feedAndDrain(_ harness: TerminalTestHarness, _ report: [UInt8]) {
        harness.feedEscapeSequence(report)
        harness.sync()
        drainMainQueue()
    }

    // user@X first reported without a token (frozen remote: X isn't one of our
    // names, e.g. a Tailscale name), then by shell integration with a matching
    // token (local). Same user and hostname, so isEqualToRemoteHost: and
    // _lastPushedHostname both said "unchanged" and the session stayed remote.
    func testRemoteToLocalhostForSameUserAndHostNotifiesSession() {
        let harness = TerminalTestHarness()
        feedAndDrain(harness, bytes("\u{1b}]7;file://user@\(remoteName)/Users/user\u{1b}\\"))
        XCTAssertEqual(harness.delegate.currentHostDidChangeCalls.last?.localityState, .remote)

        harness.newline()
        feedAndDrain(harness, verifiedOSC7(user: "user", host: remoteName))
        let host = harness.delegate.currentHostDidChangeCalls.last
        XCTAssertEqual(host?.hostname, remoteName)
        XCTAssertEqual(host?.localityState, .localhost)
    }

    // The reverse: user@X verified local, then a shell on another machine that
    // happens to use the same name reports a mismatched token (remote).
    func testLocalhostToRemoteForSameUserAndHostNotifiesSession() {
        let harness = TerminalTestHarness()
        feedAndDrain(harness, verifiedOSC7(user: "user", host: remoteName))
        XCTAssertEqual(harness.delegate.currentHostDidChangeCalls.last?.localityState, .localhost)

        harness.feedEscapeSequence(ftcs("B"))
        inputWasWrittenToTask(harness)
        harness.feedEscapeSequence(ftcs("C"))
        harness.newline()
        let mismatched = "1:00000000-0000-0000-0000-000000000000"
        feedAndDrain(harness,
                     bytes("\u{1b}]7;file://user@\(remoteName)/Users/user?machineID=\(mismatched)\u{07}"))
        let host = harness.delegate.currentHostDidChangeCalls.last
        XCTAssertEqual(host?.hostname, remoteName)
        XCTAssertEqual(host?.localityState, .remote)
    }
    // MARK: - Verification reaches the session

    // A tokenless report for a host we don't recognize is a guess, so the paste dialog
    // keeps Paste Path available.
    func testTokenlessRemoteIsUnverified() {
        let harness = TerminalTestHarness()
        harness.feedEscapeSequence(tokenlessOSC7(host: remoteName))
        let host = sessionHost(harness)
        XCTAssertEqual(host?.localityState, .remote)
        XCTAssertEqual(host?.localityVerified, false)
    }

    // A token that doesn't match ours proves another machine.
    func testMismatchedTokenRemoteIsVerified() {
        let harness = TerminalTestHarness()
        harness.feedEscapeSequence(bytes("\u{1b}]7;file://user@\(remoteName)/home/user?machineID=1:00000000-0000-0000-0000-000000000000\u{07}"))
        let host = sessionHost(harness)
        XCTAssertEqual(host?.localityState, .remote)
        XCTAssertEqual(host?.localityVerified, true)
    }

    // Same user@host and same locality, but now proven: the session must hear about it,
    // or it keeps offering the escape hatch on a host known to be remote.
    func testUnverifiedToVerifiedRemoteNotifiesSession() {
        let harness = TerminalTestHarness()
        harness.feedEscapeSequence(bytes("\u{1b}]7;file://user@\(remoteName)/home/user\u{1b}\\"))
        XCTAssertEqual(sessionHost(harness)?.localityVerified, false)

        harness.newline()
        harness.feedEscapeSequence(bytes("\u{1b}]7;file://user@\(remoteName)/home/user?machineID=1:00000000-0000-0000-0000-000000000000\u{07}"))
        let host = sessionHost(harness)
        XCTAssertEqual(host?.localityState, .remote)
        XCTAssertEqual(host?.localityVerified, true)
    }

    // The duplicate is ignored outright, so the directory is the verified report's.
    func testIgnoredDuplicateLeavesVerifiedDirectory() {
        let harness = TerminalTestHarness()
        harness.feedEscapeSequence(ftcs("D;0"))
        harness.feedEscapeSequence(verifiedOSC7(path: "/Users/user/verified"))
        harness.feedEscapeSequence(tokenlessOSC7(host: staleName, path: "/Users/user/elsewhere"))
        _ = sessionHost(harness)
        harness.sync()
        XCTAssertEqual(harness.currentPath, "/Users/user/verified")
    }
}
