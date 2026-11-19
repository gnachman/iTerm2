//
//  LightweightHTMLParserTests.swift
//  ModernTests
//
//  The lightweight HTML parser used by HTML tab titles and rich tab content
//  lines: <b>, <i>, <u>, <font color>, and a few entities.
//

import XCTest
@testable import iTerm2SharedARC

final class LightweightHTMLParserTests: XCTestCase {
    private let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12),
                                                       .foregroundColor: NSColor.textColor]

    private func parse(_ html: String) -> NSAttributedString {
        return NSAttributedString.fromLightweightHTML(html, attributes: base)
    }

    private func color(_ string: NSAttributedString, at index: Int) -> NSColor? {
        return string.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    private func assertColor(_ actual: NSColor?, _ hex: (CGFloat, CGFloat, CGFloat),
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let srgb = actual?.usingColorSpace(.sRGB) else {
            XCTFail("no color", file: file, line: line)
            return
        }
        XCTAssertEqual(srgb.redComponent, hex.0, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(srgb.greenComponent, hex.1, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(srgb.blueComponent, hex.2, accuracy: 0.01, file: file, line: line)
    }

    func testFontColor() {
        let result = parse("<font color=\"#ff8000\">red</font> plain")
        XCTAssertEqual(result.string, "red plain")
        assertColor(color(result, at: 0), (1, 0.5, 0))
        XCTAssertEqual(color(result, at: 4), NSColor.textColor)
    }

    func testSpacesAroundAQuotedColor() {
        let result = parse("<font color=\" #f00 \">x</font>")
        XCTAssertEqual(result.string, "x")
        assertColor(color(result, at: 0), (1, 0, 0))
    }

    func testShortHexAndSingleQuotesAndCase() {
        let result = parse("<FONT COLOR='#0f0'>x</FONT>y")
        XCTAssertEqual(result.string, "xy")
        assertColor(color(result, at: 0), (0, 1, 0))
        XCTAssertEqual(color(result, at: 1), NSColor.textColor)
    }

    // As in HTML, a value without spaces needs no quotes.
    func testUnquotedColor() {
        let result = parse("<font color=#00f>x</font>y")
        XCTAssertEqual(result.string, "xy")
        assertColor(color(result, at: 0), (0, 0, 1))
        XCTAssertEqual(color(result, at: 1), NSColor.textColor)
    }

    // A color from a variable may be empty when there's none to show, quoted
    // or not.
    func testEmptyOrInvalidColorKeepsTheNormalColor() {
        for html in ["<font color=\"\">x</font>", "<font color=\"bogus\">x</font>", "<font color=>x</font>"] {
            let result = parse(html)
            XCTAssertEqual(result.string, "x", html)
            XCTAssertEqual(color(result, at: 0), NSColor.textColor, html)
        }
    }

    func testNestedColorsRestoreTheOuterOne() {
        let result = parse("<font color=\"#ff0000\">a<font color=\"#0000ff\">b</font>c</font>d")
        XCTAssertEqual(result.string, "abcd")
        assertColor(color(result, at: 0), (1, 0, 0))
        assertColor(color(result, at: 1), (0, 0, 1))
        assertColor(color(result, at: 2), (1, 0, 0))
        XCTAssertEqual(color(result, at: 3), NSColor.textColor)
    }

    func testColorAndBoldCombine() {
        let result = parse("<b><font color=\"#ff0000\">x</font></b>")
        assertColor(color(result, at: 0), (1, 0, 0))
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
    }

    // Everything iterm2.escape_html() produces.
    func testEntities() {
        XCTAssertEqual(parse("&lt;&gt;&quot;&#39;&amp;lt;").string, "<>\"'&lt;")
    }

    // Text whose only markup closes a tag, as one row of a wrapping line may,
    // is markup too.
    func testOnlyClosingTags() {
        XCTAssertEqual(parse("x</b>").string, "x")
        XCTAssertEqual(parse("x</font>").string, "x")
    }

    func testTextWithoutMarkupIsUnchanged() {
        let result = parse("a < b")
        XCTAssertEqual(result.string, "a < b")
    }
}
