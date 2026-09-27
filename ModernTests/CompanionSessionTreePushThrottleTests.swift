//
//  CompanionSessionTreePushThrottleTests.swift
//  iTerm2 ModernTests
//
//  The bridge rate-limits its unsolicited session-tree pushes so a rapidly
//  churning session title can't flood the relay, while an idle change (a new
//  session) still goes out immediately. These exercise the pure decision.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionSessionTreePushThrottleTests: XCTestCase {
    private typealias Action = CompanionHostBridge.SessionTreePushAction

    private func action(now: TimeInterval, last: TimeInterval?, alreadyScheduled: Bool = false) -> Action {
        CompanionHostBridge.sessionTreePushAction(now: now, lastPush: last,
                                                  minInterval: 2.0,
                                                  alreadyScheduled: alreadyScheduled)
    }

    func testFirstPushGoesOutImmediately() {
        XCTAssertEqual(action(now: 100, last: nil), .pushNow)
    }

    func testIdlePushGoesOutImmediately() {
        // Last push was well beyond the interval: send now.
        XCTAssertEqual(action(now: 105, last: 100), .pushNow)
        // Exactly at the interval boundary also sends.
        XCTAssertEqual(action(now: 102, last: 100), .pushNow)
    }

    func testRapidChangeIsDeferredForTheRemainingInterval() {
        // 0.5s after the last push (interval 2.0): queue a trailing push 1.5s out.
        XCTAssertEqual(action(now: 100.5, last: 100), .scheduleAfter(1.5))
    }

    func testChangeWhileScheduledRidesTheQueuedPush() {
        // A push is already queued; further changes must not queue another.
        XCTAssertEqual(action(now: 100.5, last: 100, alreadyScheduled: true), .alreadyScheduled)
        // Even when idle long enough, a pending trailing push takes precedence (it
        // re-reads the tree at fire time, so the latest state still ships).
        XCTAssertEqual(action(now: 200, last: 100, alreadyScheduled: true), .alreadyScheduled)
    }
}
