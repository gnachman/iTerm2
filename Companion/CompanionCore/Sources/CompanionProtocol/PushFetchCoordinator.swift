//
//  PushFetchCoordinator.swift
//  CompanionCore
//
//  The decision core of the Notification Service Extension (docs/push.txt
//  section 6), factored out of the UNNotificationServiceExtension shell so every
//  path is unit-testable with no network, keychain, or push stack. Given the
//  pushed collapse token it reads the per-chat watermark, fetches new messages,
//  and decides whether to show content or the generic fallback, advancing the
//  watermark on a successful fetch.
//
//  It is generic over the preview type so it can live in the package (the
//  concrete CompanionMessagePreview depends on the chat model, which is not in
//  the package). The NSE instantiates PushFetchCoordinator<CompanionMessagePreview>.
//
//  Deliberately I/O-free: the connect + Noise handshake + messagesSince live in
//  the injected `fetch` closure, and the deadline + hard transport cancel are
//  the shell's job (URLSession's receive ignores cooperative cancellation), so
//  this type never hangs in a test.
//

import Foundation

public struct PushFetchCoordinator<Preview> {
    public enum Decision {
        /// Render one notification per preview (titled with chatName); append a
        /// "+N more" hint when truncated.
        case content(chatName: String, previews: [Preview], truncated: Bool)
        /// Show the generic fallback (nothing new, token matched no chat, or the
        /// fetch failed).
        case fallback
    }

    /// What `fetch` returns; mirrors CompanionClient.messagesSince's reply.
    public struct Reply {
        public let chatName: String
        public let previews: [Preview]
        public let maxSeq: Int64
        public let truncated: Bool
        /// The host resolved the chat but our watermark was beyond its tip (the
        /// chat DB rewound). Reset the watermark DOWN to maxSeq rather than
        /// max-merging. The host sets this ONLY for a resolved chat, so the
        /// maxSeq:0 of a token-matched-no-chat reply does not trigger a reset.
        public let reset: Bool

        public init(chatName: String, previews: [Preview], maxSeq: Int64, truncated: Bool, reset: Bool) {
            self.chatName = chatName
            self.previews = previews
            self.maxSeq = maxSeq
            self.truncated = truncated
            self.reset = reset
        }
    }

    private let watermarks: WatermarkStore
    private let normalLimit: Int
    private let firstRunLimit: Int
    private let fetch: (_ collapseToken: String, _ sinceSeq: Int64, _ limit: Int) async throws -> Reply

    /// - firstRunLimit: when there is no watermark yet, fetch only this many
    ///   (newest) messages instead of dumping history; the watermark still jumps
    ///   to the chat's tip so the backlog never re-notifies.
    public init(watermarks: WatermarkStore,
                normalLimit: Int = 10,
                firstRunLimit: Int = 1,
                fetch: @escaping (String, Int64, Int) async throws -> Reply) {
        self.watermarks = watermarks
        self.normalLimit = normalLimit
        self.firstRunLimit = firstRunLimit
        self.fetch = fetch
    }

    /// The decision plus a DEFERRED watermark write. run() does NOT mutate the
    /// watermark itself: the caller races run() against a delivery deadline and
    /// uses whichever finishes first, so a watermark advance applied inside run()
    /// could persist for a decision the caller then throws away - skipping that
    /// content forever while only the generic fallback was shown. So run() returns
    /// the pending write and the caller commit()s it ONLY for the outcome it
    /// actually delivers.
    public struct Outcome {
        public let decision: Decision
        let token: String
        let pendingWatermark: Int64?   // nil = leave the watermark unchanged
        let resets: Bool               // true = set (may lower); false = advance (max-merge)
    }

    public func run(collapseToken token: String) async -> Outcome {
        let existing = watermarks.watermark(forToken: token)
        let sinceSeq = existing ?? 0
        let limit = (existing == nil) ? firstRunLimit : normalLimit
        do {
            let reply = try await fetch(token, sinceSeq, limit)
            // Compute, but do NOT apply, the watermark move. A successful fetch
            // (even an empty one) wants to advance to the chat's tip so a backlog
            // can't re-notify; a reset moves it DOWN to a rewound chat's tip.
            let decision: Decision = reply.previews.isEmpty
                ? .fallback
                : .content(chatName: reply.chatName,
                           previews: reply.previews,
                           truncated: reply.truncated)
            return Outcome(decision: decision,
                           token: token,
                           pendingWatermark: reply.maxSeq,
                           resets: reply.reset)
        } catch {
            // A failed fetch leaves the watermark untouched.
            return Outcome(decision: .fallback, token: token, pendingWatermark: nil, resets: false)
        }
    }

    /// The outcome to use when the delivery deadline fires before run() finishes:
    /// the generic fallback, with NO watermark move (so nothing fetched-but-undelivered is skipped).
    public func deadlineOutcome(collapseToken token: String) -> Outcome {
        Outcome(decision: .fallback, token: token, pendingWatermark: nil, resets: false)
    }

    /// Apply the deferred watermark write. The caller invokes this ONLY for the
    /// outcome it actually delivered, so a discarded (deadline-lost) outcome never
    /// moves the watermark. A reset may lower it (set); otherwise max-merge
    /// (advance), so maxSeq 0 (token matched no chat) never lowers it.
    public func commitWatermark(_ outcome: Outcome) {
        guard let value = outcome.pendingWatermark else { return }
        if outcome.resets {
            watermarks.set(token: outcome.token, to: value)
        } else {
            watermarks.advance(token: outcome.token, to: value)
        }
    }
}
