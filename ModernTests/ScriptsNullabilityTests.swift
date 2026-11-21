//
//  ScriptsNullabilityTests.swift
//  ModernTests
//
//  Documents the nullability claims of iTermScriptHistory that the
//  nullability sanitizer found false (unit N4 of
//  docs/swift-migration/nullability-triage.md). The Objective-C method returns
//  nil, and accepts nil, by design; these tests pin what Swift sees.
//  iTermScriptsMenuController is not visible to Swift; its claims are pinned
//  in ScriptsMenuControllerNullabilityTests.m.
//

import XCTest
@testable import iTerm2SharedARC

final class ScriptsNullabilityTests: XCTestCase {
    // -[iTermScriptHistory entryWithIdentifier:] is a search. While its return
    // was claimed nonnull, Swift held the nil it returned for an unknown
    // identifier as a non-optional reference, and this assertion saw a value.
    func testEntryWithUnknownIdentifierIsNil() {
        let identifier = "no-such-entry-" + UUID().uuidString
        XCTAssertNil(iTermScriptHistory.sharedInstance().entry(withIdentifier: identifier))
    }

    // Objective-C callers pass a connection key read from a dictionary, which
    // can be nil, so the parameter is optional. That claim is pinned at
    // compile time: passing a String? compiles only because the parameter is
    // optional. The value is non-nil at run time on purpose, because a nil
    // would reach -isEqualToString:, whose parameter Apple declares nonnull,
    // and the nullability sanitizer would report it.
    func testEntryWithOptionalIdentifierCompiles() {
        let identifier: String? = "no-such-entry-" + UUID().uuidString
        XCTAssertNil(iTermScriptHistory.sharedInstance().entry(withIdentifier: identifier))
    }
}
