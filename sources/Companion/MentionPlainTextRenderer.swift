//
//  MentionPlainTextRenderer.swift
//  iTerm2
//
//  Plain-text rendering of @-mentions for push notifications. The chat UI turns
//  a "@<session_guid>" into a clickable, terminal-glyph link via
//  OrchestrationMentionRenderer (attributed strings), but a notification body is
//  plain text - so a raw "@<uuid>" would otherwise show up verbatim on the lock
//  screen. This replaces each mention with "🖥 <session name>" (or
//  "[defunct session]" when it no longer resolves), reusing the shared
//  MentionParser so a mention means the same thing here as everywhere else.
//

import Foundation

enum MentionPlainTextRenderer {
    /// Glyph prefixed to a resolved mention so the reader can tell it points at
    /// an iTerm2 session. A thin space separates it from the name.
    static let sessionPrefix = "🖥\u{2009}"

    /// Replace every @-mention in `input` with its resolved display name (with a
    /// terminal glyph), or "[defunct session]" when `resolve` returns nil for it.
    /// `resolve` takes a mention identifier (the text after "@", e.g. a bare
    /// session guid or "wg-<uuid>") and returns the entity's current name.
    static func render(_ input: String, resolve: (_ identifier: String) -> String?) -> String {
        let mentions = MentionParser.mentions(in: input)
        guard !mentions.isEmpty else { return input }

        let ns = input as NSString
        let result = NSMutableString()
        var cursor = 0
        for mention in mentions {
            let whole = mention.range
            if whole.location > cursor {
                result.append(ns.substring(with: NSRange(location: cursor,
                                                         length: whole.location - cursor)))
            }
            if let name = resolve(mention.identifier) {
                result.append(sessionPrefix + name)
            } else {
                result.append("[defunct session]")
            }
            cursor = whole.location + whole.length
        }
        if cursor < ns.length {
            result.append(ns.substring(from: cursor))
        }
        return result as String
    }
}
