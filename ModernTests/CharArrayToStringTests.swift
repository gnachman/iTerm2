//
//  CharArrayToStringTests.swift
//  ModernTests
//
//  CharArrayToString wraps a buffer of UTF-16 code units in an NSString
//  without copying. It used to keep NSUTF16LittleEndianStringEncoding
//  (0x94000100) in an int, which truncated it to a negative value that was
//  sign-extended back to 0xFFFFFFFF94000100 when passed as an
//  NSStringEncoding; Foundation happened to decode that the same way. The
//  variable is an NSStringEncoding now. See
//  docs/swift-migration/integer-findings.md section 4.2.
//

import XCTest
@testable import iTerm2SharedARC

final class CharArrayToStringTests: XCTestCase {
    private func decode(_ string: String, count: Int? = nil) -> String? {
        var units = Array(string.utf16)
        let length = Int32(count ?? units.count)
        return units.withUnsafeMutableBufferPointer { buffer in
            return CharArrayToString(buffer.baseAddress, length)
        }
    }

    func testASCII() {
        XCTAssertEqual(decode("Hello, world"), "Hello, world")
    }

    func testNonASCIIAndSurrogatePairs() {
        let text = "caf\u{e9} \u{7ffb}\u{771f} \u{1F600} \u{05e9}\u{05dc}\u{05d5}\u{05dd}"
        XCTAssertEqual(decode(text), text)
    }

    func testLengthLimitsTheString() {
        XCTAssertEqual(decode("abcdef", count: 3), "abc")
    }

    func testEmpty() {
        XCTAssertEqual(decode(""), "")
    }
}
