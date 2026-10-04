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

import Foundation
import os

/// Whether the main thread is serving its queue, as the link sees it. A protocol
/// so tests can substitute a fake.
protocol CompanionMainStallSource: AnyObject, Sendable {
    func isMainBlocked() -> Bool

    /// `changed` is called, on any thread, each time isMainBlocked() changes.
    /// Keep the returned token to stay subscribed.
    func addObserver(_ changed: @escaping @Sendable () -> Void) -> AnyObject
}

/// The decision logic, with time passed in so it can be tested without waiting.
struct CompanionMainStallTracker: Sendable {
    /// How long a block may sit unrun on the main queue before the main thread
    /// counts as blocked. Long enough that ordinary busy moments do not flap
    /// the status; short enough to beat the phone's request timeouts.
    static let threshold: TimeInterval = 2

    private(set) var isBlocked = false
    /// When the outstanding probe was posted, or nil if none is outstanding.
    private var probePostedAt: TimeInterval?

    /// Called periodically. Returns whether a new probe block should be posted
    /// to the main queue now, and whether `isBlocked` just changed.
    mutating func tick(now: TimeInterval) -> (postProbe: Bool, changed: Bool) {
        guard let probePostedAt else {
            self.probePostedAt = now
            return (true, false)
        }
        // One probe at a time: a blocked main queue would otherwise collect a
        // pile of them, all to run at once when it resumes.
        if !isBlocked && now - probePostedAt >= Self.threshold {
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

    /// The observer token. Held weakly here, so dropping the token unsubscribes.
    private final class Observer: Sendable {
        let changed: @Sendable () -> Void
        init(changed: @escaping @Sendable () -> Void) {
            self.changed = changed
        }
    }

    private struct WeakObserver: Sendable {
        weak var observer: Observer?
    }

    private struct State: Sendable {
        var tracker = CompanionMainStallTracker()
        var observers: [WeakObserver] = []
        /// Whether the automatic tick loop is running.
        var ticking = false

        mutating func liveObservers() -> [Observer] {
            observers.removeAll { $0.observer == nil }
            return observers.compactMap { $0.observer }
        }
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let now: @Sendable () -> TimeInterval
    private let runOnMain: @Sendable (@escaping @Sendable () -> Void) -> Void
    private let ticksAutomatically: Bool

    /// - now: the clock. Must not advance while the Mac is asleep.
    /// - runOnMain: posts a block to the main queue.
    /// - ticksAutomatically: when true, tick() is called about once a second
    ///   while anything is subscribed. Tests pass false and call tick().
    init(now: @escaping @Sendable () -> TimeInterval = CompanionMainThreadMonitor.uptimeExcludingSleep,
         runOnMain: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) },
         ticksAutomatically: Bool = true) {
        self.now = now
        self.runOnMain = runOnMain
        self.ticksAutomatically = ticksAutomatically
    }

    /// Check on the main thread now.
    func tick() {
        let time = now()
        let (postProbe, toNotify) = state.withLock { state -> (Bool, [Observer]) in
            let result = state.tracker.tick(now: time)
            return (result.postProbe, result.changed ? state.liveObservers() : [])
        }
        if !toNotify.isEmpty {
            RLog("Companion: the main thread has stopped responding")
        }
        for observer in toNotify {
            observer.changed()
        }
        if postProbe {
            runOnMain { [weak self] in
                self?.probeRan()
            }
        }
    }

    private func probeRan() {
        let toNotify = state.withLock { state -> [Observer] in
            return state.tracker.probeRan() ? state.liveObservers() : []
        }
        if !toNotify.isEmpty {
            RLog("Companion: the main thread is responding again")
        }
        for observer in toNotify {
            observer.changed()
        }
    }

    func isMainBlocked() -> Bool {
        return state.withLock { $0.tracker.isBlocked }
    }

    func addObserver(_ changed: @escaping @Sendable () -> Void) -> AnyObject {
        let observer = Observer(changed: changed)
        let startTicking = state.withLock { state -> Bool in
            state.observers.append(WeakObserver(observer: observer))
            guard ticksAutomatically, !state.ticking else {
                return false
            }
            state.ticking = true
            return true
        }
        if startTicking {
            startTickLoop()
        }
        return observer
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
                let keepGoing = self.state.withLock { state -> Bool in
                    if state.liveObservers().isEmpty {
                        state.ticking = false
                        return false
                    }
                    return true
                }
                guard keepGoing else {
                    return
                }
                self.tick()
            }
        }
    }
}
