//
//  CanonicalEncodingTests.swift
//  CompanionCore
//
//  Pins the length-prefixed, domain-separated encoding, including a fixed test
//  vector that the JS relay's canonicalEncode must reproduce byte-for-byte (the
//  same vector is asserted in the worker's canonical.test.js).
//

import XCTest
import CryptoKit
@testable import CompanionProtocol

final class CanonicalEncodingTests: XCTestCase {
    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    // SHARED CROSS-LANGUAGE VECTOR: encode("test", [0x0102, "hi"]).
    //   len32("test")=00000004 "test"=74657374
    //   len32(0102) =00000002 0102
    //   len32("hi") =00000002 6869
    func test_crossLanguageVector() {
        let encoded = CanonicalEncoding.encode(domain: "test", [Data([0x01, 0x02]), Data("hi".utf8)])
        XCTAssertEqual(hex(encoded), "0000000474657374000000020102000000026869")
    }

    func test_isUnambiguous_acrossFieldBoundaries() {
        // The classic ambiguity ("AB","C") vs ("A","BC") must NOT collide.
        let a = CanonicalEncoding.encode(domain: "d", [Data("AB".utf8), Data("C".utf8)])
        let b = CanonicalEncoding.encode(domain: "d", [Data("A".utf8), Data("BC".utf8)])
        XCTAssertNotEqual(a, b)
    }

    func test_domainSeparation() {
        // Same fields under different domains never collide.
        let join = CanonicalEncoding.encode(domain: "join", [Data("x".utf8)])
        let del = CanonicalEncoding.encode(domain: "delete", [Data("x".utf8)])
        XCTAssertNotEqual(join, del)
    }

    func test_emptyFieldsAreDistinguished() {
        // Zero fields vs one empty field differ (the count is implicit in the
        // bytes but the length prefixes still disambiguate).
        let none = CanonicalEncoding.encode(domain: "d", [])
        let oneEmpty = CanonicalEncoding.encode(domain: "d", [Data()])
        XCTAssertNotEqual(none, oneEmpty)
    }
}
