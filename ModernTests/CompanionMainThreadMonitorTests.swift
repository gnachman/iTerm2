//
//  CompanionMainThreadMonitorTests.swift
//  iTerm2 ModernTests
//
//  CompanionMainThreadMonitor notices when the main thread has stopped serving
//  its dispatch queue, so the companion app can be told the Mac will not answer
//  requests for now. These tests pin:
//
//    - The rule: a probe posted to the main queue that has not run within the
//      threshold means blocked; the probe running means not blocked.
//    - One probe at a time, and observers hear about transitions only.
//    - Against the real main queue: frozen by a modal run loop started from a
//      main-queue callout, it reports blocked, and reports unblocked when the
//      freeze ends.
//
//  Time is injected, so nothing here waits for a clock.
//

import XCTest
import os
@testable import iTerm2SharedARC

final class CompanionMainStallTrackerTests: XCTestCase {
    private let threshold = CompanionMainStallTracker.threshold

    func testFirstTickPostsAProbeAndAPromptProbeMeansNotBlocked() {
        var tracker = CompanionMainStallTracker()
        XCTAssertFalse(tracker.isBlocked)
        let first = tracker.tick(now: 100)
        XCTAssertTrue(first.postProbe)
        XCTAssertFalse(first.changed)
        XCTAssertFalse(tracker.probeRan(), "it was never blocked, so nothing changed")
        XCTAssertFalse(tracker.isBlocked)
        // The next tick probes again.
        XCTAssertTrue(tracker.tick(now: 101).postProbe)
    }

    func testOnlyOneProbeIsOutstandingAtATime() {
        var tracker = CompanionMainStallTracker()
        XCTAssertTrue(tracker.tick(now: 100).postProbe)
        XCTAssertFalse(tracker.tick(now: 100.5).postProbe)
        XCTAssertFalse(tracker.tick(now: 101).postProbe)
    }

    func testProbeUnrunPastTheThresholdMeansBlockedUntilItRuns() {
        var tracker = CompanionMainStallTracker()
        _ = tracker.tick(now: 100)
        let early = tracker.tick(now: 100 + threshold - 0.1)
        XCTAssertFalse(early.changed)
        XCTAssertFalse(tracker.isBlocked, "a busy moment shorter than the threshold is not a stall")

        let late = tracker.tick(now: 100 + threshold)
        XCTAssertTrue(late.changed)
        XCTAssertTrue(tracker.isBlocked)
        XCTAssertFalse(late.postProbe)
        XCTAssertFalse(tracker.tick(now: 100 + threshold + 5).changed, "still blocked: no second transition")

        XCTAssertTrue(tracker.probeRan(), "the probe finally ran: unblocked")
        XCTAssertFalse(tracker.isBlocked)
        XCTAssertTrue(tracker.tick(now: 200).postProbe)
    }
}

extension CompanionMainStallTrackerTests {
    /// When there is a specific reason to suspect a stall, a much shorter wait
    /// is enough: a main thread that is serving its queue runs a probe at once.
    func testExpeditedThresholdDeclaresAStallSooner() {
        let expedited = CompanionMainStallTracker.expeditedThreshold
        XCTAssertLessThan(expedited, CompanionMainStallTracker.threshold)

        var tracker = CompanionMainStallTracker()
        _ = tracker.tick(now: 0)
        let early = tracker.tick(now: expedited - 0.01, threshold: expedited)
        XCTAssertFalse(early.changed)
        let late = tracker.tick(now: expedited, threshold: expedited)
        XCTAssertTrue(late.changed)
        XCTAssertTrue(tracker.isBlocked)

        // The ordinary threshold is unaffected.
        var ordinary = CompanionMainStallTracker()
        _ = ordinary.tick(now: 0)
        XCTAssertFalse(ordinary.tick(now: expedited).changed)
    }
}

final class CompanionMainThreadMonitorTests: XCTestCase {
    /// A clock the test sets by hand.
    private final class Clock: Sendable {
        private let value = OSAllocatedUnfairLock(initialState: TimeInterval(1000))
        var now: TimeInterval {
            get { value.withLock { $0 } }
            set { value.withLock { $0 = newValue } }
        }
    }

    /// Collects the probes the monitor posts instead of running them.
    private final class ProbeQueue: Sendable {
        private let probes = OSAllocatedUnfairLock(initialState: [@Sendable () -> Void]())
        var count: Int { probes.withLock { $0.count } }
        func post(_ probe: @escaping @Sendable () -> Void) {
            probes.withLock { $0.append(probe) }
        }
        func runAll() {
            let all = probes.withLock { probes -> [@Sendable () -> Void] in
                let all = probes
                probes = []
                return all
            }
            all.forEach { $0() }
        }
    }

    func testObserversHearAboutTransitionsOnly() {
        let clock = Clock()
        let queue = ProbeQueue()
        let monitor = CompanionMainThreadMonitor(now: { clock.now },
                                                 runOnMain: { queue.post($0) },
                                                 ticksAutomatically: false)
        let changes = OSAllocatedUnfairLock(initialState: [Bool]())
        let token = monitor.addObserver { [weak monitor] in
            let blocked = monitor?.isMainBlocked() ?? false
            changes.withLock { $0.append(blocked) }
        }

        monitor.tick()
        XCTAssertEqual(queue.count, 1)
        clock.now += 1
        monitor.tick()
        XCTAssertEqual(queue.count, 1, "the first probe is still outstanding")
        XCTAssertEqual(changes.withLock { $0 }, [])
        XCTAssertFalse(monitor.isMainBlocked())

        clock.now += CompanionMainStallTracker.threshold
        monitor.tick()
        monitor.tick()
        XCTAssertTrue(monitor.isMainBlocked())
        XCTAssertEqual(changes.withLock { $0 }, [true])

        queue.runAll()
        XCTAssertFalse(monitor.isMainBlocked())
        XCTAssertEqual(changes.withLock { $0 }, [true, false])

        // Healthy again: probes come and go with nothing to report.
        clock.now += 1
        monitor.tick()
        queue.runAll()
        XCTAssertEqual(changes.withLock { $0 }, [true, false])
        _ = token
    }

    func testDroppingTheTokenUnsubscribes() {
        let clock = Clock()
        let queue = ProbeQueue()
        let monitor = CompanionMainThreadMonitor(now: { clock.now },
                                                 runOnMain: { queue.post($0) },
                                                 ticksAutomatically: false)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        var token: AnyObject? = monitor.addObserver { calls.withLock { $0 += 1 } }
        _ = token
        token = nil
        monitor.tick()
        clock.now += CompanionMainStallTracker.threshold
        monitor.tick()
        XCTAssertTrue(monitor.isMainBlocked())
        XCTAssertEqual(calls.withLock { $0 }, 0)
    }

    /// With the real main queue: a probe posted during a freeze does not run, so
    /// the monitor reports blocked; when the freeze ends it runs and the monitor
    /// reports unblocked.
    func testReportsBlockedDuringAFreezeAndUnblockedAfterIt() async throws {
        let clock = Clock()
        let monitor = CompanionMainThreadMonitor(now: { clock.now }, ticksAutomatically: false)
        let (unblocked, unblockedContinuation) = AsyncStream<Void>.makeStream()
        let token = monitor.addObserver { [weak monitor] in
            if monitor?.isMainBlocked() == false {
                unblockedContinuation.yield()
            }
        }
        try await FrozenMainQueue.run { freeze in
            monitor.tick()
            await freeze.waitForRunLoopPasses(3)
            XCTAssertFalse(monitor.isMainBlocked(), "not yet: the threshold has not passed")
            clock.now += CompanionMainStallTracker.threshold
            monitor.tick()
            XCTAssertTrue(monitor.isMainBlocked())
        }
        try await FrozenMainQueue.withFailsafe("the monitor to report unblocked") {
            for await _ in unblocked { break }
        }
        XCTAssertFalse(monitor.isMainBlocked())
        _ = token
    }

    /// A phone that connects while the main queue is ALREADY frozen (so nothing
    /// was subscribed, and nothing was ticking, when the freeze began). The
    /// monitor must start measuring the moment it is subscribed to, and must
    /// answer isMainBlocked() from the current time, not from its last tick:
    /// the link asks while building the hello reply, and no tick may have
    /// happened yet.
    func testSubscribingDuringAFreezeIsMeasuredFromThatMomentWithoutATick() async throws {
        let clock = Clock()
        let monitor = CompanionMainThreadMonitor(now: { clock.now }, ticksAutomatically: false)
        let (unblocked, unblockedContinuation) = AsyncStream<Void>.makeStream()
        var token: AnyObject?
        try await FrozenMainQueue.run { freeze in
            token = monitor.addObserver { [weak monitor] in
                if monitor?.isMainBlocked() == false {
                    unblockedContinuation.yield()
                }
            }
            await freeze.waitForRunLoopPasses(3)
            XCTAssertFalse(monitor.isMainBlocked(), "not yet: the threshold has not passed")
            clock.now += CompanionMainStallTracker.threshold
            XCTAssertTrue(monitor.isMainBlocked(), "no tick happened, and none should be needed")
        }
        try await FrozenMainQueue.withFailsafe("the monitor to report unblocked") {
            for await _ in unblocked { break }
        }
        _ = token
    }

    /// Collects the delayed blocks the monitor schedules instead of waiting.
    private final class DelayedBlocks: Sendable {
        private let blocks = OSAllocatedUnfairLock(initialState: [(delay: TimeInterval, block: @Sendable () -> Void)]())
        var delays: [TimeInterval] { blocks.withLock { $0.map { $0.delay } } }
        func schedule(_ delay: TimeInterval, _ block: @escaping @Sendable () -> Void) {
            blocks.withLock { $0.append((delay, block)) }
        }
        func runAll() {
            let all = blocks.withLock { blocks -> [@Sendable () -> Void] in
                let all = blocks.map { $0.block }
                blocks = []
                return all
            }
            all.forEach { $0() }
        }
    }

    /// An alert that can block the app has just appeared. The monitor probes
    /// at once and checks again a moment later: a probe still unrun by then
    /// means blocked, long before the ordinary threshold.
    func testExpediteReportsAStallAfterTheShortThreshold() {
        let clock = Clock()
        let queue = ProbeQueue()
        let delayed = DelayedBlocks()
        let monitor = CompanionMainThreadMonitor(now: { clock.now },
                                                 runOnMain: { queue.post($0) },
                                                 ticksAutomatically: false,
                                                 after: { delayed.schedule($0, $1) })
        let changes = OSAllocatedUnfairLock(initialState: 0)
        let token = monitor.addObserver { changes.withLock { $0 += 1 } }
        queue.runAll()  // the probe posted on subscribing

        monitor.expedite()
        XCTAssertEqual(queue.count, 1, "probed at once")
        XCTAssertEqual(delayed.delays, [CompanionMainStallTracker.expeditedThreshold])
        XCTAssertFalse(monitor.isMainBlocked())

        // The moment passes and the probe has not run. Well short of the
        // ordinary threshold. (A round number, so the clock's arithmetic is exact.)
        clock.now += 0.5
        delayed.runAll()
        XCTAssertEqual(changes.withLock { $0 }, 1, "observers are told without anyone asking")
        XCTAssertTrue(monitor.isMainBlocked())
        _ = token
    }

    /// The alert was started by something the user did at the Mac, which does
    /// not freeze the main queue: the probe runs, and nothing is reported.
    func testExpediteReportsNothingWhenTheProbeRuns() {
        let clock = Clock()
        let queue = ProbeQueue()
        let delayed = DelayedBlocks()
        let monitor = CompanionMainThreadMonitor(now: { clock.now },
                                                 runOnMain: { queue.post($0) },
                                                 ticksAutomatically: false,
                                                 after: { delayed.schedule($0, $1) })
        let changes = OSAllocatedUnfairLock(initialState: 0)
        let token = monitor.addObserver { changes.withLock { $0 += 1 } }
        queue.runAll()

        monitor.expedite()
        queue.runAll()
        clock.now += CompanionMainStallTracker.expeditedThreshold
        delayed.runAll()
        XCTAssertEqual(changes.withLock { $0 }, 0)
        XCTAssertFalse(monitor.isMainBlocked())
        _ = token
    }

    func testDefaultClockDoesNotGoBackwards() {
        let first = CompanionMainThreadMonitor.uptimeExcludingSleep()
        let second = CompanionMainThreadMonitor.uptimeExcludingSleep()
        XCTAssertGreaterThan(first, 0)
        XCTAssertGreaterThanOrEqual(second, first)
    }
}
