//
//  MarkdownPortholeRenderingTests.swift
//  iTerm2 ModernTests
//
//  End-to-end output of the imgcat Markdown porthole: SwiftyMarkdown with
//  MarkdownPreprocessor's inline rewrites, then MarkdownPortholeStyler. The
//  first section is output that predates SwiftyMarkdown's CommonMark block
//  parser; the second is output that parser made possible.
//

import XCTest
import AppKit
@testable import iTerm2SharedARC

final class MarkdownPortholeRenderingTests: XCTestCase {
    private let font = NSFont.userFixedPitchFont(ofSize: 12)!
    private let lineStyleKey = NSAttributedString.Key("swiftyMarkdownLineStyle")

    private struct Paragraph: CustomStringConvertible {
        let text: String
        let attributes: [NSAttributedString.Key: Any]

        var style: String? {
            return attributes[NSAttributedString.Key("swiftyMarkdownLineStyle")] as? String
        }
        var paragraphStyle: NSParagraphStyle? {
            return attributes[.paragraphStyle] as? NSParagraphStyle
        }
        var font: NSFont? {
            return attributes[.font] as? NSFont
        }
        var firstLineHeadIndent: CGFloat {
            return paragraphStyle?.firstLineHeadIndent ?? 0
        }
        var headIndent: CGFloat {
            return paragraphStyle?.headIndent ?? 0
        }
        var textBlocks: [NSTextBlock] {
            return paragraphStyle?.textBlocks ?? []
        }
        /// How far the first line's text starts from the left edge, counting the
        /// margins, borders, and padding of enclosing text blocks.
        var leftInset: CGFloat {
            let blocks = textBlocks.reduce(CGFloat(0)) { sum, block in
                sum + block.width(for: .margin, edge: .minX)
                    + block.width(for: .border, edge: .minX)
                    + block.width(for: .padding, edge: .minX)
            }
            return blocks + firstLineHeadIndent
        }
        var description: String {
            return "\(text.debugDescription) \(style ?? "-") first=\(firstLineHeadIndent) head=\(headIndent) blocks=\(textBlocks.count)"
        }
    }

    private func render(_ markdown: String) -> NSAttributedString {
        return MarkdownPortholeRenderer.attributedString(markdown: markdown,
                                                         font: font,
                                                         textColor: .white,
                                                         backgroundColor: .black,
                                                         imageLoader: nil)
    }

    private func paragraphs(_ markdown: String) -> [Paragraph] {
        let attributed = render(markdown)
        var result = [Paragraph]()
        var location = 0
        for text in attributed.string.components(separatedBy: "\n") {
            let length = (text as NSString).length
            if length > 0 {
                result.append(Paragraph(text: text, attributes: attributed.attributes(at: location, effectiveRange: nil)))
            }
            location += length + 1
        }
        return result
    }

    private func texts(_ markdown: String) -> [String] {
        return paragraphs(markdown).map(\.text)
    }

    private func paragraph(_ text: String, in paragraphs: [Paragraph], file: StaticString = #filePath, line: UInt = #line) -> Paragraph? {
        let found = paragraphs.first { $0.text == text }
        XCTAssertNotNil(found, "No paragraph \(text.debugDescription) in \(paragraphs)", file: file, line: line)
        return found
    }

    private func isFixedPitch(_ font: NSFont?) -> Bool {
        return font?.isFixedPitch ?? false
    }

    // MARK: - Output that predates the block parser

    func testWrappedLinesReflowIntoOneParagraph() {
        XCTAssertEqual(texts("Para one\nwraps here.\n\nPara two."), ["Para one wraps here.", "Para two."])
    }

    func testHardBreaksBecomeLineSeparators() {
        XCTAssertEqual(texts("line one  \nline two\\\nline three"), ["line one\u{2028}line two\u{2028}line three"])
    }

    func testHeadingIsBoldAndScaled() {
        let all = paragraphs("# Title\n\nbody")
        guard let title = paragraph("Title", in: all) else {
            return
        }
        XCTAssertEqual(title.style, "h1")
        XCTAssertEqual(title.font?.pointSize, 24)
        XCTAssertTrue(title.font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
    }

    func testBulletGlyphsByLevel() {
        XCTAssertEqual(texts("- a\n  - b\n    - c"), ["•\ta", "◦\tb", "▪\tc"])
    }

    func testNestedMarkerSitsUnderParentText() {
        let all = paragraphs("- a\n  - b\n    - c")
        XCTAssertEqual(all.count, 3)
        guard all.count == 3 else {
            return
        }
        XCTAssertEqual(all[1].firstLineHeadIndent, all[0].headIndent)
        XCTAssertEqual(all[2].firstLineHeadIndent, all[1].headIndent)
        XCTAssertGreaterThan(all[1].headIndent, all[0].headIndent)
        XCTAssertGreaterThan(all[2].headIndent, all[1].headIndent)
    }

    func testOrderedListNumbering() {
        XCTAssertEqual(texts("1. one\n2. two\n10. ten"), ["1.\tone", "2.\ttwo", "3.\tten"])
    }

    func testOrderedListStartNumber() {
        XCTAssertEqual(texts("3. three\n4. four"), ["3.\tthree", "4.\tfour"])
    }

    func testNumbersLineUp() {
        let all = paragraphs("1. one\n2. two\n10. ten")
        XCTAssertEqual(Set(all.map(\.headIndent)).count, 1, "\(all)")
    }

    func testTaskCheckboxes() {
        XCTAssertEqual(texts("- [x] done\n- [ ] todo"), ["☑\tdone", "☐\ttodo"])
    }

    func testQuoteLinesJoinInATextBlock() {
        let all = paragraphs("> quoted\n> more")
        XCTAssertEqual(all.map(\.text), ["quoted more"])
        XCTAssertEqual(all.first?.style, "blockquote")
        XCTAssertEqual(all.first?.textBlocks.count, 1)
    }

    func testCodeBlockIsMonospacedInATextBlock() {
        let all = paragraphs("```swift\nlet x = 1\n\nlet y = 2\n```")
        XCTAssertEqual(all.map(\.text), ["let x = 1", " ", "let y = 2"])
        for paragraph in all {
            XCTAssertEqual(paragraph.style, "codeblock")
            XCTAssertEqual(paragraph.textBlocks.count, 1)
            XCTAssertTrue(isFixedPitch(paragraph.font), "\(paragraph)")
        }
    }

    func testRule() {
        let all = paragraphs("a\n\n***\n\nb")
        XCTAssertEqual(all.map(\.style), ["body", "horizontalRule", "body"])
    }

    func testTableCellsAreTableBlocksWithBoldHeader() {
        let all = paragraphs("| a | b |\n|---|---|\n| 1 | 2 |")
        XCTAssertEqual(all.map(\.text), ["a", "b", "1", "2"])
        XCTAssertTrue(all.allSatisfy { $0.textBlocks.first is NSTextTableBlock })
        XCTAssertTrue(all[0].font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
        XCTAssertFalse(all[2].font?.fontDescriptor.symbolicTraits.contains(.bold) ?? true)
    }

    func testLocalImageIsAPlaceholderAndRemoteImageIsALink() {
        let attributed = render("![alt](img.png) and ![remote](https://x.y/i.png)")
        let string = attributed.string as NSString
        let alt = string.range(of: "alt")
        let remote = string.range(of: "remote")
        XCTAssertTrue(attributed.attribute(.link, at: alt.location, effectiveRange: nil) is MarkdownImageReference)
        XCTAssertEqual((attributed.attribute(.link, at: remote.location, effectiveRange: nil) as? URL)?.absoluteString
                       ?? attributed.attribute(.link, at: remote.location, effectiveRange: nil) as? String,
                       "https://x.y/i.png")
    }

    func testInlineCodeAndLink() {
        let attributed = render("`code` and [l](https://x.y)")
        XCTAssertEqual(attributed.string, "code and l")
        XCTAssertTrue(isFixedPitch(attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont))
        let l = (attributed.string as NSString).range(of: "l", options: .backwards)
        XCTAssertNotNil(attributed.attribute(.link, at: l.location, effectiveRange: nil))
    }

    func testEscapesAndPrivateUseGlyphsSurvive() {
        XCTAssertEqual(texts("\\# not a heading \u{E0A0}"), ["# not a heading \u{E0A0}"])
    }

    func testFrontMatterIsHidden() {
        XCTAssertEqual(texts("---\ntitle: x\n---\n\nHello"), ["Hello"])
    }

    func testRuleAtStartDoesNotHideTheDocument() {
        XCTAssertEqual(paragraphs("***\n\nHello").map(\.style), ["horizontalRule", "body"])
    }

    func testListItemParagraphsDoNotBecomeCode() {
        let all = paragraphs("1. a\n\n    b\n\n    c")
        XCTAssertEqual(all.map(\.text), ["1.\ta", "b", "c"])
        XCTAssertEqual(all.dropFirst().map(\.style), ["body", "body"])
    }

    func testTildeFence() {
        let all = paragraphs("~~~\nx\n~~~\n\nafter")
        XCTAssertEqual(all.map(\.text), ["x", "after"])
        XCTAssertEqual(all.map(\.style), ["codeblock", "body"])
    }

    func testCodeBlocksSeparatedByABlankLineGetSeparateBoxes() {
        let all = paragraphs("```\na\n```\n\n```\nb\n```")
        guard let a = paragraph("a", in: all), let b = paragraph("b", in: all) else {
            return
        }
        XCTAssertFalse(a.textBlocks.first === b.textBlocks.first)
    }

    func testTablesSeparatedByABlankLineHaveAGap() {
        XCTAssertGreaterThanOrEqual(visibleGap("| a |\n|---|\n| 1 |\n\n| b |\n|---|\n| 2 |", between: "1", and: "b") ?? 0, 6)
    }

    func testAdjacentCodeBlocksGetSeparateBoxes() {
        let all = paragraphs("```sh\nls\n```\n```python\nprint(1)\n```")
        guard let ls = paragraph("ls", in: all), let print = paragraph("print(1)", in: all) else {
            return
        }
        XCTAssertFalse(ls.textBlocks.first === print.textBlocks.first)
    }

    /// The drawn gap, in points, between the boxes around `upper` and `lower`: the
    /// longest run of background-colored rows between the two lines of text, just
    /// inside the boxes' left edge.
    private func visibleGap(_ markdown: String, between upper: String, and lower: String) -> CGFloat? {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        textView.isVerticallyResizable = true
        textView.drawsBackground = true
        textView.backgroundColor = .black
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(render(markdown))
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else {
            return nil
        }
        layoutManager.ensureLayout(for: container)
        textView.sizeToFit()
        func lineRect(_ text: String) -> NSRect? {
            let range = (textView.string as NSString).range(of: text)
            guard range.location != NSNotFound else {
                return nil
            }
            let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
            return layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        }
        guard let top = lineRect(upper), let bottom = lineRect(lower),
              let bitmap = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) else {
            return nil
        }
        textView.cacheDisplay(in: textView.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsHigh) / textView.bounds.height
        var longest = 0
        var run = 0
        for y in Int(top.maxY * scale)..<Int(bottom.minY * scale) {
            // Inside the boxes, which start after the text container's inset, and left of the text.
            guard let color = bitmap.colorAt(x: Int(9 * scale), y: y)?.usingColorSpace(.deviceRGB) else {
                continue
            }
            let isBackground = color.redComponent < 0.02 && color.greenComponent < 0.02 && color.blueComponent < 0.02
            run = isBackground ? run + 1 : 0
            longest = max(longest, run)
        }
        return CGFloat(longest) / scale
    }

    func testVisibleGapBetweenBlocks() {
        // The gap between paragraphs and blocks is 0.6em, which is 7.2 points here.
        // TextKit paints a block's margins with its background, so this measures the
        // drawn image rather than the layout.
        for (markdown, upper, lower) in [("```\na\n```\n\n```\nb\n```", "a", "b"),
                                         ("```sh\nls\n```\n```python\nprint(1)\n```", "ls", "print(1)"),
                                         ("| t |\n|---|\n| 1 |\n\n```\nb\n```", "1", "b"),
                                         ("```\na\n```\n\n| t |\n|---|\n| 1 |", "a", "t"),
                                         ("> q\n\n```\nb\n```", "q", "b"),
                                         ("```\na\n```\n\n> > nested", "a", "nested"),
                                         ("```\na\n```\n\n> ```\n> code\n> ```", "a", "code"),
                                         ("```\na\n```\n\n> | t |\n> |---|\n> | 1 |", "a", "t")] {
            let gap = visibleGap(markdown, between: upper, and: lower)
            XCTAssertNotNil(gap, markdown)
            XCTAssertGreaterThanOrEqual(gap ?? 0, 6, markdown)
        }
    }

    // Drawing raises an exception for some text block arrangements TextKit doesn't
    // support, such as a table nested in another block.
    func testTypographySampleDraws() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let markdown = try String(contentsOf: repository.appendingPathComponent("tests/markdown-typography-sample.md"), encoding: .utf8)
        for width in [300.0, 500.0, 800.0] {
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
            textView.isVerticallyResizable = true
            textView.textContainer?.widthTracksTextView = true
            textView.textStorage?.setAttributedString(render(markdown))
            if let layoutManager = textView.layoutManager, let container = textView.textContainer {
                layoutManager.ensureLayout(for: container)
            }
            textView.sizeToFit()
            // Draw in slices, as scrolling does. Drawing everything at once doesn't
            // reach the failure.
            var y = 0.0
            while y < textView.bounds.height {
                let rect = NSRect(x: 0, y: y, width: width, height: min(200, textView.bounds.height - y))
                guard let bitmap = textView.bitmapImageRepForCachingDisplay(in: rect) else {
                    XCTFail("No bitmap")
                    return
                }
                textView.cacheDisplay(in: rect, to: bitmap)
                y += 150
            }
        }
    }

    func testBlankLineInsideACodeBlockKeepsOneBox() {
        let all = paragraphs("```\na\n\nb\n```")
        guard let a = paragraph("a", in: all), let b = paragraph("b", in: all) else {
            return
        }
        XCTAssertTrue(a.textBlocks.first === b.textBlocks.first)
    }

    func testShorterFenceInsideLongerFenceIsCode() {
        let all = paragraphs("````\n```\nx\n```\n````")
        XCTAssertEqual(all.map(\.text), ["```", "x", "```"])
        XCTAssertTrue(all.allSatisfy { $0.style == "codeblock" }, "\(all)")
    }

    func testIndentedCodeAfterHeading() {
        XCTAssertEqual(paragraphs("# H\n    code").map(\.style), ["h1", "codeblock"])
    }

    func testNumberingContinuesAcrossCodeInItem() {
        XCTAssertEqual(texts("1. a\n\n    ```\n    x\n    ```\n\n2. b"), ["1.\ta", "x", "2.\tb"])
    }

    func testNumberOtherThanOneDoesNotInterruptParagraph() {
        XCTAssertEqual(texts("first released in\n2020. It grew."), ["first released in 2020. It grew."])
    }

    func testSetextHeading() {
        XCTAssertEqual(paragraphs("Title\n===\n\nbody").map(\.style), ["h1", "body"])
    }

    func testTableWithoutOuterPipes() {
        XCTAssertEqual(texts("a | b\n--|--\n1 | 2"), ["a", "b", "1", "2"])
    }

    func testFrontMatterClosedWithDotsIsHidden() {
        XCTAssertEqual(texts("---\ntitle: x\n...\n\nHello"), ["Hello"])
    }

    func testFootnotes() {
        XCTAssertEqual(texts("text[^1]\n\n[^1]: A note."), ["text¹", "¹ A note."])
    }

    func testFootnoteDefinitionsBackToBack() {
        XCTAssertEqual(texts("text[^1][^2]\n\n[^1]: First.\n[^2]: Second."), ["text¹²", "¹ First.", "² Second."])
    }

    func testOrderedTaskItemsKeepTheirNumbers() {
        XCTAssertEqual(texts("1. [x] done\n2. [ ] todo"), ["1.\t☑ done", "2.\t☐ todo"])
    }

    func testTrailingBRDoesNotAddALine() {
        XCTAssertEqual(texts("a<br>\n\nb"), ["a", "b"])
        XCTAssertEqual(texts("| a<br> | b |\n|---|---|\n| 1 | 2 |"), ["a", "b", "1", "2"])
    }

    // A definition can't interrupt a paragraph (CommonMark), so it shows as text and
    // doesn't define anything; after a blank line it's hidden and resolves.
    func testReferenceImageDefinitionMustStartAParagraph() {
        func hasImage(_ attributed: NSAttributedString) -> Bool {
            var found = false
            attributed.enumerateAttribute(.link, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
                found = found || value is MarkdownImageReference
            }
            return found
        }
        let interrupting = render("see ![i][d]\n[d]: pic.png")
        XCTAssertTrue(interrupting.string.contains("pic.png"), interrupting.string)
        XCTAssertFalse(hasImage(interrupting))

        let separate = render("see ![i][d]\n\n[d]: pic.png")
        XCTAssertFalse(separate.string.contains("pic.png"), separate.string)
        XCTAssertTrue(hasImage(separate))
    }

    func testStrippedHTMLLeavesNoLeadingSpace() {
        XCTAssertEqual(texts("<details>\n<summary>Click</summary>"), ["Click"])
    }

    func testReferenceLabelWithUnderscore() {
        let attributed = render("see [docs][api_ref]\n\n[api_ref]: https://x.com/")
        let range = (attributed.string as NSString).range(of: "docs")
        let value = attributed.attribute(.link, at: range.location, effectiveRange: nil)
        XCTAssertEqual((value as? URL)?.absoluteString ?? value as? String, "https://x.com/")
    }

    func testIntrawordUnderscoresSurvive() {
        XCTAssertEqual(texts("Call snake_case_name now."), ["Call snake_case_name now."])
    }

    // MARK: - Output from the block parser

    func testListItemContinuationParagraphIsIndentedToItemText() {
        let all = paragraphs("1. a\n\n   para\n\n2. b")
        XCTAssertEqual(all.map(\.text), ["1.\ta", "para", "2.\tb"])
        guard all.count == 3 else {
            return
        }
        XCTAssertEqual(all[1].firstLineHeadIndent, all[0].headIndent)
        XCTAssertEqual(all[1].headIndent, all[0].headIndent)
    }

    func testCodeBlockInListItemIsIndentedToItemText() {
        let all = paragraphs("1. a\n\n   ```\n   x\n   ```")
        guard let item = paragraph("1.\ta", in: all), let code = paragraph("x", in: all) else {
            return
        }
        XCTAssertEqual(code.textBlocks.first?.width(for: .margin, edge: .minX), item.headIndent)
    }

    func testBlocksInQuoteInListItemAreInsetOnce() {
        let all = paragraphs("1. Item\n\n   > Note:\n   > ```\n   > code\n   > ```\n   > # Heading\n   > > inner")
        guard let item = paragraph("1.\tItem", in: all),
              let note = paragraph("Note:", in: all),
              let code = paragraph("code", in: all),
              let heading = paragraph("Heading", in: all),
              let inner = paragraph("inner", in: all) else {
            return
        }
        // The quote is inset to the item's text; what's inside it is not inset again.
        XCTAssertEqual(note.textBlocks.first?.width(for: .margin, edge: .minX), item.headIndent)
        XCTAssertEqual(code.textBlocks.count, 2)
        XCTAssertEqual(code.textBlocks.last?.width(for: .margin, edge: .minX), 0)
        XCTAssertEqual(heading.firstLineHeadIndent, 0)
        XCTAssertEqual(inner.textBlocks.count, 2)
        XCTAssertEqual(inner.textBlocks.last?.width(for: .margin, edge: .minX), 0)
    }

    func testListInQuoteInListItemIsInsetOnce() {
        let all = paragraphs("- a\n\n  > q\n  > - n")
        guard let a = paragraph("•\ta", in: all),
              let q = paragraph("q", in: all),
              let n = all.first(where: { $0.text.hasSuffix("\tn") }) else {
            XCTFail("\(all)")
            return
        }
        // The quote is inset to a's text, and the nested item starts at the quote's edge.
        XCTAssertEqual(q.textBlocks.first?.width(for: .margin, edge: .minX), a.headIndent)
        XCTAssertEqual(n.firstLineHeadIndent, 0)
    }

    func testQuoteOpenedByNestedItemIsInsetToParentItem() {
        let all = paragraphs("- a\n  > - b")
        guard let a = paragraph("•\ta", in: all),
              let b = all.first(where: { $0.text.hasSuffix("\tb") }) else {
            XCTFail("\(all)")
            return
        }
        XCTAssertEqual(b.textBlocks.count, 1)
        XCTAssertEqual(b.textBlocks.first?.width(for: .margin, edge: .minX), a.headIndent)
        XCTAssertEqual(b.firstLineHeadIndent, 0)
    }

    func testTableInQuoteIsInsetToTheQuotesText() {
        let all = paragraphs("> q\n>\n> | a | b |\n> |---|---|\n> | 1 | 2 |\n>\n> after")
        guard let q = paragraph("q", in: all),
              let cell = paragraph("a", in: all),
              let after = paragraph("after", in: all),
              let block = cell.textBlocks.first as? NSTextTableBlock else {
            return
        }
        // TextKit can't draw a table nested in another block, so the table isn't in
        // the quote's block but lines up with its text. The quote resumes after it.
        XCTAssertEqual(cell.textBlocks.count, 1)
        XCTAssertEqual(block.table.width(for: .margin, edge: .minX), q.leftInset)
        XCTAssertTrue(after.textBlocks.first === q.textBlocks.first)
    }

    func testTableInListItemIsInsetToItemText() {
        let all = paragraphs("1. item\n\n   | a | b |\n   |---|---|\n   | 1 | 2 |")
        guard let item = paragraph("1.\titem", in: all),
              let cell = paragraph("a", in: all),
              let block = cell.textBlocks.last as? NSTextTableBlock else {
            XCTFail("\(all)")
            return
        }
        XCTAssertEqual(block.table.width(for: .margin, edge: .minX), item.headIndent)
    }

    func testQuoteAfterAListIsSeparateFromAQuoteInTheList() {
        for markdown in ["- a\n\n  > q1\n\n> q2", "- a\n  - b\n\n    > q1\n\n  > q2"] {
            let all = paragraphs(markdown)
            guard let q1 = paragraph("q1", in: all), let q2 = paragraph("q2", in: all) else {
                continue
            }
            XCTAssertFalse(q1.textBlocks.first === q2.textBlocks.first, markdown)
            XCTAssertLessThan(q2.textBlocks.first?.width(for: .margin, edge: .minX) ?? 0,
                              q1.textBlocks.first?.width(for: .margin, edge: .minX) ?? 0, markdown)
        }
    }

    func testQuotesInDifferentItemsAreSeparate() {
        let all = paragraphs("- a\n\n  > q1\n- b\n\n  > q2")
        guard let q1 = paragraph("q1", in: all), let q2 = paragraph("q2", in: all) else {
            return
        }
        XCTAssertFalse(q1.textBlocks.first === q2.textBlocks.first)
    }

    func testEverythingInAQuoteIsDimmed() {
        let attributed = render("> text\n>\n> - li\n>\n> # H")
        func alpha(_ text: String) -> CGFloat {
            let range = (attributed.string as NSString).range(of: text)
            return (attributed.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor)?.alphaComponent ?? 1
        }
        XCTAssertLessThan(alpha("text"), 1)
        XCTAssertEqual(alpha("li"), alpha("text"))
        XCTAssertEqual(alpha("H"), alpha("text"))
    }

    func testRuleInListItemIsInsetToItemText() {
        let all = paragraphs("- a\n\n  ***")
        guard let a = paragraph("•\ta", in: all), let rule = all.first(where: { $0.style == "horizontalRule" }) else {
            XCTFail("\(all)")
            return
        }
        XCTAssertEqual(rule.textBlocks.first?.width(for: .margin, edge: .minX), a.headIndent)
    }

    func testNestedQuoteIsInsetFurther() {
        let all = paragraphs("> a\n>\n> > b")
        guard let outer = paragraph("a", in: all), let inner = paragraph("b", in: all) else {
            return
        }
        XCTAssertGreaterThan(inner.leftInset, outer.leftInset)
    }

    func testFourthListLevelIsIndentedFurther() {
        let all = paragraphs("- a\n  - b\n    - c\n      - d")
        XCTAssertEqual(all.count, 4)
        guard all.count == 4 else {
            return
        }
        XCTAssertGreaterThan(all[3].headIndent, all[2].headIndent)
    }
}
