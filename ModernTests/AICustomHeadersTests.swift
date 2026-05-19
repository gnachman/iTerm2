//
//  AICustomHeadersTests.swift
//  iTerm2 ModernTests
//
//  Offline coverage for AICustomHeaders.merged(into:): the helper that
//  layers user-defined HTTP headers on top of built-in ones for every
//  outbound AI request. Validates the toggle, name/value sanitization,
//  override behavior, and that values are not allowed to inject extra
//  headers via CRLF.
//

import XCTest
@testable import iTerm2SharedARC

final class AICustomHeadersTests: XCTestCase {
    private var savedEnabled: Bool = false
    private var savedRaw: Any?

    override func setUp() {
        super.setUp()
        savedEnabled = iTermPreferences.bool(forKey: kPreferenceKeyAICustomHeadersEnabled)
        savedRaw = iTermPreferences.object(forKey: kPreferenceKeyAICustomHeaders)
    }

    override func tearDown() {
        iTermPreferences.setBool(savedEnabled, forKey: kPreferenceKeyAICustomHeadersEnabled)
        iTermPreferences.setObject(savedRaw, forKey: kPreferenceKeyAICustomHeaders)
        super.tearDown()
    }

    private func setHeaders(_ entries: [[String: String]], enabled: Bool = true) {
        iTermPreferences.setBool(enabled, forKey: kPreferenceKeyAICustomHeadersEnabled)
        iTermPreferences.setObject(entries, forKey: kPreferenceKeyAICustomHeaders)
    }

    func testToggleOffReturnsBaseUnchanged() {
        setHeaders([["name": "X-Foo", "value": "bar"]], enabled: false)
        let result = AICustomHeaders.merged(into: ["Content-Type": "application/json"])
        XCTAssertEqual(result, ["Content-Type": "application/json"])
    }

    func testCustomHeaderIsAppended() {
        setHeaders([["name": "X-Route", "value": "alpha"]])
        let result = AICustomHeaders.merged(into: ["Content-Type": "application/json"])
        XCTAssertEqual(result["X-Route"], "alpha")
        XCTAssertEqual(result["Content-Type"], "application/json")
    }

    func testCustomHeaderOverridesBuiltIn() {
        setHeaders([["name": "User-Agent", "value": "override"]])
        let result = AICustomHeaders.merged(into: ["User-Agent": "iTerm2"])
        XCTAssertEqual(result["User-Agent"], "override")
    }

    func testEmptyNameIsSkipped() {
        setHeaders([
            ["name": "", "value": "ignored"],
            ["name": "X-Keep", "value": "kept"],
        ])
        let result = AICustomHeaders.merged(into: [:])
        XCTAssertNil(result[""])
        XCTAssertEqual(result["X-Keep"], "kept")
    }

    func testInvalidNameCharactersAreRejected() {
        setHeaders([
            ["name": "Bad Name", "value": "x"],
            ["name": "Bad:Name", "value": "x"],
            ["name": "Bad\nName", "value": "x"],
        ])
        let result = AICustomHeaders.merged(into: ["Content-Type": "application/json"])
        XCTAssertEqual(result, ["Content-Type": "application/json"])
    }

    func testCRLFInValueIsRejected() {
        setHeaders([
            ["name": "X-Injected", "value": "ok\r\nX-Smuggled: yes"],
            ["name": "X-Normal", "value": "fine"],
        ])
        let result = AICustomHeaders.merged(into: [:])
        XCTAssertNil(result["X-Injected"])
        XCTAssertNil(result["X-Smuggled"])
        XCTAssertEqual(result["X-Normal"], "fine")
    }

    func testNULInValueIsRejected() {
        setHeaders([["name": "X-Null", "value": "ab\0cd"]])
        let result = AICustomHeaders.merged(into: [:])
        XCTAssertNil(result["X-Null"])
    }

    func testEmptyValueIsAllowed() {
        setHeaders([["name": "X-Empty", "value": ""]])
        let result = AICustomHeaders.merged(into: [:])
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
