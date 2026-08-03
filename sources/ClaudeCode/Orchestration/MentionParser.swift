//
//  MentionParser.swift
//  iTerm2
//
//  NOTE: This file is also compiled into the iTerm2 Companion iOS app. Keep it
//  platform-neutral (Foundation only); Mac-only code goes in sibling files.
//
//  Finds @-prefixed session/workgroup mentions in chat text. Both the user and
//  the AI write them: an at sign followed by a session reference or workgroup_id.
//  The Mac's OrchestrationMentionRenderer and the phone's message bubbles use
//  this same parser so a mention means the same thing on both ends.
//

import Foundation

enum MentionParser {
    // Matches "@" followed by a session/workgroup identifier:
    //   @<uuid>                  a legacy session_guid
    //   @ptys_<...>              a session stableID (see iTermStableSessionID)
    //   @session:<uuid|ptys_...> a synthetic single-session workgroup_id
    //   @wg-<uuid>               a real workgroup instance id
    // Case-insensitive so a stableID the model lowercased still matches; the
    // captured prefix is lowercased and a stableID token is folded to canonical
    // form below so downstream comparisons (claim scopes) stay stable. The
    // trailing lookahead keeps us from matching only a prefix of a longer run.
    private static let uuidPattern =
        "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
    private static let idPattern = "\(uuidPattern)|\(StableSessionID.tokenPattern)"
    private static let regex = try! NSRegularExpression(
        pattern: "@(session:|wg-)?(\(idPattern))(?![0-9A-Za-z-])",
        options: [.caseInsensitive])

    struct Mention {
        /// The whole match including the "@", in the searched string's UTF-16
        /// coordinates.
        var range: NSRange
        /// "session:" / "wg-" / nil (a bare session reference), lowercased.
        var prefix: String?
        /// The captured id without any prefix: a UUID verbatim, or a stableID in
        /// canonical form.
        var token: String
        /// The identifier as written, without the "@" (prefix plus token).
        var identifier: String { (prefix ?? "") + token }
    }

    static func mentions(in string: String) -> [Mention] {
        let ns = string as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        return regex.matches(in: string, range: fullRange).map { match in
            let prefixRange = match.range(at: 1)
            let rawToken = ns.substring(with: match.range(at: 2))
            // A stableID matched case-insensitively (or with Crockford
            // confusables) is folded to canonical form so its identifier is
            // stable for claim-scope comparison; a UUID is left verbatim.
            let token = StableSessionID.canonical(rawToken) ?? rawToken
            return Mention(range: match.range,
                           prefix: prefixRange.location == NSNotFound
                               ? nil
                               : ns.substring(with: prefixRange).lowercased(),
                           token: token)
        }
    }

    /// Splits a bare identifier (a mention without its "@") into prefix and
    /// token, or nil when it is not a single well-formed mention identifier.
    /// The token comes back canonical, so the input need not be (e.g. a
    /// lowercased stableID splits and returns the uppercase canonical form).
    static func split(identifier: String) -> (prefix: String?, token: String)? {
        let full = "@" + identifier
        guard let mention = mentions(in: full).first,
              mention.range.location == 0,
              mention.range.length == (full as NSString).length else {
            return nil
        }
        return (mention.prefix, mention.token)
    }
}
