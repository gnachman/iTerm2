//
//  RestoreBaselineTests.swift
//  ModernTests
//
//  Tests for EventTriggerEvaluator.reconcileRestoredBaseline(_:currentAncestry:), which re-derives
//  the job-ended edges lost across a session save/restore. The session computes currentAncestry
//  synchronously at restore (empty for a fresh relaunch/exited session; a live walk for a reattached
//  one), so there is no async post-restore reading stream to disambiguate.
//

import XCTest
@testable import iTerm2SharedARC

final class RestoreBaselineTests: XCTestCase {
    private var evaluator: EventTriggerEvaluator!
    private struct Fire {
        let matchType: iTermTriggerMatchType
        let captures: [String]
    }
    private var fires: [Fire]!

    override func setUp() {
        super.setUp()
        evaluator = EventTriggerEvaluator(sessionDescription: "test")
        fires = []
        evaluator.fireTriggerHandler = { [weak self] trigger, captures, _ in
            self?.fires.append(Fire(matchType: trigger.matchType, captures: captures))
        }
    }

    override func tearDown() {
        evaluator = nil
        fires = nil
        super.tearDown()
    }

    private func loadJobTriggers(_ names: [String]) {
        func dict(_ matchType: iTermTriggerMatchType, _ job: String) -> [String: Any] {
            return [
                "action": "AlertTrigger",
                "regex": "",
                "parameter": "test",
                "matchType": NSNumber(value: matchType.rawValue),
                "disabled": NSNumber(value: false),
                "eventParams": ["jobName": job]
            ]
        }
        var triggers: [[String: Any]] = []
        for name in names {
            triggers.append(dict(.eventJobEnded, name))
            triggers.append(dict(.eventJobStarted, name))
        }
        evaluator.loadFromProfileArray(triggers)
    }

    private func jobEndedFires() -> [Fire] { fires.filter { $0.matchType == .eventJobEnded } }
    private func jobStartedFires() -> [Fire] { fires.filter { $0.matchType == .eventJobStarted } }

    // Fresh relaunch / exited: currentAncestry == [] means every saved job is gone -> Job Ended for
    // each (that has a trigger), and no Job Started.
    func testReconcileFiresJobEndedForAllBaselineJobsWhenNothingRunning() {
        loadJobTriggers(["claude"])
        evaluator.reconcileRestoredBaseline(["claude", "zsh"], currentAncestry: [])
        XCTAssertEqual(jobEndedFires().count, 1)
        XCTAssertEqual(jobEndedFires().first?.captures, ["claude"])
        XCTAssertEqual(jobStartedFires().count, 0)
    }

    // Reattach with the job still running: nothing departed -> no Job Ended, and the silent seed
    // means the first live reading of the same ancestry fires no spurious Job Started.
    func testReconcileSurvivedJobFiresNothingAndSuppressesRefire() {
        loadJobTriggers(["claude"])
        evaluator.reconcileRestoredBaseline(["claude"], currentAncestry: ["claude"])
        XCTAssertEqual(jobEndedFires().count, 0)
        XCTAssertEqual(jobStartedFires().count, 0)
        // First live reading matches the seeded ancestry -> no delta -> no re-fire.
        evaluator.foregroundJobAncestors = ["claude"]
        XCTAssertEqual(jobStartedFires().count, 0)
    }

    // Reattach where the job died but the shell survived: Job Ended for the departed job only.
    func testReconcileReattachFiresJobEndedForDepartedJobOnly() {
        loadJobTriggers(["claude", "zsh"])
        evaluator.reconcileRestoredBaseline(["claude", "zsh"], currentAncestry: ["zsh"])
        XCTAssertEqual(jobEndedFires().count, 1)
        XCTAssertEqual(jobEndedFires().first?.captures, ["claude"])
        XCTAssertEqual(jobStartedFires().count, 0)
    }

    // After reconcile against [], normal reading-to-reading diffing resumes: rerunning the job fires
    // Job Started.
    func testNormalDiffingResumesAfterReconcile() {
        loadJobTriggers(["claude"])
        evaluator.reconcileRestoredBaseline(["claude"], currentAncestry: [])
        XCTAssertEqual(jobEndedFires().count, 1)
        evaluator.foregroundJobAncestors = ["claude"]   // user reruns claude
        XCTAssertEqual(jobStartedFires().count, 1)
        XCTAssertEqual(jobStartedFires().first?.captures, ["claude"])
    }

    // Case-insensitive membership: a differently-cased survivor is not treated as departed.
    func testReconcileMembershipIsCaseInsensitive() {
        loadJobTriggers(["claude"])
        evaluator.reconcileRestoredBaseline(["Claude"], currentAncestry: ["claude"])
        XCTAssertEqual(jobEndedFires().count, 0)
    }

    // F36: a saved chain with a repeated name that is entirely gone fires Job Ended once per
    // distinct name, matching the live path (which folds into a set).
    func testReconcileDeduplicatesRepeatedNames() {
        loadJobTriggers(["make"])
        evaluator.reconcileRestoredBaseline(["make", "make", "bash"], currentAncestry: [])
        XCTAssertEqual(jobEndedFires().count, 1)
        XCTAssertEqual(jobEndedFires().first?.captures, ["make"])
    }

    // F35: a live ancestry update arriving during the async restore gap (buffered) must not fire a
    // spurious Job Started for a survived job before reconcile runs; reconcile then fires nothing.
    func testBufferedLiveUpdateDuringRestoreGapDoesNotFire() {
        loadJobTriggers(["claude", "vim"])
        evaluator.beginDeferringLiveUpdatesForRestore()
        evaluator.foregroundJobAncestors = ["claude"]    // process-cache update during the gap
        XCTAssertEqual(jobStartedFires().count, 0, "buffered update must not fire")
        evaluator.reconcileRestoredBaseline(["claude"], currentAncestry: ["claude"])
        XCTAssertEqual(jobStartedFires().count, 0)
        XCTAssertEqual(jobEndedFires().count, 0)
        // Live diffing resumes after reconcile (seeded to ["claude"]).
        evaluator.foregroundJobAncestors = ["claude", "vim"]
        XCTAssertEqual(jobStartedFires().count, 1)
        XCTAssertEqual(jobStartedFires().first?.captures, ["vim"])
    }

    // endDeferring (the no-baseline-trigger case) resumes live diffing from the buffered value.
    func testEndDeferringResumesLiveDiffing() {
        loadJobTriggers(["claude"])
        evaluator.beginDeferringLiveUpdatesForRestore()
        evaluator.foregroundJobAncestors = ["zsh"]       // buffered, no fire
        XCTAssertEqual(jobStartedFires().count, 0)
        evaluator.endDeferringLiveUpdatesForRestore()
        evaluator.foregroundJobAncestors = ["claude", "zsh"]
        XCTAssertEqual(jobStartedFires().count, 1)
        XCTAssertEqual(jobStartedFires().first?.captures, ["claude"])
    }

    // Sanity: ordinary (non-restore) ancestry diffing still fires both edges.
    func testOrdinaryDiffingFiresStartedAndEnded() {
        loadJobTriggers(["claude"])
        evaluator.foregroundJobAncestors = ["claude", "zsh"]
        XCTAssertEqual(jobStartedFires().count, 1)
        evaluator.foregroundJobAncestors = ["zsh"]
        XCTAssertEqual(jobEndedFires().count, 1)
    }
}
