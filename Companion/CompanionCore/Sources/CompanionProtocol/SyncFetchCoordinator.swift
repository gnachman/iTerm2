//
//  SyncFetchCoordinator.swift
//  CompanionCore
//
//  The decision core for the contentless-wakeup push (protocol revision >= 2),
//  the sibling of PushFetchCoordinator. On a wakeup the NSE asks the mac for
//  everything new across ALL chats and alerts in one round trip; this type
//  decides which items to surface and computes the DEFERRED cursor writes the
//  shell commits only for the outcome it actually delivers.
//
//  Two cursor kinds, kept separate on purpose (docs: watermark model):
//    - A single global FLOOR per stream (message, alert) bounds the fetch window
//      and is advanced only here, after a successful sync.
//    - The existing PER-CHAT watermarks remain the read-state suppression gate:
//      reading a chat in the app advances its watermark, so a message whose
//      seq <= that chat's watermark is filtered out here even though it is above
//      the global floor. This prevents read-state in one chat from suppressing an
//      older unread message in another (their seqs share one global space).
//
//  Deliberately I/O-free and unit-testable: the connect + handshake + syncSince
//  live in the injected `fetch` closure, and the per-chat token is computed by the
//  injected `tokenForChat` (the NSE supplies HMAC(roomSecret, chatID)); tests pass
//  an identity closure.
//

import Foundation

public struct SyncFetchCoordinator {
    /// One notification to render, preserving the host's GLOBAL time order across
    /// chats and alerts. The shell anchors the first (oldest), sounds/"+ more"s the
    /// last (newest), and computes each threadIdentifier on-device (from chatID for
    /// a message, from the alert key for an alert).
    public enum RenderItem: Equatable {
        case message(chatID: String, chatName: String, uniqueID: UUID, author: String, body: String)
        case alert(alertID: UUID, threadKey: String, title: String, body: String)
    }

    public enum Decision: Equatable {
        /// Render the items IN THE ORDER GIVEN (the host's global time order,
        /// oldest first); append a "+ more" hint to the anchor when truncated.
        case content(items: [RenderItem], truncated: Bool)
        /// The fetch SUCCEEDED but produced nothing to show (everything was
        /// already-read, or a reset resync): the cursors still advance, but no
        /// user-facing content is warranted - the unavoidable push notification is
        /// delivered SILENTLY (no sound). Distinct from `.fallback`.
        case silent
        /// The fetch FAILED (or could not run): show the generic fallback. The
        /// cursors are left untouched so the next wakeup retries.
        case fallback
    }

    private let watermarks: WatermarkStore
    private let normalLimit: Int
    private let firstRunLimit: Int
    private let tokenForChat: (String) -> String
    private let fetch: (_ messageSeq: Int64, _ alertSeq: Int64, _ limit: Int) async throws -> NSESyncSince.Reply

    /// - firstRunLimit: when there is no message floor yet (first sync after the
    ///   upgrade to revision 2), fetch only this many newest items instead of the
    ///   whole backlog; the floor still jumps to the tip so nothing re-notifies.
    /// - tokenForChat: maps a chatID to its per-chat watermark key
    ///   (HMAC(roomSecret, chatID) in production).
    public init(watermarks: WatermarkStore,
                normalLimit: Int = 20,
                firstRunLimit: Int = 1,
                tokenForChat: @escaping (String) -> String,
                fetch: @escaping (Int64, Int64, Int) async throws -> NSESyncSince.Reply) {
        self.watermarks = watermarks
        self.normalLimit = normalLimit
        self.firstRunLimit = firstRunLimit
        self.tokenForChat = tokenForChat
        self.fetch = fetch
    }

    /// The decision plus DEFERRED cursor writes. run() never mutates a cursor
    /// itself: the caller races run() against a delivery deadline and uses whichever
    /// finishes first, so a write applied inside run() could persist for a decision
    /// the caller then throws away (skipping that content forever). commit() applies
    /// these ONLY for the outcome actually delivered.
    public struct Outcome {
        public let decision: Decision
        // Per-chat watermark advances (token -> max seq seen for that chat).
        let perChatAdvances: [String: Int64]
        // Global floor writes; nil = leave unchanged. `reset` = set (may lower)
        // rather than advance (max-merge).
        let messageFloor: (value: Int64, reset: Bool)?
        let alertFloor: (value: Int64, reset: Bool)?
        // On a message-store rewind, clear all per-chat watermarks before applying
        // the advances above, so a stale-high watermark can't suppress the new
        // lower seq space.
        let resetChatWatermarks: Bool
    }

    public func run() async -> Outcome {
        let messageFloorValue = watermarks.floor(.message)
        let alertFloorValue = watermarks.floor(.alert)
        // "First run" keys off the MESSAGE floor: an absent message floor means the
        // upgrade just happened and the whole message history is "new" relative to
        // seq 0, so the limit must bound the flood. An absent alert floor is not a
        // flood risk (the alert table is brand-new post-upgrade).
        let firstRun = (messageFloorValue == nil)
        // First run sends a NEGATIVE message floor as an explicit signal to the
        // host: fetch the NEWEST `firstRunLimit` messages (a teaser) and jump the
        // floor straight to the global tip, so the post-upgrade backlog is skipped
        // rather than notified one-window-at-a-time. A normal run sends its real
        // floor and the host drains oldest-first, advancing the floor only to what
        // it actually covered (so a truncated window never buries the tail).
        let messageSeq = messageFloorValue ?? -1
        let alertSeq = alertFloorValue ?? 0
        let limit = firstRun ? firstRunLimit : normalLimit
        do {
            let reply = try await fetch(messageSeq, alertSeq, limit)
            return decide(reply)
        } catch {
            // A failed fetch leaves every cursor untouched (the NSE shows the
            // generic fallback and retries on the next push). Log via the package
            // hook so the cause is diagnosable; no message content is involved.
            CompanionLog.log("SyncFetchCoordinator: fetch failed (\(error)); delivering fallback")
            return Outcome(decision: .fallback, perChatAdvances: [:],
                           messageFloor: nil, alertFloor: nil, resetChatWatermarks: false)
        }
    }

    private func decide(_ reply: NSESyncSince.Reply) -> Outcome {
        var renderItems: [RenderItem] = []
        var perChatAdvances: [String: Int64] = [:]

        for item in reply.items {
            switch item {
            case .message(let m):
                let token = tokenForChat(m.chatID)
                // The whole message store rewound: every per-chat watermark is
                // about to be cleared, so don't gate on the now-stale value.
                let suppressed = !reply.messageReset
                    && (watermarks.watermark(forToken: token).map { m.seq <= $0 } ?? false)
                // Advance the chat's watermark to the max seq we SAW for it
                // (whether or not we surface it), so an already-read message both
                // suppresses here and never re-notifies.
                perChatAdvances[token] = max(perChatAdvances[token] ?? Int64.min, m.seq)
                if !suppressed {
                    renderItems.append(.message(chatID: m.chatID, chatName: m.chatName,
                                                uniqueID: m.uniqueID, author: m.author, body: m.body))
                }
            case .alert(let a):
                // Alerts have no in-app read-state; the global alert floor is their
                // only suppression, and the host already returned seq > floor.
                renderItems.append(.alert(alertID: a.alertID, threadKey: a.threadKey,
                                          title: a.title, body: a.body))
            }
        }

        // reply.items is already in the host's global time order; renderItems
        // preserves it (suppressed messages are simply dropped), so the shell can
        // anchor the oldest and sound/flag the newest. An empty render set after a
        // SUCCESSFUL fetch (everything already-read, or a reset resync) is `.silent`
        // - the cursors still advance, but no spurious user-facing content is shown.
        // (Genuine fetch failure returns `.fallback` from the catch in run().)
        let decision: Decision = renderItems.isEmpty
            ? .silent
            : .content(items: renderItems, truncated: reply.truncated)
        // Counts and cursors only; never chat names or message/alert content.
        CompanionLog.log("SyncFetchCoordinator: fetched \(reply.items.count) item(s) -> render \(renderItems.count); maxMessageSeq=\(reply.maxMessageSeq), maxAlertSeq=\(reply.maxAlertSeq), messageReset=\(reply.messageReset), alertReset=\(reply.alertReset), truncated=\(reply.truncated)")
        return Outcome(decision: decision,
                       perChatAdvances: perChatAdvances,
                       messageFloor: (reply.maxMessageSeq, reply.messageReset),
                       alertFloor: (reply.maxAlertSeq, reply.alertReset),
                       resetChatWatermarks: reply.messageReset)
    }

    /// The outcome to use when the delivery deadline fires before run() finishes:
    /// the generic fallback, with NO cursor move.
    public func deadlineOutcome() -> Outcome {
        Outcome(decision: .fallback, perChatAdvances: [:],
                messageFloor: nil, alertFloor: nil, resetChatWatermarks: false)
    }

    /// Apply the deferred cursor writes. Invoked by the caller ONLY for the outcome
    /// it actually delivered, so a discarded (deadline-lost) outcome moves nothing.
    public func commit(_ outcome: Outcome) {
        if outcome.resetChatWatermarks {
            watermarks.resetChatWatermarks()
        }
        for (token, seq) in outcome.perChatAdvances {
            if outcome.resetChatWatermarks {
                watermarks.set(token: token, to: seq)   // start the new seq space cleanly
            } else {
                watermarks.advance(token: token, to: seq)
            }
        }
        if let floor = outcome.messageFloor {
            if floor.reset { watermarks.setFloor(.message, to: floor.value) }
            else { watermarks.advanceFloor(.message, to: floor.value) }
        }
        if let floor = outcome.alertFloor {
            if floor.reset { watermarks.setFloor(.alert, to: floor.value) }
            else { watermarks.advanceFloor(.alert, to: floor.value) }
        }
    }
}
