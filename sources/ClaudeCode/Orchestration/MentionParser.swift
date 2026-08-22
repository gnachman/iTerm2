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
    // Same shape but with an optional "@". Used only when the caller opts in
    // (a message authored by the AI, which sometimes drops the "@"). A bare
    // match this admits is further gated below to the self-validating stableID
    // form so a stray UUID in prose is never mistaken for a mention.
    private static let regexOptionalAt = try! NSRegularExpression(
        pattern: "@?(session:|wg-)?(\(idPattern))(?![0-9A-Za-z-])",
        options: [.caseInsensitive])

    private static let atSignChar = unichar(UInt8(ascii: "@"))

    // A bare mention must not be glued to the preceding character (so a stableID
    // embedded in a longer token isn't clipped out as a mention). "@"-signed
    // mentions rely on the "@" as their own left boundary and skip this.
    private static let boundaryExcluded: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "_-")
        return set
    }()

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

    /// Finds every mention in `string`.
    ///
    /// When `atSignOptional` is true (the message was authored by the AI, which
    /// sometimes forgets the "@"), a mention may also appear with no leading
    /// "@". To keep false positives out of ordinary prose, such a bare match is
    /// admitted only when it is a self-validating stableID (the checksummed
    /// `ptys_...` form) with no prefix and a clean left boundary; a bare UUID or
    /// a bare "session:"/"wg-" form still requires the "@". An "@"-signed
    /// mention behaves identically regardless of this flag.
    static func mentions(in string: String, atSignOptional: Bool = false) -> [Mention] {
        let ns = string as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let re = atSignOptional ? regexOptionalAt : regex
        return re.matches(in: string, range: fullRange).compactMap { match -> Mention? in
            let prefixRange = match.range(at: 1)
            let hasPrefix = prefixRange.location != NSNotFound
            let rawToken = ns.substring(with: match.range(at: 2))
            // A stableID matched case-insensitively (or with Crockford
            // confusables) is folded to canonical form so its identifier is
            // stable for claim-scope comparison; a UUID is left verbatim.
            let canonicalStableID = StableSessionID.canonical(rawToken)
            let atSigned = ns.character(at: match.range.location) == atSignChar
            if !atSigned {
                // Bare match (only the optional-@ regex produces these). Accept
                // only a prefix-less, checksum-valid stableID with a boundary
                // before it so a UUID or an embedded id isn't picked up.
                guard !hasPrefix,
                      canonicalStableID != nil,
                      hasLeftBoundary(before: match.range.location, in: ns) else {
                    return nil
                }
            }
            return Mention(range: match.range,
                           prefix: hasPrefix
                               ? ns.substring(with: prefixRange).lowercased()
                               : nil,
                           token: canonicalStableID ?? rawToken)
        }
    }

    private static func hasLeftBoundary(before location: Int, in ns: NSString) -> Bool {
        guard location > 0 else { return true }
        guard let scalar = Unicode.Scalar(ns.character(at: location - 1)) else {
            return true
        }
        return !boundaryExcluded.contains(scalar)
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
