//
//  StringFilenameSanitizationTests.swift
//  iTerm2
//
//  Created by George Nachman on 9/29/26.
//

import XCTest
@testable import iTerm2SharedARC

final class StringFilenameSanitizationTests: XCTestCase {
    func testPlainNameIsUnchanged() {
        XCTAssertEqual("Session 1.itermarchive".it_sanitizedForFilename(), "Session 1.itermarchive")
    }

    func testSlashesBecomeUnderscores() {
        // The path that failed in issue 13094: every slash became a directory separator.
        let name = "IPython: Users/me (-bash) — ~ — /dev/ttys001.itermarchive"
        let result = name.it_sanitizedForFilename()
        XCTAssertFalse(result.contains("/"))
        XCTAssertEqual(result, "IPython_ Users_me (-bash) — ~ — _dev_ttys001.itermarchive")
    }

    func testColonsBecomeUnderscores() {
        XCTAssertEqual("13:50:56.log".it_sanitizedForFilename(), "13_50_56.log")
    }

    func testCharactersIllegalOnNonNativeVolumesBecomeUnderscores() {
        XCTAssertEqual("a\\b*c?d\"e<f>g|h".it_sanitizedForFilename(), "a_b_c_d_e_f_g_h")
    }

    func testControlCharactersBecomeUnderscores() {
        XCTAssertEqual("a\u{0}b\nc\td\u{1b}[me\u{7f}f\u{85}g".it_sanitizedForFilename(),
                       "a_b_c_d_[me_f_g")
    }

    func testLeadingAndTrailingWhitespaceIsTrimmed() {
        XCTAssertEqual("  name\u{202f} ".it_sanitizedForFilename(), "name")
    }

    func testLeadingDotDoesNotHideTheFile() {
        XCTAssertEqual(".config".it_sanitizedForFilename(), "_config")
    }

    func testEmptyNameYieldsPlaceholder() {
        XCTAssertEqual("".it_sanitizedForFilename(), "_")
        XCTAssertEqual("   ".it_sanitizedForFilename(), "_")
    }

    func testLongNameIsTruncatedToByteLimitPreservingExtension() {
        let stem = String(repeating: "x", count: 300)
        let result = (stem + ".itermarchive").it_sanitizedForFilename()
        XCTAssertLessThanOrEqual(result.utf8.count, 255)
        XCTAssertTrue(result.hasSuffix(".itermarchive"))
        XCTAssertTrue(result.hasPrefix("xxxx"))
    }

    func testTruncationCountsBytesNotCharacters() {
        // Each em dash is three bytes of UTF-8.
        let name = String(repeating: "—", count: 200)
        let result = name.it_sanitizedForFilename()
        XCTAssertLessThanOrEqual(result.utf8.count, 255)
        XCTAssertEqual(result.count, 85)
    }

    func testTruncationDoesNotSplitAGraphemeCluster() {
        // A family emoji is 25 bytes. 10 of them is 250 bytes, so the 11th
        // must be dropped whole rather than cut mid-sequence.
        let family = "👨‍👩‍👧‍👦"
        let name = String(repeating: family, count: 11)
        let result = name.it_sanitizedForFilename()
        XCTAssertLessThanOrEqual(result.utf8.count, 255)
        XCTAssertEqual(result, String(repeating: family, count: 10))
    }

    func testCustomByteLimit() {
        XCTAssertEqual("abcdefghij".it_sanitizedForFilename(maxBytes: 4), "abcd")
        XCTAssertEqual("abcdefghij.log".it_sanitizedForFilename(maxBytes: 8), "abcd.log")
    }

    func testLongExtensionIsNotPreserved() {
        // Something that merely looks like an extension but is too long to be one
        // is truncated along with the rest of the name.
        let name = "short." + String(repeating: "y", count: 300)
        let result = name.it_sanitizedForFilename()
        XCTAssertLessThanOrEqual(result.utf8.count, 255)
        XCTAssertTrue(result.hasPrefix("short."))
    }

    func testObjCBridge() {
        XCTAssertEqual(("a/b:c" as NSString).it_sanitizedForFilename(), "a_b_c")
    }
}
