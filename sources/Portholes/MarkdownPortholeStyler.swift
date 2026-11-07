//
//  MarkdownPortholeStyler.swift
//  iTerm2SharedARC
//
//  SwiftyMarkdown produces an attributed string with one paragraph per block
//  (one per line for code), blank paragraphs for blank lines, and almost no
//  paragraph styling. This pass rebuilds it with proper vertical rhythm,
//  hanging list indents, backgrounds for code, a bar for blockquotes, full-width
//  rules, and tables whose columns fit their content.
//

import AppKit
import Foundation

struct MarkdownPortholeStyler {
    static let lineStyleKey = NSAttributedString.Key("swiftyMarkdownLineStyle")
    static let characterStylesKey = NSAttributedString.Key("swiftyMarkdownCharacterStyle")
    static let listLevelKey = NSAttributedString.Key("swiftyMarkdownListLevel")
    static let quoteDepthKey = NSAttributedString.Key("swiftyMarkdownQuoteDepth")
    static let codeBlockStartKey = NSAttributedString.Key("swiftyMarkdownCodeBlockStart")

    let points: CGFloat
    let bodyFont: NSFont
    let codeFont: NSFont
    let textColor: NSColor
    let backgroundColor: NSColor
    let images: [MarkdownPreprocessor.Image]
    let imageLoader: MarkdownImageLoader?

    static func headingScale(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 2.0
        case 2: return 1.5
        case 3: return 1.25
        default: return 1.0
        }
    }

    private enum Kind: Equatable {
        case heading(Int)
        case body
        case code
        case quote
        case list(level: Int)
        case rule
        case table
    }

    private final class Paragraph {
        let text: NSMutableAttributedString  // without trailing newline
        let kind: Kind
        let blankBefore: Bool
        // The level of the innermost list item containing this paragraph.
        let listLevel: Int?
        let quoteDepth: Int
        // For a line of code, whether it's the first line of its block.
        let startsCodeBlock: Bool
        var hasAttachment = false
        // Enclosing quote blocks, outermost first, then any block of its own.
        var blocks = [NSTextBlock]()
        // A block this paragraph opened directly in a list item, to be inset to the item's text.
        var blockInListItem: NSTextBlock?
        // Whether this paragraph sits directly in its list item rather than in a quote
        // inside it. Only then does it line up with the item's text itself.
        var directlyInListItem = false
        // For a nested list item, whether a quote between it and its parent item
        // already insets it, so it doesn't also take the parent's text indent.
        var insetByEnclosingQuote = false
        // For a table directly in a list item, how far it's inset to the item's text.
        var tableIndent: CGFloat = 0
        // The height of an empty paragraph to put above this one, which separates
        // two adjacent blocks.
        var spacerAbove: CGFloat = 0
        var firstInBlock = false
        var spacingBefore: CGFloat = 0
        var spacingAfter: CGFloat = 0

        init(text: NSMutableAttributedString, kind: Kind, blankBefore: Bool, listLevel: Int?, quoteDepth: Int, startsCodeBlock: Bool) {
            self.text = text
            self.kind = kind
            self.blankBefore = blankBefore
            self.listLevel = listLevel
            self.quoteDepth = quoteDepth
            self.startsCodeBlock = startsCodeBlock
        }

        var fullRange: NSRange {
            return NSRange(location: 0, length: text.length)
        }

        var isBlockKind: Bool {
            switch kind {
            case .code, .quote, .rule, .table:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Entry point

    func style(_ input: NSAttributedString) -> NSAttributedString {
        let paragraphs = split(input)
        guard !paragraphs.isEmpty else {
            return input
        }
        insertImages(paragraphs)
        assignBlocks(paragraphs)
        assignSpacing(paragraphs)
        substituteListMarkers(paragraphs)
        let markerColumns = listMarkerColumns(paragraphs)
        // Where the text of the most recent item at each list level starts, so a nested
        // item's marker lines up under its parent's text.
        var textStarts = [CGFloat]()
        for paragraph in paragraphs {
            // Where the text of the list item containing this paragraph starts. For a
            // list item, that's its parent, which a quote the item opens sits in.
            let itemTextStart: CGFloat
            if case .list(let level) = paragraph.kind {
                itemTextStart = level > 0 && level <= textStarts.count ? textStarts[level - 1] : 0
            } else if let level = paragraph.listLevel, level < textStarts.count {
                itemTextStart = textStarts[level]
            } else {
                itemTextStart = 0
            }
            // A block directly in the item is inset to its text, and so is text
            // directly in the item. Inside a quote in the item, the quote is inset.
            paragraph.blockInListItem?.setWidth(itemTextStart, type: .absoluteValueType, for: .margin, edge: .minX)
            let itemIndent = paragraph.directlyInListItem ? itemTextStart : 0
            if paragraph.quoteDepth > 0 && paragraph.kind != .code && paragraph.kind != .table {
                dimQuotedText(paragraph)
            }
            switch paragraph.kind {
            case .heading(let level):
                styleHeading(paragraph, level: level, indent: itemIndent)
            case .body:
                let style = NSMutableParagraphStyle()
                style.firstLineHeadIndent = itemIndent
                style.headIndent = itemIndent
                styleProse(paragraph, style: style)
            case .code:
                styleCodeLine(paragraph)
            case .quote:
                styleQuote(paragraph)
            case .list(let level):
                // Positions inside a quote are measured from the quote's edge.
                let indent = level > 0 && level <= textStarts.count && !paragraph.insetByEnclosingQuote ? textStarts[level - 1] : 0
                let textStart = styleListItem(paragraph, level: level, indent: indent, columns: markerColumns)
                textStarts = Array(textStarts.prefix(level)) + [textStart]
            case .rule:
                styleRule(paragraph)
            case .table:
                paragraph.tableIndent = itemIndent
            }
        }
        styleTables(paragraphs)

        let result = NSMutableAttributedString()
        for (i, paragraph) in paragraphs.enumerated() {
            if paragraph.spacerAbove > 0 {
                result.append(spacer(height: paragraph.spacerAbove))
            }
            result.append(paragraph.text)
            if i + 1 < paragraphs.count || paragraph.kind == .table {
                // Table cells must end in a newline carrying the cell's paragraph style.
                var attributes = paragraph.text.length > 0 ? paragraph.text.attributes(at: paragraph.text.length - 1, effectiveRange: nil) : [:]
                // A background or link on the newline would paint to the end of the line.
                attributes[.backgroundColor] = nil
                attributes[.link] = nil
                attributes[.underlineStyle] = nil
                attributes[.strikethroughStyle] = nil
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }
        MarkdownPreprocessor.restorePlaceholders(in: result)
        return result
    }

    // An empty paragraph exactly `height` tall, in no block.
    private func spacer(height: CGFloat) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        return NSAttributedString(string: "\n", attributes: [.paragraphStyle: style,
                                                              .font: NSFont.systemFont(ofSize: 1)])
    }

    // MARK: - Splitting

    private func split(_ input: NSAttributedString) -> [Paragraph] {
        var paragraphs = [Paragraph]()
        let string = input.string as NSString
        var location = 0
        var blankBefore = false
        while location < string.length {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            location = range.location + range.length
            var contentRange = range
            if contentRange.length > 0 && string.character(at: contentRange.location + contentRange.length - 1) == 0x0A {
                contentRange.length -= 1
            }
            let attributes = range.length > 0 ? input.attributes(at: range.location, effectiveRange: nil) : [:]
            let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
            let isTableCell = paragraphStyle?.textBlocks.contains { $0 is NSTextTableBlock } ?? false
            let content = string.substring(with: contentRange)
            let listLevel = (attributes[Self.listLevelKey] as? NSNumber)?.intValue
            let quoteDepth = (attributes[Self.quoteDepthKey] as? NSNumber)?.intValue ?? 0
            let kind = isTableCell ? Kind.table : kind(for: attributes[Self.lineStyleKey] as? String, listLevel: listLevel)
            // A whitespace-only line inside a code block is a real (blank) line of code.
            if !isTableCell && kind != .code && content.trimmingCharacters(in: .whitespaces).isEmpty {
                blankBefore = true
                continue
            }
            let text: NSMutableAttributedString
            if contentRange.length == 0 {
                // An empty line of code. It needs a character to carry its paragraph style.
                text = NSMutableAttributedString(string: " ", attributes: attributes)
            } else {
                text = NSMutableAttributedString(attributedString: input.attributedSubstring(from: contentRange))
            }
            paragraphs.append(Paragraph(text: text,
                                        kind: kind,
                                        blankBefore: blankBefore,
                                        listLevel: listLevel,
                                        quoteDepth: quoteDepth,
                                        startsCodeBlock: attributes[Self.codeBlockStartKey] as? Bool ?? false))
            blankBefore = false
        }
        return paragraphs
    }

    private func kind(for lineStyle: String?, listLevel: Int?) -> Kind {
        switch lineStyle {
        case "h1", "previousH1": return .heading(1)
        case "h2", "previousH2": return .heading(2)
        case "h3": return .heading(3)
        case "h4": return .heading(4)
        case "h5": return .heading(5)
        case "h6": return .heading(6)
        case "codeblock": return .code
        case "blockquote": return .quote
        case "unorderedList", "orderedList",
            "unorderedListIndentFirstOrder", "orderedListIndentFirstOrder",
            "unorderedListIndentSecondOrder", "orderedListIndentSecondOrder":
            return .list(level: listLevel ?? 0)
        case "horizontalRule": return .rule
        default: return .body
        }
    }

    // MARK: - Blocks and spacing

    private var subtleColor: NSColor {
        return textColor.withAlphaComponent(backgroundColor.isDark ? 0.10 : 0.07)
    }

    private var borderColor: NSColor {
        return textColor.withAlphaComponent(0.3)
    }

    // The table a cell belongs to, or nil if the paragraph isn't a table cell.
    private func textTable(of paragraph: Paragraph) -> NSTextTable? {
        guard paragraph.text.length > 0,
              let style = paragraph.text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle else {
            return nil
        }
        return (style.textBlocks.last as? NSTextTableBlock)?.table
    }

    private func makeQuoteBlock() -> NSTextBlock {
        let block = NSTextBlock()
        block.setValue(100, type: .percentageValueType, for: .width)
        block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        block.setBorderColor(borderColor)
        block.setWidth(points * 0.9, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(points * 0.2, type: .absoluteValueType, for: .padding, edge: .minY)
        block.setWidth(points * 0.2, type: .absoluteValueType, for: .padding, edge: .maxY)
        return block
    }

    private func makeCodeBlock() -> NSTextBlock {
        let block = NSTextBlock()
        block.setValue(100, type: .percentageValueType, for: .width)
        block.backgroundColor = subtleColor
        block.setWidth(points * 0.6, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(points * 0.6, type: .absoluteValueType, for: .padding, edge: .maxX)
        block.setWidth(points * 0.4, type: .absoluteValueType, for: .padding, edge: .minY)
        block.setWidth(points * 0.4, type: .absoluteValueType, for: .padding, edge: .maxY)
        return block
    }

    private func assignBlocks(_ paragraphs: [Paragraph]) {
        // One block per level of quoting, shared by consecutive quoted paragraphs in
        // the same list items. Each remembers the items it was opened in (see itemPath).
        var quoteBlocks = [(block: NSTextBlock, items: [Int])]()
        // Identifies the most recent item at each list level, outermost first.
        var itemPath = [Int]()
        var nextItemID = 0
        var codeBlock: NSTextBlock?
        var previous: Paragraph?
        // How many quotes enclose the most recent item at each list level. A block
        // inside a quote inside an item is laid out within the quote, which is
        // already inset, so it must not be inset again.
        var itemQuoteDepths = [Int]()
        for paragraph in paragraphs {
            defer {
                previous = paragraph
            }
            // The quote depth of the list item that contains this paragraph. For a list
            // item, that's its parent item, since a quote it opens sits in the parent.
            let itemQuoteDepth: Int?
            // The items that contain this paragraph, and the items a quote opened here
            // would be in. A quote opened by a list item sits in its parent item.
            let enclosingItems: [Int]
            let itemsForNewQuote: [Int]
            if case .list(let level) = paragraph.kind {
                itemPath = Array(itemPath.prefix(level)) + [nextItemID]
                nextItemID += 1
                enclosingItems = itemPath
                itemsForNewQuote = Array(itemPath.prefix(level))
                itemQuoteDepth = level > 0 && level - 1 < itemQuoteDepths.count ? itemQuoteDepths[level - 1] : nil
                if let itemQuoteDepth {
                    paragraph.insetByEnclosingQuote = itemQuoteDepth != paragraph.quoteDepth
                }
                itemQuoteDepths = Array(itemQuoteDepths.prefix(level)) + [paragraph.quoteDepth]
            } else {
                itemQuoteDepth = paragraph.listLevel.flatMap { $0 < itemQuoteDepths.count ? itemQuoteDepths[$0] : nil }
                paragraph.directlyInListItem = itemQuoteDepth == paragraph.quoteDepth
                enclosingItems = paragraph.listLevel.map { Array(itemPath.prefix($0 + 1)) } ?? []
                itemsForNewQuote = enclosingItems
            }
            let depth = paragraph.quoteDepth
            // A quote opened in list items this paragraph isn't in is a different quote.
            if let stale = quoteBlocks.firstIndex(where: { !enclosingItems.starts(with: $0.items) }) {
                quoteBlocks.removeSubrange(stale...)
            }
            if quoteBlocks.count > depth {
                quoteBlocks.removeLast(quoteBlocks.count - depth)
            }
            while quoteBlocks.count < depth {
                let block = makeQuoteBlock()
                quoteBlocks.append((block, itemsForNewQuote))
                paragraph.firstInBlock = true
                // A quote directly in a list item is inset to the item's text. A quote
                // that contains the list (or is inside another quote) is not.
                if let itemQuoteDepth, quoteBlocks.count == itemQuoteDepth + 1 {
                    paragraph.blockInListItem = block
                }
            }
            var blocks = quoteBlocks.map(\.block)
            switch paragraph.kind {
            case .table:
                // The table's own blocks come from SwiftyMarkdown. TextKit can't draw a
                // table nested in another block (it raises an exception), so the quotes
                // here only tell styleTables how far to inset the table.
                let previousTable = previous.flatMap { textTable(of: $0) }
                if previousTable == nil || previousTable !== textTable(of: paragraph) {
                    paragraph.firstInBlock = true
                }
                codeBlock = nil
            case .code:
                if let codeBlock, let previous, previous.kind == .code, !paragraph.startsCodeBlock,
                   previous.quoteDepth == depth, previous.listLevel == paragraph.listLevel {
                    blocks.append(codeBlock)
                } else {
                    let block = makeCodeBlock()
                    codeBlock = block
                    blocks.append(block)
                    paragraph.firstInBlock = true
                    if paragraph.directlyInListItem {
                        paragraph.blockInListItem = block
                    }
                }
            case .rule:
                let block = NSTextBlock()
                block.setValue(100, type: .percentageValueType, for: .width)
                block.setWidth(1, type: .absoluteValueType, for: .border, edge: .minY)
                block.setBorderColor(borderColor)
                blocks.append(block)
                paragraph.firstInBlock = true
                if paragraph.directlyInListItem {
                    paragraph.blockInListItem = block
                }
                codeBlock = nil
            default:
                codeBlock = nil
            }
            paragraph.blocks = blocks
        }
    }

    private func assignSpacing(_ paragraphs: [Paragraph]) {
        let em = points
        for (i, paragraph) in paragraphs.enumerated() {
            guard i > 0 else {
                continue
            }
            let previous = paragraphs[i - 1]
            let gap: CGFloat
            switch (previous.kind, paragraph.kind) {
            case (.heading, .heading(let level)):
                gap = em * (level <= 2 ? 0.8 : 0.6)
            case (.heading, _):
                gap = em * 0.4
            case (_, .heading(let level)):
                gap = em * (level <= 2 ? 1.3 : 1.0)
            case (.list, .list):
                gap = paragraph.blankBefore ? em * 0.5 : em * 0.15
            case (.code, .code) where !paragraph.firstInBlock, (.table, .table) where !paragraph.firstInBlock:
                // The same code block or table continues.
                gap = 0
            case (.quote, .quote):
                gap = paragraph.blankBefore ? em * 0.5 : 0
            default:
                gap = em * 0.6
            }
            let previousIsInBlock = !previous.blocks.isEmpty || previous.kind == .table
            if paragraph.firstInBlock && previousIsInBlock {
                // Between two blocks, paragraph spacing lands inside one of them and TextKit
                // paints block margins with the block's background, so the only way to get
                // a visible gap is an empty paragraph outside both.
                paragraph.spacerAbove = gap
            } else if paragraph.firstInBlock {
                // Above a block, the gap goes on the paragraph before it.
                previous.spacingAfter = gap
            } else {
                paragraph.spacingBefore = gap
            }
        }
    }

    // MARK: - Paragraph styling

    // The body font's natural line height, fixed so lines with inline code don't grow.
    private var proseLineHeight: CGFloat {
        return ceil(NSLayoutManager().defaultLineHeight(for: bodyFont))
    }

    private func apply(_ style: NSMutableParagraphStyle, to paragraph: Paragraph) {
        style.paragraphSpacingBefore = paragraph.spacingBefore
        style.paragraphSpacing = paragraph.spacingAfter
        if !paragraph.blocks.isEmpty {
            style.textBlocks = paragraph.blocks
        }
        paragraph.text.addAttribute(.paragraphStyle, value: style, range: paragraph.fullRange)
    }

    private func styleProse(_ paragraph: Paragraph, style: NSMutableParagraphStyle) {
        style.minimumLineHeight = proseLineHeight
        if !paragraph.hasAttachment {
            // A fixed height keeps lines with code spans even, but would clip an image.
            style.maximumLineHeight = proseLineHeight
        }
        apply(style, to: paragraph)
        styleCodeSpans(in: paragraph, size: round(points * 0.9))
    }

    private func styleHeading(_ paragraph: Paragraph, level: Int, indent: CGFloat) {
        let size = max(4, round(points * Self.headingScale(level)))
        paragraph.text.enumerateAttribute(.font, in: paragraph.fullRange, options: []) { value, range, _ in
            guard let font = value as? NSFont, font.pointSize != size else {
                return
            }
            if let resized = NSFont(descriptor: font.fontDescriptor, size: size) {
                paragraph.text.addAttribute(.font, value: resized, range: range)
            }
        }
        if level == 6 {
            paragraph.text.addAttribute(.foregroundColor, value: textColor.withAlphaComponent(0.7), range: paragraph.fullRange)
        }
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        apply(style, to: paragraph)
        styleCodeSpans(in: paragraph, size: round(size * 0.85))
    }

    private func styleCodeLine(_ paragraph: Paragraph) {
        let style = NSMutableParagraphStyle()
        style.headIndent = points * 2
        apply(style, to: paragraph)
    }

    private func styleQuote(_ paragraph: Paragraph) {
        styleProse(paragraph, style: NSMutableParagraphStyle())
    }

    // Text in a quote (prose, list items, headings) is dimmed. Code keeps its color.
    private func dimQuotedText(_ paragraph: Paragraph) {
        let dimmed = textColor.withAlphaComponent(0.75)
        paragraph.text.enumerateAttribute(.foregroundColor, in: paragraph.fullRange, options: []) { value, range, _ in
            if let color = value as? NSColor, color == textColor {
                paragraph.text.addAttribute(.foregroundColor, value: dimmed, range: range)
            }
        }
    }

    private struct MarkerColumns {
        let gap: CGFloat
        // Bullet glyphs carry their own side bearing, so they need less of a gap.
        let bulletGap: CGFloat
        let task: CGFloat
        let ordered: CGFloat

        // Every item at a nesting level uses the same bullet, so sizing the column
        // from the item's own bullet keeps a level aligned without padding “•” out
        // to the width of “▪”.
        func bullet(_ marker: NSAttributedString) -> CGFloat {
            return ceil(marker.size().width + bulletGap)
        }
    }

    private static let checkboxes: Set<String> = ["☐", "☑"]

    // Width from the start of a marker to the start of its item's text. Checkboxes
    // and numbers share a width across the document so they line up; bullets are
    // sized individually so they aren't padded out to fit a checkbox or “10.”.
    private func listMarkerColumns(_ paragraphs: [Paragraph]) -> MarkerColumns {
        let gap = points * 0.4
        var widestCheckbox = CGFloat(0)
        var widestNumber = CGFloat(0)
        for paragraph in paragraphs {
            guard case .list = paragraph.kind, let marker = listMarker(paragraph) else {
                continue
            }
            if Self.checkboxes.contains(marker.string) {
                widestCheckbox = max(widestCheckbox, marker.size().width)
            } else if Self.isOrderedMarker(marker.string) {
                widestNumber = max(widestNumber, marker.size().width)
            }
        }
        return MarkerColumns(gap: gap,
                             bulletGap: points * 0.2,
                             task: ceil(max(widestCheckbox, points * 0.5) + gap),
                             ordered: ceil(max(widestNumber, points) + gap))
    }

    private static func isOrderedMarker(_ marker: String) -> Bool {
        return marker.first?.isNumber ?? false
    }

    // The marker SwiftyMarkdown inserted, e.g. “•” or “3.”, after any leading tabs.
    private func listMarker(_ paragraph: Paragraph) -> NSAttributedString? {
        let string = paragraph.text.string as NSString
        var start = 0
        while start < string.length && string.character(at: start) == 0x09 {
            start += 1
        }
        let tab = string.range(of: "\t", range: NSRange(location: start, length: string.length - start))
        guard tab.location != NSNotFound else {
            return nil
        }
        return paragraph.text.attributedSubstring(from: NSRange(location: start, length: tab.location - start))
    }

    // Removes the tabs SwiftyMarkdown uses for nesting and picks each item's final
    // marker, so the marker columns can be measured from what will be drawn.
    private func substituteListMarkers(_ paragraphs: [Paragraph]) {
        for paragraph in paragraphs {
            guard case .list(let level) = paragraph.kind else {
                continue
            }
            substituteListMarker(paragraph, level: level)
        }
    }

    private func substituteListMarker(_ paragraph: Paragraph, level: Int) {
        let string = paragraph.text.string as NSString
        var leadingTabs = 0
        while leadingTabs < string.length && string.character(at: leadingTabs) == 0x09 {
            leadingTabs += 1
        }
        if leadingTabs > 0 {
            paragraph.text.deleteCharacters(in: NSRange(location: 0, length: leadingTabs))
        }
        if level > 0, let marker = listMarker(paragraph), marker.string == "•" {
            paragraph.text.replaceCharacters(in: NSRange(location: 0, length: marker.length), with: level == 1 ? "◦" : "▪")
        }
    }

    /// Returns the x position where the item's text starts.
    private func styleListItem(_ paragraph: Paragraph, level: Int, indent: CGFloat, columns: MarkerColumns) -> CGFloat {
        let column: CGFloat
        let marker = listMarker(paragraph) ?? NSAttributedString()
        if Self.checkboxes.contains(marker.string) {
            column = columns.task
        } else if Self.isOrderedMarker(marker.string) {
            column = columns.ordered
        } else {
            column = columns.bullet(marker)
        }
        let textStart = indent + column
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent
        style.headIndent = textStart
        style.tabStops = [NSTextTab(textAlignment: .left, location: textStart, options: [:])]
        style.defaultTabInterval = points * 2
        styleProse(paragraph, style: style)
        return textStart
    }

    private func styleRule(_ paragraph: Paragraph) {
        paragraph.text.replaceCharacters(in: paragraph.fullRange, with: "\u{00A0}")
        paragraph.text.addAttribute(.font, value: NSFont.systemFont(ofSize: 2), range: paragraph.fullRange)
        apply(NSMutableParagraphStyle(), to: paragraph)
    }

    private func styleCodeSpans(in paragraph: Paragraph, size: CGFloat) {
        paragraph.text.enumerateAttribute(Self.characterStylesKey, in: paragraph.fullRange, options: []) { value, range, _ in
            guard let styles = value as? [String], styles.contains("code") else {
                return
            }
            let font = NSFont(descriptor: codeFont.fontDescriptor, size: size) ?? codeFont
            paragraph.text.addAttribute(.font, value: font, range: range)
            paragraph.text.addAttribute(.backgroundColor, value: subtleColor, range: range)
        }
    }

    // MARK: - Images

    private static let imagePlaceholderRegex = try! NSRegularExpression(
        pattern: MarkdownPreprocessor.imageStart + "([0-9]+)" + MarkdownPreprocessor.imageEnd)

    // Replaces each image placeholder with the image, or with its alt text linking to
    // the source when the image can't be shown.
    private func insertImages(_ paragraphs: [Paragraph]) {
        for paragraph in paragraphs {
            let matches = Self.imagePlaceholderRegex.matches(in: paragraph.text.string, range: paragraph.fullRange)
            for match in matches.reversed() {
                let digits = (paragraph.text.string as NSString).substring(with: match.range(at: 1))
                guard let index = Int(digits), index < images.count else {
                    paragraph.text.deleteCharacters(in: match.range)
                    continue
                }
                let info = images[index]
                let attributes = paragraph.text.attributes(at: match.range.location, effectiveRange: nil)
                let replacement: NSAttributedString
                if MarkdownImageLoader.isEmbedded(info.source),
                   let image = imageLoader?.image(for: info.source) {
                    replacement = inlineImage(image, alt: info.alt, attributes: attributes)
                    paragraph.hasAttachment = true
                } else {
                    replacement = imagePlaceholder(info, attributes: attributes)
                }
                paragraph.text.replaceCharacters(in: match.range, with: replacement)
            }
        }
    }

    // An image whose bytes are in the Markdown itself. Its size is the author's to
    // choose, so showing it inline reveals nothing about this Mac.
    private func inlineImage(_ image: NSImage,
                             alt: String,
                             attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.attachmentCell = MarkdownImageAttachmentCell(image: image)
        let result = NSMutableAttributedString(attachment: attachment)
        var attributes = attributes
        attributes[.toolTip] = alt.isEmpty ? nil : alt
        result.addAttributes(attributes, range: NSRange(location: 0, length: result.length))
        return result
    }

    // An image that would come from a file. It isn't read until the user clicks the
    // placeholder, and the placeholder's size doesn't depend on the file, so the
    // layout (which a program can measure with cursor reports) can't reveal whether
    // a file exists or what shape it is.
    private func imagePlaceholder(_ info: MarkdownPreprocessor.Image,
                                  attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var attributes = attributes
        attributes[.link] = MarkdownImageReference(source: info.source, alt: info.alt)
        attributes[.toolTip] = String(localized: "MarkdownPorthole.ShowImageToolTip",
                                      defaultValue: "Click to show the image",
                                      comment: "Tooltip on a placeholder for an image in Markdown shown in the terminal. Clicking it shows the image in a popover.")
        let label = info.alt.isEmpty ? (info.source as NSString).lastPathComponent : info.alt
        let result = NSMutableAttributedString()
        if let symbol = NSImage(systemSymbolName: SFSymbol.photo.rawValue, accessibilityDescription: nil) {
            let font = attributes[.font] as? NSFont ?? bodyFont
            let height = ceil(font.capHeight * 1.25)
            let width = ceil(height * symbol.size.width / max(1, symbol.size.height))
            let attachment = NSTextAttachment()
            attachment.image = symbol.it_image(withTintColor: textColor, size: NSSize(width: width, height: height))
            attachment.bounds = NSRect(x: 0, y: floor((font.capHeight - height) / 2), width: width, height: height)
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: "\u{00A0}"))
        }
        result.append(NSAttributedString(string: label))
        result.addAttributes(attributes, range: NSRange(location: 0, length: result.length))
        return result
    }

    // MARK: - Tables

    private func styleTables(_ paragraphs: [Paragraph]) {
        var cellsByTable = [ObjectIdentifier: [(block: NSTextTableBlock, paragraph: Paragraph)]]()
        var tables = [ObjectIdentifier: NSTextTable]()
        for paragraph in paragraphs where paragraph.kind == .table {
            guard let style = paragraph.text.length > 0 ? paragraph.text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle : nil,
                  let block = style.textBlocks.last as? NSTextTableBlock else {
                continue
            }
            let id = ObjectIdentifier(block.table)
            tables[id] = block.table
            cellsByTable[id, default: []].append((block, paragraph))
        }
        for (id, cells) in cellsByTable {
            guard let table = tables[id] else {
                continue
            }
            var columnWidths = [CGFloat](repeating: 0, count: table.numberOfColumns)
            for cell in cells {
                let padding = cell.block.width(for: .padding, edge: .minX) + cell.block.width(for: .padding, edge: .maxX)
                let border = cell.block.width(for: .border, edge: .minX) + cell.block.width(for: .border, edge: .maxX)
                let column = cell.block.startingColumn
                if column < columnWidths.count {
                    columnWidths[column] = max(columnWidths[column], ceil(cell.paragraph.text.size().width) + padding + border + 2)
                }
            }
            // A table directly in a list item is inset to the item's text.
            if let first = cells.first {
                // Line up with the text of the quotes the table is in, without being in them.
                let quoteInset = first.paragraph.blocks.reduce(CGFloat(0)) { sum, block in
                    sum + block.width(for: .margin, edge: .minX)
                        + block.width(for: .border, edge: .minX)
                        + block.width(for: .padding, edge: .minX)
                }
                table.setWidth(first.paragraph.tableIndent + quoteInset, type: .absoluteValueType, for: .margin, edge: .minX)
            }
            // A column of prose would make the table wider than the porthole, and TextKit
            // then squeezes every column until short words break mid-word. Leave such
            // columns unsized and stretch the table to the full width so they take what
            // the sized columns leave and wrap there.
            let proseWidth = points * 30
            let hasProseColumn = columnWidths.contains { $0 > proseWidth }
            if hasProseColumn {
                table.setValue(100, type: .percentageValueType, for: .width)
            }
            for cell in cells {
                let column = cell.block.startingColumn
                if column < columnWidths.count, columnWidths[column] <= proseWidth {
                    cell.block.setValue(columnWidths[column], type: .absoluteValueType, for: .width)
                }
                cell.block.setBorderColor(borderColor)
                if cell.block.startingRow == 0 {
                    cell.block.backgroundColor = subtleColor
                }
                if let style = cell.paragraph.text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle,
                   let mutable = style.mutableCopy() as? NSMutableParagraphStyle {
                    mutable.textBlocks = [cell.block]
                    mutable.paragraphSpacingBefore = cell.paragraph.spacingBefore
                    mutable.paragraphSpacing = cell.paragraph.spacingAfter
                    mutable.minimumLineHeight = proseLineHeight
                    mutable.maximumLineHeight = proseLineHeight
                    cell.paragraph.text.addAttribute(.paragraphStyle, value: mutable, range: cell.paragraph.fullRange)
                }
                styleCodeSpans(in: cell.paragraph, size: round(points * 0.9))
            }
        }
    }
}
