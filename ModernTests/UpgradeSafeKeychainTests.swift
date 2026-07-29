//
//  UpgradeSafeKeychainTests.swift
//  ModernTests
//
//  Covers the pure migration decisions of iTermUpgradeSafeKeychain: which store a
//  read result routes to. The actual SecItem I/O is intentionally not exercised
//  (it needs a signed host with the keychain-access-group entitlement); these
//  tests pin the branching that decides whether we already have an answer from the
//  data-protection keychain, must fall back to the legacy keychain, or must
//  migrate a legacy value forward.
//

import XCTest
import Security
@testable import iTerm2SharedARC

final class UpgradeSafeKeychainTests: XCTestCase {
    // MARK: - planAfterDataProtectionRead

    func testDataProtectionSuccessIsReturnedVerbatim() {
        XCTAssertEqual(
            iTermUpgradeSafeKeychain.planAfterDataProtectionRead(status: errSecSuccess),
            .useDataProtectionResult)
    }

    func testDataProtectionNotFoundConsultsLegacy() {
        XCTAssertEqual(
            iTermUpgradeSafeKeychain.planAfterDataProtectionRead(status: errSecItemNotFound),
            .consultLegacy)
    }

    func testMissingEntitlementFallsBackToLegacy() {
        // A build without a usable keychain-access-groups entitlement can't touch the
        // data-protection keychain, so the login keychain is still the real store and
        // we must fall back to it (degrade to old behavior), not surface an error.
        XCTAssertEqual(
            iTermUpgradeSafeKeychain.planAfterDataProtectionRead(status: errSecMissingEntitlement),
            .consultLegacy)
    }

    func testDataProtectionHardErrorIsNotMaskedByLegacy() {
        // A locked/denied keychain must surface as an error, NOT be retried against
        // the legacy store (which could then wrongly report the item absent).
        XCTAssertEqual(
            iTermUpgradeSafeKeychain.planAfterDataProtectionRead(status: errSecAuthFailed),
            .useDataProtectionResult)
        XCTAssertEqual(
            iTermUpgradeSafeKeychain.planAfterDataProtectionRead(status: errSecInteractionNotAllowed),
            .useDataProtectionResult)
    }

    // MARK: - planAfterLegacyRead

    func testLegacyValuePresentTriggersMigration() {
        XCTAssertEqual(
            iTermUpgradeSafeKeychain.planAfterLegacyRead(status: errSecSuccess),
            .migrate)
    }

    func testLegacyAbsentReportsAbsent() {
        XCTAssertEqual(
            iTermUpgradeSafeKeychain.planAfterLegacyRead(status: errSecItemNotFound),
            .reportAbsent)
    }

    func testLegacyHardErrorIsSurfacedNotMigrated() {
        XCTAssertEqual(
            iTermUpgradeSafeKeychain.planAfterLegacyRead(status: errSecAuthFailed),
            .reportLegacyError)
        XCTAssertEqual(
            iTermUpgradeSafeKeychain.planAfterLegacyRead(status: errSecInteractionNotAllowed),
            .reportLegacyError)
    }

    // MARK: - shouldMigrateLegacyValue

    func testNonEmptyLegacyValueIsMigrated() {
        XCTAssertTrue(iTermUpgradeSafeKeychain.shouldMigrateLegacyValue(Data([1, 2, 3])))
    }

    func testEmptyLegacyValueIsNotMigrated() {
        // An empty "" tombstone must be reaped, not migrated (empty kSecValueData
        // does not round-trip, so migrating it would loop forever and could resurrect
        // a cleared key).
        XCTAssertFalse(iTermUpgradeSafeKeychain.shouldMigrateLegacyValue(Data()))
    }

    func testNilLegacyValueIsNotMigrated() {
        XCTAssertFalse(iTermUpgradeSafeKeychain.shouldMigrateLegacyValue(nil))
    }
}
