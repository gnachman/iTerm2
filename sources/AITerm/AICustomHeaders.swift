//
//  AICustomHeaders.swift
//  iTerm2
//

struct AICustomHeaders {
    static func merged(into base: [String: String]) -> [String: String] {
        guard iTermPreferences.bool(forKey: kPreferenceKeyAICustomHeadersEnabled),
              let raw = iTermPreferences.object(forKey: kPreferenceKeyAICustomHeaders) as? [[String: String]] else {
            return base
        }
        var result = base
        for entry in raw {
            guard let name = entry["name"], !name.isEmpty else { continue }
            let value = entry["value"] ?? ""
            if result[name] != nil {
                DLog("AI custom header overrides built-in header field \"\(name)\"")
            }
            result[name] = value
        }
        return result
    }
}
