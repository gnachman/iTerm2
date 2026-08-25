//
//  AICustomHeadersTests.swift
//  iTerm2 ModernTests
//
//  Offline coverage for AICustomHeaders.merged(into:customHeaders:): the helper
//  that layers a model's user-defined HTTP headers on top of built-in ones for
//  every outbound AI request. Validates name/value sanitization, override
//  behavior, and that values are not allowed to inject extra headers via CRLF.
//

import XCTest
@testable import iTerm2SharedARC

final class AICustomHeadersTests: XCTestCase {
    func testEmptyHeadersReturnBaseUnchanged() {
        let result = AICustomHeaders.merged(into: ["Content-Type": "application/json"],
                                            customHeaders: [])
        XCTAssertEqual(result, ["Content-Type": "application/json"])
    }

    func testCustomHeaderIsAppended() {
        let result = AICustomHeaders.merged(into: ["Content-Type": "application/json"],
                                            customHeaders: [["name": "X-Route", "value": "alpha"]])
        XCTAssertEqual(result["X-Route"], "alpha")
        XCTAssertEqual(result["Content-Type"], "application/json")
    }

    func testCustomHeaderOverridesBuiltIn() {
        let result = AICustomHeaders.merged(into: ["User-Agent": "iTerm2"],
                                            customHeaders: [["name": "User-Agent", "value": "override"]])
        XCTAssertEqual(result["User-Agent"], "override")
    }

    func testEmptyNameIsSkipped() {
        let result = AICustomHeaders.merged(into: [:],
                                            customHeaders: [
                                                ["name": "", "value": "ignored"],
                                                ["name": "X-Keep", "value": "kept"],
                                            ])
        XCTAssertNil(result[""])
        XCTAssertEqual(result["X-Keep"], "kept")
    }

    func testInvalidNameCharactersAreRejected() {
        let result = AICustomHeaders.merged(into: ["Content-Type": "application/json"],
                                            customHeaders: [
                                                ["name": "Bad Name", "value": "x"],
                                                ["name": "Bad:Name", "value": "x"],
                                                ["name": "Bad\nName", "value": "x"],
                                            ])
        XCTAssertEqual(result, ["Content-Type": "application/json"])
    }

    func testCRLFInValueIsRejected() {
        let result = AICustomHeaders.merged(into: [:],
                                            customHeaders: [
                                                ["name": "X-Injected", "value": "ok\r\nX-Smuggled: yes"],
                                                ["name": "X-Normal", "value": "fine"],
                                            ])
        XCTAssertNil(result["X-Injected"])
        XCTAssertNil(result["X-Smuggled"])
        XCTAssertEqual(result["X-Normal"], "fine")
    }

    func testNULInValueIsRejected() {
        let result = AICustomHeaders.merged(into: [:],
                                            customHeaders: [["name": "X-Null", "value": "ab\0cd"]])
        XCTAssertNil(result["X-Null"])
    }

    func testEmptyValueIsAllowed() {
        let result = AICustomHeaders.merged(into: [:],
                                            customHeaders: [["name": "X-Empty", "value": ""]])
        XCTAssertEqual(result["X-Empty"], "")
    }

    func testValidationHelpers() {
        XCTAssertTrue(AICustomHeaders.isValidName("X-Custom-Header"))
        XCTAssertTrue(AICustomHeaders.isValidName("Authorization"))
        XCTAssertFalse(AICustomHeaders.isValidName(""))
        XCTAssertFalse(AICustomHeaders.isValidName("with space"))
        XCTAssertFalse(AICustomHeaders.isValidName("with:colon"))
        XCTAssertFalse(AICustomHeaders.isValidName("with\rcr"))

        XCTAssertTrue(AICustomHeaders.isValidValue("anything goes 123 !@#"))
        XCTAssertTrue(AICustomHeaders.isValidValue(""))
        XCTAssertFalse(AICustomHeaders.isValidValue("with\nnewline"))
        XCTAssertFalse(AICustomHeaders.isValidValue("with\rreturn"))
        XCTAssertFalse(AICustomHeaders.isValidValue("with\0nul"))
    }
}
