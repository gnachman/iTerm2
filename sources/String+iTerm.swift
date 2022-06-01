//
//  String+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/19/22.
//

import Foundation

extension String {
    func containsCaseInsensitive(_ substring: String) -> Bool {
        if substring.isEmpty {
            return true
        }
        return range(of: substring, options: .caseInsensitive, range: nil, locale:nil) != nil
    }

    func substring(nsrange: NSRange) -> String {
        return (self as NSString).substring(with: nsrange)
    }

    var trimmingTrailingNewline: String {
        if hasSuffix("\n") {  // because of Swift's unicode juju this also drops \r\n
            return String(dropLast())
        }
        return self
    }

    func split(onFirst separator: String) -> (Substring, Substring)? {
        return Substring(self).split(onFirst: separator)
    }

    init(ascii: UInt8) {
        self.init(Character(UnicodeScalar(ascii)))
    }

    func substringAfterFirst(_ pattern: String) -> Substring {
        guard let i = range(of: pattern) else {
            return Substring()
        }
        return self[i.upperBound...]
    }
}

extension Substring {
    func split(onFirst separator: String) -> (Substring, Substring)? {
        guard let range = range(of: separator) else {
            return nil
        }
        return (self[..<range.lowerBound], self[range.upperBound...])
    }
}


