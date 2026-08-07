//
//  CodexTitleStatusDecoderTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class CodexTitleStatusDecoderTests: XCTestCase {

    func testBrailleSpinnerPrefix_isWorking() {
        XCTAssertTrue(CodexTitleStatusDecoder.isWorkingTitle("⠙ iTerm2"))
        XCTAssertTrue(CodexTitleStatusDecoder.isWorkingTitle("⠹ iTerm2"))
        XCTAssertTrue(CodexTitleStatusDecoder.isWorkingTitle("⠇ iTerm2"))
        XCTAssertTrue(CodexTitleStatusDecoder.isWorkingTitle("⠿ Some Project"))
    }

    func testPlainTitle_isNotWorking() {
        XCTAssertFalse(CodexTitleStatusDecoder.isWorkingTitle("iTerm2"))
        XCTAssertFalse(CodexTitleStatusDecoder.isWorkingTitle("Some Project"))
    }

    func testEmptyTitle_isNotWorking() {
        XCTAssertFalse(CodexTitleStatusDecoder.isWorkingTitle(""))
    }

    func testBrailleWithoutSpace_isNotWorking() {
        // A braille glyph at position 0 but no following space - not Codex's format.
        XCTAssertFalse(CodexTitleStatusDecoder.isWorkingTitle("⠙iTerm2"))
        XCTAssertFalse(CodexTitleStatusDecoder.isWorkingTitle("⠙"))
    }

    func testBrailleNotAtStart_isNotWorking() {
        // Braille not at position 0 doesn't count - prevents matching titles that
        // legitimately contain a braille character later.
        XCTAssertFalse(CodexTitleStatusDecoder.isWorkingTitle(" ⠙ iTerm2"))
        XCTAssertFalse(CodexTitleStatusDecoder.isWorkingTitle("foo ⠙ bar"))
    }

    func testOtherUnicodeSpinners_areNotWorking() {
        // Only U+2800..U+28FF Braille Patterns count. Other spinner glyphs from
        // different libraries (e.g. unicode block elements, geometric shapes) don't.
        XCTAssertFalse(CodexTitleStatusDecoder.isWorkingTitle("◐ Working"))
        XCTAssertFalse(CodexTitleStatusDecoder.isWorkingTitle("◓ Working"))
        XCTAssertFalse(CodexTitleStatusDecoder.isWorkingTitle("| Working"))
        XCTAssertFalse(CodexTitleStatusDecoder.isWorkingTitle("/ Working"))
    }

    func testJustOutsideBrailleBlock_isNotWorking() {
        // Glyphs adjacent to the Braille Patterns block must not match: that pins
        // the boundary so a future widening (e.g. accidentally including arrows
        // or geometric shapes) shows up as a test failure rather than a quiet
        // overreach.
        let beforeBlock = Unicode.Scalar(0x27FF)!
        let afterBlock = Unicode.Scalar(0x2900)!
        XCTAssertFalse(CodexTitleStatusDecoder.isWorkingTitle("\(beforeBlock) project"))
        XCTAssertFalse(CodexTitleStatusDecoder.isWorkingTitle("\(afterBlock) project"))
    }

    func testWordsAloneAreNotWorking() {
        // The second-opinion's main worry: bare 'Working' / 'Thinking' / 'Ready' must not match.
        XCTAssertFalse(CodexTitleStatusDecoder.isWorkingTitle("Working"))
        XCTAssertFalse(CodexTitleStatusDecoder.isWorkingTitle("Thinking"))
        XCTAssertFalse(CodexTitleStatusDecoder.isWorkingTitle("Ready"))
        XCTAssertFalse(CodexTitleStatusDecoder.isWorkingTitle("Working on PR #123"))
    }
}
