//
//  iTermQuickLookDomainAllowlist.swift
//  iTerm2SharedARC
//
//  Decides which web URLs may open a Quick Look popover on hover.
//

import Foundation

// Raw values are stored in user defaults (kPreferenceKeyQuickLookHoverMode); do not renumber.
@objc enum iTermQuickLookHoverMode: Int {
    case off = 0
    case hover = 1
    case commandHover = 2
}

struct iTermQuickLookDomainAllowlist {
    private let entries: [String]

    // Entries are separated by commas and/or whitespace. An empty list allows every web URL.
    init(string: String) {
        let separators = CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines)
        entries = string.components(separatedBy: separators).compactMap {
            Self.normalizedHost($0)
        }
    }

    var isEmpty: Bool {
        return entries.isEmpty
    }

    func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        if entries.isEmpty {
            return true
        }
        guard let host = url.host.flatMap({ Self.normalizedHost($0) }) else {
            return false
        }
        return entries.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // Lowercases, drops trailing dots and converts an internationalized name to its ASCII (punycode)
    // form so that "bücher.de" and "xn--bcher-kva.de" compare equal.
    private static func normalizedHost(_ string: String) -> String? {
        var host = string.lowercased()
        while host.hasSuffix(".") {
            host.removeLast()
        }
        if host.isEmpty {
            return nil
        }
        if host.unicodeScalars.contains(where: { !$0.isASCII }) {
            guard let ascii = NSURL(string: "https://" + host)?.host?.lowercased(),
                  ascii.unicodeScalars.allSatisfy({ $0.isASCII }) else {
                return nil
            }
            return ascii
        }
        return host
    }
}
