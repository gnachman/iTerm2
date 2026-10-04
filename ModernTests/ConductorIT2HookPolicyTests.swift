//
//  ConductorIT2HookPolicyTests.swift
//  iTerm2 ModernTests
//
//  What a remote it2 call does before it runs, given the API setting and the
//  connection's authorization state (Phase 3d).
//
//  A Claude Code hook must never block and never complain. It runs on every tool
//  call, so waiting on the authorization prompt stalls the agent, and printing an
//  error puts the same text in the transcript over and over. So a hook that cannot
//  run yet completes immediately, successfully and silently; when the decision is
//  still open it also raises the prompt, so that once the user answers the NEXT
//  hook succeeds. An interactive command keeps the existing behaviour: it waits for
//  the prompt and reports a denial.
//

import XCTest
@testable import iTerm2SharedARC

final class ConductorIT2HookPolicyTests: XCTestCase {
    private let hook = ["handle-agent-hook"]
    private let interactive = ["session", "list"]

    private func policy(_ argv: [String], apiEnabled: Bool = true, decision: Bool?) -> IT2RunPolicy {
        return IT2RunPolicy.decide(argv: argv, apiEnabled: apiEnabled, decision: decision)
    }

    // MARK: - Hooks

    // The core case: first hook on a fresh connection. Raise the prompt but do not wait for it.
    func testUndecidedHookPromptsWithoutBlocking() {
        XCTAssertEqual(policy(hook, decision: nil), .promptThenSucceedSilently)
    }

    func testGrantedHookRuns() {
        XCTAssertEqual(policy(hook, decision: true), .authorizeThenRun)
    }

    // Denied is a decision the user made; a hook must not keep reminding them of it.
    func testDeniedHookSucceedsSilently() {
        XCTAssertEqual(policy(hook, decision: false), .succeedSilently)
    }

    // With the API off nothing can run, and saying so on every tool call is noise.
    func testHookWithTheAPIOffSucceedsSilently() {
        XCTAssertEqual(policy(hook, apiEnabled: false, decision: nil), .succeedSilently)
        XCTAssertEqual(policy(hook, apiEnabled: false, decision: true), .succeedSilently)
    }

    func testHookWithArgumentsIsStillAHook() {
        XCTAssertEqual(policy(["handle-agent-hook", "--agent", "codex"], decision: nil),
                       .promptThenSucceedSilently)
    }

    // Same rule it2.py uses to decide whether to forward stdin, so the two agree on what a hook is.
    func testLeadingFlagsAreSkippedWhenFindingTheCommand() {
        XCTAssertTrue(IT2RunPolicy.isNonBlockingHook(argv: ["--verbose", "handle-agent-hook"]))
        XCTAssertFalse(IT2RunPolicy.isNonBlockingHook(argv: ["--verbose", "session", "list"]))
        XCTAssertFalse(IT2RunPolicy.isNonBlockingHook(argv: []))
    }

    // MARK: - Interactive commands keep the existing behaviour

    func testInteractiveCommandWaitsForThePrompt() {
        XCTAssertEqual(policy(interactive, decision: nil), .authorizeThenRun)
    }

    func testInteractiveCommandReportsADisabledAPI() {
        XCTAssertEqual(policy(interactive, apiEnabled: false, decision: nil), .reportAPIDisabled)
    }

    // A denial is reported to a person who typed the command; that is useful, not noise.
    func testInteractiveCommandStillAuthorizesWhenDenied() {
        XCTAssertEqual(policy(interactive, decision: false), .authorizeThenRun)
    }
}
