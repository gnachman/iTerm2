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

    static func merged(into base: [String: String]) -> [String: String] {
        guard iTermPreferences.bool(forKey: kPreferenceKeyAICustomHeadersEnabled),
              let raw = iTermPreferences.object(forKey: kPreferenceKeyAICustomHeaders) as? [[String: String]] else {
            return base
        }
        var result = base
        for entry in raw {
            guard let name = entry["name"], isValidName(name) else { continue }
            let value = entry["value"] ?? ""
            guard isValidValue(value) else {
                DLog("Skipping AI custom header \"\(name)\" because its value contains a control character")
                continue
            }
            if result[name] != nil {
                DLog("AI custom header overrides existing header field \"\(name)\"")
            }
            result[name] = value
        }
        return result
    }
}
