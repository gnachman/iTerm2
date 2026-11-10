//
//  FoldSummaryLineTests.swift
//  iTerm2
//
//  Tests for the single line that replaces a folded region:
//  [first line] …N lines… [last line].
//

import XCTest
@testable import iTerm2SharedARC

final class FoldSummaryLineTests: XCTestCase {
    private let width: Int32 = 40

    private func makeLine(_ text: String,
                          background: UInt32? = nil,
                          doubleWidth: Bool = false,
                          attribute: iTermExternalAttribute? = nil) -> ScreenCharArray {
        var cells = [screen_char_t]()
        for unit in text.utf16 {
            var c = screen_char_t()
            c.code = unit
            c.foregroundColorMode = ColorModeAlternate.rawValue
            c.foregroundColor = UInt32(ALTSEM_DEFAULT)
            if let background {
                c.backgroundColorMode = ColorModeNormal.rawValue
                c.backgroundColor = background
            } else {
                c.backgroundColorMode = ColorModeAlternate.rawValue
                c.backgroundColor = UInt32(ALTSEM_DEFAULT)
            }
            cells.append(c)
            if doubleWidth {
                var spacer = c
                ScreenCharSetDWL_SPACER(&spacer)
                cells.append(spacer)
            }
        }
        var continuation = screen_char_t()
        continuation.code = UInt16(EOL_HARD)
        let result = cells.withUnsafeBufferPointer { buffer in
            MutableScreenCharArray(copyOfLine: buffer.baseAddress!,
                                   length: Int32(buffer.count),
                                   continuation: continuation)
        }
        if let attribute {
            let eaIndex = iTermExternalAttributeIndex()
            eaIndex.setAttributes(attribute, at: 0, count: Int32(cells.count))
            result.setExternalAttributesIndex(eaIndex)
        }
        return result
    }

    private func urlAttribute() -> iTermExternalAttribute {
        return iTermExternalAttribute(havingUnderlineColor: false,
                                      underlineColor: VT100TerminalColorValue(red: 0, green: 0, blue: 0, mode: ColorModeAlternate, hasDarkVariant: false, redDark: 0, greenDark: 0, blueDark: 0),
                                      url: iTermURL(url: URL(string: "https://example.com/")!, identifier: nil, target: nil),
                                      blockIDList: nil,
                                      controlCode: nil,
                                      dualModeForeground: iTermDualModeColor(),
                                      dualModeBackground: iTermDualModeColor())!
    }

    private func isMuted(_ c: screen_char_t) -> Bool {
        return c.faint != 0 && c.italic != 0 &&
            c.backgroundColorMode == ColorModeAlternate.rawValue &&
            c.backgroundColor == UInt32(ALTSEM_DEFAULT)
    }

    func testFirstLineKeepsItsColorsAndTheRestIsMuted() {
        let summary = PTYTextView.firstEllipsisLast(makeLine("$ ls", background: 5),
                                                    makeLine("out"),
                                                    length: width,
                                                    count: 3)
        XCTAssertEqual(summary.length, width)
        for i in 0..<4 {
            let c = summary.line[i]
            XCTAssertEqual(c.backgroundColorMode, ColorModeNormal.rawValue, "cell \(i)")
            XCTAssertEqual(c.backgroundColor, 5, "cell \(i)")
            XCTAssertEqual(c.faint, 0, "cell \(i)")
            XCTAssertEqual(c.italic, 0, "cell \(i)")
        }
        for i in 4..<Int(summary.length) {
            XCTAssertTrue(isMuted(summary.line[i]), "cell \(i)")
        }
    }

    func testDoubleWidthFirstLineBecomesSingleWidth() {
        let attribute = urlAttribute().copy(with: iTermLineAttribute.doubleHeightTop)
        let summary = PTYTextView.firstEllipsisLast(makeLine("AB", doubleWidth: true, attribute: attribute),
                                                    makeLine(""),
                                                    length: width,
                                                    count: 1)
        XCTAssertEqual(summary.length, width)
        XCTAssertEqual(summary.line[0].code, UInt16(UInt8(ascii: "A")))
        XCTAssertEqual(summary.line[1].code, UInt16(UInt8(ascii: "B")))
        for i in 0..<Int(summary.length) {
            XCTAssertFalse(ScreenCharIsDWL_SPACER(summary.line[i]), "cell \(i)")
        }

        // Other attributes survive, but not the line attribute, which would make the whole
        // summary double height once it is in scrollback.
        let eaIndex = summary.eaIndex
        XCTAssertNotNil(eaIndex?.attribute(at: 0)?.url)
        XCTAssertEqual(eaIndex?.attribute(at: 0)?.lineAttribute, iTermLineAttribute.singleWidth)
        XCTAssertEqual(eaIndex?.uniformLineAttribute() ?? .singleWidth, iTermLineAttribute.singleWidth)
    }

    func testFirstLineAttributesDoNotSpillPastTheFirstLine() {
        // The first line is too long to fit, so it is truncated. Its attributes from beyond the
        // truncation point must not land on the marker or the last line.
        let first = makeLine(String(repeating: "x", count: 60), attribute: urlAttribute())
        let summary = PTYTextView.firstEllipsisLast(first,
                                                    makeLine("yyyy"),
                                                    length: width,
                                                    count: 10)
        XCTAssertEqual(summary.length, width)
        XCTAssertNotNil(summary.eaIndex?.attribute(at: 0)?.url)
        for i in 0..<Int(summary.length) where isMuted(summary.line[i]) {
            XCTAssertNil(summary.eaIndex?.attribute(at: Int32(i))?.url, "cell \(i)")
        }
    }
}
