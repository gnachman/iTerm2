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

        public init(chatName: String, previews: [Preview], maxSeq: Int64, truncated: Bool) {
            self.chatName = chatName
            self.previews = previews
            self.maxSeq = maxSeq
            self.truncated = truncated
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

    public func run(collapseToken token: String) async -> Decision {
        let existing = watermarks.watermark(forToken: token)
        let sinceSeq = existing ?? 0
        let limit = (existing == nil) ? firstRunLimit : normalLimit
        do {
            let reply = try await fetch(token, sinceSeq, limit)
            // Advance the watermark to the chat's tip on ANY successful fetch
            // (even an empty one) so a backlog can't re-notify. advance is a
            // max-merge, so a maxSeq of 0 (token matched no chat) never lowers an
            // existing value. A failed fetch throws and leaves the watermark
            // untouched (the transient-failure case in the host reply).
            watermarks.advance(token: token, to: reply.maxSeq)
            if reply.previews.isEmpty {
                return .fallback
            }
            return .content(chatName: reply.chatName,
                            previews: reply.previews,
                            truncated: reply.truncated)
        } catch {
            return .fallback
        }
    }
}
