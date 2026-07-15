//
//  StableSessionID.swift
//  iTerm2
//
//  NOTE: This file is also compiled into the iTerm2 Companion iOS app. Keep it
//  platform-neutral (Foundation only); Mac-only code goes in sibling files.
//
//  A stable per-session identifier. Unlike PTYSession.guid it survives a shell
//  reload: replaceTerminatedShellWithNewInstance rotates the guid but keeps the
//  same object, and this id with it. Format:
//
//      ptys_9QK3ZM7WX4VBT
//
//  "ptys_" + 12 Crockford base32 chars + 1 checksum char. The canonical form is
//  the lowercase prefix followed by an uppercase body; validation accepts any
//  case (prefix and body) and normalizes back to canonical.
//  The prefix makes it greppable and unmistakable for a UUID, a hex hash, or a
//  base64 blob. The checksum lets us reject a truncated or mangled id (which an
//  AI agent is prone to produce) instead of resolving it to the wrong session.
//

import Foundation

@objc(iTermStableSessionID)
class StableSessionID: NSObject {
    /// Leading tag. Kept in one constant so the whole scheme is a one-line rename.
    static let prefix = "ptys_"

    /// Crockford base32: digits plus A-Z minus I, L, O, U. Canonical uppercase.
    private static let alphabetString = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    private static let alphabet = Array(alphabetString)
    private static let alphabetIndex: [Character: Int] = {
        var m = [Character: Int]()
        for (i, c) in alphabet.enumerated() {
            m[c] = i
        }
        return m
    }()

    private static let bodyLength = 12

    /// Regex character class matching one canonical body/check char. Derived from
    /// `alphabet` so it can never drift from what `generate()` mints.
    static let charClass = "[\(alphabetString)]"

    /// Full token pattern (prefix + 13 canonical chars, no anchors) for embedding
    /// in a larger regex. Built from `prefix`/`charClass`/`bodyLength` so a rename
    /// of `prefix` or a change to `alphabet` flows through automatically.
    ///
    /// This matches the STRICT canonical shape only (uppercase, tight alphabet).
    /// Free-text detection is deliberately strict to keep false positives low, so
    /// the pattern by itself does NOT match a case- or confusable-mangled id.
    /// Leniency lives in `canonical(_:)`, which folds case and Crockford
    /// confusables for a candidate you already hold (a stored reference, an
    /// API/mention parameter, or a substring a scanner extracted). Since the agent
    /// is always shown canonical ids, its emitted mentions are canonical and match
    /// this pattern; the fold is a safety net, not a detection widener. A scanner
    /// that also wants to catch a case-mangled id should match this pattern
    /// case-insensitively and then confirm with `canonical(_:)`, whose checksum is
    /// the authoritative gate.
    static let tokenPattern = prefix + charClass + "{\(bodyLength + 1)}"

    /// Mints a fresh id. Canonical (uppercase, strict alphabet) by construction.
    @objc static func generate() -> String {
        var indices = [Int]()
        indices.reserveCapacity(bodyLength)
        for _ in 0..<bodyLength {
            indices.append(Int(arc4random_uniform(UInt32(alphabet.count))))
        }
        let body = String(indices.map { alphabet[$0] })
        let check = alphabet[checksum(of: indices)]
        return prefix + body + String(check)
    }

    /// True if `candidate` is a well-formed stable id (prefix, length, alphabet,
    /// checksum). Accepts any case and Crockford-confusable input.
    @objc static func isValid(_ candidate: String) -> Bool {
        return canonical(candidate) != nil
    }

    /// Returns the canonical (uppercase, strict-alphabet) form of `candidate` if
    /// it is a valid stable id, else nil. Normalize an id through this before
    /// using it as a lookup key so that case and Crockford confusables (I/L->1,
    /// O->0) do not cause a miss.
    @objc static func canonical(_ candidate: String) -> String? {
        // Case-insensitive prefix so the recommended case-insensitive scan (which
        // may capture an uppercased "PTYS_") round-trips through here. The
        // canonical output always uses the lowercase prefix constant.
        guard candidate.prefix(prefix.count).lowercased() == prefix else {
            return nil
        }
        let rest = candidate.dropFirst(prefix.count)
        guard rest.count == bodyLength + 1 else {
            return nil
        }
        var indices = [Int]()
        indices.reserveCapacity(bodyLength + 1)
        for ch in rest {
            guard let idx = alphabetIndex[normalize(ch)] else {
                return nil
            }
            indices.append(idx)
        }
        let bodyIndices = Array(indices.prefix(bodyLength))
        guard indices[bodyLength] == checksum(of: bodyIndices) else {
            return nil
        }
        return prefix + String(indices.map { alphabet[$0] })
    }

    // MARK: - Private

    /// Position-weighted checksum mod 32. Catches every single-character error in
    /// the first body position and adjacent transpositions of unequal chars.
    private static func checksum(of body: [Int]) -> Int {
        var sum = 0
        for (i, v) in body.enumerated() {
            sum += (i + 1) * v
        }
        return sum % alphabet.count
    }

    /// Uppercases and folds Crockford confusables so a mistyped id still resolves.
    private static func normalize(_ ch: Character) -> Character {
        switch ch {
        case "i", "I", "l", "L":
            return "1"
        case "o", "O":
            return "0"
        default:
            let up = ch.uppercased()
            return up.count == 1 ? Character(up) : ch
        }
    }
}
