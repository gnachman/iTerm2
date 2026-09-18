//
//  PeriodicSchedulerUrgentTests.swift
//  ModernTests
//
//  Pins PeriodicScheduler.markNeedsUpdate(within:), which lets a caller that cannot
//  tolerate the current period pull in an already-armed reset. This is what keeps SSH
//  conductor side effects off the background session's one-second batching period; see
//  issue 13013. The interesting case is the steady state, where an update is already
//  pending and plain markNeedsUpdate() would silently wait out the whole period.
//
//  Three rules keep these from being flaky or from wedging the suite:
//
//  1. The scheduler under test gets its own serial queue, never DispatchQueue.main, so
//     waiting for it never pumps the host app's main run loop. Pumping it from a test
//     picks up whatever another test left pending there; one such leftover is an
//     NSCoreDragManager drag that blocks until a mouse-up that never comes, which hangs
//     the entire suite. Nothing here is main-queue-specific: the logic under test is the
//     deadline/generation bookkeeping, which is queue-agnostic.
//
//  2. No XCTestExpectation is ever fulfilled from the scheduler's action. A scheduler
//     arms its next reset with `queue.asyncAfter`, and that block outlives the test that
//     created it. Fulfilling an expectation after its test has finished is an XCTest API
//     violation. Instead the action only bumps a counter, and each test polls it.
//
//  3. Timing assertions are one-sided: "the action ran well before `period` elapsed",
//     with an order-of-magnitude margin. A slow or loaded machine cannot fail them.
//

import XCTest
@testable import iTerm2SharedARC

class PeriodicSchedulerUrgentTests: XCTestCase {
    // Long enough that the urgent path is unmistakably distinguishable from waiting one
    // out, short enough that a stray armed reset does not linger past the whole file.
    private let period = 5.0
    private let urgentDelay = 1.0 / 30.0

    // Counts action invocations. A class so the scheduler's action and the test body
    // share one, and so a late firing after the test has returned is harmless.
    private class Counter {
        private let mutex = Mutex()
        private var _value = 0
        var value: Int { return mutex.sync { _value } }
        func increment() { mutex.sync { _value += 1 } }
    }

    private func makeScheduler(_ counter: Counter) -> PeriodicScheduler {
        let queue = DispatchQueue(label: "com.iterm2.PeriodicSchedulerUrgentTests")
        return PeriodicScheduler(queue, period: period) {
            counter.increment()
        }
    }

    // Blocks the calling thread until `condition` holds or `timeout` elapses. Sleeps
    // rather than running the run loop; see rule 1 at the top of this file.
    @discardableResult
    private func poll(upTo timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return condition()
    }

    // The first update is not throttled: nothing is pending yet, so it runs immediately.
    func testUrgentUpdateRunsImmediatelyWhenNothingPending() {
        let counter = Counter()
        let scheduler = makeScheduler(counter)

        scheduler.markNeedsUpdate(within: urgentDelay)

        XCTAssertEqual(counter.value, 1)
    }

    // The case that matters. After one update the scheduler has a `period` reset armed
    // and _updatePending is true, so plain markNeedsUpdate() would do nothing until it
    // expires. The urgent request must supersede that reset.
    func testUrgentUpdatePullsInArmedReset() {
        let counter = Counter()
        let scheduler = makeScheduler(counter)

        scheduler.markNeedsUpdate(within: urgentDelay)
        XCTAssertEqual(counter.value, 1)

        // An update is now pending with a `period` reset armed.
        scheduler.markNeedsUpdate(within: urgentDelay)
        let ran = poll(upTo: period - 1.0) { counter.value >= 2 }

        XCTAssertTrue(ran, "urgent update never ran; it waited out the period")
    }

    // A non-urgent caller must still be throttled by the period. Without this, pulling in
    // the reset would be indistinguishable from removing the rate limit.
    func testNonUrgentUpdateStillWaitsOutThePeriod() {
        let counter = Counter()
        let scheduler = makeScheduler(counter)

        scheduler.markNeedsUpdate(within: urgentDelay)
        XCTAssertEqual(counter.value, 1)

        scheduler.markNeedsUpdate()
        // Far less than `period`, so a correctly throttled scheduler cannot have run yet.
        poll(upTo: 0.5) { false }

        XCTAssertEqual(counter.value, 1, "non-urgent update was not throttled")
    }

    // Repeated urgent requests must coalesce rather than arming a reset apiece. This is
    // what the generation counter in resetAfterDelay(_:) is for: only the newest armed
    // reset is honored, so 20 requests inside one urgent delay do not buy 20 runs.
    func testRepeatedUrgentRequestsDoNotMultiplyResets() {
        let counter = Counter()
        let scheduler = makeScheduler(counter)

        scheduler.markNeedsUpdate(within: urgentDelay)
        XCTAssertEqual(counter.value, 1)

        for _ in 0..<20 {
            scheduler.markNeedsUpdate(within: urgentDelay)
        }
        poll(upTo: 0.5) { false }

        // Generous upper bound: 0.5s of 1/30s windows is at most ~16 legitimate runs, and
        // in practice the requests coalesce into far fewer. A regression that armed one
        // reset per request would blow past this.
        let count = counter.value
        XCTAssertGreaterThanOrEqual(count, 2)
        XCTAssertLessThanOrEqual(count, 20, "urgent requests did not coalesce")
    }
}
