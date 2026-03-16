//
//  NSStringQuotedStringForPasteTests.swift
//  iTerm2
//
//  Created by George Nachman on 3/15/26.
//

import XCTest
@testable import iTerm2SharedARC

final class NSStringQuotedStringForPasteTests: XCTestCase {

    // MARK: - Basic ASCII Tests

    func testSimpleASCIIString() {
        let input = "hello"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"hello\"")
    }

    func testASCIIWithSpaces() {
        let input = "hello world"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"hello world\"")
    }

    func testEmptyString() {
        let input = ""
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"\"")
    }

    // MARK: - Special Character Escaping

    func testDoubleQuoteEscaping() {
        let input = "say \"hello\""
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"say \\\"hello\\\"\"")
    }

    func testBackslashEscaping() {
        let input = "path\\to\\file"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"path\\\\to\\\\file\"")
    }

    func testNewlineEscaping() {
        let input = "line1\nline2"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"line1\\nline2\"")
    }

    func testTabEscaping() {
        let input = "col1\tcol2"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"col1\\tcol2\"")
    }

    func testCarriageReturnEscaping() {
        let input = "line1\rline2"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"line1\\rline2\"")
    }

    // MARK: - Control Character Escaping

    func testC0ControlCharacterEscaping() {
        // Test ASCII control character (0x01 = SOH)
        let input = "hello\u{01}world"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"hello\\x01world\"")
    }

    func testDELCharacterEscaping() {
        // Test DEL character (0x7F)
        let input = "hello\u{7F}world"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"hello\\x7fworld\"")
    }

    func testC1ControlCharacterEscaping() {
        // Test C1 control character (0x85 = NEL)
        let input = "hello\u{85}world"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"hello\\x85world\"")
    }

    // MARK: - Unicode Tests (The Bug Fix)

    func testCyrillicCharactersNotEscaped() {
        // This is the main bug: Cyrillic should NOT be escaped
        let input = "/Users/test/Пример/Output"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"/Users/test/Пример/Output\"")
    }

    func testChineseCharactersNotEscaped() {
        let input = "/Users/test/文件夹/file"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"/Users/test/文件夹/file\"")
    }

    func testJapaneseCharactersNotEscaped() {
        let input = "/Users/test/フォルダ/file"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"/Users/test/フォルダ/file\"")
    }

    func testArabicCharactersNotEscaped() {
        let input = "/Users/test/مجلد/file"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"/Users/test/مجلد/file\"")
    }

    func testEmojiNotEscaped() {
        // Emoji are supplementary plane characters (> 0xFFFF)
        let input = "folder📁name"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"folder📁name\"")
    }

    func testComplexEmojiWithZWJNotEscaped() {
        // Family emoji uses ZWJ sequences
        let input = "test👨‍👩‍👧file"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"test👨‍👩‍👧file\"")
    }

    func testLatinExtendedNotEscaped() {
        // Characters like ñ, ü, é should not be escaped
        let input = "/Users/test/café/naïve"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"/Users/test/café/naïve\"")
    }

    // MARK: - Mixed Content Tests

    func testMixedUnicodeAndSpecialChars() {
        // Combine Unicode with characters that DO need escaping
        let input = "Пример with \"quotes\""
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"Пример with \\\"quotes\\\"\"")
    }

    func testMixedUnicodeAndBackslash() {
        let input = "Пример\\path"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"Пример\\\\path\"")
    }

    // MARK: - Edge Cases

    func testNonBreakingSpaceNotEscaped() {
        // U+00A0 is the first character >= 0xA0, should not be escaped
        let input = "hello\u{A0}world"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"hello\u{A0}world\"")
    }

    func testPrivateUseAreaNotEscaped() {
        // Private Use Area characters (U+E000-U+F8FF) should not be escaped
        let input = "test\u{E000}char"
        let result = (input as NSString).quotedStringForPaste()
        XCTAssertEqual(result, "\"test\u{E000}char\"")
    }
}
