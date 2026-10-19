//
//  MetalUnavailableReasonDescriptionTests.swift
//  ModernTests
//
//  Help > GPU Renderer Availability showed “GPU rendering is off in the current
//  session because This tab has too many split panes”: a separately localized
//  reason fragment was injected into a sentence frame, so its capitalization and
//  punctuation did not fit and translations could not reorder it. Each reason is
//  now its own complete sentence. QA finding F-429.
//

import XCTest
@testable import iTerm2SharedARC

final class MetalUnavailableReasonDescriptionTests: XCTestCase {
    func testNoReasonHasNoDescription() {
        XCTAssertNil(iTermMetalUnavailableReasonDescription(.none))
    }

    func testEveryReasonIsACompleteSentence() {
        let last = iTermMetalUnavailableReason.notATerminal.rawValue
        var seen = Set<String>()
        // One past the last case checks the fallback for an unknown reason too.
        for raw in 1...(last + 1) {
            guard let reason = iTermMetalUnavailableReason(rawValue: raw) else {
                XCTFail("No reason \(raw)")
                continue
            }
            guard let description = iTermMetalUnavailableReasonDescription(reason) else {
                XCTFail("No description for reason \(raw)")
                continue
            }
            XCTAssertTrue(description.hasPrefix("GPU rendering is off in the current session because "),
                          "reason \(raw): \(description)")
            XCTAssertTrue(description.hasSuffix(".") || description.hasSuffix("!"),
                          "reason \(raw) is not a complete sentence: \(description)")
            XCTAssertFalse(description.contains("because This"), "reason \(raw): \(description)")
            XCTAssertFalse(description.contains("\""), "reason \(raw) has a straight quote: \(description)")
            XCTAssertFalse(description.contains("'"), "reason \(raw) has a straight apostrophe: \(description)")
            XCTAssertTrue(seen.insert(description).inserted, "reason \(raw) repeats another reason")
        }
    }

    func testTooManySplitPanesReadsAsOneSentence() {
        XCTAssertEqual(iTermMetalUnavailableReasonDescription(.tooManyPanesReason),
                       "GPU rendering is off in the current session because this tab has too many split panes.")
    }
}
