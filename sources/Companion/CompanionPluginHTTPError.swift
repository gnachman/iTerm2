//
//  CompanionPluginHTTPError.swift
//  iTerm2
//
//  The companion plugin's HTTP bridge returns errors as a single string, which
//  the (signed) JS forwards verbatim. Encoding URLSession's error code in that
//  string, alongside its message, lets callers rebuild a URLError and explain a
//  failure specifically (a DNS failure vs. a timeout) instead of quoting text.
//

import Foundation

enum CompanionPluginHTTPError {
    private static let prefix = "URLError "

    /// "URLError <code>: <message>" for a URLSession error, else the message.
    static func encode(_ error: Error) -> String {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else {
            return error.localizedDescription
        }
        return "\(prefix)\(ns.code): \(error.localizedDescription)"
    }

    /// The URLError an encoded string describes, if any, and the message to
    /// show. Any other string (an HTTP status, an older plain message) is
    /// returned as the message with no URLError.
    static func decode(_ string: String) -> (urlError: URLError?, message: String) {
        guard string.hasPrefix(prefix),
              let colon = string.firstIndex(of: ":"),
              let code = Int(string[string.index(string.startIndex, offsetBy: prefix.count)..<colon]) else {
            return (nil, string)
        }
        let message = string[string.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return (URLError(URLError.Code(rawValue: code), userInfo: [NSLocalizedDescriptionKey: message]), message)
    }
}
