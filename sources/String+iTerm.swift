//
//  String+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/19/22.
//

import Foundation
import Security

extension String {
    func containsCaseInsensitive(_ substring: String) -> Bool {
        if substring.isEmpty {
            return true
        }
        return range(of: substring, options: .caseInsensitive, range: nil, locale:nil) != nil
    }

    func localizedCaseInsensitiveHasPrefix(_ prefix: String) -> Bool {
        if prefix.isEmpty {
            return true
        }
        return range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive, .anchored], range: nil, locale: nil) != nil
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
        // This used to use URL(fileURLWithPath:) to try to be nice and modern and Swifty but it
        // FREAKING CHECKS IF THE FILE EXISTS and is SO SLOW. I wonder if anyone at Apple has ever
        // used a computer before sometimes.
        return (self as NSString).appendingPathComponent(pathComponent)
    }

    var deletingLastPathComponent: String {
        return (self as NSString).deletingLastPathComponent
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
        return self[range.lowerBound...]
    }

    var deletingPathExtension: String {
        return (self as NSString).deletingPathExtension
    }

    var pathExtension: String {
        return (self as NSString).pathExtension
    }

    func substituting(_ substitutions: [String: String]) -> String {
        var temp = self
        for (key, value) in substitutions {
            temp = temp.replacingOccurrences(of: key, with: value)
        }
        return temp
    }

    var base64Decoded: String? {
        guard let data = Data(base64Encoded: self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    var base64Encoded: String {
        return Data(self.utf8).base64EncodedString()
    }

    var nonEmptyBase64Encoded: String {
        return Data(self.utf8).nonEmptyBase64EncodedString()
    }
}

@objc
extension NSString {
    @objc(stringWithHumanReadableSize:)
    static func stringWithHumanReadableSize(_ value: UInt64) -> String {
        if value < 1024 {
            return String(value) + " bytes"
        }
        var num = value
        var pow = 0
        var exact = true
        while num >= 1024 * 1024 {
            pow += 1
            if num % 1024 != 0 {
                exact = false
            }
            num /= 1024
        }
        // Show 2 fraction digits, always rounding downwards. Printf rounds floats to the nearest
        // representable value, so do the calculation with integers until we get 100-fold the desired
        // value, and then switch to float.
        if 100 * num % 1024 != 0 {
            exact = false
        }
        num = 100 * num / 1024
        let iecPrefixes = [ "Ki", "Mi", "Gi", "Ti", "Pi", "Ei" ]
        let formatted = String(format: "%.2f", Double(num) / 100.0)
        return "\(exact ? "" : "≈")\(formatted) \(iecPrefixes[pow])"
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

extension String {
    func keyValuePair(_ separator: Character) -> (Substring, Substring)? {
        guard let i = firstIndex(of: separator) else {
            return nil
        }
        return (self[..<i], self[index(after: i)...])
    }
}

extension String {
    // "foo|bar".split(separator: "|", escape: "_")   -> ["foo", "bar"]
    // "foo_|bar".split(separator: "|", escape: "_")  -> ["foo|bar"]
    // "foo__|bar".split(separator: "|", escape: "_") -> ["foo_", "bar"]
    // "foo_bar".split(separator: "|", escape: "_")   -> ["foobar"]
    func split(separator: Character, escape: Character) -> [String] {
        if isEmpty {
            return []
        }
        var result = [String]()
        var current = ""
        var isEscaped = false

        for char in self {
            if isEscaped {
                if char == separator || char == escape {
                    current.append(char)  // Treat escaped separator or escape as a literal
                } else {
                    // Drop the escape character before non-special characters
                    current.append(char)
                }
                isEscaped = false
                continue
            }

            // Not escaped.
            if char == escape {
                isEscaped = true  // Next character should be treated as escaped
                continue
            }

            if char == separator {
                // Split on unescaped separator
                result.append(current)
                current = ""
            } else {
                // Regular character
                current.append(char)
            }
        }

        // Append the last part
        result.append(current)

        return result
    }
}

extension String {
    var entireRange: Range<Index> {
        startIndex..<endIndex
    }

    public func nsrangeOfUTF16Character(from aSet: CharacterSet,
                                        options mask: String.CompareOptions = [],
                                        range aRange: Range<Self.Index>? = nil) -> NSRange? {
        guard let range = rangeOfCharacter(from: aSet, options: mask, range: aRange) else {
            return nil
        }
        let location = utf16.distance(from: utf16.startIndex, to: range.lowerBound.samePosition(in: utf16)!)
        let length = utf16.distance(from: range.lowerBound.samePosition(in: utf16)!,
                                    to: range.upperBound.samePosition(in: utf16)!)
        return NSRange(location: location, length: length)
    }

    // UTF-16 offsets to String.Index
    public func range(lowerBound: Int, upperBound: Int) -> Range<String.Index> {
        let lower = utf16.index(utf16.startIndex, offsetBy: lowerBound, limitedBy: utf16.endIndex)
        let upper = utf16.index(utf16.startIndex, offsetBy: upperBound, limitedBy: utf16.endIndex)

        guard let lowerIndex = lower?.samePosition(in: self),
              let upperIndex = upper?.samePosition(in: self) else {
            it_fatalError("Invalid UTF-16 offsets for range conversion")
        }

        return lowerIndex..<upperIndex
    }
}

extension String {
    func utf16OffsetOfLine(_ n: Int) -> Int? {
        guard n >= 0 else { return nil }

        var offset = 0
        var lineCount = 0
        let utf16View = self.utf16

        for (i, character) in utf16View.enumerated() {
            if lineCount == n {
                return offset
            }

            if character == 0x0A { // '\n' in UTF-16
                lineCount += 1
                offset = i + 1
            }
        }

        return lineCount == n ? offset : nil
    }
}

extension String {
    func ranges(of searchString: String) -> [Range<String.Index>] {
        guard !searchString.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStartIndex = self.startIndex

        while searchStartIndex < self.endIndex,
              let range = self.range(of: searchString, range: searchStartIndex..<self.endIndex) {
            ranges.append(range)
            searchStartIndex = range.upperBound
        }
        return ranges
    }
}

extension String {
    mutating func removePrefix(_ prefix: String) {
        guard self.hasPrefix(prefix) else { return }
        self.removeFirst(prefix.count)
    }

    mutating func removeSuffix(_ suffix: String) {
        guard self.hasSuffix(suffix) else { return }
        self.removeLast(suffix.count)
    }
}

extension String {
    var mayContainRTL: Bool {
        let rtlSmellingCodePoints = iTermPreferences.bool(forKey: kPreferenceKeyBidi) ? NSCharacterSet.rtlSmellingCodePoints()! : CharacterSet()
        let rtlFound = rangeOfCharacter(from: rtlSmellingCodePoints) != nil
        return rtlFound
    }
}

extension String {
    var trimmingTrailingNulls: Self {
        var result = self
        while !result.isEmpty && result.last == "\0" {
            result.removeLast()
        }
        return result
    }
}

extension NSString {
    var trimmingTrailingNulls: String {
        String(self).trimmingTrailingNulls
    }
}

extension String {
    var halved: (String, String) {
        let middleIndex = index(startIndex, offsetBy: count / 2)
        let head = String(prefix(upTo: middleIndex))
        let tail = String(suffix(from: middleIndex))
        return (head, tail)
    }
}

extension String {
    var lossyData: Data {
        return Data(utf8)
    }
}

extension Optional where Wrapped == String {
    static func concat(_ lhs: String?, _ rhs: String?) -> String? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case let (l?, r?):
            return l + r
        case let (l?, nil):
            return l
        case let (nil, r?):
            return r
        }
    }
}

extension String {
    var escapedForHTML: String {
        var result = self
        result = result.replacingOccurrences(of: "&",  with: "&amp;")
        result = result.replacingOccurrences(of: "<",  with: "&lt;")
        result = result.replacingOccurrences(of: ">",  with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'",  with: "&#39;")
        return result
    }
    
    static func makeSecureHexString(byteCount: Int = 16) -> String? {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault,
                               byteCount,
                               $0.baseAddress!)
        }
        guard status == errSecSuccess else {
            return nil
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

import Foundation

extension String {
    subscript(utf16 range: NSRange) -> String {
        let utf16View = utf16

        let fromUtf16Index = utf16View.index(
                utf16View.startIndex,
                offsetBy: range.location,
                limitedBy: utf16View.endIndex)!
        let toUtf16Index = utf16View.index(
                fromUtf16Index,
                offsetBy: range.length,
                limitedBy: utf16View.endIndex)!

        let startIndex = String.Index(fromUtf16Index, within: self)!
        let endIndex = String.Index(toUtf16Index, within: self)!

        return String(self[startIndex..<endIndex])
    }

    subscript(utf16: Range<Int>) -> String {
        return self[utf16: NSRange(utf16)]
    }

    subscript(utf16 range: PartialRangeFrom<Int>) -> String {
        let utf16View = utf16
        let startLocation = range.lowerBound
        let utf16Count = utf16View.count
        let length = utf16Count - startLocation
        let nsRange = NSRange(location: startLocation, length: length)
        return self[utf16: nsRange]
    }
}
extension String {
    func chunk(_ maxSize: Int, continuation: String = "") -> [String] {
        var parts = [String]()
        var index = self.startIndex
        while index < self.endIndex {
            let end = self.index(index,
                                 offsetBy: min(maxSize,
                                               self.distance(from: index,
                                                             to: self.endIndex)))
            let part = String(self[index..<end]) + (end < self.endIndex ? continuation : "")
            if !part.isEmpty {
                parts.append(part)
            }
            index = end
        }
        return parts
    }
}

extension String {
    func split(maxWidth: Int) -> [String] {
        guard maxWidth > 0 else {
            return [self]
        }
        var result: [String] = []
        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: maxWidth, limitedBy: endIndex) ?? endIndex
            result.append(String(self[start..<end]))
            start = end
        }
        return result
    }
}
