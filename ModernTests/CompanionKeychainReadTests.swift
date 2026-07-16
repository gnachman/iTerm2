//
//  CompanionKeychainReadTests.swift
//  ModernTests
//
//  P5: a keychain read must distinguish "genuinely absent" (errSecItemNotFound)
//  from "present but unreadable right now" (a transient access failure such as a
//  code-signature confirmation prompt denied at launch, or a locked keychain).
//  Conflating them made pairingCompleteness() report the pairing incomplete
//  forever after one transient failure, spamming the re-pair modal and wedging
//  resume. interpretKeychainStatus is the pure core of that distinction.
//

import XCTest
import Security
@testable import iTerm2SharedARC

final class CompanionKeychainReadTests: XCTestCase {
    func testValidItemIsFound() {
        let data = Data(repeating: 7, count: 32)
        XCTAssertEqual(CompanionMacIdentity.interpretKeychainStatus(errSecSuccess, data: data),
                       .found(data))
    }

    func testNotFoundIsAbsent() {
        XCTAssertEqual(CompanionMacIdentity.interpretKeychainStatus(errSecItemNotFound, data: nil),
                       .absent)
    }

    func testAccessDeniedIsUnreadableNotAbsent() {
        // The core bug: a transient access failure must NOT read as absent, or the
        // pairing looks permanently incomplete.
        let result = CompanionMacIdentity.interpretKeychainStatus(errSecInteractionNotAllowed, data: nil)
        XCTAssertEqual(result, .unreadable(errSecInteractionNotAllowed))
        XCTAssertNotEqual(result, .absent)
    }

    func testAuthFailedIsUnreadable() {
        XCTAssertEqual(CompanionMacIdentity.interpretKeychainStatus(errSecAuthFailed, data: nil),
                       .unreadable(errSecAuthFailed))
    }

    func testMalformedItemIsUnreadableNotFound() {
        // Success but wrong size: the item exists but is unusable. It must not read
        // as found (callers would use garbage) nor as absent (it is present).
        let short = Data(repeating: 1, count: 16)
        let result = CompanionMacIdentity.interpretKeychainStatus(errSecSuccess, data: short)
        if case .unreadable = result { } else {
            XCTFail("malformed (wrong size) should be .unreadable, got \(result)")
        }
    }
}
