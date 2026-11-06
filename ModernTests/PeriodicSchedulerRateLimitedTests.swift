//
//  PeriodicSchedulerRateLimitedTests.swift
//  ModernTests
//
//  Pins PeriodicScheduler.markNeedsUpdate(deferredBy:notMoreOftenThan:), which lets a
//  title change in a hidden session escape the session's one-second batching period
//  without flushing more often than the minimum interval. An animated title in a
//  background tab otherwise advances only once a second.
//
//  These follow the same three rules as PeriodicSchedulerUrgentTests: a private serial
//  queue rather than DispatchQueue.main, no XCTestExpectation fulfilled from the action,
//  and one-sided timing assertions with an order-of-magnitude margin.
//

import XCTest
@testable import iTerm2SharedARC

class PeriodicSchedulerRateLimitedTests: XCTestCase {
    // Long enough that nothing here can be satisfied by the periodic reset instead of by
    // the rate-limited flush under test.
    private let period = 30.0
    private let shortDelay = 0.01

    // Counts action invocations. A class so the scheduler's action and the test body
    // share one, and so a late firing after the test has returned is harmless.
    private class Counter {
        private let mutex = Mutex()
        private var _value = 0
        var value: Int { return mutex.sync { _value } }
        func increment() { mutex.sync { _value += 1 } }
    }

    private func makeScheduler(_ counter: Counter, period: TimeInterval? = nil) -> PeriodicScheduler {
        let queue = DispatchQueue(label: "com.iterm2.PeriodicSchedulerRateLimitedTests")
        return PeriodicScheduler(queue, period: period ?? self.period) {
            counter.increment()
        }
    }

    // Blocks the calling thread until `condition` holds or `timeout` elapses. Sleeps
    // rather than running the run loop; see the note at the top of
    // PeriodicSchedulerUrgentTests.
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

    // Runs the action once so the scheduler is throttled for the rest of `period`, the
    // steady state of a busy hidden session.
    private func throttle(_ scheduler: PeriodicScheduler, _ counter: Counter) {
        scheduler.markNeedsUpdate()
        XCTAssertTrue(poll(upTo: 1.0) { counter.value == 1 })
    }

    // The point of the method: a throttled scheduler flushes well before its period ends.
    func testEscapesPeriodWhileThrottled() {
        let counter = Counter()
        let scheduler = makeScheduler(counter)
        throttle(scheduler, counter)

        scheduler.markNeedsUpdate(deferredBy: shortDelay, notMoreOftenThan: 0.1)

        XCTAssertTrue(poll(upTo: 1.0) { counter.value == 2 },
                      "the update waited for the period")
    }

    // The deferral still applies, so a title coalesces with a prompt redrawn around it.
    func testDoesNotRunImmediately() {
        let counter = Counter()
        let scheduler = makeScheduler(counter)

        scheduler.markNeedsUpdate(deferredBy: 2.0, notMoreOftenThan: 0.1)

        XCTAssertEqual(counter.value, 0, "the flush lost its deferral")
    }

    // A request right after a flush waits until the minimum interval has passed, and is
    // not lost while it waits.
    func testSuccessiveFlushesRespectMinimumInterval() {
        let counter = Counter()
        let scheduler = makeScheduler(counter)
        throttle(scheduler, counter)

        scheduler.markNeedsUpdate(deferredBy: shortDelay, notMoreOftenThan: 2.0)
        XCTAssertTrue(poll(upTo: 1.0) { counter.value == 2 })

        scheduler.markNeedsUpdate(deferredBy: shortDelay, notMoreOftenThan: 2.0)
        XCTAssertEqual(counter.value, 2, "flushed sooner than the minimum interval")
        XCTAssertTrue(poll(upTo: 5.0) { counter.value == 3 },
                      "the spaced request never flushed")
    }

    // Requests made while a flush is owed ride that flush rather than adding their own.
    // This is what keeps a flood of title changes from flushing more than once.
    func testRequestsWhileOwedShareOneFlush() {
        let counter = Counter()
        let scheduler = makeScheduler(counter)
        throttle(scheduler, counter)

        for _ in 0..<5 {
            scheduler.markNeedsUpdate(deferredBy: 0.05, notMoreOftenThan: 0.1)
        }
        XCTAssertTrue(poll(upTo: 1.0) { counter.value == 2 })
        poll(upTo: 0.5) { false }
        XCTAssertEqual(counter.value, 2, "requests made while a flush was owed flushed again")
    }

    // When some other flush serves the owed request early, the next request's interval
    // is measured from that flush, not from the later deadline the owed request was given.
    func testIntervalMeasuredFromFlushThatServedRequest() {
        let counter = Counter()
        let scheduler = makeScheduler(counter)

        scheduler.markNeedsUpdate(deferredBy: 5.0, notMoreOftenThan: 0.2)
        // Unthrottled, so this flushes now and serves the request above.
        scheduler.markNeedsUpdate()
        XCTAssertTrue(poll(upTo: 1.0) { counter.value == 1 })

        scheduler.markNeedsUpdate(deferredBy: shortDelay, notMoreOftenThan: 0.2)

        XCTAssertTrue(poll(upTo: 2.0) { counter.value == 2 },
                      "the interval was measured from the served request's deadline")
    }

    // A visible session's period is already shorter than the minimum interval. There the
    // request is an ordinary deferred one and must not add flushes beyond the period.
    func testNoEscapeWhenPeriodIsNotLongerThanMinimumInterval() {
        let counter = Counter()
        let scheduler = makeScheduler(counter, period: 5.0)
        throttle(scheduler, counter)

        scheduler.markNeedsUpdate(deferredBy: shortDelay, notMoreOftenThan: 10.0)
        poll(upTo: 0.5) { false }

        XCTAssertEqual(counter.value, 1, "escaped a period no longer than the minimum interval")
    }
}
