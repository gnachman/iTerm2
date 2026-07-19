//
//  RelayReconnectBackoff.swift
//  CompanionCore
//
//  The full-jitter reconnect backoff of design §7.3 / Appendix C, shared by both
//  endpoints so a whole-host reconnect storm flattens the same way. Full jitter
//  (a uniform delay in [0, window]) is the flattest scheme for a synchronized
//  herd; the window starts at RECONNECT_JITTER_INITIAL and grows full-jitter
//  exponential to RECONNECT_BACKOFF_CAP. One consecutive-failure counter drives
//  it for every failure class (re-resolve, retry-here, connect failure), which is
//  what keeps a skew-window bounce from becoming a tight loop.
//

import Foundation

public struct RelayReconnectBackoff: Sendable {
    /// First-reconnect jitter window `[0, initialJitter]` (default 3 s).
    public let initialJitter: TimeInterval
    /// Exponential base for subsequent failures (default 1 s).
    public let base: TimeInterval
    /// Maximum jitter window (default 30 s).
    public let cap: TimeInterval

    public init(initialJitter: TimeInterval = 3, base: TimeInterval = 1, cap: TimeInterval = 30) {
        self.initialJitter = initialJitter
        self.base = base
        self.cap = cap
    }

    /// The upper bound of the jitter window for the nth consecutive failure
    /// (n >= 1; the first reconnect is n == 1). The first reconnect uses the flat
    /// `initialJitter`; each subsequent failure uses `min(cap, base * 2^n)`. The
    /// actual delay is a uniform draw in `[0, upperBound]` (full jitter).
    public func jitterUpperBound(consecutiveFailures n: Int) -> TimeInterval {
        precondition(n >= 1, "consecutiveFailures is 1-based")
        if n == 1 {
            return initialJitter
        }
        return min(cap, base * pow(2, Double(n)))
    }

    /// A jittered delay in `[0, jitterUpperBound(n)]` (full jitter). Non-async and
    /// side-effect-free apart from the RNG draw, so callers schedule the sleep.
    public func delay(consecutiveFailures n: Int) -> TimeInterval {
        Double.random(in: 0...jitterUpperBound(consecutiveFailures: n))
    }
}
