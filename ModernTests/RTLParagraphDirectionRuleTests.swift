//
//  RTLParagraphDirectionRuleTests.swift
//  ModernTests
//
//  Paragraph direction detection: first-strong by default, plus the optional
//  advanced setting that lays a line that starts left-to-right out
//  right-to-left once it holds a minimum number of right-to-left words.
//

import XCTest
@testable import iTerm2SharedARC

class RTLParagraphDirectionRuleTests: XCTestCase {
    private let keys = ["DetectParagraphDirection", "RtlParagraphMinimumWords"]

    // Runs `body` with the given minimum, then restores whatever the test
    // defaults domain held before.
    private func withMinimumWords(_ minimum: Int, detect: Bool = true, _ body: () -> Void) {
        let d = iTermUserDefaults.userDefaults()
        let saved = keys.map { d.object(forKey: $0) }
        d.set(detect, forKey: "DetectParagraphDirection")
        d.set(minimum, forKey: "RtlParagraphMinimumWords")
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
            }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        body()
    }

    private func bidiInfo(_ line: String) -> BidiDisplayInfoObjc? {
        return BidiDisplayInfoObjc(screenCharArrayWithDefaultStyle(line, eol: EOL_HARD))
    }

    // A line with no right-to-left characters has no bidi info at all.
    private func isRTL(_ line: String) -> Bool {
        return bidiInfo(line)?.paragraphIsRTL ?? false
    }

    // A list item the way a TUI prints it: Latin label, then three Persian words.
    private let listItemWithThreeRTLWords = "- UI-6: Deploy در دو مرحله."
    // An English sentence quoting one Persian word.
    private let englishWithOneRTLWord = "The word سلام means hello in Persian."
    // Opens with a Persian word and ends in English.
    private let persianOpening = "سلام دنیا means hello world"

    func testDefaultIsFirstStrong() {
        withMinimumWords(0) {
            XCTAssertNotNil(bidiInfo(listItemWithThreeRTLWords), "probe: a mixed line has bidi info")
            XCTAssertFalse(isRTL(listItemWithThreeRTLWords), "opens LTR, stays LTR")
            XCTAssertFalse(isRTL(englishWithOneRTLWord), "opens LTR, stays LTR")
            XCTAssertTrue(isRTL(persianOpening), "opens RTL, is RTL")
            XCTAssertFalse(isRTL("plain English"), "no RTL characters")
        }
    }

    func testLineOpeningLTRFlipsAtTheMinimum() {
        withMinimumWords(3) {
            XCTAssertTrue(isRTL(listItemWithThreeRTLWords), "three RTL words meet a minimum of 3")
            XCTAssertFalse(isRTL(englishWithOneRTLWord), "one RTL word is below a minimum of 3")
        }
        withMinimumWords(4) {
            XCTAssertFalse(isRTL(listItemWithThreeRTLWords), "three RTL words are below a minimum of 4")
        }
        withMinimumWords(1) {
            XCTAssertTrue(isRTL(englishWithOneRTLWord), "one RTL word meets a minimum of 1")
        }
    }

    func testMinimumDoesNotAffectOtherLines() {
        withMinimumWords(3) {
            XCTAssertTrue(isRTL(persianOpening), "a line that opens RTL is RTL whatever the minimum")
            XCTAssertFalse(isRTL("plain English"), "a line with no RTL words never flips")
        }
    }

    func testZWNJAndMarksDoNotSplitAWord() {
        // «دانش‌آموزان» holds a ZWNJ and «کاملاً» a combining fathatan; each is one word.
        withMinimumWords(3) {
            XCTAssertFalse(isRTL("ok دانش‌آموزان کاملاً"), "two RTL words, not four")
        }
        withMinimumWords(2) {
            XCTAssertTrue(isRTL("ok دانش‌آموزان کاملاً"), "two RTL words meet a minimum of 2")
        }
    }

    func testDetectionOffMeansLTR() {
        withMinimumWords(1, detect: false) {
            XCTAssertFalse(isRTL(listItemWithThreeRTLWords), "the minimum only applies when auto-detect is on")
            XCTAssertFalse(isRTL(persianOpening), "auto-detect off: LTR")
        }
    }
}
