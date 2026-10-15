//
//  CockpitChipSendPlanTests.swift
//  ModernTests
//
//  QA finding F-242: after a chipped session's tab was closed, Shift-Return
//  refused the whole send with “Unknown target @ptys_…” (an internal id),
//  so the targets that still existed got nothing. A gone target is now
//  skipped and named by its chip's display name.
//

import XCTest
@testable import iTerm2SharedARC

final class CockpitChipSendPlanTests: XCTestCase {
    private let chips: [(token: String, name: String)] = [
        ("ptys_ONE", "ONE (-zsh)"),
        ("ptys_THREE", "THREE (-zsh)"),
    ]

    func testGoneTargetIsSkippedAndOthersStillGetTheCommand() {
        let plan = CockpitWindowController.chipSendPlan(command: "echo STALE3",
                                                        resolvedCount: 1,
                                                        unknownTokens: ["@ptys_THREE"],
                                                        chips: chips)
        XCTAssertEqual(plan, .send(skipped: ["THREE (-zsh)"]))
    }

    func testAllTargetsGoneNamesThemByDisplayName() {
        let plan = CockpitWindowController.chipSendPlan(command: "echo hi",
                                                        resolvedCount: 0,
                                                        unknownTokens: ["@ptys_ONE", "@ptys_THREE"],
                                                        chips: chips)
        XCTAssertEqual(plan, .allGone(["ONE (-zsh)", "THREE (-zsh)"]))
    }

    func testAllResolvedSendsWithNothingSkipped() {
        let plan = CockpitWindowController.chipSendPlan(command: "ls",
                                                        resolvedCount: 2,
                                                        unknownTokens: [],
                                                        chips: chips)
        XCTAssertEqual(plan, .send(skipped: []))
    }

    func testEmptyCommandAsksForOne() {
        let plan = CockpitWindowController.chipSendPlan(command: "",
                                                        resolvedCount: 0,
                                                        unknownTokens: ["@ptys_ONE"],
                                                        chips: chips)
        XCTAssertEqual(plan, .needsCommand)
    }

    func testResolvedToNothingWithoutGoneTargets() {
        // A tab chip whose tab has no sessions resolves to nothing but
        // isn't unknown.
        let plan = CockpitWindowController.chipSendPlan(command: "ls",
                                                        resolvedCount: 0,
                                                        unknownTokens: [],
                                                        chips: chips)
        XCTAssertEqual(plan, .noMatches)
    }

    func testDuplicateGoneTokensAreNamedOnce() {
        let plan = CockpitWindowController.chipSendPlan(command: "ls",
                                                        resolvedCount: 1,
                                                        unknownTokens: ["@ptys_THREE", "@ptys_THREE"],
                                                        chips: chips)
        XCTAssertEqual(plan, .send(skipped: ["THREE (-zsh)"]))
    }

    func testGoneTokenWithoutChipFallsBackToToken() {
        let plan = CockpitWindowController.chipSendPlan(command: "ls",
                                                        resolvedCount: 1,
                                                        unknownTokens: ["@tab:42"],
                                                        chips: chips)
        XCTAssertEqual(plan, .send(skipped: ["tab:42"]))
    }
}
