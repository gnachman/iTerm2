//
//  PeriodicSchedulerDeferredTests.swift
//  ModernTests
//
//  Pins PeriodicScheduler.markNeedsUpdate(deferred:), which withholds a flush for a
//  short delay so more tokens land in one batch and intermediate state is never drawn
//  (issue 10206: a terminal that hides the cursor and shows it again a few tokens later).
//
//  The case that regressed is a lone deferred request on an otherwise idle scheduler.
//  Its only scheduling opportunity is the timer this method arms, because the hot caller
//  (TokenExecutorImpl.setSideEffectFlag) only reaches here on a flag's 0 -> 1 transition
//  and the flag is not cleared until the side effects actually execute. If that timer is
//  never armed, the update waits for some unrelated caller to flush it, which on a quiet
//  session may not happen at all.
//
//  These follow the same three rules as PeriodicSchedulerUrgentTests: a private serial
//  queue rather than DispatchQueue.main, no XCTestExpectation fulfilled from the action,
//  and one-sided timing assertions with an order-of-magnitude margin.
//

import XCTest
@testable import iTerm2SharedARC

class PeriodicSchedulerDeferredTests: XCTestCase {
    // Long enough that nothing here can be satisfied by the periodic reset instead of by
    // the deferred timer under test.
    private let period = 5.0
    private let shortDelay = 0.05
    private let longDelay = 2.0

    // Counts action invocations. A class so the scheduler's action and the test body
    // share one, and so a late firing after the test has returned is harmless.
    private class Counter {
        private let mutex = Mutex()
        private var _value = 0
        var value: Int { return mutex.sync { _value } }
        func increment() { mutex.sync { _value += 1 } }
    }

    private func makeScheduler(_ counter: Counter) -> PeriodicScheduler {
        let queue = DispatchQueue(label: "com.iterm2.PeriodicSchedulerDeferredTests")
        return PeriodicScheduler(queue, period: period) {
            counter.increment()
        }
    }

    // Blocks the calling thread until `condition` holds or `timeout` elapses. Sleeps
    // rather than running the run loop; see the note at the top of this file.
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

    // The regression test. A single deferred request on an idle scheduler must arm a
    // timer of its own; nothing else is coming to flush it.
    func testLoneDeferredUpdateRuns() {
        let counter = Counter()
        let scheduler = makeScheduler(counter)

        scheduler.markNeedsUpdate(deferred: shortDelay)

        let ran = poll(upTo: 1.0) { counter.value >= 1 }
        XCTAssertTrue(ran, "a lone deferred update never ran; no timer was armed for it")
    }

    // Deferred means deferred: the action must not run before the delay elapses, which is
    // the whole reason callers use this instead of markNeedsUpdate().
    func testDeferredUpdateDoesNotRunImmediately() {
        let counter = Counter()
        let scheduler = makeScheduler(counter)

        scheduler.markNeedsUpdate(deferred: longDelay)
        XCTAssertEqual(counter.value, 0)

        // Far less than longDelay, so a correctly deferred scheduler cannot have run yet.
        poll(upTo: 0.3) { false }

        XCTAssertEqual(counter.value, 0, "deferred update ran before its delay elapsed")
    }

    // A burst must arm one timer, not one apiece, and must produce one flush. The hot
    // callers hit this on every linefeed, so the coalescing is load-bearing.
    func testDeferredUpdatesCoalesce() {
        let counter = Counter()
        let scheduler = makeScheduler(counter)

        for _ in 0..<20 {
            scheduler.markNeedsUpdate(deferred: shortDelay)
        }

        XCTAssertTrue(poll(upTo: 1.0) { counter.value >= 1 })
        // Let any stragglers land before counting. `period` is long enough that the
        // periodic reset cannot contribute a second run here.
        poll(upTo: 0.3) { false }

        XCTAssertEqual(counter.value, 1, "deferred requests did not coalesce into one flush")
    }

    // The half-period variant must read the period and arm against it atomically. If a
    // caller could read the period, lose the race to a session becoming visible, and then
    // arm the window it computed from the old period, a now-visible session would sit for
    // half a background second.
    func testHalfPeriodDeferredUsesTheCurrentPeriod() {
        let counter = Counter()
        let scheduler = makeScheduler(counter)

        // period is 5.0 here, so half of it is far beyond any poll below.
        scheduler.period = shortDelay * 2.0
        scheduler.markNeedsUpdateDeferredByHalfPeriod()

        let ran = poll(upTo: 1.0) { counter.value >= 1 }
        XCTAssertTrue(ran, "half-period deferred flush did not use the current period")
    }

    // A hidden session arms a deferred flush half a background period out, and that can
    // be the only thing scheduled: no update is throttled, so there is no reset behind it.
    // When the user switches to that tab, expedite(within:) has to pull the deferred
    // deadline in, not just an armed reset, or the first paint waits out the old window.
    func testExpeditePullsInAnArmedDeferredFlush() {
        let counter = Counter()
        let scheduler = makeScheduler(counter)

        // Nothing has flushed, so no reset is armed and no update is pending. The
        // deferred timer is the only thing scheduled.
        scheduler.markNeedsUpdate(deferred: longDelay)

        scheduler.period = shortDelay * 2.0
        scheduler.expedite(within: shortDelay)

        let ran = poll(upTo: longDelay / 2.0) { counter.value >= 1 }
        XCTAssertTrue(ran, "expedite did not pull in the armed deferred flush")

        // The superseded timer must not buy a second run at its original deadline.
        poll(upTo: longDelay) { false }
        XCTAssertEqual(counter.value, 1, "superseded deferred flush ran anyway")
    }

    // Expediting must not manufacture a deferred flush that nobody asked for.
    func testExpediteWithNothingArmedDoesNothing() {
        let counter = Counter()
        let scheduler = makeScheduler(counter)

        scheduler.expedite(within: shortDelay)
        poll(upTo: 0.5) { false }

        XCTAssertEqual(counter.value, 0, "expedite flushed with nothing armed")
    }

    // A request that is not sooner than the armed one rides it rather than pushing the
    // flush out to its own later deadline.
    func testLaterDeferredRequestCoalescesIntoArmedOne() {
        let counter = Counter()
        let scheduler = makeScheduler(counter)

        scheduler.markNeedsUpdate(deferred: shortDelay)
        scheduler.markNeedsUpdate(deferred: longDelay)

        // Well short of longDelay: the already-armed shortDelay flush must win.
        let ran = poll(upTo: longDelay / 2.0) { counter.value >= 1 }
        XCTAssertTrue(ran, "a later deferred request pushed out an already-armed flush")
    }

    // The mirror image: a request sooner than the armed one must supersede it instead of
    // coalescing into a deadline it cannot tolerate.
    func testSoonerDeferredRequestSupersedesArmedOne() {
        let counter = Counter()
        let scheduler = makeScheduler(counter)

        scheduler.markNeedsUpdate(deferred: longDelay)
        scheduler.markNeedsUpdate(deferred: shortDelay)

        let ran = poll(upTo: longDelay / 2.0) { counter.value >= 1 }
        XCTAssertTrue(ran, "a sooner deferred request did not supersede the armed flush")

        // The superseded timer must not buy a second run when its deadline arrives.
        poll(upTo: longDelay) { false }
        XCTAssertEqual(counter.value, 1, "superseded deferred flush ran anyway")
    }
}
