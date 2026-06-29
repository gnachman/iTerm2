//
//  MentionParser.swift
//  iTerm2
//
//  NOTE: This file is also compiled into the iTerm2 Companion iOS app. Keep it
//  platform-neutral (Foundation only); Mac-only code goes in sibling files.
//
//  Finds @-prefixed session/workgroup mentions in chat text. Both the user and
//  the AI write them: an at sign followed by a session_guid or workgroup_id.
//  The Mac's OrchestrationMentionRenderer and the phone's message bubbles use
//  this same parser so a mention means the same thing on both ends.
//

import Foundation

enum MentionParser {
    // Matches "@" followed by a session/workgroup identifier:
    //   @<uuid>           a session_guid
    //   @session:<uuid>   a synthetic single-session workgroup_id
    //   @wg-<uuid>        a real workgroup instance id
    // The trailing lookahead keeps us from matching only a prefix of a
    // longer hex/dash run that merely starts like a UUID.
    private static let uuidPattern =
        "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
    private static let regex = try! NSRegularExpression(
        pattern: "@(session:|wg-)?(\(uuidPattern))(?![0-9A-Fa-f-])")

    struct Mention {
        /// The whole match including the "@", in the searched string's UTF-16
        /// coordinates.
        var range: NSRange
        /// "session:" / "wg-" / nil (a bare session guid).
        var prefix: String?
        /// The captured UUID, without any prefix.
        var uuid: String
        /// The identifier as written, without the "@" (prefix plus uuid).
        var identifier: String { (prefix ?? "") + uuid }
    }

    static func mentions(in string: String) -> [Mention] {
        let ns = string as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        return regex.matches(in: string, range: fullRange).map { match in
            let prefixRange = match.range(at: 1)
            return Mention(range: match.range,
                           prefix: prefixRange.location == NSNotFound
                               ? nil
                               : ns.substring(with: prefixRange),
                           uuid: ns.substring(with: match.range(at: 2)))
        }
    }

    /// Splits a bare identifier (a mention without its "@") back into prefix
    /// and uuid, or nil when it is not a well-formed mention identifier.
    static func split(identifier: String) -> (prefix: String?, uuid: String)? {
        guard let mention = mentions(in: "@" + identifier).first,
              mention.identifier == identifier else {
            return nil
        }
        return (mention.prefix, mention.uuid)
    }
}
