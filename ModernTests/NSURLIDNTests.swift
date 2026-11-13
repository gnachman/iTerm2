//
//  NSURLIDNTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class NSURLIDNTests: XCTestCase {
    func testEncodesInternationalHostname() {
        XCTAssertEqual(NSURL.idnEncodedHostname("bücher.example"), "xn--bcher-kva.example")
    }

    // The punycode encoder used to alloca() a buffer the size of the label before checking that the
    // label fit in a hostname, so a huge label from terminal text could exhaust the stack.
    func testHugeLabelIsLeftAloneWithoutExhaustingTheStack() {
        let label = String(repeating: "ü", count: 8_000_000)
        XCTAssertEqual(NSURL.idnEncodedHostname(label), label)
    }
}
