//
//  MarkdownPreprocessor.swift
//  iTerm2SharedARC
//
//  SwiftyMarkdown (used by the imgcat porthole) understands a narrow Markdown
//  dialect: one source line per paragraph, tab-indented nested lists whose
//  ordered items all start with “1. ”, backtick fences with a lowercase info
//  string, and so on. This rewrites ordinary CommonMark/GFM into that dialect
//  so that the renderer sees something it can lay out well.
//

import Foundation

struct MarkdownPreprocessor {
    // Placeholders use Unicode noncharacters (U+FDD0 to U+FDEF), which real text
    // shouldn't contain. Any that do appear in the input are removed so they can't
    // be mistaken for placeholders. (Private-use characters were not safe: Nerd
    // Fonts puts glyphs there.)
    private static let noncharacters: ClosedRange<UInt32> = 0xFDD0...0xFDEF

    // Characters SwiftyMarkdown would misread: those whose backslash escape it doesn't
    // understand, and the backtick of a “```” line inside a longer fence. They are
    // swapped for placeholders before rendering and restored afterwards.
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

    // Ordered list items are emitted as “1. ” (the only marker SwiftyMarkdown recognizes)
    // with the real number encoded in front of the content, which the styler decodes.
    static let orderedNumberStart = noncharacter(0xFDE0)
    static let orderedNumberEnd = noncharacter(0xFDE1)

    static func encodedOrderedNumber(_ number: Int) -> String {
        return orderedNumberStart + String(number) + orderedNumberEnd
    }

    // An image that may be shown inline is replaced by its index in `Result.images`
    // between these markers. Remote images are never fetched; they become links.
    static let imageStart = noncharacter(0xFDE2)
    static let imageEnd = noncharacter(0xFDE3)

    static func encodedImage(_ index: Int) -> String {
        return imageStart + String(index) + imageEnd
    }

    // A hard line break inside a paragraph. SwiftyMarkdown treats every newline as a
    // paragraph break, so this stands in until the styler turns it into U+2028.
    static let lineBreak = noncharacter(0xFDE4)

    struct Image: Equatable {
        let alt: String
        let source: String
    }

    struct Result {
        let text: String
        let images: [Image]
    }

    private final class Collector {
        var images = [Image]()
        var references = [String: String]()

        func add(alt: String, source: String) -> String {
            images.append(Image(alt: alt, source: source))
            return MarkdownPreprocessor.encodedImage(images.count - 1)
        }
    }

    private enum JoinMode {
        case none  // The next line starts a new paragraph.
        case soft  // The next line continues the paragraph after a space.
        case hard  // The next line continues the paragraph after a line break.
    }

    private enum Block {
        case none
        case paragraph
        case list
        case quote
        case code
        case table
        case heading
        case other
    }

    // MARK: - Public API

    static func normalize(_ markdown: String) -> String {
        return process(markdown).text
    }

    static func process(_ markdown: String) -> Result {
        let cleaned = String(String.UnicodeScalarView(markdown.unicodeScalars.filter { !noncharacters.contains($0.value) }))
        let lines = removingFrontMatter(cleaned.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n"))
        let collector = Collector()
        collector.references = referenceDefinitions(in: lines)

        var out = [String]()
        var previous = Block.none
        var joinMode = JoinMode.none
        var inFence = false
        var fenceIndent = 0
        var fenceCharacter: Character = "`"
        var fenceLength = 3
        var inTable = false
        var inIndentedCode = false
        // Whether a list is still open: indented content and blank lines keep it open,
        // anything else at the left margin closes it.
        var listActive = false
        // Where the text of each open list item starts, outermost first. As in
        // CommonMark, an item indented at least to its parent's text column nests
        // under it, so nesting doesn't depend on a document-wide indent unit.
        var openItemColumns = [Int]()
        // Where the text of the most recent list item starts. Inside a list, content
        // must be indented four past this to be an indented code block.
        var listContentColumn = 0
        var orderedCounters = [0, 0, 0]
        // How far lines must be indented to be (or stay) an indented code block.
        var codeIndent: Int {
            return listActive ? listContentColumn + 4 : 4
        }

        func closeList() {
            listActive = false
            openItemColumns = []
            listContentColumn = 0
            orderedCounters = [0, 0, 0]
        }

        func emitBlank() {
            if let last = out.last, !last.isEmpty {
                out.append("")
            }
            joinMode = .none
        }

        func emit(_ text: String, block: Block, hardBreak: Bool) {
            out.append(text)
            previous = block
            joinMode = hardBreak ? .hard : .soft
        }

        func join(_ text: String, hardBreak: Bool) {
            out[out.count - 1] += (joinMode == .hard ? lineBreak : " ") + text
            joinMode = hardBreak ? .hard : .soft
        }

        var i = 0
        while i < lines.count {
            let raw = lines[i]
            i += 1

            let indent = indentWidth(of: raw)
            if inFence {
                // A closing fence may be indented at most three spaces past the opener.
                if indent < fenceIndent + 4 && isFenceClose(raw, character: fenceCharacter, length: fenceLength) {
                    out.append("```")
                    inFence = false
                    previous = .code
                    joinMode = .none
                } else {
                    let line = dropIndent(raw, upTo: fenceIndent)
                    if line == "```" {
                        // A shorter fence inside a longer one is content, but SwiftyMarkdown
                        // would end the code block at it.
                        out.append(placeholder(for: "`") + "``")
                    } else {
                        out.append(line.isEmpty ? " " : line)
                    }
                }
                continue
            }
            // A fence indented as far as an indented code block is part of that code.
            if indent < codeIndent, let fence = fenceOpen(raw) {
                if fence.indent < 2 {
                    closeList()
                }
                inFence = true
                fenceIndent = fence.indent
                fenceCharacter = fence.character
                fenceLength = fence.length
                out.append("```")
                previous = .code
                joinMode = .none
                continue
            }

            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            // Keeps trailing whitespace so that a two-space hard break survives.
            let content = String(raw.drop(while: { $0 == " " || $0 == "\t" }))
            if trimmed.isEmpty {
                inTable = false
                if inIndentedCode,
                   let next = nextNonBlankLine(in: lines, from: i),
                   indentWidth(of: next) >= codeIndent {
                    // Keep an indented code block contiguous across its blank lines.
                    out.append("     ")
                    continue
                }
                inIndentedCode = false
                if previous == .list,
                   let next = nextNonBlankLine(in: lines, from: i),
                   listItem(next) != nil {
                    // A blank line between list items would reset SwiftyMarkdown's numbering.
                    joinMode = .none
                    continue
                }
                emitBlank()
                continue
            }

            // Indented text right after a paragraph, list item, or quote continues it;
            // after anything else (like a heading) it's an indented code block.
            let continuesText = joinMode != .none && (previous == .paragraph || previous == .list || previous == .quote)
            let isIndentedCode = indent >= codeIndent && (inIndentedCode || !continuesText)

            // Tables
            if inTable && raw.contains("|") {
                out.append(pipeWrapped(inlineTransform(trimmed, collector).text))
                continue
            }
            if !isIndentedCode, raw.contains("|"), i < lines.count, isTableSeparator(lines[i]) {
                if indent < 2 {
                    closeList()
                }
                out.append(pipeWrapped(inlineTransform(trimmed, collector).text))
                out.append(pipeWrapped(lines[i].trimmingCharacters(in: .whitespaces)))
                i += 1
                inTable = true
                previous = .table
                joinMode = .none
                continue
            }
            inTable = false

            // Indented code blocks
            if isIndentedCode {
                out.append("    " + dropIndent(raw, upTo: codeIndent))
                inIndentedCode = true
                previous = .code
                joinMode = .none
                continue
            }
            inIndentedCode = false

            // Headings
            if let heading = atxHeading(trimmed, collector) {
                closeList()
                emit(heading, block: .heading, hardBreak: true)
                continue
            }
            if joinMode != .none && previous == .paragraph, let underline = setextUnderline(trimmed) {
                emit(underline, block: .heading, hardBreak: true)
                continue
            }

            // Thematic breaks
            if isThematicBreak(trimmed) {
                closeList()
                emitBlank()
                // Four dashes because SwiftyMarkdown takes an exact “---” on the first line
                // as the start of front matter and drops what follows.
                emit("----", block: .other, hardBreak: true)
                continue
            }

            // Footnote and reference definitions
            if let footnote = footnoteDefinition(trimmed, collector) {
                closeList()
                emit(footnote, block: .other, hardBreak: true)
                continue
            }
            if isReferenceDefinition(trimmed) {
                closeList()
                emit(trimmed, block: .other, hardBreak: true)
                continue
            }

            // Blockquotes
            if trimmed.hasPrefix(">") {
                // Strip from the untrimmed line so trailing spaces (a hard break) survive.
                let quoted = stripQuoteMarkers(content)
                if quoted.trimmingCharacters(in: .whitespaces).isEmpty {
                    emitBlank()
                    continue
                }
                let (text, hardBreak) = inlineTransform(quoted, collector)
                if joinMode != .none && previous == .quote {
                    join(text, hardBreak: hardBreak)
                } else {
                    if indent < 2 {
                        closeList()
                    }
                    emit("> " + text, block: .quote, hardBreak: hardBreak)
                }
                continue
            }

            // List items. As in CommonMark, an ordered list can interrupt a paragraph only
            // if it starts at 1, so hard-wrapped prose like “in\n2020. It” stays prose. A
            // sibling of an open list's items isn't starting a list, so it always may.
            if let item = listItem(raw),
               !(joinMode != .none && previous == .paragraph && (item.number ?? 1) != 1 &&
                 !(listActive && item.indent < listContentColumn)) {
                while let parentColumn = openItemColumns.last, item.indent < parentColumn {
                    openItemColumns.removeLast()
                }
                // SwiftyMarkdown has three list levels.
                let level = min(2, openItemColumns.count)
                openItemColumns.append(item.contentColumn)
                let (text, hardBreak) = inlineTransform(taskListGlyphs(item.content), collector)
                var prefix = String(repeating: "\t", count: level)
                if let number = item.number {
                    if listActive && orderedCounters[level] > 0 {
                        orderedCounters[level] += 1
                    } else {
                        orderedCounters[level] = number
                    }
                    prefix += "1. " + encodedOrderedNumber(orderedCounters[level])
                } else {
                    orderedCounters[level] = 0
                    prefix += "- "
                }
                for deeper in (level + 1)..<orderedCounters.count {
                    orderedCounters[deeper] = 0
                }
                listActive = true
                listContentColumn = item.contentColumn
                emit(prefix + text, block: .list, hardBreak: hardBreak)
                continue
            }

            // Plain text, possibly continuing the previous paragraph, list item, or quote.
            let (text, hardBreak) = inlineTransform(content, collector)
            if joinMode != .none && (previous == .paragraph || previous == .list || previous == .quote) {
                join(text, hardBreak: hardBreak)
            } else {
                if indent < 2 {
                    closeList()
                }
                emit(text, block: .paragraph, hardBreak: hardBreak)
            }
        }

        while out.last?.isEmpty == true {
            out.removeLast()
        }
        return Result(text: out.joined(separator: "\n"), images: collector.images)
    }

    /// Replaces the private-use placeholders inserted for escaped characters with the originals.
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

    // MARK: - Line classification

    private struct ListItem {
        let indent: Int
        let number: Int?  // nil for unordered items
        let content: String
        // Where the item's text starts, counting a tab as four columns.
        let contentColumn: Int
    }

    private static let listItemRegex = try! NSRegularExpression(pattern: "^([ \\t]*)(?:([-*+])|(\\d{1,9}[.)]))(?:[ \\t]+(.*))?$")

    private static func listItem(_ line: String) -> ListItem? {
        guard let match = listItemRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else {
            return nil
        }
        let ns = line as NSString
        let indentString = ns.substring(with: match.range(at: 1))
        // Reject “**bold**” and “- - -”, which are not list items.
        let content = match.range(at: 4).location == NSNotFound ? "" : ns.substring(with: match.range(at: 4))
        if match.range(at: 4).location == NSNotFound && !line.hasSuffix(" ") && !line.hasSuffix("\t") {
            // A bare marker with no space after it is not a list item.
            let afterIndent = ns.substring(from: match.range(at: 1).location + match.range(at: 1).length)
            if afterIndent.count > 2 {
                return nil
            }
        }
        if isThematicBreak(line.trimmingCharacters(in: .whitespaces)) {
            return nil
        }
        var number: Int?
        if match.range(at: 3).location != NSNotFound {
            number = Int(ns.substring(with: match.range(at: 3)).dropLast())
        }
        // A marker with no text after it is followed by an implied space.
        let contentColumn = match.range(at: 4).location == NSNotFound
            ? columnWidth(of: line) + 1
            : columnWidth(of: ns.substring(to: match.range(at: 4).location))
        return ListItem(indent: indentWidth(of: indentString),
                        number: number,
                        content: content,
                        contentColumn: contentColumn)
    }

    // Width of a string in columns, counting a tab as four.
    private static func columnWidth(of string: String) -> Int {
        return string.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    private static func indentWidth(of string: String) -> Int {
        var width = 0
        for c in string {
            if c == " " {
                width += 1
            } else if c == "\t" {
                width += 4
            } else {
                break
            }
        }
        return width
    }

    private static func dropIndent(_ line: String, upTo count: Int) -> String {
        var remaining = count
        var index = line.startIndex
        while remaining > 0 && index < line.endIndex {
            if line[index] == " " {
                remaining -= 1
            } else if line[index] == "\t" {
                remaining -= 4
            } else {
                break
            }
            index = line.index(after: index)
        }
        return String(line[index...])
    }

    private static func nextNonBlankLine(in lines: [String], from start: Int) -> String? {
        var i = start
        while i < lines.count {
            if !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                return lines[i]
            }
            i += 1
        }
        return nil
    }

    private static let fenceRegex = try! NSRegularExpression(pattern: "^([ \\t]*)(```+|~~~+)")

    private static func fenceOpen(_ line: String) -> (indent: Int, character: Character, length: Int)? {
        guard let match = fenceRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else {
            return nil
        }
        let ns = line as NSString
        let fence = ns.substring(with: match.range(at: 2))
        let rest = ns.substring(from: match.range.location + match.range.length)
        // An opening backtick fence may not contain backticks in its info string.
        if fence.first == "`" && rest.contains("`") {
            return nil
        }
        return (indentWidth(of: ns.substring(with: match.range(at: 1))), fence.first!, fence.count)
    }

    // A closing fence must be at least as long as the one that opened the block.
    private static func isFenceClose(_ line: String, character: Character, length: Int) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= length && trimmed.allSatisfy { $0 == character }
    }

    private static let atxHeadingRegex = try! NSRegularExpression(pattern: "^(#{1,6})[ \\t]+(.*?)(?:[ \\t]+#+)?[ \\t]*$")

    private static func atxHeading(_ line: String, _ collector: Collector) -> String? {
        guard let match = atxHeadingRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else {
            return nil
        }
        let ns = line as NSString
        let hashes = ns.substring(with: match.range(at: 1))
        let text = inlineTransform(ns.substring(with: match.range(at: 2)), collector).text
        return hashes + " " + text
    }

    /// Drops YAML front matter: a “---” first line through the next “---” or “...”.
    /// SwiftyMarkdown would drop it too, but only when the opener is still the first
    /// line of what it's given.
    private static func removingFrontMatter(_ lines: [String]) -> [String] {
        func trimmed(_ line: String) -> String {
            return line.trimmingCharacters(in: .whitespaces)
        }
        guard let first = lines.first, trimmed(first) == "---",
              let close = lines.dropFirst().firstIndex(where: { trimmed($0) == "---" || trimmed($0) == "..." }) else {
            return lines
        }
        return Array(lines[(close + 1)...])
    }

    private static func setextUnderline(_ line: String) -> String? {
        if line.count >= 1 && line.allSatisfy({ $0 == "=" }) {
            return "==="
        }
        if line.count >= 1 && line.allSatisfy({ $0 == "-" }) {
            return "---"
        }
        return nil
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3, let first = stripped.first, "-*_".contains(first) else {
            return false
        }
        return stripped.allSatisfy { $0 == first }
    }

    private static let referenceDefinitionRegex = try! NSRegularExpression(pattern: "^\\[[^\\]]+\\]:[ \\t]*\\S")

    private static func isReferenceDefinition(_ line: String) -> Bool {
        return referenceDefinitionRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    private static let footnoteDefinitionRegex = try! NSRegularExpression(pattern: "^\\[\\^([^\\]]+)\\]:[ \\t]*(.*)$")

    private static func footnoteDefinition(_ line: String, _ collector: Collector) -> String? {
        guard let match = footnoteDefinitionRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else {
            return nil
        }
        let ns = line as NSString
        let label = superscript(ns.substring(with: match.range(at: 1)))
        let text = inlineTransform(ns.substring(with: match.range(at: 2)), collector).text
        return label + " " + text
    }

    private static func stripQuoteMarkers(_ line: String) -> String {
        var result = Substring(line)
        while result.hasPrefix(">") {
            result = result.dropFirst()
            if result.hasPrefix(" ") {
                result = result.dropFirst()
            }
        }
        return String(result.drop(while: { $0 == " " || $0 == "\t" }))
    }

    private static func taskListGlyphs(_ content: String) -> String {
        if content.hasPrefix("[ ] ") {
            return "☐ " + content.dropFirst(4)
        }
        if content.hasPrefix("[x] ") || content.hasPrefix("[X] ") {
            return "☑ " + content.dropFirst(4)
        }
        return content
    }

    // MARK: - Tables

    private static func isTableSeparator(_ line: String) -> Bool {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") || trimmed.contains("-") else {
            return false
        }
        guard trimmed.contains("|") else {
            return false
        }
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        let cells = trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !cells.isEmpty else {
            return false
        }
        return cells.allSatisfy { cell in
            var body = Substring(cell)
            if body.hasPrefix(":") {
                body = body.dropFirst()
            }
            if body.hasSuffix(":") {
                body = body.dropLast()
            }
            return !body.isEmpty && body.allSatisfy { $0 == "-" }
        }
    }

    private static func pipeWrapped(_ row: String) -> String {
        var result = row
        if !result.hasPrefix("|") {
            result = "| " + result
        }
        if !result.hasSuffix("|") {
            result += " |"
        }
        return result
    }

    // MARK: - Inline transforms

    // Opening and closing backtick runs must be whole runs of the same length.
    private static let codeSpanRegex = try! NSRegularExpression(pattern: "(?<!`)(`+)(?!`)(.+?)(?<!`)\\1(?!`)")

    /// Applies inline rewrites to the parts of a line outside code spans. The returned
    /// text may contain newlines (from <br>); `hardBreak` reports a trailing hard break.
    private static func inlineTransform(_ line: String, _ collector: Collector) -> (text: String, hardBreak: Bool) {
        var text = line
        var hardBreak = false
        if text.hasSuffix("\\") {
            text.removeLast()
            hardBreak = true
        } else if text.hasSuffix("  ") {
            hardBreak = true
        }
        text = convertingHTMLCode(text.trimmingCharacters(in: .whitespaces))

        var result = ""
        let ns = text as NSString
        var cursor = 0
        for match in codeSpanRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += transformTextSegment(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), collector)
            if match.range(at: 1).length == 1 {
                result += ns.substring(with: match.range)
            } else {
                // ``code with a ` in it``. As in CommonMark, one space of padding on
                // each side is dropped.
                var code = ns.substring(with: match.range(at: 2))
                if code.count >= 2, code.hasPrefix(" "), code.hasSuffix(" "), code.contains(where: { $0 != " " }) {
                    code = String(code.dropFirst().dropLast())
                }
                result += codeSpan(code)
            }
            cursor = match.range.location + match.range.length
        }
        result += transformTextSegment(ns.substring(from: cursor), collector)

        if result.hasSuffix(lineBreak) {
            result.removeLast()
            hardBreak = true
        }
        return (result, hardBreak)
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
    private static let protectedRunRegex = try! NSRegularExpression(pattern: "\\]\\([^)]*\\)|https?://[^\\s<>]+|www\\.[^\\s<>]+")
    private static let intrawordUnderscoreRegex = try! NSRegularExpression(pattern: "(?<=[\\p{L}\\p{N}])_(?=[\\p{L}\\p{N}])")

    private static func transformTextSegment(_ segment: String, _ collector: Collector) -> String {
        var s = segment
        s = htmlCommentRegex.stringByReplacingMatches(in: s, range: fullRange(s), withTemplate: "")
        s = htmlBreakRegex.stringByReplacingMatches(in: s, range: fullRange(s), withTemplate: lineBreak)
        s = htmlBoldRegex.stringByReplacingMatches(in: s, range: fullRange(s), withTemplate: "**$2**")
        s = htmlItalicRegex.stringByReplacingMatches(in: s, range: fullRange(s), withTemplate: "*$2*")
        s = htmlStrikeRegex.stringByReplacingMatches(in: s, range: fullRange(s), withTemplate: "~~$2~~")
        s = htmlAnchorRegex.stringByReplacingMatches(in: s, range: fullRange(s), withTemplate: "[$2]($1)")
        s = htmlStripRegex.stringByReplacingMatches(in: s, range: fullRange(s), withTemplate: "")
        s = autolinkRegex.stringByReplacingMatches(in: s, range: fullRange(s), withTemplate: "[$1]($1)")
        s = mailAutolinkRegex.stringByReplacingMatches(in: s, range: fullRange(s), withTemplate: "[$1](mailto:$1)")
        s = decodeEntities(s)
        s = replacingMatches(escapeRegex, in: s) { match, ns in
            let c = ns.substring(with: match.range(at: 1)).first!
            return placeholder(for: c)
        }
        s = replacingMatches(imageRegex, in: s) { match, ns in
            let alt = ns.substring(with: match.range(at: 1))
            let bracketed = match.range(at: 2).location != NSNotFound
            let source = ns.substring(with: match.range(at: bracketed ? 2 : 3))
            return image(alt: alt, source: source, collector: collector)
        }
        s = replacingMatches(referenceImageRegex, in: s) { match, ns in
            let alt = ns.substring(with: match.range(at: 1))
            var label = ns.substring(with: match.range(at: 2))
            if label.isEmpty {
                label = alt
            }
            guard let source = collector.references[label.lowercased()] else {
                return "[\(alt)][\(label)]"
            }
            return image(alt: alt, source: source, collector: collector)
        }
        s = replacingMatches(footnoteReferenceRegex, in: s) { match, ns in
            superscript(ns.substring(with: match.range(at: 1)))
        }
        s = linkingBareURLs(s)
        s = escapingIntrawordUnderscores(s)
        return s
    }

    /// Remote images become links so that nothing is fetched over the network. Anything
    /// else (a path, a file: URL, or a data: URL) may be shown inline.
    private static func image(alt: String, source: String, collector: Collector) -> String {
        if isRemote(source) {
            let text = alt.isEmpty ? (source as NSString).lastPathComponent : alt
            return "[\(text)](\(source))"
        }
        return collector.add(alt: alt, source: source)
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

    private static let referenceDefinitionCaptureRegex = try! NSRegularExpression(pattern: "^[ ]{0,3}\\[([^\\]^][^\\]]*)\\]:[ \\t]*<?([^>\\s]+)>?")

    private static func referenceDefinitions(in lines: [String]) -> [String: String] {
        var result = [String: String]()
        for line in lines {
            guard let match = referenceDefinitionCaptureRegex.firstMatch(in: line, range: fullRange(line)) else {
                continue
            }
            let ns = line as NSString
            let label = ns.substring(with: match.range(at: 1)).lowercased()
            if result[label] == nil {
                result[label] = ns.substring(with: match.range(at: 2))
            }
        }
        return result
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
