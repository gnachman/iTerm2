//
//  AIBackslashEscapesTests.swift
//  iTerm2 ModernTests
//
//  Pins decodeAIBackslashEscapes' edge cases. The non-BMP surrogate-pair
//  path is dense enough that the "high surrogate at end of input" branches
//  are easy to break silently; these tests lock the throw behavior so a
//  regression surfaces immediately.
//

import XCTest
@testable import iTerm2SharedARC

final class AIBackslashEscapesTests: XCTestCase {

    // MARK: - Basic escapes

    func test_simpleEscapes_decode() throws {
        XCTAssertEqual(try decodeAIBackslashEscapes("\\n"), "\n")
        XCTAssertEqual(try decodeAIBackslashEscapes("\\r"), "\r")
        XCTAssertEqual(try decodeAIBackslashEscapes("\\t"), "\t")
        XCTAssertEqual(try decodeAIBackslashEscapes("\\\\"), "\\")
    }

    func test_unknownEscape_throws() {
        XCTAssertThrowsError(try decodeAIBackslashEscapes("\\q")) { error in
            guard case AIBackslashEscapeError.unknownEscape = error else {
                return XCTFail("expected unknownEscape, got \(error)")
            }
        }
    }

    func test_danglingBackslash_throws() {
        XCTAssertThrowsError(try decodeAIBackslashEscapes("ab\\")) { error in
            guard case AIBackslashEscapeError.danglingBackslash = error else {
                return XCTFail("expected danglingBackslash, got \(error)")
            }
        }
    }

    // MARK: - BMP \uXXXX

    func test_bmpUnicode_decodes() throws {
        XCTAssertEqual(try decodeAIBackslashEscapes("\\u0041"), "A")
        XCTAssertEqual(try decodeAIBackslashEscapes("\\u00e9"), "é")
        XCTAssertEqual(try decodeAIBackslashEscapes("\\u4E2D"), "中")
    }

    func test_bmpUnicode_truncated_throws() {
        XCTAssertThrowsError(try decodeAIBackslashEscapes("\\u00")) { error in
            guard case AIBackslashEscapeError.truncatedUnicodeEscape = error else {
                return XCTFail("expected truncatedUnicodeEscape, got \(error)")
            }
        }
    }

    func test_bmpUnicode_nonHex_throws() {
        XCTAssertThrowsError(try decodeAIBackslashEscapes("\\uXYZW")) { error in
            guard case AIBackslashEscapeError.invalidUnicodeScalar = error else {
                return XCTFail("expected invalidUnicodeScalar, got \(error)")
            }
        }
    }

    // MARK: - Surrogate pairs

    func test_surrogatePair_decodesEmoji() throws {
        XCTAssertEqual(try decodeAIBackslashEscapes("\\uD83D\\uDE00"), "😀")
    }

    func test_surrogatePair_decodesNonBMPCJK() throws {
        XCTAssertEqual(try decodeAIBackslashEscapes("\\uD834\\uDD1E"), "𝄞")
    }

    // The "high surrogate at end of input" cluster. Each must throw,
    // and the throw must distinguish between "truncated" (not enough
    // characters to even form a low-surrogate escape) and "invalid"
    // (enough characters but the shape is wrong).

    func test_highSurrogate_atEndOfInput_throws() {
        // Nothing at all after the high surrogate.
        XCTAssertThrowsError(try decodeAIBackslashEscapes("\\uD834")) { error in
            guard case AIBackslashEscapeError.invalidUnicodeScalar = error else {
                return XCTFail("expected invalidUnicodeScalar, got \(error)")
            }
        }
    }

    func test_highSurrogate_followedByLoneBackslash_throws() {
        // High surrogate plus a single stray backslash. Not enough
        // characters to form \\uXXXX, so we expect invalidUnicodeScalar
        // (the index-by-2 check fails before we even look at the chars).
        XCTAssertThrowsError(try decodeAIBackslashEscapes("\\uD834\\")) { error in
            guard case AIBackslashEscapeError.invalidUnicodeScalar = error else {
                return XCTFail("expected invalidUnicodeScalar, got \(error)")
            }
        }
    }

    func test_highSurrogate_followedByBackslashU_throws() {
        // High surrogate plus \u but no hex digits.
        XCTAssertThrowsError(try decodeAIBackslashEscapes("\\uD834\\u")) { error in
            guard case AIBackslashEscapeError.truncatedUnicodeEscape = error else {
                return XCTFail("expected truncatedUnicodeEscape, got \(error)")
            }
        }
    }

    func test_highSurrogate_followedByPartialLowSurrogateHex_throws() {
        // High surrogate plus \uDC (only 2 of 4 hex digits).
        XCTAssertThrowsError(try decodeAIBackslashEscapes("\\uD834\\uDC")) { error in
            guard case AIBackslashEscapeError.truncatedUnicodeEscape = error else {
                return XCTFail("expected truncatedUnicodeEscape, got \(error)")
            }
        }
    }

    func test_highSurrogate_followedByBMPScalar_throws() {
        // \uD834 followed by ꯍ, where ABCD is a valid BMP scalar
        // but not a low surrogate. The combined sequence is malformed.
        XCTAssertThrowsError(try decodeAIBackslashEscapes("\\uD834\\uABCD")) { error in
            guard case AIBackslashEscapeError.invalidUnicodeScalar = error else {
                return XCTFail("expected invalidUnicodeScalar, got \(error)")
            }
        }
    }

    func test_loneLowSurrogate_throws() {
        // Unpaired low surrogate.
        XCTAssertThrowsError(try decodeAIBackslashEscapes("\\uDC00")) { error in
            guard case AIBackslashEscapeError.invalidUnicodeScalar = error else {
                return XCTFail("expected invalidUnicodeScalar, got \(error)")
            }
        }
    }

    // MARK: - Mixed content

    func test_mixedLiteralAndEscapes_decode() throws {
        XCTAssertEqual(try decodeAIBackslashEscapes("hello\\nworld"), "hello\nworld")
        XCTAssertEqual(try decodeAIBackslashEscapes("a\\u0042c"), "aBc")
        XCTAssertEqual(try decodeAIBackslashEscapes("foo\\uD83D\\uDE00bar"), "foo😀bar")
    }

    func test_noBackslashes_returnsInputUnchanged() throws {
        XCTAssertEqual(try decodeAIBackslashEscapes(""), "")
        XCTAssertEqual(try decodeAIBackslashEscapes("hello world"), "hello world")
        XCTAssertEqual(try decodeAIBackslashEscapes("中文"), "中文")
    }
}
