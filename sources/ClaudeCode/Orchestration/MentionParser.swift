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

    /// Text with its mentions swapped for opaque placeholders, so a markdown
    /// pass can't mangle them. A stableID contains "_", so two of them in one
    /// paragraph ("@ptys_A... and @ptys_B...") otherwise pair up as emphasis
    /// delimiters and the underscores are consumed, leaving unlinkable text.
    struct Protected {
        /// The text to hand to the markdown renderer.
        var text: String
        /// (placeholder, original mention text) pairs. Each placeholder occurs
        /// once in `text`; put the original back after rendering.
        var substitutions: [(placeholder: String, original: String)]
    }

    /// Spans of raw markdown whose text is not subject to emphasis parsing, or
    /// which don't end up in the visible string: fenced code blocks, inline
    /// code spans, link destinations, autolinks, and bare URLs. Mentions there
    /// are left alone by `protect` because markdown can't eat their
    /// underscores, and a placeholder there would leak into a code block's
    /// copy-button text or a link's target, where nothing restores it. This is
    /// a deliberately loose approximation of CommonMark; erring toward
    /// excluding a span only means a mention in it is no worse off than
    /// before protection existed.
    private static func spanRegex(includingFences: Bool) -> NSRegularExpression {
        // The fence pattern's group comes first, so the inline code pattern's
        // backreference depends on whether it's there.
        let codeGroup = includingFences ? 2 : 1
        let fence = [
            // Fenced block: through the matching closing fence, or to the end.
            "^[ \\t]{0,3}(`{3,}|~{3,}).*?(?:^[ \\t]{0,3}\\1|\\z)",
        ]
        let others = [
            // Inline code: a backtick run through the next run of equal length,
            // not crossing a blank line.
            "(`+)(?:(?!\\n[ \\t]*\\n).)+?(?<!`)\\\(codeGroup)(?!`)",
            // Link destination: "](...)".
            "\\]\\([^)\\n]*\\)",
            // Autolink: "<scheme:...>".
            "<[A-Za-z][A-Za-z0-9+.-]*:[^<>\\s]*>",
            // Bare URL.
            "https?://[^\\s<>()]+",
        ]
        return try! NSRegularExpression(pattern: ((includingFences ? fence : []) + others).joined(separator: "|"),
                                        options: [.anchorsMatchLines, .dotMatchesLineSeparators])
    }

    private static let unprotectedSpanRegex = spanRegex(includingFences: true)
    /// For a caller that knows the code lines exactly, which the loose fence
    /// pattern can contradict (a fence in a list item ends with the item).
    private static let unprotectedInlineSpanRegex = spanRegex(includingFences: false)

    /// Replaces every mention (including bare stableIDs) outside the spans
    /// described at `unprotectedSpanRegex` with a purely alphanumeric
    /// placeholder that has no markdown meaning. A random nonce keeps
    /// placeholders from colliding with anything already in the text, and the
    /// trailing "Z" keeps one index from being a prefix of another.
    /// `codeLines` returns the zero-based numbers of lines the renderer shows as
    /// code blocks (lines are separated by "\n", "\r\n", or "\r"), which are
    /// left alone too, in place of the loose fence pattern. It's called only if
    /// there are mentions, since finding code can mean parsing the whole message.
    /// The Mac gets them from SwiftyMarkdown, which matches its rendering exactly;
    /// the phone passes nil and relies on unprotectedSpanRegex.
    static func protect(_ string: String, codeLines: (() -> IndexSet)? = nil) -> Protected {
        var found = mentions(in: string, atSignOptional: true)
        guard !found.isEmpty else {
            return Protected(text: string, substitutions: [])
        }
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        let code = codeLines?() ?? IndexSet()
        let codeLineRanges = code.isEmpty ? [] : lineRanges(of: string).enumerated().compactMap { i, range in
            code.contains(i) ? range : nil
        }
        let spanMatches: [NSRange]
        if codeLines == nil {
            spanMatches = unprotectedSpanRegex.matches(in: string, range: fullRange).map(\.range)
        } else {
            // Blank out the code lines so the inline code pattern can't pair a fence
            // line with another block's. Same-length spaces keep the offsets valid.
            let masked = NSMutableString(string: string)
            for range in codeLineRanges {
                masked.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
            }
            spanMatches = unprotectedInlineSpanRegex.matches(in: masked as String, range: fullRange).map(\.range)
        }
        let unprotected = spanMatches + codeLineRanges
        found.removeAll { mention in
            unprotected.contains { NSIntersectionRange($0, mention.range).length > 0 }
        }
        guard !found.isEmpty else {
            return Protected(text: string, substitutions: [])
        }
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let result = NSMutableString(string: string)
        var substitutions = [(placeholder: String, original: String)]()
        for (i, mention) in found.enumerated().reversed() {
            let placeholder = "iTermMention\(nonce)X\(i)Z"
            substitutions.append((placeholder, result.substring(with: mention.range)))
            result.replaceCharacters(in: mention.range, with: placeholder)
        }
        return Protected(text: result as String, substitutions: substitutions)
    }

    /// The range of each line, without its terminator, splitting at "\n",
    /// "\r\n", and "\r".
    private static func lineRanges(of string: String) -> [NSRange] {
        let ns = string as NSString
        var result = [NSRange]()
        var start = 0
        var i = 0
        while i < ns.length {
            let c = ns.character(at: i)
            if c == 0x0A || c == 0x0D {
                result.append(NSRange(location: start, length: i - start))
                if c == 0x0D && i + 1 < ns.length && ns.character(at: i + 1) == 0x0A {
                    i += 1
                }
                start = i + 1
            }
            i += 1
        }
        result.append(NSRange(location: start, length: ns.length - start))
        return result
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
