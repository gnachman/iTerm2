//
//  BindingsDowngradeCompatibilityTests.swift
//  iTerm2 ModernTests
//
//  A palette-index color escape (OSC 1337 SetColors=badge=i:3) stores a
//  KEY_BINDINGS value as a dictionary {expression, owner}. iTerm2 3.7.4's
//  -[PTYSession makeBindings:] treats every KEY_BINDINGS value as an expression
//  string and crashes on a dictionary, so restoring saved state written by a
//  newer build crashed 3.7.4 at every launch. Arrangements must therefore keep
//  only strings under KEY_BINDINGS and carry the richer form elsewhere, while the
//  new build still restores the owner.
//

import XCTest
@testable import iTerm2SharedARC

final class BindingsDowngradeCompatibilityTests: XCTestCase {
    private let badgeKey = KEY_BADGE_COLOR
    private let userKey = KEY_NAME

    private func paletteValue(_ expression: String) -> Any {
        return iTermProfilePreferences.paletteBindingValue(withExpression: expression)
    }

    private func profileWithMixedBindings() -> [AnyHashable: Any] {
        return [KEY_NAME: "Test",
                KEY_GUID: ProfileModel.freshGuid()!,
                KEY_BINDINGS: [badgeKey: paletteValue("colors.ansi.yellow"),
                               userKey: "user.title"]]
    }

    /// The test 3.7.4 cares about: every KEY_BINDINGS value is a string, because
    /// 3.7.4's makeBindings: passes each value to the expression parser as one.
    private func assertLegacyBindingsAreStrings(_ profile: [AnyHashable: Any],
                                                file: StaticString = #filePath,
                                                line: UInt = #line) {
        guard let raw = profile[KEY_BINDINGS] else {
            return
        }
        guard let bindings = raw as? NSDictionary else {
            XCTFail("KEY_BINDINGS is not a dictionary: \(raw)", file: file, line: line)
            return
        }
        for (key, value) in bindings {
            XCTAssertTrue(value is NSString,
                          "KEY_BINDINGS[\(key)] is \(type(of: value)), which 3.7.4 cannot consume",
                          file: file, line: line)
        }
    }

    private func bindings(_ profile: [AnyHashable: Any]) -> NSDictionary? {
        return profile[KEY_BINDINGS] as? NSDictionary
    }

    // MARK: - Helpers

    func testDowngradeCompatibleProfileHasOnlyStringBindings() {
        let encoded = iTermProfilePreferences.profile(byMakingBindingsDowngradeCompatible: profileWithMixedBindings())
        assertLegacyBindingsAreStrings(encoded)
        // The user-authored string binding stays where 3.7.4 can use it.
        XCTAssertEqual(bindings(encoded)?[userKey] as? String, "user.title")
        XCTAssertNil(bindings(encoded)?[badgeKey])
    }

    func testRoundTripPreservesOwner() {
        let original = profileWithMixedBindings()
        let encoded = iTermProfilePreferences.profile(byMakingBindingsDowngradeCompatible: original)
        let decoded = iTermProfilePreferences.profile(byRestoringDowngradeCompatibleBindings: encoded)
        XCTAssertEqual(decoded as NSDictionary, original as NSDictionary)
        let badgeValue = bindings(decoded)?[badgeKey]
        XCTAssertTrue(iTermProfilePreferences.bindingValueIsPaletteOwned(badgeValue as Any))
        XCTAssertEqual(iTermProfilePreferences.expression(forBindingValue: badgeValue as Any), "colors.ansi.yellow")
    }

    // State written before this fix has the dictionary form directly under
    // KEY_BINDINGS. The new build must still read it with the owner intact.
    func testLegacyDictionaryFormStillDecodes() {
        let original = profileWithMixedBindings()
        let decoded = iTermProfilePreferences.profile(byRestoringDowngradeCompatibleBindings: original)
        XCTAssertEqual(decoded as NSDictionary, original as NSDictionary)
    }

    // Encoding state that was itself decoded from the old dictionary form still
    // produces strings-only KEY_BINDINGS.
    func testReencodingLegacyDictionaryFormIsDowngradeCompatible() {
        let decoded = iTermProfilePreferences.profile(byRestoringDowngradeCompatibleBindings: profileWithMixedBindings())
        let encoded = iTermProfilePreferences.profile(byMakingBindingsDowngradeCompatible: decoded)
        assertLegacyBindingsAreStrings(encoded)
    }

    func testProfileWithOnlyStringBindingsIsUnchanged() {
        let profile: [AnyHashable: Any] = [KEY_NAME: "Test",
                                           KEY_BINDINGS: [userKey: "user.title"]]
        let encoded = iTermProfilePreferences.profile(byMakingBindingsDowngradeCompatible: profile)
        XCTAssertEqual(encoded as NSDictionary, profile as NSDictionary)
        let decoded = iTermProfilePreferences.profile(byRestoringDowngradeCompatibleBindings: encoded)
        XCTAssertEqual(decoded as NSDictionary, profile as NSDictionary)
    }

    // A profile with only palette-owned bindings encodes to an empty (but still
    // string-only) KEY_BINDINGS and decodes back to the original.
    func testOnlyPaletteBindingsRoundTrip() {
        let original: [AnyHashable: Any] = [KEY_NAME: "Test",
                                            KEY_BINDINGS: [badgeKey: paletteValue("colors.ansi.yellow")]]
        let encoded = iTermProfilePreferences.profile(byMakingBindingsDowngradeCompatible: original)
        assertLegacyBindingsAreStrings(encoded)
        XCTAssertEqual(bindings(encoded)?.count ?? 0, 0)
        let decoded = iTermProfilePreferences.profile(byRestoringDowngradeCompatibleBindings: encoded)
        XCTAssertEqual(decoded as NSDictionary, original as NSDictionary)
    }

    // If an older version edits the strings-only KEY_BINDINGS (say, the user adds
    // a binding on a key that the newer build had a palette binding for), the
    // older version's string wins when the newer build reads it back.
    func testLegacyStringWinsOverStashedValueForSameKey() {
        let encoded = iTermProfilePreferences.profile(byMakingBindingsDowngradeCompatible: profileWithMixedBindings())
        var edited = encoded
        var legacy = (bindings(encoded) as? [String: Any]) ?? [:]
        legacy[badgeKey] = "user.badgeColor"
        edited[KEY_BINDINGS] = legacy
        let decoded = iTermProfilePreferences.profile(byRestoringDowngradeCompatibleBindings: edited)
        XCTAssertEqual(bindings(decoded)?[badgeKey] as? String, "user.badgeColor")
        XCTAssertEqual(bindings(decoded)?[userKey] as? String, "user.title")
    }

    // MARK: - PTYSession arrangement

    // The arrangement a session writes (window state and saved arrangements both
    // come from here) must have strings-only bindings in its profile.
    func testSessionArrangementProfileHasOnlyStringBindings() {
        let session = PTYSession(synthetic: false)!
        session.profile = profileWithMixedBindings()
        let adapter = iTermMutableDictionaryEncoderAdapter.encoder()
        XCTAssertTrue(session.encodeArrangement(withContents: false, encoder: adapter))
        guard let profile = adapter.mutableDictionary["Bookmark"] as? [AnyHashable: Any] else {
            XCTFail("Arrangement has no profile: \(adapter.mutableDictionary)")
            return
        }
        assertLegacyBindingsAreStrings(profile)
        XCTAssertEqual(bindings(profile)?[userKey] as? String, "user.title")

        // And the new build gets the owner back.
        let restored = iTermProfilePreferences.profile(byRestoringDowngradeCompatibleBindings: profile)
        XCTAssertTrue(iTermProfilePreferences.bindingValueIsPaletteOwned(bindings(restored)?[badgeKey] as Any))
        // The live session's profile is untouched.
        XCTAssertTrue(iTermProfilePreferences.bindingValueIsPaletteOwned(bindings(session.profile!)?[badgeKey] as Any))
    }
}
