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

    // HTTP field names are case-insensitive, so a custom "authorization" must
    // replace the built-in "Authorization" rather than joining it in the
    // dictionary: two entries differing only in case reach URLRequest as one
    // field whose winner depends on dictionary order (issue 13021).
    func testCustomHeaderOverridesBuiltInRegardlessOfCase() {
        let result = AICustomHeaders.merged(into: ["Authorization": "Bearer placeholder"],
                                            customHeaders: [["name": "authorization",
                                                             "value": "Bearer secret"]])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.value, "Bearer secret")
    }

    // The user's spelling wins, so the wire shows what they typed.
    func testCaseInsensitiveOverrideKeepsTheUsersSpelling() {
        let result = AICustomHeaders.merged(into: ["x-api-key": "placeholder"],
                                            customHeaders: [["name": "X-API-Key",
                                                             "value": "secret"]])
        XCTAssertEqual(result, ["X-API-Key": "secret"])
    }

    func testLaterCustomHeaderOverridesAnEarlierOneDifferingOnlyInCase() {
        let result = AICustomHeaders.merged(into: [:],
                                            customHeaders: [
                                                ["name": "X-Route", "value": "alpha"],
                                                ["name": "x-route", "value": "beta"],
                                            ])
        XCTAssertEqual(result, ["x-route": "beta"])
    }

    // A rejected custom header must not take the built-in one down with it.
    func testInvalidValueLeavesTheBuiltInHeaderIntact() {
        let result = AICustomHeaders.merged(into: ["Authorization": "Bearer placeholder"],
                                            customHeaders: [["name": "authorization",
                                                             "value": "Bearer bad\r\nX-Smuggled: yes"]])
        XCTAssertEqual(result, ["Authorization": "Bearer placeholder"])
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
