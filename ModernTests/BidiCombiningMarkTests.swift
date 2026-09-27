//
//  BidiCombiningMarkTests.swift
//  ModernTests
//
//  A combining mark stored in a complex cell (e.g. کاملاً = …لا + U+064B
//  FATHATAN merged into the alef's cell) must not perturb the visual cell
//  mapping. The lam-alef ligature collapses two cells into one glyph and the
//  mark is a zero-width glyph credited to the alef's cell; the LUT must still
//  place the word's cells in strictly right-to-left order.
//

import XCTest
@testable import iTerm2SharedARC

class BidiCombiningMarkTests: XCTestCase {
    private func setBidiPreference(_ enabled: Bool) {
        iTermPreferences.setBool(enabled, forKey: kPreferenceKeyBidi)
        let deadline = Date().addingTimeInterval(0.5)
        while iTermPreferences.bidiEnabled() != enabled && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }

    override func setUp() { super.setUp(); setBidiPreference(true) }
    override func tearDown() { setBidiPreference(false); super.tearDown() }

    private func assertAdjacentRTL(_ s: String, cells: ClosedRange<Int32>,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let sca = screenCharArrayWithDefaultStyle(s, eol: EOL_HARD)
        guard let info = BidiDisplayInfoObjc(sca) else {
            return XCTFail("no bidi info", file: file, line: line)
        }
        for cell in cells {
            let here = info.visualForLogical(cell)
            let next = info.visualForLogical(cell + 1)
            XCTAssertEqual(next, here - 1,
                           "cell \(cell)→\(here), cell \(cell + 1)→\(next); expected adjacent RTL cells",
                           file: file, line: line)
        }
    }

    func testLamAlefWithFathatanKeepsCellsInRTLOrder() {
        // «کاملاً درست.»: the word ends in lam + alef + fathatan. The mark
        // merges into the alef's cell; the lam-alef ligature consumes the
        // alef's glyph. Cells of کاملاً: ک=23 ا=24 م=25 ل=26 اً=27, space=28.
        assertAdjacentRTL("آیا این درست است؟ بله؛ کاملاً درست.",
                          cells: 23...27)
    }

    func testLamAlefWithoutMarkKeepsCellsInRTLOrder() {
        // Control: lam-alef with no mark. Cells of سلام: س=0 ل=1 ا=2 م=3, space=4.
        assertAdjacentRTL("سلام خوب", cells: 0...3)
    }
}
