//
//  WorkgroupGitPollPolicyTests.swift
//  iTerm2 ModernTests
//
//  When a workgroup's git poller runs. Polling with diff stats walks the
//  whole working tree, so it must not run every tick for idle or hidden
//  workgroups (issue 13243).
//

import XCTest
@testable import iTerm2SharedARC

final class WorkgroupGitPollPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    // A visible workgroup whose last poll was 10 seconds ago, with nothing
    // else going on.
    private func inputs(_ leaderState: SessionState,
                        configure: (inout WorkgroupGitPollPolicy.Inputs) -> Void = { _ in }) -> WorkgroupGitPollPolicy.Inputs {
        var result = WorkgroupGitPollPolicy.Inputs(
            lastPoll: now.addingTimeInterval(-10),
            now: now,
            contextChanged: false,
            pollRequested: false,
            anyMemberVisible: true,
            memberBecameVisible: false,
            visibleMemberAwaitsChanges: false,
            leaderState: leaderState,
            leaderQuietSince: nil,
            lastNewline: now.addingTimeInterval(-1000),
            lastPollTimedOut: false)
        configure(&result)
        return result
    }

    func testFirstPollAlwaysRuns() {
        XCTAssertTrue(WorkgroupGitPollPolicy.shouldPoll(inputs(.idle) {
            $0.lastPoll = nil
            $0.anyMemberVisible = false
        }))
    }

    func testContextChangeRunsEvenWhenHidden() {
        XCTAssertTrue(WorkgroupGitPollPolicy.shouldPoll(inputs(.idle) {
            $0.contextChanged = true
            $0.anyMemberVisible = false
        }))
    }

    func testRequestedPollRunsEvenWhenHiddenAndIdle() {
        // A Diff member about to launch needs current state.
        XCTAssertTrue(WorkgroupGitPollPolicy.shouldPoll(inputs(.idle) {
            $0.lastPoll = self.now.addingTimeInterval(-1)
            $0.pollRequested = true
            $0.anyMemberVisible = false
        }))
    }

    func testWorkingLeaderPolls() {
        XCTAssertTrue(WorkgroupGitPollPolicy.shouldPoll(inputs(.working)))
    }

    func testWaitingLeaderDoesNotPoll() {
        // Blocked on the user, so it isn't changing the tree.
        XCTAssertFalse(WorkgroupGitPollPolicy.shouldPoll(inputs(.waiting)))
    }

    func testWaitingLeaderPollsOnceAfterItStartsWaiting() {
        XCTAssertTrue(WorkgroupGitPollPolicy.shouldPoll(inputs(.waiting) {
            $0.leaderQuietSince = self.now.addingTimeInterval(-5)
        }))
        XCTAssertFalse(WorkgroupGitPollPolicy.shouldPoll(inputs(.waiting) {
            $0.leaderQuietSince = self.now.addingTimeInterval(-20)
        }))
    }

    func testHiddenWorkgroupDoesNotPollEvenWhenWorking() {
        XCTAssertFalse(WorkgroupGitPollPolicy.shouldPoll(inputs(.working) {
            $0.anyMemberVisible = false
            $0.lastNewline = self.now
        }))
    }

    func testIdleLeaderDoesNotPoll() {
        XCTAssertFalse(WorkgroupGitPollPolicy.shouldPoll(inputs(.idle)))
    }

    func testIdleLeaderPollsOnceAfterTurnEnds() {
        // The turn ended after the last poll.
        XCTAssertTrue(WorkgroupGitPollPolicy.shouldPoll(inputs(.idle) {
            $0.leaderQuietSince = self.now.addingTimeInterval(-5)
        }))
        // A poll ran after the turn ended and its grace period passed.
        XCTAssertFalse(WorkgroupGitPollPolicy.shouldPoll(inputs(.idle) {
            $0.leaderQuietSince = self.now.addingTimeInterval(-20)
        }))
    }

    func testNewlinePollsWhenIdle() {
        XCTAssertTrue(WorkgroupGitPollPolicy.shouldPoll(inputs(.idle) {
            $0.lastNewline = self.now.addingTimeInterval(-11)
        }))
    }

    func testMemberBecomingVisiblePollsWhenIdle() {
        XCTAssertTrue(WorkgroupGitPollPolicy.shouldPoll(inputs(.idle) {
            $0.memberBecameVisible = true
        }))
    }

    func testFallbackCatchesOutsideChangesWhenIdle() {
        // Changes saved in another app don't show up as a newline, so a
        // visible workgroup still polls now and then.
        XCTAssertTrue(WorkgroupGitPollPolicy.shouldPoll(inputs(.idle) {
            $0.lastPoll = self.now.addingTimeInterval(-31)
        }))
        XCTAssertTrue(WorkgroupGitPollPolicy.shouldPoll(inputs(.waiting) {
            $0.lastPoll = self.now.addingTimeInterval(-31)
        }))
        XCTAssertTrue(WorkgroupGitPollPolicy.shouldPoll(inputs(.unknown) {
            $0.lastPoll = self.now.addingTimeInterval(-31)
        }))
    }

    func testFallbackDoesNotRunWhenHidden() {
        XCTAssertFalse(WorkgroupGitPollPolicy.shouldPoll(inputs(.idle) {
            $0.lastPoll = self.now.addingTimeInterval(-1000)
            $0.anyMemberVisible = false
        }))
    }

    func testVisibleDiffAwaitingChangesPollsEveryFewSeconds() {
        // A Diff peer showing the waiting-for-changes overlay launches as
        // soon as a poll sees a change, so don't make it wait for the
        // fallback. But a clean tree with an idle leader is a common steady
        // state, so not every tick either.
        XCTAssertFalse(WorkgroupGitPollPolicy.shouldPoll(inputs(.idle) {
            $0.lastPoll = self.now.addingTimeInterval(-2)
            $0.visibleMemberAwaitsChanges = true
        }))
        XCTAssertTrue(WorkgroupGitPollPolicy.shouldPoll(inputs(.idle) {
            $0.lastPoll = self.now.addingTimeInterval(-6)
            $0.visibleMemberAwaitsChanges = true
        }))
    }

    func testTimeoutStopsEveryTickPolling() {
        // In a repository whose polls time out, retrying every tick pays
        // full price for nothing.
        XCTAssertFalse(WorkgroupGitPollPolicy.shouldPoll(inputs(.working) {
            $0.lastPollTimedOut = true
        }))
        XCTAssertFalse(WorkgroupGitPollPolicy.shouldPoll(inputs(.idle) {
            $0.lastPollTimedOut = true
            $0.lastPoll = self.now.addingTimeInterval(-6)
            $0.visibleMemberAwaitsChanges = true
        }))
    }

    func testTimeoutKeepsSlowTriggers() {
        XCTAssertTrue(WorkgroupGitPollPolicy.shouldPoll(inputs(.working) {
            $0.lastPollTimedOut = true
            $0.lastPoll = self.now.addingTimeInterval(-31)
        }))
        XCTAssertTrue(WorkgroupGitPollPolicy.shouldPoll(inputs(.working) {
            $0.lastPollTimedOut = true
            $0.lastNewline = self.now
        }))
        XCTAssertTrue(WorkgroupGitPollPolicy.shouldPoll(inputs(.working) {
            $0.lastPollTimedOut = true
            $0.pollRequested = true
        }))
        XCTAssertTrue(WorkgroupGitPollPolicy.shouldPoll(inputs(.working) {
            $0.lastPollTimedOut = true
            $0.memberBecameVisible = true
        }))
    }

    func testNoStatusPollsOnlyOnNewlineOrFallback() {
        XCTAssertFalse(WorkgroupGitPollPolicy.shouldPoll(inputs(.unknown)))
        XCTAssertTrue(WorkgroupGitPollPolicy.shouldPoll(inputs(.unknown) {
            $0.lastNewline = self.now
        }))
    }
}
