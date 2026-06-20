//
//  MessagesSinceResponder.swift
//  iTerm2
//
//  Mac-side core of the relay-push `messagesSince` reply (see docs/push.txt
//  section 2). Given the rows fetched for one chat (seq > the phone's
//  watermark, newest first), it produces the short, display-ready previews the
//  Notification Service Extension turns into one notification each.
//
//  Two properties are load-bearing and unit-tested here, decoupled from the
//  database and the wire:
//    - Memory/bandwidth: each preview is a SHORT string built with
//      Content.snippetText(maxLength:), which renders attachments as byte-free
//      placeholders ("📄 name") and truncates the body. A 100 KB agent turn or a
//      multi-MB attachment never crosses the wire or enters the NSE.
//    - Visibility: hiddenFromClient messages (bookkeeping like .commit /
//      .remoteCommandResponse) are dropped in Swift, because hiddenFromClient is
//      a computed property over decoded content and cannot be filtered in SQL.
//    - Authorship: only AGENT messages are previewed. A push fires for an agent
//      turn, but messagesSince returns everything new since the watermark - which
//      includes the user's own message(s) that preceded the reply (and watcher
//      events, which are user-authored). Notifying the user about their own
//      messages is wrong, so they are dropped here.
//

import Foundation

enum MessagesSinceResponder {
    struct Result: Equatable {
        /// Newest first, at most `limit` entries. CompanionMessagePreview is the
        /// wire type, so summarize produces exactly what the reply ships.
        let previews: [CompanionMessagePreview]
        /// More visible messages existed than `limit` (so the NSE may add a
        /// "+N more" hint). A floor when the caller's fetch window was itself
        /// capped (the true surplus can be larger).
        let truncated: Bool
    }

    /// - Parameters:
    ///   - fetched: rows for the chat with seq greater than the phone's
    ///     watermark, ordered NEWEST FIRST (seq DESC).
    ///   - limit: maximum previews to return (one notification each).
    ///   - bodyMaxLength: per-message body cap passed to snippetText.
    static func summarize(fetched: [Message], limit: Int, bodyMaxLength: Int) -> Result {
        // Defensive: prefix(_:) traps on a negative count. Callers should clamp
        // untrusted limits, but the helper must not be a trap either.
        let cap = max(limit, 0)
        // Only agent messages: never notify the user about their own messages
        // (or user-authored watcher events) that messagesSince swept up along
        // with the agent reply that triggered the push.
        let visible = fetched.filter { !$0.hiddenFromClient && $0.author == .agent }
        let shown = visible.prefix(cap)
        let previews = shown.map { message in
            CompanionMessagePreview(uniqueID: message.uniqueID,
                                    author: message.author,
                                    body: message.content.snippetText(maxLength: bodyMaxLength) ?? "")
        }
        return Result(previews: Array(previews), truncated: visible.count > cap)
    }
}
