//
//  AICustomHeaders.swift
//  iTerm2
//

import Foundation

@objc class AICustomHeaders: NSObject {
    // RFC 7230 token chars allowed in HTTP field names.
    private static let tokenChars: Set<Character> = Set(
        "!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    )

    @objc static func isValidName(_ name: String) -> Bool {
        return !name.isEmpty && name.allSatisfy { tokenChars.contains($0) }
    }

    @objc static func isValidValue(_ value: String) -> Bool {
        // Check scalars rather than Characters: "\r\n" is a single
        // grapheme cluster, so iterating Characters would miss it.
        return !value.unicodeScalars.contains { $0 == "\r" || $0 == "\n" || $0 == "\0" }
    }

    // Merges a model's custom headers into `base`. Headers are per-model (each
    // manual model carries its own list, set in the editor) so an authenticated
    // self-hosted endpoint can send the auth header it requires without affecting
    // other models. Each entry is a {"name": ..., "value": ...} dictionary.
    static func merged(into base: [String: String],
                       customHeaders: [[String: String]]) -> [String: String] {
        guard !customHeaders.isEmpty else {
            return base
        }
        var result = base
        for entry in customHeaders {
            guard let name = entry["name"], isValidName(name) else { continue }
            let value = entry["value"] ?? ""
            guard isValidValue(value) else {
                RLog("Skipping AI custom header \"\(name)\" because its value contains a control character")
                continue
            }
            // HTTP field names are case-insensitive, so drop any existing field
            // that differs from this one only in case before inserting. Leaving
            // both in the dictionary would send one field whose value depends on
            // dictionary iteration order: a custom "authorization" would then
            // only sometimes beat the built-in "Authorization" (issue 13021).
            // The user's spelling replaces ours.
            let superseded = result.keys.filter {
                $0.caseInsensitiveCompare(name) == .orderedSame
            }
            for existing in superseded {
                RLog("AI custom header overrides existing header field \"\(existing)\"")
                result.removeValue(forKey: existing)
            }
            result[name] = value
        }
        return result
    }
}
