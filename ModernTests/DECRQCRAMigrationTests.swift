//
//  DECRQCRAMigrationTests.swift
//  ModernTests
//
//  The DECRQCRA announcement used to save its answer under NoSyncDisableDECRQCRA
//  while the setting was read from DisableDECRQCRA. These cover the one-time
//  migration to the setting's own key.
//

import XCTest
@testable import iTerm2SharedARC

final class DECRQCRAMigrationTests: XCTestCase {
    private let suite = "test.iterm2.decrqcra.migration"
    private let oldKey = "NoSyncDisableDECRQCRA"
    private let newKey = "DisableDECRQCRA"

    private func freshDefaults() -> UserDefaults {
        let ud = UserDefaults(suiteName: suite)!
        ud.removePersistentDomain(forName: suite)
        return ud
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testSavedNoIsCarriedOver() {
        let ud = freshDefaults()
        ud.set(true, forKey: oldKey)
        iTermUserDefaults.performMigrations(in: ud)
        XCTAssertEqual(ud.object(forKey: newKey) as? Bool, true)
        XCTAssertNil(ud.object(forKey: oldKey), "old key must be removed")
    }

    func testSavedYesIsCarriedOver() {
        let ud = freshDefaults()
        ud.set(false, forKey: oldKey)
        iTermAdvancedSettingsModel.migrateDECRQCRASetting(in: ud)
        XCTAssertEqual(ud.object(forKey: newKey) as? Bool, false)
        XCTAssertNil(ud.object(forKey: oldKey))
    }

    func testDoesNotOverrideAnExplicitNewChoice() {
        let ud = freshDefaults()
        ud.set(false, forKey: oldKey)
        ud.set(true, forKey: newKey)  // Disabled in Advanced Settings.
        iTermAdvancedSettingsModel.migrateDECRQCRASetting(in: ud)
        XCTAssertEqual(ud.object(forKey: newKey) as? Bool, true)
        XCTAssertNil(ud.object(forKey: oldKey))
    }

    func testNoOldKeyLeavesNewKeyUntouched() {
        let ud = freshDefaults()
        iTermAdvancedSettingsModel.migrateDECRQCRASetting(in: ud)
        XCTAssertNil(ud.object(forKey: newKey))
    }
}
