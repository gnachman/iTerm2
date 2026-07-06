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
//  Two cursor kinds, and why both are needed (the contentless wakeup, rev >= 2):
//
//  Message.seq is GLOBAL and monotonic across all chats (one Message table,
//  INTEGER PRIMARY KEY AUTOINCREMENT) - no two messages share a seq. There are
//  two independent writers of "what has the user already seen", and only one
//  moves in global-seq order:
//    - the NSE pulling: fetches seq > floor in order and advances the floor to
//      the max served. A single global counter (the floor) is perfect for this.
//    - the app reading: opening a chat in the foreground advances THAT chat's
//      watermark to its tip. This is a per-chat jump, NOT coordinated with other
//      chats' positions on the global line - so it cannot share one global
//      counter without burying other chats' older-but-unread messages.
//
//  Worked example (chats A and B; floor = syncFloor.message; wmA/wmB per-chat).
//  Start synced/read to seq 200:  floor=200  wmA=200  wmB=200
//    1. B gets a message -> (201,B). Mac sends a wakeup; phone offline, APNs
//       holds it pending.
//    2. A gets three messages -> (202,A)(203,A)(204,A). Three more wakeups, all
//       with the SAME sentinel collapse id, so APNs COALESCES the four pending
//       wakeups into one. Phone still offline.
//    3. User opens the APP and reads chat A (foreground) before the push lands.
//       The app receives history(maxSeq:204) and advances ONLY wmA -> 204; it
//       does NOT touch the floor.   State: floor=200  wmA=204  wmB=200
//       (B@201 is still unread; the user never opened B.)
//    4. App backgrounds; the one coalesced wakeup is delivered; the NSE runs:
//         syncSince { messageSeq: 200 (=floor), ... }
//         reply items: B@201, A@202, A@203, A@204   (maxMessageSeq=204)
//       Per-chat gate: B@201 > wmB(200) -> RENDER "Chat B"; A@202/203/204 all
//       <= wmA(204) -> SKIP (already read in the app). Commit wmB->201,
//       floor->204.   Result: B notified, A's read messages suppressed. Correct.
//
//  A single global counter cannot do this. At step 3 the app must mark A read:
//    - advance the one cursor to 204  -> step 4 fetches seq>204 -> B@201 is
//      below it, never fetched, never notified (B silently buried); or
//    - leave the one cursor at 200     -> step 4 re-notifies A@202/203/204 that
//      the user just read in the app.
//  The split wins because the app's read-state write is per-chat (wmA only),
//  while the NSE-only floor still bounds the fetch in seq order. If re-notifying
//  foreground-read messages were acceptable, the per-chat watermarks could be
//  dropped and the floor alone would suffice - that is the real UX trade.
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
    private static let floorPrefix = "syncFloor."

    public init(backing: WatermarkBacking) {
        self.backing = backing
    }

    /// The two global query floors for the unified syncSince push (revision >= 2).
    /// A floor only bounds the fetch window and is advanced ONLY by the NSE after a
    /// successful sync; per-chat `watermark.` values remain the read-state
    /// suppression gate. Keeping these separate prevents read-state in one chat
    /// from suppressing an older unread message in another (their seqs share one
    /// global space).
    public enum FloorKind: String {
        case message
        case alert
    }

    /// The global floor for `kind`, or nil if none has been recorded yet (first
    /// run after upgrading to the contentless-wakeup protocol).
    public func floor(_ kind: FloorKind) -> Int64? {
        backing.watermarkValue(forKey: Self.floorPrefix + kind.rawValue)
    }

    /// Monotonic max-merge of a global floor (same discipline as advance()).
    @discardableResult
    public func advanceFloor(_ kind: FloorKind, to candidate: Int64) -> Int64 {
        let key = Self.floorPrefix + kind.rawValue
        if let existing = backing.watermarkValue(forKey: key), candidate <= existing {
            return existing
        }
        backing.setWatermarkValue(candidate, forKey: key)
        return candidate
    }

    /// Unconditionally set a global floor, including LOWERING it (used only on a
    /// host-reported reset, when the store rewound below the stored floor).
    public func setFloor(_ kind: FloorKind, to value: Int64) {
        backing.setWatermarkValue(value, forKey: Self.floorPrefix + kind.rawValue)
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

    /// Forget all per-chat watermarks and the global sync floors (on unpair).
    public func reset() {
        backing.removeWatermarks(matchingPrefix: Self.prefix)
        backing.removeWatermarks(matchingPrefix: Self.floorPrefix)
    }

    /// Forget only the per-chat watermarks (used when the host reports the message
    /// store rewound, so a stale-high watermark can't suppress notifications in the
    /// new, lower seq space). Leaves the global floors alone.
    public func resetChatWatermarks() {
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
