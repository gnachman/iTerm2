//
//  CompanionMainThreadMonitor.swift
//  iTerm2
//
//  Notices when the main thread has stopped serving its dispatch queue, so the
//  companion app can be told that the Mac will not answer requests for now.
//
//  The usual cause is a modal alert started from a main-queue callout, which
//  freezes the main queue until it is dismissed. Alerts shown by iTermWarning
//  are reported to the phone individually (see iTermModalAlertRegistry). This
//  covers everything else: a plain NSAlert, an open or save panel, or the app
//  simply being busy. In those cases the phone can do nothing but wait, and it
//  needs to know that it is waiting rather than disconnected.
//
//  The monitor posts a block to the main queue and watches whether it runs.
//  It uses a clock that does not advance while the Mac is asleep, so waking up
//  does not look like a stall.
//
//  It only runs while something is subscribed, so that an app with no phone
//  connected does no periodic work. The cost is that a stall which began
//  before the first subscriber arrived is measured from the subscription, not
//  from when it began: a phone that connects during a freeze is told the Mac is
//  blocked up to CompanionMainStallTracker.threshold seconds late.
//

import Foundation
import os

/// Whether the main thread is serving its queue, as the link sees it. A protocol
/// so tests can substitute a fake.
protocol CompanionMainStallSource: AnyObject, Sendable {
    func isMainBlocked() -> Bool

    /// `changed` is called, on any thread, each time isMainBlocked() changes.
    /// Keep the returned token to stay subscribed.
    func addObserver(_ changed: @escaping @Sendable () -> Void) -> AnyObject

    /// There is reason to think the main thread may have just become blocked
    /// (an alert that can block it has appeared). Find out quickly, rather than
    /// after the usual threshold: probe now, and if the probe has not run a
    /// moment later, report the main thread blocked.
    func expedite()
}

/// The decision logic, with time passed in so it can be tested without waiting.
struct CompanionMainStallTracker: Sendable {
    /// How long a block may sit unrun on the main queue before the main thread
    /// counts as blocked. Long enough that ordinary busy moments do not flap
    /// the status; short enough to beat the phone's request timeouts.
    static let threshold: TimeInterval = 2
    /// How long a probe may sit unrun after expedite() before the main thread
    /// counts as blocked. A main thread that is serving its queue runs a probe
    /// within milliseconds, so when there is already a specific reason to
    /// suspect a stall this can be far shorter than `threshold`.
    static let expeditedThreshold: TimeInterval = 0.3

    private(set) var isBlocked = false
    /// When the outstanding probe was posted, or nil if none is outstanding.
    private var probePostedAt: TimeInterval?

    /// Called periodically. Returns whether a new probe block should be posted
    /// to the main queue now, and whether `isBlocked` just changed.
    mutating func tick(now: TimeInterval,
                       threshold: TimeInterval = CompanionMainStallTracker.threshold) -> (postProbe: Bool, changed: Bool) {
        guard let probePostedAt else {
            self.probePostedAt = now
            return (true, false)
        }
        // One probe at a time: a blocked main queue would otherwise collect a
        // pile of them, all to run at once when it resumes.
        if !isBlocked && now - probePostedAt >= threshold {
            isBlocked = true
            return (false, true)
        }
        return (false, false)
    }

    /// The probe block ran on the main thread. Returns whether `isBlocked` just
    /// changed.
    mutating func probeRan() -> Bool {
        probePostedAt = nil
        guard isBlocked else {
            return false
        }
        isBlocked = false
        return true
    }
}

final class CompanionMainThreadMonitor: CompanionMainStallSource {
    static let shared = CompanionMainThreadMonitor()

    /// Seconds since boot, not counting time asleep.
    static func uptimeExcludingSleep() -> TimeInterval {
        return TimeInterval(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000
    }

    private static let tickIntervalNanos: UInt64 = 1_000_000_000

    private struct State: Sendable {
        var tracker = CompanionMainStallTracker()
        /// Whether the automatic tick loop is running.
        var ticking = false
    }

    private let observers = WeakObserverList()

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let now: @Sendable () -> TimeInterval
    private let runOnMain: @Sendable (@escaping @Sendable () -> Void) -> Void
    private let ticksAutomatically: Bool
    private let after: @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void

    /// - now: the clock. Must not advance while the Mac is asleep.
    /// - runOnMain: posts a block to the main queue.
    /// - ticksAutomatically: when true, tick() is called about once a second
    ///   while anything is subscribed. Tests pass false and call tick().
    /// - after: runs a block after a delay, off the main thread. Injected for
    ///   tests.
    init(now: @escaping @Sendable () -> TimeInterval = CompanionMainThreadMonitor.uptimeExcludingSleep,
         runOnMain: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) },
         ticksAutomatically: Bool = true,
         after: @escaping @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void = { delay, block in
             DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: block)
         }) {
        self.now = now
        self.runOnMain = runOnMain
        self.ticksAutomatically = ticksAutomatically
        self.after = after
    }

    /// Check on the main thread now.
    func tick() {
        tick(threshold: CompanionMainStallTracker.threshold)
    }

    private func tick(threshold: TimeInterval) {
        let time = now()
        let result = state.withLock { $0.tracker.tick(now: time, threshold: threshold) }
        if result.changed {
            RLog("Companion: the main thread has stopped responding")
            observers.notify()
        }
        if result.postProbe {
            runOnMain { [weak self] in
                self?.probeRan()
            }
        }
    }

    private func probeRan() {
        let changed = state.withLock { $0.tracker.probeRan() }
        if changed {
            RLog("Companion: the main thread is responding again")
            observers.notify()
        }
    }

    func expedite() {
        // Make sure a probe is outstanding. If one already is, it is at least as
        // old as one posted now would be, so judging it by the short threshold
        // cannot report a stall that is not there.
        tick()
        let threshold = CompanionMainStallTracker.expeditedThreshold
        after(threshold) { [weak self] in
            self?.tick(threshold: threshold)
        }
    }

    func isMainBlocked() -> Bool {
        // Evaluated against the clock now, not as of the last tick. The link
        // asks while it builds a hello reply, which can come before any tick.
        tick()
        return state.withLock { $0.tracker.isBlocked }
    }

    func addObserver(_ changed: @escaping @Sendable () -> Void) -> AnyObject {
        let token = observers.add(changed)
        let startTicking = state.withLock { state -> Bool in
            guard ticksAutomatically, !state.ticking else {
                return false
            }
            state.ticking = true
            return true
        }
        if startTicking {
            startTickLoop()
        }
        // Start measuring now, not at the first tick a second from now. A phone
        // may be connecting while the main queue is already frozen: nothing was
        // subscribed when the freeze began, so nothing has been measured yet.
        tick()
        return token
    }

    /// Ticks about once a second for as long as anything is subscribed, then
    /// stops, so an idle app (no phone connected) does no periodic work.
    private func startTickLoop() {
        Task.detached { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: Self.tickIntervalNanos)
                guard let self else {
                    return
                }
                if self.observers.isEmpty {
                    let stop = self.state.withLock { state -> Bool in
                        // Checked again under the lock that addObserver takes
                        // after subscribing, so a subscriber that arrived just
                        // now is not left without a loop.
                        guard self.observers.isEmpty else {
                            return false
                        }
                        state.ticking = false
                        return true
                    }
                    if stop {
                        return
                    }
                }
                self.tick()
            }
        }
    }
}
