//
//  ClaudeCodeIt2ReachabilityTests.swift
//  iTerm2 ModernTests
//
//  Claude Code runs it2 by name from its Bash tool, a `sh -c`, so on a host reached through SSH
//  Integration it needs ~/.iterm2/bin on PATH. The shell-integration scripts put it there from
//  zsh 20, bash 23, fish 26, tcsh 10 and xonsh 5. When claude starts on such a host with an older
//  script, and the Claude Code integration is in use there, the user is told; nobody else is.
//

import XCTest
@testable import iTerm2SharedARC

final class ClaudeCodeIt2ReachabilityTests: XCTestCase {
    private typealias R = ClaudeCodeIt2Reachability

    func testEachShellsMinimum() {
        for (shell, minimum) in [("zsh", 20), ("bash", 23), ("fish", 26), ("tcsh", 10), ("xonsh", 5)] {
            XCTAssertEqual(R.verdict(shell: shell, version: minimum), .current, shell)
            XCTAssertEqual(R.verdict(shell: shell, version: minimum + 3), .current, shell)
            XCTAssertEqual(R.verdict(shell: shell, version: minimum - 1),
                           .tooOld(shell: shell, version: minimum - 1, minimum: minimum), shell)
        }
    }

    // Released 3.7.3 shipped zsh 17; the "critical updates only" setting would call that current.
    // This is about whether claude can reach iTerm2, so that setting plays no part.
    func testReleasedScriptsAreTooOldWhateverTheUpdateSetting() {
        XCTAssertEqual(R.verdict(shell: "zsh", version: 17), .tooOld(shell: "zsh", version: 17, minimum: 20))
        XCTAssertEqual(R.verdict(shell: "zsh", version: 5), .tooOld(shell: "zsh", version: 5, minimum: 20))
    }

    // Nothing reported (no shell integration loaded, or a guard skipped it) is not "old".
    func testNothingReportedIsUnknown() {
        XCTAssertEqual(R.verdict(shell: nil, version: nil), .unknown)
        XCTAssertEqual(R.verdict(shell: "zsh", version: nil), .unknown)
    }

    // A script so old it names no shell predates every minimum.
    func testVersionWithoutAShellIsTooOld() {
        XCTAssertEqual(R.verdict(shell: nil, version: 3), .tooOld(shell: nil, version: 3, minimum: nil))
    }

    // A shell this table does not know cannot be judged.
    func testUnknownShellIsUnknown() {
        XCTAssertEqual(R.verdict(shell: "nushell", version: 1), .unknown)
    }

    // Only where the Claude Code integration is in use: installed on that host, or the session is
    // in the Claude Code workgroup (Try It Now, or the auto-enter trigger). Only over SSH
    // Integration: locally the native it2 is on PATH.
    func testWhenToCheck() {
        XCTAssertTrue(R.shouldCheck(overSSHIntegration: true, hookInstalledOnHost: true, inClaudeCodeWorkgroup: false))
        XCTAssertTrue(R.shouldCheck(overSSHIntegration: true, hookInstalledOnHost: false, inClaudeCodeWorkgroup: true))
        XCTAssertFalse(R.shouldCheck(overSSHIntegration: true, hookInstalledOnHost: false, inClaudeCodeWorkgroup: false))
        XCTAssertFalse(R.shouldCheck(overSSHIntegration: false, hookInstalledOnHost: true, inClaudeCodeWorkgroup: true))
    }
}

// The once-per-connection bookkeeping behind the warning. Both cases below were seen live: the
// check ran before anything had looked for the hook on the host, so it skipped, and a check that
// found an old version while another prompt was up waited for a claude launch that never came.
final class ClaudeCodeIt2CheckSchedulerTests: XCTestCase {
    private func input(connection: String = "c1",
                       session: String = "s1",
                       version: Int? = 14,
                       inWorkgroup: Bool = false,
                       hookPresent: Bool = false) -> ClaudeCodeIt2CheckScheduler.Input {
        return .init(connection: connection, sessionGUID: session,
                     shell: version == nil ? nil : "zsh", version: version,
                     inClaudeCodeWorkgroup: inWorkgroup, hookPresent: hookPresent)
    }

    func testRecordedHookWarnsOnce() {
        let scheduler = ClaudeCodeIt2CheckScheduler()
        XCTAssertEqual(scheduler.evaluate(input(hookPresent: true), promptBusy: false), .warn)
        XCTAssertEqual(scheduler.evaluate(input(hookPresent: true), promptBusy: false), .alreadyChecked)
    }

    func testNotInUseIsLeftAlone() {
        let scheduler = ClaudeCodeIt2CheckScheduler()
        XCTAssertEqual(scheduler.evaluate(input(), promptBusy: false), .notInUse)
    }

    // The hook is on the host, found by the health check after the first evaluation.
    func testHookFoundOnTheHostCountsAsInUse() {
        let scheduler = ClaudeCodeIt2CheckScheduler()
        XCTAssertEqual(scheduler.evaluate(input(), promptBusy: false), .notInUse)
        scheduler.hookFound(onConnection: "c1")
        XCTAssertEqual(scheduler.evaluate(input(), promptBusy: false), .warn)
    }

    // Deferred while another prompt is up, then handed back once it is gone.
    func testDeferredCheckIsHandedBack() {
        let scheduler = ClaudeCodeIt2CheckScheduler()
        XCTAssertEqual(scheduler.evaluate(input(inWorkgroup: true), promptBusy: true), .deferred)
        XCTAssertEqual(scheduler.takeDeferred(), ["s1"])
        XCTAssertEqual(scheduler.takeDeferred(), [])
        XCTAssertEqual(scheduler.evaluate(input(inWorkgroup: true), promptBusy: false), .warn)
    }

    func testCurrentAndUnknownAreDoneWithoutAWarning() {
        let scheduler = ClaudeCodeIt2CheckScheduler()
        XCTAssertEqual(scheduler.evaluate(input(connection: "a", version: 20, hookPresent: true), promptBusy: false), .fine)
        XCTAssertEqual(scheduler.evaluate(input(connection: "b", version: nil, hookPresent: true), promptBusy: false), .fine)
        XCTAssertEqual(scheduler.evaluate(input(connection: "a", version: 14, hookPresent: true), promptBusy: false),
                       .alreadyChecked)
    }

    // Each connection is its own: another host, or a reconnect, is checked again.
    func testConnectionsAreIndependent() {
        let scheduler = ClaudeCodeIt2CheckScheduler()
        XCTAssertEqual(scheduler.evaluate(input(connection: "a", hookPresent: true), promptBusy: false), .warn)
        XCTAssertEqual(scheduler.evaluate(input(connection: "b", hookPresent: true), promptBusy: false), .warn)
    }
}

