//
//  MarkdownPreprocessor.swift
//  iTerm2SharedARC
//
//  Inline rewrites for the imgcat Markdown porthole. SwiftyMarkdown parses the
//  block structure and passes each paragraph's source through transformInline
//  before parsing its inline content. That turns HTML, entities, autolinks, and
//  footnotes into what SwiftyMarkdown's tokenizer understands, swaps characters
//  it would misread for placeholders, and replaces images with placeholders so
//  that nothing is loaded until the user asks.
//

import Foundation
import SwiftyMarkdown

final class MarkdownPreprocessor {
    // Placeholders use Unicode noncharacters (U+FDD0 to U+FDEF), which real text
    // shouldn't contain. Any that do appear in the input are removed so they can't
    // be mistaken for placeholders. (Private-use characters were not safe: Nerd
    // Fonts puts glyphs there.)
    private static let noncharacters: ClosedRange<UInt32> = 0xFDD0...0xFDEF

    // Characters SwiftyMarkdown would misread: those whose backslash escape it doesn't
    // understand, and backticks inside a code span. They are swapped for placeholders
    // before rendering and restored afterwards.
    private static let placeholderCharacters: [Character] = ["#", ">", "+", "-", "|", "!", "<", "~", ".", "`"]
    private static let placeholderBase: UInt32 = 0xFDD0

    // Swift doesn't allow noncharacters in string literals.
    private static func noncharacter(_ value: UInt32) -> String {
        it_assert(noncharacters.contains(value))
        return String(UnicodeScalar(value)!)
    }

    private static func placeholder(for character: Character) -> String {
        let index = placeholderCharacters.firstIndex(of: character)!
        return noncharacter(placeholderBase + UInt32(index))
    }

    // An image that may be shown inline is replaced by its index in `images`
    // between these markers. Remote images are never fetched; they become links.
    static let imageStart = noncharacter(0xFDE2)
    static let imageEnd = noncharacter(0xFDE3)

    static func encodedImage(_ index: Int) -> String {
        return imageStart + String(index) + imageEnd
    }

    // A line break from <br>, which restorePlaceholders turns into U+2028.
    static let lineBreak = noncharacter(0xFDE4)

    struct Image: Equatable {
        let alt: String
        let source: String
    }

    /// The Markdown to render, without noncharacters.
    let text: String
    /// The images transformInline has replaced with placeholders, by index.
    private(set) var images = [Image]()
    // Link reference definitions by normalized label, for the paragraph being rewritten.
    private var references = [String: String]()

    init(_ markdown: String) {
        text = String(String.UnicodeScalarView(markdown.unicodeScalars.filter { !Self.noncharacters.contains($0.value) }))
    }

    /// Replaces the placeholders inserted for escaped characters with the originals.
    static func restorePlaceholders(in attributedString: NSMutableAttributedString) {
        let string = attributedString.string as NSString
        let lineBreakCharacter = (lineBreak as NSString).character(at: 0)
        var i = string.length - 1
        while i >= 0 {
            let c = string.character(at: i)
            let scalar = UInt32(c)
            if c == lineBreakCharacter {
                attributedString.replaceCharacters(in: NSRange(location: i, length: 1), with: "\u{2028}")
            } else if scalar >= placeholderBase && scalar < placeholderBase + UInt32(placeholderCharacters.count) {
                let original = placeholderCharacters[Int(scalar - placeholderBase)]
                attributedString.replaceCharacters(in: NSRange(location: i, length: 1), with: String(original))
            }
            i -= 1
        }
    }

    private func addImage(alt: String, source: String) -> String {
        images.append(Image(alt: alt, source: source))
        return Self.encodedImage(images.count - 1)
    }

    private static let footnoteDefinitionRegex = try! NSRegularExpression(pattern: "^\\[\\^([^\\]]+)\\]:[ \\t]*")

    // MARK: - Inline transforms

    // Opening and closing backtick runs must be whole runs of the same length.
    private static let codeSpanRegex = try! NSRegularExpression(pattern: "(?<!`)(`+)(?!`)(.+?)(?<!`)\\1(?!`)")

    /// Rewrites one paragraph's Markdown source (or a heading's, list item's, or
    /// table cell's) outside its code spans. `references` are the document's link
    /// reference definitions as SwiftyMarkdown found them, keyed by
    /// SwiftyMarkdown.normalizedLinkLabel(_:).
    func transformInline(_ source: String, references: [String: String] = [:]) -> String {
        self.references = references
        var text = source
        var prefix = ""
        let range = NSRange(location: 0, length: (text as NSString).length)
        if let match = Self.footnoteDefinitionRegex.firstMatch(in: text, range: range) {
            // “[^1]: A note.” becomes “¹ A note.”
            let ns = text as NSString
            prefix = Self.superscript(ns.substring(with: match.range(at: 1))) + " "
            text = ns.substring(from: match.range.location + match.range.length)
        }
        text = Self.convertingHTMLCode(text)

        var result = prefix
        let ns = text as NSString
        var cursor = 0
        for match in Self.codeSpanRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += transformTextSegment(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            if match.range(at: 1).length == 1 {
                result += ns.substring(with: match.range)
            } else {
                // ``code with a ` in it``. As in CommonMark, one space of padding on
                // each side is dropped.
                var code = ns.substring(with: match.range(at: 2))
                if code.count >= 2, code.hasPrefix(" "), code.hasSuffix(" "), code.contains(where: { $0 != " " }) {
                    code = String(code.dropFirst().dropLast())
                }
                result += Self.codeSpan(code)
            }
            cursor = match.range.location + match.range.length
        }
        result += transformTextSegment(ns.substring(from: cursor))
        // A <br> at the end would leave an empty line under the paragraph, and HTML
        // stripped from either end would leave a space.
        while let last = result.last, String(last) == Self.lineBreak || last == " " || last == "\t" {
            result.removeLast()
        }
        while let first = result.first, first == " " || first == "\t" {
            result.removeFirst()
        }
        return result
    }

    /// Turns <code>…</code> outside existing code spans into a code span, so that
    /// the code-span protection in inlineTransform keeps other rewrites out of it.
    /// Whichever starts first, a code span or a <code> element, claims its text, so a
    /// backtick inside <code> can't pair with one outside it.
    private static func convertingHTMLCode(_ text: String) -> String {
        let ns = text as NSString
        var result = ""
        var cursor = 0
        while cursor < ns.length {
            let rest = NSRange(location: cursor, length: ns.length - cursor)
            let span = codeSpanRegex.firstMatch(in: text, range: rest)
            let element = htmlCodeRegex.firstMatch(in: text, range: rest)
            guard let next = [span, element].compactMap({ $0 }).min(by: { $0.range.location < $1.range.location }) else {
                break
            }
            result += ns.substring(with: NSRange(location: cursor, length: next.range.location - cursor))
            if next === element {
                result += codeSpan(decodeEntities(ns.substring(with: next.range(at: 1))))
            } else {
                result += ns.substring(with: next.range)
            }
            cursor = next.range.location + next.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    // SwiftyMarkdown only understands single-backtick code spans, so backticks in
    // the code become placeholders instead of lengthening the delimiter.
    private static func codeSpan(_ code: String) -> String {
        return "`" + code.replacingOccurrences(of: "`", with: placeholder(for: "`")) + "`"
    }

    private static let htmlCommentRegex = try! NSRegularExpression(pattern: "[ \\t]*<!--.*?-->(?=[ \\t])|<!--.*?-->", options: [.dotMatchesLineSeparators])
    private static let htmlBreakRegex = try! NSRegularExpression(pattern: "[ \\t]*<br[ \\t]*/?>[ \\t]*", options: [.caseInsensitive])
    private static let htmlBoldRegex = try! NSRegularExpression(pattern: "<(b|strong)>(.*?)</\\1>", options: [.caseInsensitive])
    private static let htmlItalicRegex = try! NSRegularExpression(pattern: "<(i|em)>(.*?)</\\1>", options: [.caseInsensitive])
    private static let htmlCodeRegex = try! NSRegularExpression(pattern: "<code>(.*?)</code>", options: [.caseInsensitive])
    private static let htmlStrikeRegex = try! NSRegularExpression(pattern: "<(s|del|strike)>(.*?)</\\1>", options: [.caseInsensitive])
    private static let htmlAnchorRegex = try! NSRegularExpression(pattern: "<a\\s[^>]*?href=\"([^\"]*)\"[^>]*>(.*?)</a>", options: [.caseInsensitive])
    private static let htmlStripRegex = try! NSRegularExpression(pattern: "</?(?:div|p|span|center|sup|sub|u|details|summary|kbd|small|font|table|thead|tbody|tr|td|th|ul|ol|li|h[1-6]|pre|hr|blockquote|img)\\b[^>]*>", options: [.caseInsensitive])
    private static let autolinkRegex = try! NSRegularExpression(pattern: "<(https?://[^\\s>]+)>")
    private static let mailAutolinkRegex = try! NSRegularExpression(pattern: "<([^\\s@<>]+@[^\\s@<>]+)>")
    private static let numericEntityRegex = try! NSRegularExpression(pattern: "&#(?:x([0-9a-fA-F]{1,6})|(\\d{1,7}));")
    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "copy": "©", "reg": "®", "trade": "™", "mdash": "—", "ndash": "–", "hellip": "…",
        "laquo": "«", "raquo": "»", "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’",
        "bull": "•", "middot": "·", "times": "×", "deg": "°", "euro": "€", "pound": "£", "yen": "¥",
    ]
    private static let namedEntityRegex = try! NSRegularExpression(pattern: "&([a-zA-Z]+);")
    private static let escapeRegex = try! NSRegularExpression(pattern: "\\\\([#>+\\-|!<~.])")
    // ![alt](dest "title") where dest may be wrapped in angle brackets to allow spaces.
    private static let imageRegex = try! NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\((?:<([^>]+)>|([^)\\s]+))(?:\\s+[^)]*)?\\)")
    // ![alt][ref] and ![alt][]
    private static let referenceImageRegex = try! NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\[([^\\]]*)\\]")
    private static let footnoteReferenceRegex = try! NSRegularExpression(pattern: "\\[\\^([^\\]]+)\\](?!:)")
    // Not after “](”, which is already a link's destination. Bare URLs in parentheses
    // are linked; the trailing “)” is moved out by fixTrailingPunctuationInBareLinks.
    private static let bareURLRegex = try! NSRegularExpression(pattern: "(?<![\\[<\\w\"'=/])(?<!\\]\\()(https?://[^\\s<>]+)")
    // A whole inline link. A URL in its text must not be linked again.
    private static let inlineLinkRegex = try! NSRegularExpression(pattern: "\\[[^\\]]*\\]\\([^)]*\\)")
    // Link destinations, reference labels (which must match their definitions), and URLs.
    private static let protectedRunRegex = try! NSRegularExpression(pattern: "\\]\\([^)]*\\)|\\]\\[[^\\]]*\\]|https?://[^\\s<>]+|www\\.[^\\s<>]+")
    private static let intrawordUnderscoreRegex = try! NSRegularExpression(pattern: "(?<=[\\p{L}\\p{N}])_(?=[\\p{L}\\p{N}])")

    private func transformTextSegment(_ segment: String) -> String {
        var s = segment
        s = Self.htmlCommentRegex.stringByReplacingMatches(in: s, range: Self.fullRange(s), withTemplate: "")
        s = Self.htmlBreakRegex.stringByReplacingMatches(in: s, range: Self.fullRange(s), withTemplate: Self.lineBreak)
        s = Self.htmlBoldRegex.stringByReplacingMatches(in: s, range: Self.fullRange(s), withTemplate: "**$2**")
        s = Self.htmlItalicRegex.stringByReplacingMatches(in: s, range: Self.fullRange(s), withTemplate: "*$2*")
        s = Self.htmlStrikeRegex.stringByReplacingMatches(in: s, range: Self.fullRange(s), withTemplate: "~~$2~~")
        s = Self.htmlAnchorRegex.stringByReplacingMatches(in: s, range: Self.fullRange(s), withTemplate: "[$2]($1)")
        s = Self.htmlStripRegex.stringByReplacingMatches(in: s, range: Self.fullRange(s), withTemplate: "")
        s = Self.autolinkRegex.stringByReplacingMatches(in: s, range: Self.fullRange(s), withTemplate: "[$1]($1)")
        s = Self.mailAutolinkRegex.stringByReplacingMatches(in: s, range: Self.fullRange(s), withTemplate: "[$1](mailto:$1)")
        s = Self.decodeEntities(s)
        s = Self.replacingMatches(Self.escapeRegex, in: s) { match, ns in
            let c = ns.substring(with: match.range(at: 1)).first!
            return Self.placeholder(for: c)
        }
        s = Self.replacingMatches(Self.imageRegex, in: s) { match, ns in
            let alt = ns.substring(with: match.range(at: 1))
            let bracketed = match.range(at: 2).location != NSNotFound
            let source = ns.substring(with: match.range(at: bracketed ? 2 : 3))
            return image(alt: alt, source: source)
        }
        s = Self.replacingMatches(Self.referenceImageRegex, in: s) { match, ns in
            let alt = ns.substring(with: match.range(at: 1))
            var label = ns.substring(with: match.range(at: 2))
            if label.isEmpty {
                label = alt
            }
            guard let source = references[SwiftyMarkdown.normalizedLinkLabel(label)] else {
                return "[\(alt)][\(label)]"
            }
            return image(alt: alt, source: source)
        }
        s = Self.replacingMatches(Self.footnoteReferenceRegex, in: s) { match, ns in
            Self.superscript(ns.substring(with: match.range(at: 1)))
        }
        s = Self.linkingBareURLs(s)
        s = Self.escapingIntrawordUnderscores(s)
        return s
    }

    /// Remote images become links so that nothing is fetched over the network. Anything
    /// else (a path, a file: URL, or a data: URL) may be shown inline.
    private func image(alt: String, source: String) -> String {
        if Self.isRemote(source) {
            let text = alt.isEmpty ? (source as NSString).lastPathComponent : alt
            return "[\(text)](\(source))"
        }
        return addImage(alt: alt, source: source)
    }

    private static func isRemote(_ source: String) -> Bool {
        guard let colon = source.firstIndex(of: ":") else {
            return false
        }
        let scheme = source[..<colon].lowercased()
        guard !scheme.isEmpty, scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }) else {
            return false
        }
        return scheme != "file" && scheme != "data"
    }

    private static func decodeEntities(_ s: String) -> String {
        var result = replacingMatches(numericEntityRegex, in: s) { match, ns in
            let value: UInt32?
            if match.range(at: 1).location != NSNotFound {
                value = UInt32(ns.substring(with: match.range(at: 1)), radix: 16)
            } else {
                value = UInt32(ns.substring(with: match.range(at: 2)))
            }
            if let value = value, let scalar = UnicodeScalar(value) {
                return String(scalar)
            }
            return ns.substring(with: match.range)
        }
        result = replacingMatches(namedEntityRegex, in: result) { match, ns in
            let name = ns.substring(with: match.range(at: 1))
            return namedEntities[name] ?? ns.substring(with: match.range)
        }
        return result
    }

    // `[https://x.y/a.](https://x.y/a.)` → `[https://x.y/a](https://x.y/a).`
    private static let bareLinkTrailingPunctuationRegex = try! NSRegularExpression(pattern: "\\[(https?://[^\\]]*?)([.,;:!?)\\]]+)\\]\\(\\1\\2\\)")

    private static func linkingBareURLs(_ s: String) -> String {
        func link(_ text: String) -> String {
            let linked = bareURLRegex.stringByReplacingMatches(in: text, range: fullRange(text), withTemplate: "[$1]($1)")
            return fixTrailingPunctuationInBareLinks(linked)
        }
        var result = ""
        let ns = s as NSString
        var cursor = 0
        for match in inlineLinkRegex.matches(in: s, range: fullRange(s)) {
            result += link(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            result += ns.substring(with: match.range)
            cursor = match.range.location + match.range.length
        }
        result += link(ns.substring(from: cursor))
        return result
    }

    private static func fixTrailingPunctuationInBareLinks(_ s: String) -> String {
        return bareLinkTrailingPunctuationRegex.stringByReplacingMatches(in: s, range: fullRange(s), withTemplate: "[$1]($1)$2")
    }

    private static func escapingIntrawordUnderscores(_ s: String) -> String {
        var result = ""
        let ns = s as NSString
        var cursor = 0
        func transform(_ text: String) -> String {
            return intrawordUnderscoreRegex.stringByReplacingMatches(in: text, range: fullRange(text), withTemplate: "\\\\_")
        }
        for match in protectedRunRegex.matches(in: s, range: fullRange(s)) {
            result += transform(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            result += ns.substring(with: match.range)
            cursor = match.range.location + match.range.length
        }
        result += transform(ns.substring(from: cursor))
        return result
    }

    private static let superscriptDigits: [Character: String] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
    ]

    private static func superscript(_ label: String) -> String {
        if label.allSatisfy({ superscriptDigits[$0] != nil }) {
            return label.map { superscriptDigits[$0]! }.joined()
        }
        return "[" + label + "]"
    }

    private static func fullRange(_ s: String) -> NSRange {
        return NSRange(location: 0, length: (s as NSString).length)
    }

    private static func replacingMatches(_ regex: NSRegularExpression,
                                         in s: String,
                                         with replacement: (NSTextCheckingResult, NSString) -> String) -> String {
        let ns = s as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: s, range: fullRange(s)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += replacement(match, ns)
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }
}
