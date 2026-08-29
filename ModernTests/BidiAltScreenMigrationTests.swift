//
//  BidiAltScreenMigrationTests.swift
//  ModernTests
//
//  The alternate-screen bidi setting was renamed (alternateScreenBidi, default
//  YES = reorder) to disableBidiInAlternateScreen (default NO = reorder) with an
//  inverted polarity and a new UserDefaults key. Without migration, a user who
//  explicitly turned OFF alt-screen reordering silently reverts to reordering on
//  upgrade. These cover the one-time migration.
//

import XCTest
@testable import iTerm2SharedARC

final class BidiAltScreenMigrationTests: XCTestCase {
    private let suite = "test.iterm2.altscreenbidi.migration"

    private func freshDefaults() -> UserDefaults {
        let ud = UserDefaults(suiteName: suite)!
        ud.removePersistentDomain(forName: suite)
        return ud
    }
    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testExplicitOptOutIsCarriedOver() {
        let ud = freshDefaults()
        ud.set(false, forKey: "AlternateScreenBidi")  // user turned reordering OFF
        iTermAdvancedSettingsModel.migrateAlternateScreenBidiSetting(in: ud)
        XCTAssertTrue(ud.bool(forKey: "DisableBidiInAlternateScreen"),
                      "an explicit opt-out must carry over to the new key")
        XCTAssertNil(ud.object(forKey: "AlternateScreenBidi"), "old key must be removed")
    }

    func testDefaultReorderingIsNotDisabled() {
        let ud = freshDefaults()
        ud.set(true, forKey: "AlternateScreenBidi")  // reordering ON (the old default)
        iTermAdvancedSettingsModel.migrateAlternateScreenBidiSetting(in: ud)
        XCTAssertFalse(ud.bool(forKey: "DisableBidiInAlternateScreen"))
        XCTAssertNil(ud.object(forKey: "AlternateScreenBidi"))
    }

    func testNoOldKeyLeavesNewKeyUntouched() {
        let ud = freshDefaults()
        iTermAdvancedSettingsModel.migrateAlternateScreenBidiSetting(in: ud)
        XCTAssertNil(ud.object(forKey: "DisableBidiInAlternateScreen"))
    }

    // The migration must be driven by iTermUserDefaults.performMigrations, which runs
    // after custom-folder (Dropbox) prefs are copied into local defaults. If it ran
    // earlier (e.g. from +[iTermAdvancedSettingsModel initialize]) a copied-down
    // opt-out would be missed and silently reverted.
    func testPerformMigrationsCarriesOverAltScreenOptOut() {
        let ud = freshDefaults()
        // Simulates the state after a Dropbox user’s explicit opt-out is copied down.
        ud.set(false, forKey: "AlternateScreenBidi")
        iTermUserDefaults.performMigrations(in: ud)
        XCTAssertTrue(ud.bool(forKey: "DisableBidiInAlternateScreen"),
                      "performMigrations must run the alt-screen migration")
        XCTAssertNil(ud.object(forKey: "AlternateScreenBidi"), "old key must be removed")
    }

    func testDoesNotOverrideAnExplicitNewChoice() {
        let ud = freshDefaults()
        ud.set(false, forKey: "AlternateScreenBidi")           // old opt-out
        ud.set(false, forKey: "DisableBidiInAlternateScreen")  // but the new key was already chosen
        iTermAdvancedSettingsModel.migrateAlternateScreenBidiSetting(in: ud)
        XCTAssertFalse(ud.bool(forKey: "DisableBidiInAlternateScreen"),
                       "must not override an existing new-key choice")
        XCTAssertNil(ud.object(forKey: "AlternateScreenBidi"))
    }
}
