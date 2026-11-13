//
//  PorterStemmerTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class PorterStemmerTests: XCTestCase {
    func testStemsOrdinaryWords() {
        XCTAssertEqual(("running" as NSString).it_stem, "run")
        XCTAssertEqual(("" as NSString).it_stem, "")
    }

    // A token of 255 or more bytes used to fill the stack buffer without a terminator, so strlen()
    // and the stemmer ran off its end.
    func testVeryLongWordDoesNotOverrunTheBuffer() {
        let long = String(repeating: "a", count: 1000) + "ing"
        let stem = (long as NSString).it_stem
        XCTAssertFalse(stem.isEmpty)
        XCTAssertLessThanOrEqual(stem.utf8.count, 1003)
    }

    // Truncating at a byte limit can split a multibyte character, which used to make the result
    // nil despite the property being nonnull.
    func testTruncationInsideAMultibyteCharacterStillReturnsAString() {
        let word = String(repeating: "a", count: 254) + "é" + "z"
        XCTAssertFalse((word as NSString).it_stem.isEmpty)
    }

    // A lone surrogate can't be encoded as UTF-8, so cStringUsingEncoding: returns NULL, which
    // used to be passed straight to strncpy.
    func testUnencodableStringDoesNotCrash() {
        let unpaired = NSString(characters: [0xD800, 0x0061], length: 2)
        XCTAssertEqual(unpaired.it_stem, unpaired as String)
    }
}
