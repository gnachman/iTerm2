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

    // Why the model editor's header rows can't be used, or nil when they can.
    // Rows with a blank name are ignored (they are dropped on save). Save and
    // Test Connection both check this, so a test can't succeed while silently
    // leaving out a header that Save would then refuse.
    @objc(validationFailureForHeaders:)
    static func validationFailure(forHeaders headers: [[String: Any]]) -> String? {
        for entry in headers {
            let name = ((entry["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                continue
            }
            let value = (entry["value"] as? String) ?? ""
            if !isValidName(name) {
                return String(localized: "AIModelEditor.InvalidHeaderName",
                              defaultValue: "Custom header name “\(name)” is not valid. Use only RFC 7230 token characters (letters, digits, and any of !#$%&'*+-.^_`|~).",
                              comment: "Validation error for an invalid custom HTTP header name; %@ is the name")
            }
            if !isValidValue(value) {
                return String(localized: "AIModelEditor.InvalidHeaderValue",
                              defaultValue: "The value for custom header “\(name)” must not contain newline or null characters.",
                              comment: "Validation error for an invalid custom HTTP header value; %@ is the header name")
            }
        }
        return nil
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
