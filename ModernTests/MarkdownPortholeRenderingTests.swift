//
//  MarkdownPortholeRenderingTests.swift
//  iTerm2 ModernTests
//
//  End-to-end output of the imgcat Markdown porthole: MarkdownPreprocessor,
//  SwiftyMarkdown, and MarkdownPortholeStyler together. SwiftyMarkdown's block
//  parser is being replaced so that the preprocessor can shrink. The first
//  section pins output that must not change while that happens; the second
//  describes output that should change and fails until it does.
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

    // MARK: - Output that must not change

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

    // MARK: - Output that should change

    func testListItemContinuationParagraphIsIndentedToItemText() {
        // Today it starts at the left margin.
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

    func testNestedQuoteIsInsetFurther() {
        // Today nested quotes are flattened.
        let all = paragraphs("> a\n>\n> > b")
        guard let outer = paragraph("a", in: all), let inner = paragraph("b", in: all) else {
            return
        }
        XCTAssertGreaterThan(inner.leftInset, outer.leftInset)
    }

    func testFourthListLevelIsIndentedFurther() {
        // Today the fourth level sits at the third level's indent.
        let all = paragraphs("- a\n  - b\n    - c\n      - d")
        XCTAssertEqual(all.count, 4)
        guard all.count == 4 else {
            return
        }
        XCTAssertGreaterThan(all[3].headIndent, all[2].headIndent)
    }
}
