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
        let rtlSmellingCodePoints = iTermAdvancedSettingsModel.bidi() ? NSCharacterSet.rtlSmellingCodePoints()! : CharacterSet()
        let rtlFound = rangeOfCharacter(from: rtlSmellingCodePoints) != nil
        return rtlFound
    }
}

