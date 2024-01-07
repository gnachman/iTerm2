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
