//
//  iTermURLHelpers.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

func normalizeURL(_ urlString: String) -> URL? {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

    // If it already has a scheme, use as-is
    if stringHasValidScheme(trimmed) {
        return URL(string: trimmed)
    }

    // If it looks like a domain/IP, add https://
    if isValidDomainOrIP(trimmed) {
        return URL(string: "https://\(trimmed)")
    }
    return nil
}

private func stringHasValidScheme(_ urlString: String) -> Bool {
    return urlString.hasPrefix("http://") ||
    urlString.hasPrefix("https://") ||
    urlString.hasPrefix(iTermBrowserSchemes.about + ":") ||
    urlString.hasPrefix("about:") ||
    urlString.hasPrefix("file://")
}

func stringIsStronglyURLLike(_ urlString: String) -> Bool {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    if stringHasValidScheme(trimmed) {
        return true
    }
    if isValidDomainOrIP(trimmed) && trimmed.contains(".") {
        return true
    }
    return false
}

private func isValidDomainOrIP(_ input: String) -> Bool {
    // Check if it contains spaces (definitely not a URL)
    if input.contains(" ") {
        return false
    }

    // Check for IPv4 address pattern
    let ipv4Pattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?$"#
    if input.range(of: ipv4Pattern, options: .regularExpression) != nil {
        return true
    }

    // Check for IPv6 address pattern (basic check)
    if input.hasPrefix("[") && input.hasSuffix("]") {
        return true
    }

    // Check for localhost or local addresses
    if input.hasPrefix("localhost") || input.hasPrefix("127.0.0.1") {
        return true
    }

    // Check if it looks like a domain (contains a dot and no spaces)
    if input.contains(".") && !input.contains(" ") {
        // Additional validation: must have at least one character before and after the dot
        let components = input.split(separator: ".")
        return components.count >= 2 && components.allSatisfy { !$0.isEmpty }
    }

    // Check for intranet-style hostnames (single word, possibly with port)
    let hostPattern = #"^[a-zA-Z0-9-]+(:\d+)?$"#
    if input.range(of: hostPattern, options: .regularExpression) != nil {
        return true
    }

    return false
}

