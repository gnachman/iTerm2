//
//  RelaySocketLifecycle.swift
//  CompanionCore
//
//  Tracks a relay socket's lifecycle timing so a drop can be attributed instead of
//  surfacing as an opaque "closed". At the moment of failure we want three numbers:
//  how long the socket had been parked, how long since the last real DATA frame
//  (NOT a keepalive ping), and how long since the last successful ping. A socket
//  that dies reliably ~N seconds after its last data frame while pings keep
//  succeeding points at an edge/proxy idle-reap that does not count WebSocket ping
//  frames as activity - a very different fix (application-level data keepalive)
//  than a flaky network. Thread-safe: send/receive/ping run on separate tasks.
//

import Foundation
import CompanionProtocol

public final class RelaySocketLifecycle: @unchecked Sendable {
    private let lock = UnfairLock()
    private let openedAt: Double
    private var lastDataAt: Double
    private var lastPingOkAt: Double = 0

    public init() {
        let now = Self.now()
        openedAt = now
        lastDataAt = now
    }

    /// Monotonic seconds (mach uptime): unaffected by wall-clock changes, and pauses
    /// during system sleep, so "parked" reflects awake time.
    private static func now() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    /// A real data frame was sent or received (resets the data-idle clock).
    public func noteData() {
        let t = Self.now()
        lock.withLock { lastDataAt = t }
    }

    /// A keepalive ping round-tripped successfully.
    public func notePingOk() {
        let t = Self.now()
        lock.withLock { lastPingOkAt = t }
    }

    /// e.g. "(parked 32s, 31s since last data frame, last ping ok 1s ago)". Append
    /// to a close/failure log so the drop's timing is visible.
    public func summary() -> String {
        let now = Self.now()
        let (parked, sinceData, lastPing) = lock.withLock {
            (now - openedAt, now - lastDataAt, lastPingOkAt)
        }
        let ping = lastPing > 0 ? "\(Int(now - lastPing))s ago" : "never"
        return "(parked \(Int(parked))s, \(Int(sinceData))s since last data frame, last ping ok \(ping))"
    }
}
