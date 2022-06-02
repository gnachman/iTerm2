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

    func takeFirst(_ n: Int) -> Substring {
        if n >= count {
            return Substring(self)
        }
        let i = index(startIndex, offsetBy: n)
        return self[..<i]
    }

    func takeLast(_ n: Int) -> Substring {
        if n >= count {
            return Substring(self)
        }
        let i = index(startIndex, offsetBy: count - n)
        return self[i...]
    }

    func truncatedWithTrailingEllipsis(to maxLength: Int) -> String {
        if count <= maxLength {
            return self
        }
        return takeFirst(maxLength - 1) + "…"
    }

    var semiVerboseDescription: String {
        let radius = 16
        let grace = 20
        if count < radius * 2 + grace {
            return self
        }
        return takeFirst(radius) + " …[\(count - 32) bytes elided]… " + takeLast(radius)
    }

    func appending(pathComponent: String) -> String {
        return URL(fileURLWithPath: self).appendingPathComponent(pathComponent).path
    }

    var expandingTildeInPath: String {
        return (self as NSString).expandingTildeInPath
    }

    func linesInFileContents() throws -> [String] {
        return try String(contentsOf: URL(fileURLWithPath: self)).components(separatedBy: .newlines)
    }

    func trimmingLeadingCharacters(in charset: CharacterSet) -> Substring {
        guard let range = self.rangeOfCharacter(from: charset.inverted) else {
            return Substring()
        }
        return self[range.upperBound...]
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


