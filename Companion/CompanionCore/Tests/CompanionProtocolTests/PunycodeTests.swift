//
//  PunycodeTests.swift
//  CompanionCore
//

import XCTest
@testable import CompanionProtocol

final class PunycodeTests: XCTestCase {
    func testPureASCIIIsUnchanged() {
        XCTAssertEqual(Punycode.encodedHost("companion-relay.iterm2.com"),
                       "companion-relay.iterm2.com")
        XCTAssertEqual(Punycode.encodedHost("example.com"), "example.com")
    }

    func testKnownLabelVectors() {
        // Classic RFC 3492 / IDNA reference encodings.
        XCTAssertEqual(Punycode.encodedHost("bücher"), "xn--bcher-kva")
        XCTAssertEqual(Punycode.encodedHost("münchen"), "xn--mnchen-3ya")
    }

    func testPerLabelEncoding() {
        // Only the non-ASCII label is encoded; ASCII labels pass through.
        XCTAssertEqual(Punycode.encodedHost("münchen.example.com"),
                       "xn--mnchen-3ya.example.com")
    }

    func testHomographLookalikeBecomesVisible() {
        // "аpple.com" with a Cyrillic 'а' (U+0430) must not render as ASCII apple.
        let spoof = "\u{0430}pple.com"
        let encoded = Punycode.encodedHost(spoof)
        XCTAssertTrue(encoded.hasPrefix("xn--"), "expected xn-- form, got \(encoded)")
        XCTAssertNotEqual(encoded, "apple.com")
    }
}
