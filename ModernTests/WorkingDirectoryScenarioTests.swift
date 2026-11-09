//
//  WorkingDirectoryScenarioTests.swift
//  ModernTests
//
//  The directory new local sessions start in, across every combination of local shell
//  integration (none, without machineID, with machineID), remote shell integration while ssh'ed
//  (none, without machineID, with machineID), and the state of a verified push's symlink
//  resolution. See docs/working-directory-design.md.
//
//  Throughout, the user cd's to D, a symlink whose target is Dr. Polls always give Dr because the
//  kernel resolves symlinks. Only a verified push (our OSC 7 with a matching machineID) gives D.
//  Polls read the local shell the user is in, which during ssh is the shell that ran ssh, so here
//  they're modeled as results with the local directory.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class WorkingDirectoryScenarioTests: XCTestCase, @preconcurrency iTermObject {
    private enum Integration: CaseIterable {
        case none
        case withoutMachineID
        case withMachineID
    }

    private enum Resolution: CaseIterable {
        // Includes a hung lookup, which hasn't replied.
        case pending
        case succeeded
        // Includes a lookup that timed out or was refused because an earlier one is stuck, both
        // of which reply nil.
        case failed
    }

    private let d = "/Users/me/src"
    private let dr = "/Volumes/Data/src"
    private let remoteDirectory = "/home/remote"
    private let remoteHost = VT100RemoteHost(username: "user", hostname: "remote.example.com")

    private var tracker: iTermSessionDirectoryTracker!
    private var mockDelegate: MockDirectoryTrackerDelegate!
    private var mockScope: iTermVariableScope!
    private var provider: MockWorkingDirectoryProvider!

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { nil }

    override func setUp() {
        super.setUp()
        reset()
    }

    /// A fresh session, for tests that loop over cases.
    private func reset() {
        let variables = iTermVariables(context: [], owner: self)
        mockScope = iTermVariableScope()
        mockScope.add(variables, toScopeNamed: nil)
        tracker = iTermSessionDirectoryTracker(variablesScope: mockScope)
        mockDelegate = MockDirectoryTrackerDelegate()
        provider = MockWorkingDirectoryProvider()
        mockDelegate.workingDirectoryProvider = provider
        tracker.delegate = mockDelegate
    }

    override func tearDown() {
        tracker = nil
        mockDelegate = nil
        mockScope = nil
        provider = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Where the local shell is, as a poll would report it.
    private var localShellDirectory: String? {
        get { provider.asyncResult }
        set { provider.asyncResult = newValue }
    }

    /// A line-feed poll that began after every push so far.
    private func linefeedPoll() {
        tracker.workingDirectoryPollerDidFindWorkingDirectory(localShellDirectory,
                                                              invalidated: false,
                                                              requestStamp: tracker.workingDirectoryPollerRequestStamp())
    }

    private func push(_ directory: String,
                      host: VT100RemoteHost?,
                      locality: VT100ScreenWorkingDirectoryLocality) {
        tracker.screenLogWorkingDirectory(onAbsoluteLine: 100,
                                          remoteHost: host,
                                          withDirectory: directory,
                                          pushType: .strongPush,
                                          locality: locality,
                                          accepted: true)
    }

    /// The local shell's prompt after a cd to `directory`.
    private func localPrompt(_ integration: Integration, directory: String) {
        switch integration {
        case .none:
            // No push. A title change or line feed after a keypress polls.
            linefeedPoll()
        case .withoutMachineID:
            push(directory, host: VT100RemoteHost.localhost(), locality: .unverified)
        case .withMachineID:
            push(directory, host: VT100RemoteHost.localhost(), locality: .verifiedReport)
        }
    }

    /// A remote shell's prompt while ssh'ed, followed by a line-feed poll.
    private func remotePrompt(_ integration: Integration) {
        switch integration {
        case .none:
            break
        case .withoutMachineID:
            // CurrentDir, or OSC 7 without a machineID.
            push(remoteDirectory, host: remoteHost, locality: .unverified)
        case .withMachineID:
            // A machineID that isn't ours proves it's remote, which is handled as unverified.
            push(remoteDirectory, host: remoteHost, locality: .unverified)
        }
        linefeedPoll()
    }

    private func finishResolution(_ index: Int, _ resolution: Resolution) {
        switch resolution {
        case .pending:
            break
        case .succeeded:
            mockDelegate.resolveCompletions[index](dr)
        case .failed:
            mockDelegate.resolveCompletions[index](nil)
        }
    }

    /// What a new local tab, split, or workgroup peer would start in.
    private func newSessionDirectory(file: StaticString = #filePath, line: UInt = #line) -> String? {
        var result: String?
        var called = false
        tracker.asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory(sshIdentity: nil) {
            result = $0
            called = true
        }
        XCTAssertTrue(called, file: file, line: line)
        return result
    }

    private func label(_ local: Integration, _ remote: Integration?, _ resolution: Resolution) -> String {
        return "local=\(local) remote=\(remote.map { "\($0)" } ?? "n/a") resolution=\(resolution)"
    }

    // MARK: - Localhost only (cases 1 to 3)

    func testLocalhost_AllIntegrations() {
        for local in Integration.allCases {
            for resolution in Resolution.allCases {
                reset()
                let context = label(local, nil, resolution)
                localShellDirectory = dr
                localPrompt(local, directory: d)
                if local == .withMachineID {
                    finishResolution(0, resolution)
                }
                linefeedPoll()

                // Only a verified push keeps the user's spelling. Every other value is a poll.
                let expected = local == .withMachineID ? d : dr
                XCTAssertEqual(newSessionDirectory(), expected, context)
                // Only a verified push is resolved.
                XCTAssertEqual(mockDelegate.resolveRequests, local == .withMachineID ? [d] : [], context)
            }
        }
    }

    // Case 2: the path variable and lastDirectory follow pushes, so they keep the reported
    // spelling even though new sessions get the resolved one.
    func testLocalhost_WithoutMachineID_PathKeepsReportedSpelling() {
        localShellDirectory = dr
        localPrompt(.withoutMachineID, directory: d)

        XCTAssertEqual(tracker.lastDirectory, d)
        XCTAssertEqual(newSessionDirectory(), dr)
    }

    // Case 3: a shell that moved without a push (e.g., exec'ed a shell without integration and
    // cd'ed) is noticed only once the verified push's resolution is known.
    func testLocalhost_WithMachineID_UnreportedMoveNoticedOnlyAfterResolution() {
        for resolution in Resolution.allCases {
            reset()
            localShellDirectory = dr
            localPrompt(.withMachineID, directory: d)
            finishResolution(0, resolution)

            localShellDirectory = "/tmp/elsewhere"
            linefeedPoll()

            let expected = resolution == .succeeded ? "/tmp/elsewhere" : d
            XCTAssertEqual(newSessionDirectory(), expected, "resolution=\(resolution)")
        }
    }

    // MARK: - ssh to a remote host (cases 4 to 12)

    func testSSH_AllIntegrations() {
        for local in Integration.allCases {
            for remote in Integration.allCases {
                for resolution in Resolution.allCases {
                    if local != .withMachineID && resolution != .pending {
                        // Nothing is resolved, so the other resolution states are the same case.
                        continue
                    }
                    reset()
                    runSSHScenario(local: local, remote: remote, resolution: resolution)
                }
            }
        }
    }

    private func runSSHScenario(local: Integration, remote: Integration, resolution: Resolution) {
        let context = label(local, remote, resolution)
        localShellDirectory = dr
        localPrompt(local, directory: d)
        if local == .withMachineID {
            finishResolution(0, resolution)
        }
        linefeedPoll()

        remotePrompt(remote)
        remotePrompt(remote)

        // The expected value from the scenario table.
        let expected: String
        switch (local, remote, resolution) {
        case (.none, _, _), (.withoutMachineID, _, _):
            expected = dr
        case (.withMachineID, .none, _):
            // D's push is still the latest, so it's kept whether or not it's resolved.
            expected = d
        case (.withMachineID, _, .succeeded):
            expected = d
        case (.withMachineID, _, _):
            // An unverified push may mean the shell moved, and with nothing to compare the
            // poll against, the poll wins. Same directory, resolved spelling.
            expected = dr
        }
        XCTAssertEqual(newSessionDirectory(), expected, context)
        XCTAssertNotEqual(tracker.verifiedLocalDirectory, remoteDirectory, context)
        // Remote paths are never resolved locally.
        XCTAssertEqual(mockDelegate.resolveRequests, local == .withMachineID ? [d] : [], context)
        // The poller keeps polling during ssh.
        XCTAssertTrue(tracker.workingDirectoryPollerShouldPoll(), context)

        // ssh exits and the local shell prompts again. The value returns to what it was before
        // ssh. If D was replaced, or its resolution failed, the push resolves again.
        localPrompt(local, directory: d)
        XCTAssertEqual(newSessionDirectory(), local == .withMachineID ? d : dr, context)
        if local == .withMachineID {
            let resolvesAgain = expected == dr || resolution == .failed
            XCTAssertEqual(mockDelegate.resolveRequests, resolvesAgain ? [d, d] : [d], context)
        }
    }

    // A pending resolution of a D that a poll replaced must not count once it finishes, and the
    // fresh resolution after ssh exits is what later polls are compared against.
    func testSSH_LateResolutionOfReplacedDirectoryIsIgnored() {
        localShellDirectory = dr
        localPrompt(.withMachineID, directory: d)
        remotePrompt(.withMachineID)
        XCTAssertEqual(newSessionDirectory(), dr)

        localPrompt(.withMachineID, directory: d)
        mockDelegate.resolveCompletions[0]("/stale/target")
        localShellDirectory = "/stale/target"
        linefeedPoll()

        // The fresh resolution is pending and D's push is the latest, so D is kept.
        XCTAssertEqual(newSessionDirectory(), d)
        mockDelegate.resolveCompletions[1](dr)
        linefeedPoll()
        XCTAssertEqual(newSessionDirectory(), "/stale/target")
    }

    // MARK: - cd foo && ssh host, with no local prompt in between

    func testCdThenSSHInOneLine() {
        let foo = "/Volumes/Data/foo"
        for local in Integration.allCases {
            for remote in Integration.allCases {
                for resolution in Resolution.allCases {
                    if local != .withMachineID && resolution != .pending {
                        continue
                    }
                    reset()
                    let context = label(local, remote, resolution)
                    localShellDirectory = dr
                    localPrompt(local, directory: d)
                    if local == .withMachineID {
                        finishResolution(0, resolution)
                    }
                    linefeedPoll()

                    localShellDirectory = foo
                    remotePrompt(remote)

                    // Known limitation: with local machineID integration and a remote that sends
                    // nothing, the move isn't noticed until D's resolution succeeds.
                    let missed = local == .withMachineID && remote == .none && resolution != .succeeded
                    XCTAssertEqual(newSessionDirectory(), missed ? d : foo, context)
                }
            }
        }
    }

    // MARK: - Nested shells

    // sudo -s runs the root shell on its own pty. The poll follows the relay to that shell, whose
    // directory can't be read, so polls give nothing and the earlier value stays.
    // Known limitation: a cd in it is missed unless it sends a verified push.
    func testRootShellWithoutVerifiedPush_KeepsEarlierDirectory() {
        localShellDirectory = dr
        linefeedPoll()

        localShellDirectory = nil
        linefeedPoll()
        push("/var/root", host: VT100RemoteHost.localhost(), locality: .unverified)

        XCTAssertEqual(newSessionDirectory(), dr)
    }

    func testRootShellWithVerifiedPush_UsesIt() {
        localShellDirectory = dr
        linefeedPoll()

        localShellDirectory = nil
        push("/var/root", host: VT100RemoteHost.localhost(), locality: .verifiedReport)
        // Resolving as the user may fail on a path only root can read.
        mockDelegate.resolveCompletions[0](nil)
        linefeedPoll()

        XCTAssertEqual(newSessionDirectory(), "/var/root")
    }

    // poetry shell with the user's integrated zsh, on poetry's pty. The poll follows the relay, so
    // it reads the same shell that pushes. It never contradicts the push, so D isn't replaced, and
    // isn't resolved again at every prompt.
    func testRelayedShellWithVerifiedPushes_PollAgreesWithPush() {
        let sub = "/Users/me/src/sub"
        let subResolved = "/Volumes/Data/src/sub"
        // Before poetry shell, the outer shell is in D.
        localShellDirectory = dr
        localPrompt(.withMachineID, directory: d)
        finishResolution(0, .succeeded)

        // In poetry shell, cd sub, then run commands.
        localShellDirectory = subResolved
        for _ in 0..<3 {
            localPrompt(.withMachineID, directory: sub)
            linefeedPoll()
        }
        mockDelegate.resolveCompletions[1](subResolved)
        for _ in 0..<3 {
            localPrompt(.withMachineID, directory: sub)
            linefeedPoll()
        }

        XCTAssertEqual(newSessionDirectory(), sub)
        XCTAssertEqual(mockDelegate.resolveRequests, [d, sub])
    }

    // MARK: - A cd and a command on one line

    // `cd ~/proj && claude`: no prompt comes between the cd and claude, so nothing is pushed.
    // Polls while claude runs read the shell that started it, now in ~/proj, which replaces D
    // once D's resolution shows they differ.
    func testCdThenCommandInOneLine() {
        let proj = "/Users/me/proj"
        for resolution in Resolution.allCases {
            reset()
            localShellDirectory = dr
            localPrompt(.withMachineID, directory: d)
            finishResolution(0, resolution)

            localShellDirectory = proj
            linefeedPoll()

            // Known limitation: with D's resolution unknown, the move isn't noticed until the
            // next prompt.
            XCTAssertEqual(newSessionDirectory(), resolution == .succeeded ? proj : d,
                           "resolution=\(resolution)")
        }
    }

    // MARK: - Symlink cases

    // A shell that reports the physical path (cd -P) pushes Dr. Polls match it textually, so it's
    // kept even when the resolution hasn't finished and an unverified push lets polls apply.
    func testPhysicalPathPush_KeptWithoutResolution() {
        localShellDirectory = dr
        localPrompt(.withMachineID, directory: dr)
        remotePrompt(.withoutMachineID)

        XCTAssertEqual(newSessionDirectory(), dr)
    }

    // Every prompt re-pushes the same D. Its cached resolution is reused, including across
    // unverified pushes, which don't discard it.
    func testRepushesAndUnverifiedPushes_ReuseCachedResolution() {
        localShellDirectory = dr
        localPrompt(.withMachineID, directory: d)
        finishResolution(0, .succeeded)
        for _ in 0..<3 {
            remotePrompt(.withoutMachineID)
            localPrompt(.withMachineID, directory: d)
        }

        XCTAssertEqual(mockDelegate.resolveRequests, [d])
        XCTAssertEqual(newSessionDirectory(), d)
    }

    // A hung lookup never replies. Re-pushes don't pile up more lookups behind it.
    func testHungResolution_IsNotRepeatedWhileOutstanding() {
        localShellDirectory = dr
        for _ in 0..<5 {
            localPrompt(.withMachineID, directory: d)
            linefeedPoll()
        }

        XCTAssertEqual(mockDelegate.resolveRequests, [d])
        XCTAssertEqual(newSessionDirectory(), d)
    }

    // Known limitation: if the symlink is retargeted while the shell sits in D, the shell is still
    // in the old target, which matches the cached resolution, so D is kept. A new session opens D,
    // which now leads to the new target.
    func testRetargetedSymlink_KeepsPushedPath() {
        localShellDirectory = dr
        localPrompt(.withMachineID, directory: d)
        finishResolution(0, .succeeded)

        // `ln -sfn /Volumes/Other/src ~/src` happens here. The shell's cwd doesn't change.
        linefeedPoll()
        localPrompt(.withMachineID, directory: d)

        XCTAssertEqual(newSessionDirectory(), d)
        XCTAssertEqual(mockDelegate.resolveRequests, [d])
    }
}
