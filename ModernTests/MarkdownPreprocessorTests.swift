//
//  MarkdownPreprocessorTests.swift
//  iTerm2 ModernTests
//
//  The imgcat Markdown porthole renders with SwiftyMarkdown, which understands
//  a narrow dialect. MarkdownPreprocessor rewrites common Markdown into that
//  dialect before rendering. These tests pin down the rewrites.
//

import XCTest
@testable import iTerm2SharedARC

final class MarkdownPreprocessorTests: XCTestCase {
    private func normalize(_ s: String) -> String {
        return MarkdownPreprocessor.normalize(s)
    }

    // An ordered item as the preprocessor emits it: “1. ” plus the encoded real number.
    private func item(_ n: Int, _ text: String, level: Int = 0) -> String {
        return String(repeating: "\t", count: level) + "1. " + MarkdownPreprocessor.encodedOrderedNumber(n) + text
    }

    private func restored(_ s: String) -> String {
        let attributed = NSMutableAttributedString(string: s)
        MarkdownPreprocessor.restorePlaceholders(in: attributed)
        return attributed.string
    }

    // MARK: Paragraph reflow

    func testWrappedParagraphLinesAreJoined() {
        XCTAssertEqual(normalize("one two\nthree four\n\nfive"),
                       "one two three four\n\nfive")
    }

    private let br = MarkdownPreprocessor.lineBreak

    func testTrailingDoubleSpaceIsAHardBreak() {
        XCTAssertEqual(normalize("one  \ntwo\nthree"), "one" + br + "two three")
    }

    func testTrailingBackslashIsAHardBreak() {
        XCTAssertEqual(normalize("one\\\ntwo"), "one" + br + "two")
    }

    func testHardBreakInsideListItemAndQuote() {
        XCTAssertEqual(normalize("- a  \n  b"), "- a" + br + "b")
        XCTAssertEqual(normalize("> a  \n> b"), "> a" + br + "b")
    }

    func testHardBreakBeforeBlankLineIsDropped() {
        XCTAssertEqual(normalize("a  \n\nb"), "a\n\nb")
    }

    func testHeadingIsNotJoinedToFollowingText() {
        XCTAssertEqual(normalize("# Title\ntext"), "# Title\ntext")
    }

    func testSetextUnderlineIsPreserved() {
        XCTAssertEqual(normalize("Title\n=====\n\nSub\n---"), "Title\n===\n\nSub\n---")
    }

    func testReferenceDefinitionIsNotJoined() {
        XCTAssertEqual(normalize("see [docs][d]\n[d]: https://example.com/"),
                       "see [docs][d]\n[d]: https://example.com/")
    }

    // MARK: Code

    func testFencedCodeIsLeftAlone() {
        let md = "```swift\nlet a_b = *x*\n\nmore  \n```"
        XCTAssertEqual(normalize(md), "```\nlet a_b = *x*\n \nmore  \n```")
    }

    func testTildeFenceBecomesBacktickFence() {
        XCTAssertEqual(normalize("~~~\ncode\n~~~"), "```\ncode\n```")
    }

    func testIndentedFenceIsDedented() {
        XCTAssertEqual(normalize("1. item\n\n   ```\n   code\n   ```"),
                       item(1, "item") + "\n\n```\ncode\n```")
    }

    func testBlankLinesInsideFencesBecomeSpaces() {
        XCTAssertEqual(normalize("```\na\n\nb\n```"), "```\na\n \nb\n```")
    }

    func testBlankLinesInsideIndentedCodeKeepTheBlockTogether() {
        XCTAssertEqual(normalize("    a\n\n    b\n\npara"), "    a\n     \n    b\n\npara")
    }

    func testIndentedCodeBlockIsPreserved() {
        XCTAssertEqual(normalize("para\n\n    for i in x:\n        print(i)\n\nafter"),
                       "para\n\n    for i in x:\n        print(i)\n\nafter")
    }

    func testShorterFenceDoesNotCloseLongerOne() {
        let normalized = normalize("````\n```swift\nlet x = 1\n```\n````\nafter")
        let lines = normalized.components(separatedBy: "\n")
        // SwiftyMarkdown ends a code block at any line that is exactly ```, so the
        // inner closing fence must not reach it as one.
        XCTAssertEqual(lines.filter { $0 == "```" }.count, 2)
        XCTAssertEqual(restored(normalized), "```\n```swift\nlet x = 1\n```\n```\nafter")
    }

    func testIndentedCodeAfterHeading() {
        XCTAssertEqual(normalize("# Title\n    code line\n    code2"),
                       "# Title\n    code line\n    code2")
    }

    func testIndentedCodeContainingTableIsCode() {
        XCTAssertEqual(normalize("    a | b\n    --|--"), "    a | b\n    --|--")
    }

    func testIndentedFenceInIndentedCodeIsCode() {
        XCTAssertEqual(normalize("Example:\n\n    ```python\n    print(1)\n    ```\n\nafter"),
                       "Example:\n\n    ```python\n    print(1)\n    ```\n\nafter")
    }

    func testIndentedFenceLineInsideFenceIsContent() {
        XCTAssertEqual(normalize("```\n    ```\ncode\n```\nafter"),
                       "```\n    ```\ncode\n```\nafter")
    }

    func testInlineCodeIsNotTransformed() {
        XCTAssertEqual(normalize("use `a_b_c` and `&amp;`"), "use `a_b_c` and `&amp;`")
    }

    // MARK: Lists

    func testOrderedListNumbersAreEncoded() {
        XCTAssertEqual(normalize("1. a\n2. b\n10. c"),
                       [item(1, "a"), item(2, "b"), item(3, "c")].joined(separator: "\n"))
    }

    func testOrderedListStartsAtFirstNumber() {
        XCTAssertEqual(normalize("5. a\n6. b"), [item(5, "a"), item(6, "b")].joined(separator: "\n"))
    }

    func testOrderedListWithParenMarker() {
        XCTAssertEqual(normalize("1) a\n2) b"), [item(1, "a"), item(2, "b")].joined(separator: "\n"))
    }

    func testNumberingContinuesAcrossIndentedBlocks() {
        let md = "1. a\n\n   ```\n   code\n   ```\n\n2. b\n\n   > quote\n\n3. c"
        XCTAssertEqual(normalize(md),
                       item(1, "a") + "\n\n```\ncode\n```\n\n" + item(2, "b") + "\n\n> quote\n\n" + item(3, "c"))
    }

    func testNumberingRestartsAfterAParagraphAtTheMargin() {
        XCTAssertEqual(normalize("1. a\n\npara\n\n1. b"),
                       item(1, "a") + "\n\npara\n\n" + item(1, "b"))
    }

    func testPlusAndStarBulletsBecomeDashes() {
        XCTAssertEqual(normalize("* a\n+ b\n- c"), "- a\n- b\n- c")
    }

    func testSpaceIndentedNestedListsBecomeTabIndented() {
        XCTAssertEqual(normalize("- a\n    - b\n        - c\n- d"),
                       "- a\n\t- b\n\t\t- c\n- d")
    }

    func testTwoSpaceIndentedNestedListsBecomeTabIndented() {
        XCTAssertEqual(normalize("- a\n  - b\n    - c"), "- a\n\t- b\n\t\t- c")
    }

    func testNestedOrderedListUsesTabs() {
        XCTAssertEqual(normalize("1. a\n    1. b\n    2. c\n2. d"),
                       [item(1, "a"), item(1, "b", level: 1), item(2, "c", level: 1), item(2, "d")].joined(separator: "\n"))
    }

    func testIndentationInsideCodeDoesNotAffectListNesting() {
        let md = "```yaml\nsteps:\n  - name: build\n```\n\n- a\n    - b"
        XCTAssertEqual(normalize(md), "```\nsteps:\n  - name: build\n```\n\n- a\n\t- b")
    }

    func testTwoAndFourSpaceListsInOneDocument() {
        XCTAssertEqual(normalize("- a\n  - b\n\npara\n\n- c\n    - d\n        - e"),
                       "- a\n\t- b\n\npara\n\n- c\n\t- d\n\t\t- e")
    }

    func testItemBetweenColumnsNestsUnderNearestParent() {
        XCTAssertEqual(normalize("- a\n    - b\n  - c"), "- a\n\t- b\n\t- c")
    }

    func testListItemContinuationLinesAreJoined() {
        XCTAssertEqual(normalize("- a long\n  item\n- b"), "- a long item\n- b")
    }

    func testSecondContinuationParagraphIsNotCode() {
        XCTAssertEqual(normalize("1. Step one\n\n    More detail.\n\n    Even more detail."),
                       item(1, "Step one") + "\n\nMore detail.\n\nEven more detail.")
    }

    func testNestedItemAfterContinuationParagraphIsNotCode() {
        XCTAssertEqual(normalize("- a\n\n    detail\n\n    - sub"),
                       "- a\n\ndetail\n\n\t- sub")
    }

    func testCodeIndentedPastListContentIsCode() {
        XCTAssertEqual(normalize("- a\n\n      code"),
                       "- a\n\n    code")
    }

    func testNumberOtherThanOneDoesNotInterruptParagraph() {
        XCTAssertEqual(normalize("The project was first released in\n2020. It has since grown a lot."),
                       "The project was first released in 2020. It has since grown a lot.")
    }

    func testOneAndBulletsInterruptParagraph() {
        XCTAssertEqual(normalize("a\n1. b"), "a\n" + item(1, "b"))
        XCTAssertEqual(normalize("a\n- b"), "a\n- b")
    }

    func testSiblingItemAfterContinuationParagraph() {
        XCTAssertEqual(normalize("1. one\n\n   para in item\n2. two"),
                       item(1, "one") + "\n\npara in item\n" + item(2, "two"))
    }

    func testBlankLinesBetweenListItemsAreDropped() {
        XCTAssertEqual(normalize("1. a\n\n2. b"), item(1, "a") + "\n" + item(2, "b"))
    }

    func testTaskListMarkersBecomeCheckboxGlyphs() {
        XCTAssertEqual(normalize("- [x] done\n- [ ] todo\n- [X] also"),
                       "- ☑ done\n- ☐ todo\n- ☑ also")
    }

    // MARK: Blockquotes

    func testBlockquoteLinesAreJoined() {
        XCTAssertEqual(normalize("> one\n> two\n>\n> three"), "> one two\n\n> three")
    }

    func testNestedBlockquoteIsFlattened() {
        XCTAssertEqual(normalize("> > inner"), "> inner")
    }

    // MARK: Thematic breaks

    func testStarAndUnderscoreRulesBecomeDashes() {
        XCTAssertEqual(normalize("a\n\n***\n\nb\n\n___\n\nc\n\n- - -"),
                       "a\n\n----\n\nb\n\n----\n\nc\n\n----")
    }

    func testRuleAtStartIsNotFrontMatter() {
        // SwiftyMarkdown treats an exact “---” first line as YAML front matter and
        // drops everything up to the next “---”.
        XCTAssertEqual(normalize("***\nHello"), "----\nHello")
    }

    func testFrontMatterIsRemoved() {
        XCTAssertEqual(normalize("---\ntitle: x\nlayout: post\n---\n\nHello"), "Hello")
    }

    func testFrontMatterClosedWithDotsIsRemoved() {
        XCTAssertEqual(normalize("---\ntitle: x\n...\nHello"), "Hello")
    }

    func testRuleWithoutBlankLineBeforeGetsOne() {
        XCTAssertEqual(normalize("a\n***\nb"), "a\n\n----\nb")
    }

    func testDashesDirectlyUnderTextStaySetextHeading() {
        XCTAssertEqual(normalize("a\n---\nb"), "a\n---\nb")
    }

    // MARK: Tables

    func testTableRowsGetOuterPipes() {
        XCTAssertEqual(normalize("Name | Value\n---- | -----\nfoo | 1"),
                       "| Name | Value |\n| ---- | ----- |\n| foo | 1 |")
    }

    func testTableWithPipesIsUnchanged() {
        let md = "| a | b |\n|---|---|\n| 1 | 2 |"
        XCTAssertEqual(normalize(md), md)
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
        XCTAssertEqual(normalize("a<br>b\nc"), "a" + br + "b c")
    }

    func testBlockHTMLTagsAreStripped() {
        XCTAssertEqual(normalize("<div align=\"center\">x</div>"), "x")
    }

    func testRemoteImagesBecomeLinks() {
        XCTAssertEqual(normalize("![alt](https://x/y.png) ![](http://x/z.png) ![r][missing]"),
                       "[alt](https://x/y.png) [z.png](http://x/z.png) [r][missing]")
    }

    func testLocalImagesBecomePlaceholders() {
        let result = MarkdownPreprocessor.process("a ![one](img/a_b.png) b ![two](<my pic.png> \"t\")")
        XCTAssertEqual(result.text,
                       "a " + MarkdownPreprocessor.encodedImage(0) + " b " + MarkdownPreprocessor.encodedImage(1))
        XCTAssertEqual(result.images, [MarkdownPreprocessor.Image(alt: "one", source: "img/a_b.png"),
                                       MarkdownPreprocessor.Image(alt: "two", source: "my pic.png")])
    }

    func testFileAndDataURLImagesAreLocal() {
        let result = MarkdownPreprocessor.process("![f](file:///tmp/x.png) ![d](data:image/png;base64,AAAA)")
        XCTAssertEqual(result.images.map(\.source), ["file:///tmp/x.png", "data:image/png;base64,AAAA"])
    }

    func testReferenceImagesResolve() {
        let md = "![local][a] ![remote][B] ![a][]\n\n[a]: pic.png\n[b]: https://x/y.png"
        let result = MarkdownPreprocessor.process(md)
        XCTAssertEqual(result.text,
                       MarkdownPreprocessor.encodedImage(0) + " [remote](https://x/y.png) " + MarkdownPreprocessor.encodedImage(1) +
                       "\n\n[a]: pic.png\n[b]: https://x/y.png")
        XCTAssertEqual(result.images.map(\.source), ["pic.png", "pic.png"])
    }

    func testImagesInsideCodeSpansAreLeftAlone() {
        let result = MarkdownPreprocessor.process("`![x](y.png)`")
        XCTAssertEqual(result.text, "`![x](y.png)`")
        XCTAssertTrue(result.images.isEmpty)
    }

    func testFootnotesBecomeSuperscripts() {
        XCTAssertEqual(normalize("text[^1] more[^12]\n\n[^1]: note one\n[^12]: note twelve"),
                       "text¹ more¹²\n\n¹ note one\n¹² note twelve")
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
