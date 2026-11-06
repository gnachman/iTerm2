//
//  ChatMarkdownRenderingTests.swift
//  iTerm2 ModernTests
//
//  How AI chat renders a reply's Markdown, end to end through
//  Message.Content.attributedStringValue. SwiftyMarkdown's block parser is
//  being replaced. The first section pins output that must not change; the
//  second describes output that should change and fails until it does.
//  StreamedMarkdownCodeBlockTests covers code blocks in streamed replies.
//

import XCTest
import AppKit
@testable import iTerm2SharedARC

final class ChatMarkdownRenderingTests: XCTestCase {
    private let lineStyleKey = NSAttributedString.Key("swiftyMarkdownLineStyle")
    private let listLevelKey = NSAttributedString.Key("swiftyMarkdownListLevel")
    private let quoteDepthKey = NSAttributedString.Key("swiftyMarkdownQuoteDepth")

    private func render(_ markdown: String) -> NSAttributedString {
        return Message.Content.markdown(markdown).attributedStringValue(linkColor: .blue, textColor: .black)
    }

    private func attributes(of substring: String, in attributed: NSAttributedString,
                            file: StaticString = #filePath, line: UInt = #line) -> [NSAttributedString.Key: Any] {
        let range = (attributed.string as NSString).range(of: substring)
        guard range.location != NSNotFound else {
            XCTFail("\(substring.debugDescription) not in \(attributed.string.debugDescription)", file: file, line: line)
            return [:]
        }
        return attributed.attributes(at: range.location, effectiveRange: nil)
    }

    private func copyButtonCount(_ attributed: NSAttributedString) -> Int {
        var count = 0
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            if value != nil {
                count += 1
            }
        }
        return count
    }

    /// The rendered text without copy buttons and the space inserted after each.
    private func textWithoutButtons(_ attributed: NSAttributedString) -> String {
        return attributed.string.replacingOccurrences(of: "\u{FFFC} ", with: "")
    }

    // MARK: - Output that must not change

    func testParagraphsSeparatedByBlankLine() {
        XCTAssertEqual(render("First.\n\nSecond.").string, "First.\n\nSecond.")
    }

    func testInlineStyles() {
        let attributed = render("**bold** *italic* `code` [link](https://iterm2.com)")
        XCTAssertEqual(attributed.string, "bold italic code link")
        let boldFont = attributes(of: "bold", in: attributed)[.font] as? NSFont
        XCTAssertTrue(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
        let codeFont = attributes(of: "code", in: attributed)[.font] as? NSFont
        XCTAssertTrue(codeFont?.isFixedPitch ?? false)
        XCTAssertNotNil(attributes(of: "link", in: attributed)[.link])
    }

    func testHeadingSize() {
        let attributed = render("# Title")
        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, max(4, round(NSFont.systemFontSize * 2)))
        XCTAssertEqual(attributed.attribute(lineStyleKey, at: 0, effectiveRange: nil) as? String, "h1")
    }

    func testBulletsAndNumbers() {
        XCTAssertEqual(render("- a\n- b").string, "・\ta\n・\tb")
        XCTAssertEqual(render("1. a\n1. b").string, "1.\ta\n2.\tb")
    }

    func testTabNestedList() {
        XCTAssertEqual(render("- a\n\t- b").string, "・\ta\n\t・\tb")
    }

    func testCodeBlockGetsOneCopyButtonAndHidesItsFences() {
        let attributed = render("Run:\n\n```python\nprint(1)\nprint(2)\n```\n\nDone.")
        XCTAssertEqual(copyButtonCount(attributed), 1)
        XCTAssertFalse(attributed.string.contains("```"))
        XCTAssertFalse(attributed.string.contains("python"))
        XCTAssertEqual(attributes(of: "print(1)", in: attributed)[lineStyleKey] as? String, "codeblock")
        XCTAssertTrue((attributes(of: "print(2)", in: attributed)[.font] as? NSFont)?.isFixedPitch ?? false)
    }

    func testCodeBlocksSeparatedByTextGetSeparateButtons() {
        XCTAssertEqual(copyButtonCount(render("```\na\n```\n\ntext\n\n```\nb\n```")), 2)
    }

    func testCodeBlocksSeparatedOnlyByBlankLinesShareAButton() {
        XCTAssertEqual(copyButtonCount(render("```\na\n```\n\n```\nb\n```")), 1)
    }

    func testCodeBlockLinesStaySeparateParagraphs() {
        // The copy button copies the rendered text of the code block's range.
        let attributed = render("```\na\nb\n```")
        XCTAssertEqual(textWithoutButtons(attributed), "a\nb")
    }

    func testIdentifiersInCodeSpansSurvive() {
        XCTAssertEqual(render("Call `snake_case_name()` now.").string, "Call snake_case_name() now.")
    }

    func testFenceWithPunctuatedLanguage() {
        // SwiftyMarkdown only accepts lowercase letters after the backticks, so
        // sanitizeMarkdownLines drops other info strings from the opener.
        let attributed = render("```c++\nint x;\n```\n\nafter")
        XCTAssertEqual(attributes(of: "int x;", in: attributed)[lineStyleKey] as? String, "codeblock")
        XCTAssertEqual(attributes(of: "after", in: attributed)[lineStyleKey] as? String, "body")
        XCTAssertFalse(attributed.string.contains("c++"))
    }

    // MARK: - Output that should change

    func testConsecutiveLinesFormOneParagraphWithALineBreak() {
        // Today each line is its own paragraph. It looks the same, but a paragraph
        // is now what a reader would call one.
        XCTAssertEqual(render("one\ntwo").string, "one\u{2028}two")
    }

    func testSpaceIndentedListNests() {
        // Models indent nested lists with spaces. Today they are flattened.
        let attributed = render("- a\n  - b")
        XCTAssertEqual(attributed.string, "・\ta\n\t・\tb")
        XCTAssertEqual((attributes(of: "b", in: attributed)[listLevelKey] as? NSNumber)?.intValue, 1)
    }

    func testListStartsAtItsFirstNumber() {
        // Today “3. a” is plain text.
        XCTAssertEqual(render("3. a\n4. b").string, "3.\ta\n4.\tb")
    }

    func testNumberingContinuesAfterItemParagraph() {
        XCTAssertEqual(render("1. a\n\n   more about a\n\n2. b").string, "1.\ta\n\nmore about a\n\n2.\tb")
    }

    func testNumberingContinuesAfterCodeInItem() {
        let attributed = render("1. Install:\n\n   ```\n   make\n   ```\n\n2. Run it.")
        XCTAssertTrue(textWithoutButtons(attributed).hasSuffix("2.\tRun it."), attributed.string.debugDescription)
        XCTAssertEqual(attributes(of: "make", in: attributed)[lineStyleKey] as? String, "codeblock")
    }

    func testNumberedListResumesAfterUnindentedFence() {
        // Models often break a numbered list with a fence at the margin and resume
        // at the next number. Today “2. Run.” is plain text.
        let attributed = render("1. Install:\n```\nmake\n```\n2. Run.")
        XCTAssertTrue(textWithoutButtons(attributed).hasSuffix("2.\tRun."), attributed.string.debugDescription)
        XCTAssertEqual(attributes(of: "Run.", in: attributed)[lineStyleKey] as? String, "orderedList")
    }

    func testTaskListItems() {
        XCTAssertEqual(render("- [ ] todo\n- [x] done").string, "☐\ttodo\n☑\tdone")
    }

    func testNestedQuote() {
        let attributed = render("> > inner")
        XCTAssertEqual(attributed.string, "inner")
        XCTAssertEqual((attributed.attribute(quoteDepthKey, at: 0, effectiveRange: nil) as? NSNumber)?.intValue, 2)
    }
}
