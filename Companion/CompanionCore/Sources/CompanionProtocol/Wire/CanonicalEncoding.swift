//
//  CanonicalEncoding.swift
//  CompanionCore
//
//  Unambiguous, domain-separated encoding for values that are hashed or signed.
//  Plain concatenation, SHA(a || b) or sign(a || b), is ambiguous: distinct
//  field tuples can produce the same bytes (H("AB"||"C") == H("A"||"BC")), so a
//  boundary an attacker controls could be shifted to forge a colliding input.
//  This encodes a tuple as a leading domain string followed by each field, each
//  element prefixed with its 4-byte big-endian length. That is unambiguous for
//  any field contents, lengths, or count, and the domain string keeps different
//  uses from ever colliding. The matching encoder in the JS relay
//  (canonicalEncode in room.js) MUST stay byte-identical; a shared test vector
//  pins it on both sides.
//

import Foundation

public enum CanonicalEncoding {
    /// `len32(domain) || domain || len32(f0) || f0 || len32(f1) || f1 || ...`
    /// where len32 is a 4-byte big-endian length. The result is fed to SHA256
    /// or an Ed25519 signature.
    public static func encode(domain: String, _ fields: [Data]) -> Data {
        var out = Data()
        appendLengthPrefixed(&out, Data(domain.utf8))
        for field in fields {
            appendLengthPrefixed(&out, field)
        }
        return out
    }

    private static func appendLengthPrefixed(_ out: inout Data, _ field: Data) {
        var length = UInt32(field.count).bigEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(field)
    }
}
