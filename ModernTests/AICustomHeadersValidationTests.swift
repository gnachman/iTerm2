//
//  AICustomHeadersValidationTests.swift
//  iTerm2
//
//  The manual AI model editor's Save and Test Connection share this check, so
//  a test can't report success while leaving out a header that Save refuses.
//

import XCTest
@testable import iTerm2SharedARC

final class AICustomHeadersValidationTests: XCTestCase {
    func testValidHeadersPass() {
        XCTAssertNil(AICustomHeaders.validationFailure(forHeaders: [["name": "X-Token", "value": "abc"]]))
    }

    func testBlankNameRowsAreIgnored() {
        XCTAssertNil(AICustomHeaders.validationFailure(forHeaders: [["name": "  ", "value": "v_empty"]]))
    }

    func testNameWithSpaceIsRefused() {
        XCTAssertEqual(AICustomHeaders.validationFailure(forHeaders: [["name": "", "value": "v_empty"],
                                                                     ["name": "Bad Name", "value": "x"]]),
                       "Custom header name “Bad Name” is not valid. Use only RFC 7230 token characters (letters, digits, and any of !#$%&'*+-.^_`|~).")
    }

    func testValueWithNewlineIsRefused() {
        XCTAssertEqual(AICustomHeaders.validationFailure(forHeaders: [["name": "X-Token", "value": "a\nb"]]),
                       "The value for custom header “X-Token” must not contain newline or null characters.")
    }
}
