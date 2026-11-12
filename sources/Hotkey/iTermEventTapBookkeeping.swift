//
//  iTermEventTapBookkeeping.swift
//  iTerm2SharedARC
//
//  State the keyboard event taps keep now that they aren't always filtering on the main thread.
//  See issue 12645.
//

import CoreGraphics
import Foundation
import os

// Remembers the most recent events a tap handled so the app can tell them apart from events that
// reached it some other way. It identifies events by timestamp and type rather than marking them,
// because other tools tag their synthetic events in kCGEventSourceUserData and rely on the tag
// surviving. The keycode isn't part of the identity because remapping can change it (Fn
// translation). Timestamps match within a microsecond because the app's copy of an event may have
// gone through NSEvent's timestamp, which is in seconds. Main thread only.
@objc(iTermRecentEventLog)
class iTermRecentEventLog: NSObject {
    private struct Key {
        var timestamp: CGEventTimestamp
        var type: CGEventType

        func matches(_ other: Key) -> Bool {
            let tolerance: CGEventTimestamp = 1_000
            let delta = timestamp > other.timestamp ? timestamp - other.timestamp : other.timestamp - timestamp
            return type == other.type && delta <= tolerance
        }
    }

    private let capacity: Int
    private var keys = [Key]()
    private var next = 0

    @objc(initWithCapacity:)
    init(capacity: Int) {
        it_assert(capacity > 0)
        self.capacity = capacity
        super.init()
    }

    @objc(recordEvent:)
    func record(_ event: CGEvent) {
        let key = Key(timestamp: event.timestamp, type: event.type)
        if keys.count < capacity {
            keys.append(key)
        } else {
            keys[next] = key
        }
        next = (next + 1) % capacity
    }

    @objc(containsEvent:)
    func contains(_ event: CGEvent) -> Bool {
        let key = Key(timestamp: event.timestamp, type: event.type)
        return keys.contains { $0.matches(key) }
    }
}

// Decides whether a flags-changed event the app received must be injected into the flags tap's
// observers because the tap didn't already report it.
//
// While iTerm2 is active the tap reports each event synchronously, before the app receives it.
// Around activation, the filtering tap may still think iTerm2 is inactive and defer the report to
// the main thread, so the app can receive the event before or after the deferred report runs.
// Either way observers must hear about it exactly once.
@objc(iTermFlagsChangedLedger)
class iTermFlagsChangedLedger: NSObject {
    // Reports made since the app last received an event. Main thread only.
    private var deliveries = 0
    // Deferred reports a received event was already attributed to. Main thread only.
    private var claimedPending = 0
    // Deferred reports not yet run. Incremented on the filter thread.
    private let pending = OSAllocatedUnfairLock(initialState: 0)

    // Reports made since the app last received an event or since -reset.
    @objc var deliveryCount: Int {
        return deliveries
    }

    // The tap reported an event synchronously.
    @objc func eventTapDidDeliverEvent() {
        deliveries += 1
    }

    // The tap will report an event later on the main thread. Safe to call from any thread.
    @objc func eventTapWillDeliverEventLater() {
        pending.withLock { $0 += 1 }
    }

    // A deferred report ran.
    @objc func eventTapDidDeliverDeferredEvent() {
        if claimedPending > 0 {
            // The app already received this event and didn't inject it.
            claimedPending -= 1
        } else {
            deliveries += 1
        }
        pending.withLock { $0 -= 1 }
    }

    // The app received a flags-changed event. Returns whether to inject it, and starts counting
    // afresh for the next one.
    @objc func appReceivedEventShouldInject() -> Bool {
        let unclaimed = pending.withLock { $0 } - claimedPending
        let inject = deliveries == 0 && unclaimed == 0
        if unclaimed > 0 {
            claimedPending += 1
        }
        deliveries = 0
        return inject
    }

    @objc func reset() {
        deliveries = 0
    }
}
