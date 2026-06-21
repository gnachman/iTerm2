//
//  WatermarkStore.swift
//  CompanionCore
//
//  The phone's per-chat "last surfaced seq" watermark for relay push, keyed by
//  the opaque collapse token (HMAC(roomSecret, chatID)). Shared by the app
//  (which advances it on a foreground sync) and the Notification Service
//  Extension (which advances it after showing content). It is the only
//  cross-process mutable state in the feature and is deliberately
//  merge-friendly so it needs no lock: advance(token:to:) is a monotonic max
//  that never lowers a stored value, so a lost update under the App Group's
//  non-atomic read-modify-write at worst re-shows one notification (benign)
//  rather than corrupting the cursor.
//

import Foundation

/// Pluggable key/value backing, injected so the merge logic is unit-testable
/// without a real UserDefaults / App Group container.
public protocol WatermarkBacking: AnyObject {
    /// The stored value, or nil if the key was never set (first run).
    func watermarkValue(forKey key: String) -> Int64?
    func setWatermarkValue(_ value: Int64, forKey key: String)
    /// Remove every key beginning with `prefix` (used on unpair).
    func removeWatermarks(matchingPrefix prefix: String)
}

public final class WatermarkStore {
    private let backing: WatermarkBacking
    private static let prefix = "watermark."

    public init(backing: WatermarkBacking) {
        self.backing = backing
    }

    /// The highest seq surfaced for the chat, or nil if none has been recorded
    /// yet (first run: the caller should show only the newest message and seed
    /// the watermark from maxSeq).
    public func watermark(forToken token: String) -> Int64? {
        backing.watermarkValue(forKey: Self.prefix + token)
    }

    /// Monotonic max-merge: store `candidate` only when it exceeds the current
    /// value (or none is set). Never lowers a stored watermark, so concurrent
    /// advances converge on the maximum regardless of order. Returns the value
    /// now in effect.
    @discardableResult
    public func advance(token: String, to candidate: Int64) -> Int64 {
        let key = Self.prefix + token
        if let existing = backing.watermarkValue(forKey: key), candidate <= existing {
            return existing
        }
        backing.setWatermarkValue(candidate, forKey: key)
        return candidate
    }

    /// Unconditionally set a watermark, including LOWERING it. Used only to
    /// reset when the host reports the chat DB rewound (seq restarted below the
    /// stored value), which the monotonic advance() would otherwise ignore -
    /// leaving the watermark stuck above the new seq space so nothing ever
    /// re-notifies.
    public func set(token: String, to value: Int64) {
        backing.setWatermarkValue(value, forKey: Self.prefix + token)
    }

    /// Forget all per-chat watermarks (on unpair).
    public func reset() {
        backing.removeWatermarks(matchingPrefix: Self.prefix)
    }
}

/// Production backing over a shared App Group UserDefaults suite. Int64 is
/// stored as Int (64-bit on iOS/macOS), and object(forKey:) distinguishes
/// "absent" (first run) from a stored 0.
public final class UserDefaultsWatermarkBacking: WatermarkBacking {
    private let defaults: UserDefaults

    public init?(appGroup: String) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return nil }
        self.defaults = defaults
    }

    public func watermarkValue(forKey key: String) -> Int64? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return Int64(defaults.integer(forKey: key))
    }

    public func setWatermarkValue(_ value: Int64, forKey key: String) {
        defaults.set(Int(value), forKey: key)
    }

    public func removeWatermarks(matchingPrefix prefix: String) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
