//
//  PTYSessionLineStyleRunTests.swift
//  iTerm2 ModernTests
//
//  stringForLine:length:eaIndex:cppsArray:stylesArray: run-length-encodes cell
//  styles. Coalescing a cell into the preceding run requires both the
//  screen_char_t attributes and the external attribute to match, so a cell that
//  carries no external attribute must never join a run whose style came from
//  one. These tests pin that: an underline color, a block ID, or an OSC 8 URL
//  must stop at the end of its own run instead of bleeding onto the plain cells
//  that follow.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionLineStyleRunTests: XCTestCase {
    private func underlineColorAttribute() -> iTermExternalAttribute? {
        let color = VT100TerminalColorValue(red: 11, green: 22, blue: 33, mode: ColorMode24bit,
                                            hasDarkVariant: false, redDark: 0, greenDark: 0, blueDark: 0)
        return iTermExternalAttribute(havingUnderlineColor: true,
                                      underlineColor: color,
                                      url: nil,
                                      blockIDList: nil,
                                      controlCode: nil,
                                      dualModeForeground: iTermDualModeColor(),
                                      dualModeBackground: iTermDualModeColor())
    }

    private func blockIDAttribute(_ blockID: String) -> iTermExternalAttribute? {
        return iTermExternalAttribute(havingUnderlineColor: false,
                                      underlineColor: VT100TerminalColorValue(),
                                      url: nil,
                                      blockIDList: blockID,
                                      controlCode: nil,
                                      dualModeForeground: iTermDualModeColor(),
                                      dualModeBackground: iTermDualModeColor())
    }

    private func urlAttribute() -> iTermExternalAttribute? {
        let url = iTermURL(url: URL(string: "https://example.com/osc8-test")!,
                           identifier: "42",
                           target: nil)
        return iTermExternalAttribute(havingUnderlineColor: false,
                                      underlineColor: VT100TerminalColorValue(),
                                      url: url,
                                      blockIDList: nil,
                                      controlCode: nil,
                                      dualModeForeground: iTermDualModeColor(),
                                      dualModeBackground: iTermDualModeColor())
    }

    // Builds a line of plain ASCII cells (identical screen_char_t attributes, so
    // only the external attributes can break a run) and returns its text and
    // styles.
    private func encode(text: String,
                        attributes: [Int: iTermExternalAttribute]) -> (text: String, styles: [ITMCellStyle]) {
        var chars = text.utf16.map { code -> screen_char_t in
            var c = screen_char_t()
            c.code = code
            return c
        }
        let eaIndex = iTermExternalAttributeIndex()
        for (index, attribute) in attributes {
            eaIndex.setAttributes(attribute, at: Int32(index), count: 1)
        }
        let cpps = NSMutableArray()
        let styles = NSMutableArray()
        let result = chars.withUnsafeMutableBufferPointer { buffer -> String in
            return PTYSession.string(forLine: buffer.baseAddress!,
                                     length: Int32(buffer.count),
                                     eaIndex: eaIndex,
                                     cppsArray: cpps,
                                     stylesArray: styles)
        }
        return (result, styles.compactMap { $0 as? ITMCellStyle })
    }

    private func totalCells(_ styles: [ITMCellStyle]) -> UInt32 {
        return styles.reduce(0) { $0 + $1.repeats }
    }

    func testUnderlineColorDoesNotLeakPastItsRun() {
        guard let ea = underlineColorAttribute() else {
            XCTFail("expected non-nil external attribute"); return
        }
        // Cell 0 is underlined; cells 1 and 2 are plain.
        let (text, styles) = encode(text: "abc", attributes: [0: ea])
        XCTAssertEqual(text, "abc")
        XCTAssertEqual(totalCells(styles), 3)
        XCTAssertEqual(styles.count, 2, "the underlined cell and the plain cells are different styles")
        XCTAssertTrue(styles[0].hasUnderlineColor)
        XCTAssertEqual(styles[0].repeats, 1, "the underline color must not extend past cell 0")
        XCTAssertFalse(styles[1].hasUnderlineColor, "plain cells must not inherit the underline color")
        XCTAssertEqual(styles[1].repeats, 2)
    }

    func testBlockIDDoesNotLeakPastItsRun() {
        guard let ea = blockIDAttribute("block-1") else {
            XCTFail("expected non-nil external attribute"); return
        }
        let (text, styles) = encode(text: "abc", attributes: [0: ea])
        XCTAssertEqual(text, "abc")
        XCTAssertEqual(totalCells(styles), 3)
        XCTAssertEqual(styles.count, 2)
        XCTAssertTrue(styles[0].hasBlockId)
        XCTAssertEqual(styles[0].blockId, "block-1")
        XCTAssertEqual(styles[0].repeats, 1, "the block ID must not extend past cell 0")
        XCTAssertFalse(styles[1].hasBlockId, "plain cells must not inherit the block ID")
        XCTAssertEqual(styles[1].repeats, 2)
    }

    func testURLDoesNotLeakPastItsRun() {
        guard let ea = urlAttribute() else {
            XCTFail("expected non-nil external attribute"); return
        }
        let (text, styles) = encode(text: "abc", attributes: [0: ea])
        XCTAssertEqual(text, "abc")
        XCTAssertEqual(totalCells(styles), 3)
        XCTAssertEqual(styles.count, 2)
        XCTAssertTrue(styles[0].hasURL)
        XCTAssertEqual(styles[0].repeats, 1, "the hyperlink must not extend past cell 0")
        XCTAssertFalse(styles[1].hasURL, "plain cells must not inherit the hyperlink")
        XCTAssertEqual(styles[1].repeats, 2)
    }

    // A link in the middle of a line: the cells on both sides are plain and must
    // be reported as such.
    func testExternalAttributeRunIsBoundedOnBothSides() {
        guard let ea = urlAttribute() else {
            XCTFail("expected non-nil external attribute"); return
        }
        let (text, styles) = encode(text: "abcde", attributes: [2: ea])
        XCTAssertEqual(text, "abcde")
        XCTAssertEqual(totalCells(styles), 5)
        XCTAssertEqual(styles.count, 3)
        XCTAssertFalse(styles[0].hasURL)
        XCTAssertEqual(styles[0].repeats, 2)
        XCTAssertTrue(styles[1].hasURL)
        XCTAssertEqual(styles[1].repeats, 1)
        XCTAssertFalse(styles[2].hasURL)
        XCTAssertEqual(styles[2].repeats, 2)
    }

    // The flip side of the same comparison: adjacent cells carrying equal
    // external attributes belong to one run.
    func testIdenticalAdjacentExternalAttributesCoalesce() {
        guard let first = urlAttribute(), let second = urlAttribute() else {
            XCTFail("expected non-nil external attributes"); return
        }
        let (text, styles) = encode(text: "abc", attributes: [0: first, 1: second])
        XCTAssertEqual(text, "abc")
        XCTAssertEqual(totalCells(styles), 3)
        XCTAssertEqual(styles.count, 2)
        XCTAssertTrue(styles[0].hasURL)
        XCTAssertEqual(styles[0].repeats, 2, "equal hyperlinks on adjacent cells are one run")
        XCTAssertFalse(styles[1].hasURL)
        XCTAssertEqual(styles[1].repeats, 1)
    }

    // Different links on adjacent cells must not merge.
    func testDifferentAdjacentExternalAttributesDoNotCoalesce() {
        guard let first = urlAttribute(), let second = blockIDAttribute("block-1") else {
            XCTFail("expected non-nil external attributes"); return
        }
        let (text, styles) = encode(text: "ab", attributes: [0: first, 1: second])
        XCTAssertEqual(text, "ab")
        XCTAssertEqual(totalCells(styles), 2)
        XCTAssertEqual(styles.count, 2)
        XCTAssertTrue(styles[0].hasURL)
        XCTAssertFalse(styles[0].hasBlockId)
        XCTAssertFalse(styles[1].hasURL)
        XCTAssertTrue(styles[1].hasBlockId)
    }
}
