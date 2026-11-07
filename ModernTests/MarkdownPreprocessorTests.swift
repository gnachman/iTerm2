//
//  MarkdownPreprocessorTests.swift
//  iTerm2 ModernTests
//
//  The imgcat Markdown porthole passes each paragraph's source through
//  MarkdownPreprocessor.transformInline before SwiftyMarkdown parses its inline
//  content. These tests pin down those rewrites. MarkdownPortholeRenderingTests
//  covers the rendered result, including block structure.
//

import XCTest
@testable import iTerm2SharedARC

final class MarkdownPreprocessorTests: XCTestCase {
    /// Rewrites `paragraph` as part of a document that also contains `document`.
    private func normalize(_ paragraph: String, in document: String? = nil) -> String {
        return MarkdownPreprocessor(document ?? paragraph).transformInline(paragraph)
    }

    private func restored(_ s: String) -> String {
        let attributed = NSMutableAttributedString(string: s)
        MarkdownPreprocessor.restorePlaceholders(in: attributed)
        return attributed.string
    }

    private let br = MarkdownPreprocessor.lineBreak

    func testNoncharactersAreRemovedFromTheDocument() {
        // Swift doesn't allow noncharacters in string literals.
        let first = String(UnicodeScalar(UInt32(0xFDD0))!)
        let last = String(UnicodeScalar(UInt32(0xFDEF))!)
        XCTAssertEqual(MarkdownPreprocessor("a" + first + "b" + last + "c").text, "abc")
    }

    // MARK: Inline

    func testIntrawordUnderscoresAreEscaped() {
        XCTAssertEqual(normalize("snake_case_name and _em_"),
                       "snake\\_case\\_name and _em_")
    }

    func testUnderscoresInsideLinkDestinationsAreNotEscaped() {
        XCTAssertEqual(normalize("[a_b](https://x.y/a_b)"), "[a\\_b](https://x.y/a_b)")
    }

    func testAngleBracketAutolinkBecomesLink() {
        XCTAssertEqual(normalize("see <https://example.com/a>"),
                       "see [https://example.com/a](https://example.com/a)")
    }

    func testBareURLBecomesLink() {
        XCTAssertEqual(normalize("see https://example.com/a_b. ok"),
                       "see [https://example.com/a_b](https://example.com/a_b). ok")
    }

    func testHTMLCodeContentIsNotTransformed() {
        XCTAssertEqual(normalize("<code>foo_bar</code> and <code>https://x.y</code>"),
                       "`foo_bar` and `https://x.y`")
    }

    func testHTMLCodeEntitiesAreDecoded() {
        XCTAssertEqual(normalize("<code>&lt;div&gt;</code>"), "`<div>`")
    }

    // SwiftyMarkdown only understands single-backtick spans, so an inner backtick
    // must not reach it as one.
    private func assertSingleBacktickSpan(_ md: String, restoresTo expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let normalized = normalize(md)
        XCTAssertEqual(normalized.filter { $0 == "`" }.count, 2, normalized, file: file, line: line)
        XCTAssertEqual(restored(normalized), expected, file: file, line: line)
    }

    func testHTMLCodeContainingBacktick() {
        assertSingleBacktickSpan("<code>a`b</code>", restoresTo: "`a`b`")
    }

    func testCodeSpanDelimitersAreWholeRuns() {
        // The single backtick doesn't close at the first backtick of “``”.
        XCTAssertEqual(normalize("`a_b ``c`` d_e`"), "`a_b ``c`` d_e`")
    }

    func testHTMLCodeWithBacktickBeforeCodeSpanOnSameLine() {
        let normalized = normalize("<code>a`b</code> and ``x`y``")
        XCTAssertEqual(normalized.filter { $0 == "`" }.count, 4, normalized)
        XCTAssertEqual(restored(normalized), "`a`b` and `x`y`")
    }

    func testHTMLCodeInsideCodeSpanIsLeftAlone() {
        XCTAssertEqual(normalize("`<code>x</code>`"), "`<code>x</code>`")
    }

    func testDoubleBacktickCodeSpan() {
        assertSingleBacktickSpan("x ``a`b`` y", restoresTo: "x `a`b` y")
        assertSingleBacktickSpan("`` `tick` ``", restoresTo: "``tick``")
    }

    func testBareURLInsideLinkTextIsNotLinked() {
        let md = "[Visit https://example.com today](https://example.com)"
        XCTAssertEqual(normalize(md), md)
    }

    func testBareURLInParenthesesBecomesLink() {
        XCTAssertEqual(normalize("Docs are online (https://example.com)."),
                       "Docs are online ([https://example.com](https://example.com)).")
    }

    func testExistingLinkIsNotRewrapped() {
        let md = "[x](https://example.com/)"
        XCTAssertEqual(normalize(md), md)
    }

    func testHTMLEntitiesAreDecoded() {
        XCTAssertEqual(normalize("a &amp; b &lt;c&gt; &copy; &#65; &#x42;"),
                       "a & b <c> © A B")
    }

    func testInlineHTMLIsConverted() {
        XCTAssertEqual(normalize("<b>bold</b> <em>em</em> <code>c</code> <!-- hidden --> x"),
                       "**bold** *em* `c` x")
    }

    func testBRTagIsAHardBreak() {
        XCTAssertEqual(normalize("a<br>b"), "a" + br + "b")
    }

    func testTrailingBRTagsAreDropped() {
        XCTAssertEqual(normalize("a<br>"), "a")
        XCTAssertEqual(normalize("a<br><br/>"), "a")
        XCTAssertEqual(normalize("<br>"), "")
    }

    func testBlockHTMLTagsAreStripped() {
        XCTAssertEqual(normalize("<div align=\"center\">x</div>"), "x")
    }

    func testRemoteImagesBecomeLinks() {
        XCTAssertEqual(normalize("![alt](https://x/y.png) ![](http://x/z.png) ![r][missing]"),
                       "[alt](https://x/y.png) [z.png](http://x/z.png) [r][missing]")
    }

    func testLocalImagesBecomePlaceholders() {
        let source = "a ![one](img/a_b.png) b ![two](<my pic.png> \"t\")"
        let preprocessor = MarkdownPreprocessor(source)
        XCTAssertEqual(preprocessor.transformInline(source),
                       "a " + MarkdownPreprocessor.encodedImage(0) + " b " + MarkdownPreprocessor.encodedImage(1))
        XCTAssertEqual(preprocessor.images, [MarkdownPreprocessor.Image(alt: "one", source: "img/a_b.png"),
                                       MarkdownPreprocessor.Image(alt: "two", source: "my pic.png")])
    }

    func testFileAndDataURLImagesAreLocal() {
        let source = "![f](file:///tmp/x.png) ![d](data:image/png;base64,AAAA)"
        let preprocessor = MarkdownPreprocessor(source)
        _ = preprocessor.transformInline(source)
        XCTAssertEqual(preprocessor.images.map(\.source), ["file:///tmp/x.png", "data:image/png;base64,AAAA"])
    }

    func testReferenceImagesResolve() {
        // SwiftyMarkdown finds the definitions; labels match regardless of case.
        let paragraph = "![local][a] ![remote][B] ![a][]"
        let preprocessor = MarkdownPreprocessor(paragraph)
        XCTAssertEqual(preprocessor.transformInline(paragraph, references: ["a": "pic.png", "b": "https://x/y.png"]),
                       MarkdownPreprocessor.encodedImage(0) + " [remote](https://x/y.png) " + MarkdownPreprocessor.encodedImage(1))
        XCTAssertEqual(preprocessor.images.map(\.source), ["pic.png", "pic.png"])
    }

    func testImagesInsideCodeSpansAreLeftAlone() {
        let preprocessor = MarkdownPreprocessor("`![x](y.png)`")
        XCTAssertEqual(preprocessor.transformInline("`![x](y.png)`"), "`![x](y.png)`")
        XCTAssertTrue(preprocessor.images.isEmpty)
    }

    func testFootnoteReferencesBecomeSuperscripts() {
        XCTAssertEqual(normalize("text[^1] more[^12]"), "text¹ more¹²")
    }

    func testFootnoteDefinitionBecomesSuperscriptLabel() {
        XCTAssertEqual(normalize("[^12]: note twelve"), "¹² note twelve")
    }

    // MARK: Escapes

    func testEscapedHashSurvivesAsPlaceholderAndRestores() {
        let normalized = normalize("\\# not a heading")
        XCTAssertFalse(normalized.hasPrefix("#"))
        XCTAssertFalse(normalized.hasPrefix("\\"))
        let attributed = NSMutableAttributedString(string: normalized)
        MarkdownPreprocessor.restorePlaceholders(in: attributed)
        XCTAssertEqual(attributed.string, "# not a heading")
    }

    func testPrivateUseCharactersSurvive() {
        // Nerd Fonts puts glyphs here; they must not be mistaken for placeholders.
        let md = "prompt \u{E000}\u{E008} and \u{E100}1\u{E101} and \u{E104}"
        XCTAssertEqual(restored(normalize(md)), md)
    }

    func testEscapesHandledBySwiftyMarkdownAreLeftAlone() {
        XCTAssertEqual(normalize("\\*a\\* \\`b\\` \\_c\\_"), "\\*a\\* \\`b\\` \\_c\\_")
    }
}
