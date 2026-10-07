//
//  ReplacedTextCounterTests.swift
//  ModernTests
//
//  The text input system measures a replacement range in UTF-16 code units,
//  but the shell deletes one character per backspace. These pin the
//  conversion so replacing an emoji doesn't also delete the character
//  before it.
//

import XCTest
@testable import iTerm2SharedARC

final class ReplacedTextCounterTests: XCTestCase {
    private func count(_ length: Int, _ text: String) -> Int {
        return iTermReplacedTextCounter.numberOfCharacters(inLastUTF16Units: length, of: text)
    }

    func testASCII() {
        XCTAssertEqual(count(1, "hello"), 1)
        XCTAssertEqual(count(5, "hello world"), 5)
    }

    func testSurrogatePairIsOneCharacter() {
        XCTAssertEqual(count(2, "ab😀"), 1)
    }

    func testSurrogatePairAndPrecedingCharacter() {
        XCTAssertEqual(count(3, "ab😀"), 2)
    }

    func testRangeSplittingSurrogatePairCoversWholeCharacter() {
        XCTAssertEqual(count(1, "ab😀"), 1)
    }

    func testCombiningMarkIsOneCharacter() {
        XCTAssertEqual(count(2, "cafe\u{301}"), 1)
    }

    func testLengthLongerThanTextIsClamped() {
        XCTAssertEqual(count(10, "ab"), 2)
    }

    func testZeroLength() {
        XCTAssertEqual(count(0, "ab"), 0)
    }
}
