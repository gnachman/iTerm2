//
//  TabStatusOSCParsingTests.swift
//  ModernTests
//
//  OSC 21337 payload parsing, with an eye on the fallback an expiring status
//  hands off to. The dangerous shape is a fallback object that exists but sets
//  nothing: it suppresses the clear-by-default and makes the status permanent,
//  so a payload that names no usable then-* field must produce no fallback at
//  all rather than an empty one.
//

import XCTest
@testable import iTerm2SharedARC

final class TabStatusOSCParsingTests: XCTestCase {
    private func parse(_ payload: String) -> VT100TabStatusUpdate {
        return VT100Terminal().tabStatusUpdate(osc21337Payload: payload)
    }

    func testPlainStatusFields() {
        let update = parse("status=working;status-color=#ff9500;indicator=#ff9500;detail=hi")
        XCTAssertEqual(update.statusPresence, .set)
        XCTAssertEqual(update.status, "working")
        XCTAssertEqual(update.statusColorPresence, .set)
        XCTAssertEqual(update.indicatorPresence, .set)
        XCTAssertEqual(update.detailPresence, .set)
        XCTAssertEqual(update.detail, "hi")
        XCTAssertEqual(update.expiresOn, .never)
        XCTAssertNil(update.expirationFallback)
    }

    func testEmptyValueClearsAField() {
        let update = parse("status=;detail=")
        XCTAssertEqual(update.statusPresence, .cleared)
        XCTAssertEqual(update.detailPresence, .cleared)
    }

    func testExpiresOnWithFallbackFields() {
        let update = parse("status=working;expires-on=progress-end;then-status=idle;then-indicator=#00d75f")
        XCTAssertEqual(update.expiresOn, .progressEnd)
        guard let fallback = update.expirationFallback else {
            XCTFail("Expected a fallback")
            return
        }
        XCTAssertEqual(fallback.statusPresence, .set)
        XCTAssertEqual(fallback.status, "idle")
        XCTAssertEqual(fallback.indicatorPresence, .set)
    }

    func testExpiresOnWithNoFallbackFieldsClears() {
        let update = parse("status=working;expires-on=progress-end")
        XCTAssertEqual(update.expiresOn, .progressEnd)
        XCTAssertEqual(update.expirationFallback?.statusPresence, .cleared)
        XCTAssertEqual(update.expirationFallback?.indicatorPresence, .cleared)
    }

    func testUnknownThenKeyFallsBackToClearing() {
        // A misspelled key must behave like the key was left out, not produce
        // a fallback that sets nothing.
        let update = parse("status=working;expires-on=progress-end;then-indicatr=#00d75f")
        XCTAssertEqual(update.expirationFallback?.statusPresence, .cleared)
    }

    func testUnparsableThenColorFallsBackToClearing() {
        // Same for a recognized key whose value is not a color: the field is
        // not set, so it must not count as a fallback either.
        let update = parse("status=working;expires-on=progress-end;then-indicator=orange")
        guard let fallback = update.expirationFallback else {
            XCTFail("Expected the clearing fallback")
            return
        }
        XCTAssertEqual(fallback.statusPresence, .cleared)
        XCTAssertEqual(fallback.indicatorPresence, .cleared)
    }

    func testUnparsableThenColorAlongsideAGoodFieldKeepsTheGoodOne() {
        let update = parse("status=working;expires-on=progress-end;then-status=idle;then-indicator=orange")
        guard let fallback = update.expirationFallback else {
            XCTFail("Expected a fallback")
            return
        }
        XCTAssertEqual(fallback.statusPresence, .set)
        XCTAssertEqual(fallback.status, "idle")
        XCTAssertEqual(fallback.indicatorPresence, .notSet)
    }

    func testThenFieldsWithoutExpiresOnAreIgnored() {
        let update = parse("status=working;then-status=idle")
        XCTAssertEqual(update.expiresOn, .never)
        XCTAssertNil(update.expirationFallback)
    }

    func testUnknownExpiresOnValueIsIgnored() {
        let update = parse("status=working;expires-on=someday;then-status=idle")
        XCTAssertEqual(update.expiresOn, .never)
        XCTAssertNil(update.expirationFallback)
    }

    func testUnparsablePrimaryColorLeavesTheFieldAlone() {
        let update = parse("status=working;indicator=orange")
        XCTAssertEqual(update.statusPresence, .set)
        XCTAssertEqual(update.indicatorPresence, .notSet)
    }
}
