//
//  URL+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/13/22.
//

import Foundation


extension URL {
    enum PathArithmeticException: Error {
        case invalidPrefix
    }

    // A description safe for the always-on retrospective ring (RLog): scheme, host,
    // and path only. Drops the three places a secret hides in a URL: userinfo
    // (user:password@), the query string (?token=…), and the fragment
    // (#access_token=…). See DebugLogging.h.
    var it_redactedDescription: String {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return "<url scheme=\(scheme ?? "?") (redacted)>"
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return "\(components.scheme ?? "?")://\(components.host ?? "")\(components.path)"
    }

    // The host in the form every comparison should be made against: lowercased,
    // with any DNS root dot removed. Anything that decides something from the
    // host must use this rather than `host`, which keeps whatever the user
    // typed. Matching verbatim let “https://API.DEEPSEEK.COM/…” and
    // “https://api.deepseek.com./…” both classify as OpenAI and carry the
    // user's OpenAI key to another vendor, and let “http://LOCALHOST:1337” look
    // like a public host (issue 13021). Empty when there is no host, so a
    // suffix test can never match by accident.
    //
    // Deliberately the same two normalizations PrivateIPChecker.normalized
    // applies: the two are consulted about the same URL and must agree on what
    // its host is called.
    var it_normalizedHost: String {
        guard var host = host?.lowercased() else {
            return ""
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }
        return host
    }

    func pathByRemovingPrefix(_ prefix: String) throws -> String {
        if !path.hasPrefix(prefix) {
            throw PathArithmeticException.invalidPrefix
        }
        return String(path.dropFirst(prefix.count))
    }

    var sanitizedForPrinting: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }

        // Convert hostname to punycode
        components.host = NSURL.idnEncodedHostname(components.host ?? "")

        // Percent-escape path, query, and fragment
        let verySafeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789./-=&")
        components.percentEncodedPath = components.path.addingPercentEncoding(withAllowedCharacters: verySafeCharacters) ?? ""
        components.percentEncodedQuery = components.query?.addingPercentEncoding(withAllowedCharacters: verySafeCharacters)
        components.percentEncodedFragment = components.fragment?.addingPercentEncoding(withAllowedCharacters: verySafeCharacters)

        return components.url
    }
}

extension NSURL {
    @objc var sanitizedForPrinting: NSURL? {
        return (self as URL).sanitizedForPrinting as NSURL?
    }
}
