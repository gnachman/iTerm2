//
//  CompanionStreamBudget.swift
//  iTerm2
//
//  A rolling byte budget for a live stream, isolated from any clock or transport
//  so it can be tested deterministically. The relay enforces a per-room daily
//  byte quota; exceeding it gets the connection force-closed and (because the
//  quota is persisted) poisons the room for the rest of the 24h window. To stay
//  under it, the streamer pauses itself before the client ceiling is reached
//  rather than letting the relay cut it off.
//

import Foundation

struct CompanionStreamBudget {
    /// Bytes allowed within one window. Set below the relay's per-room daily
    /// quota so the client pauses first.
    let limitBytes: Int
    let windowSeconds: TimeInterval

    private var windowStart: TimeInterval?
    private var bytesUsed = 0

    init(limitBytes: Int, windowSeconds: TimeInterval = 24 * 60 * 60) {
        self.limitBytes = limitBytes
        self.windowSeconds = windowSeconds
    }

    /// Account for bytes that were sent.
    mutating func record(bytes: Int, now: TimeInterval) {
        roll(now)
        bytesUsed += bytes
    }

    /// Whether the budget for the current window is used up.
    mutating func isExhausted(now: TimeInterval) -> Bool {
        roll(now)
        return bytesUsed >= limitBytes
    }

    /// Bytes still available in the current window.
    mutating func remaining(now: TimeInterval) -> Int {
        roll(now)
        return max(0, limitBytes - bytesUsed)
    }

    /// Reset the counter once the window has fully elapsed.
    private mutating func roll(_ now: TimeInterval) {
        guard let start = windowStart else {
            windowStart = now
            return
        }
        if now - start >= windowSeconds {
            windowStart = now
            bytesUsed = 0
        }
    }
}
