//
//  AISafetyCheckMigrationTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

// Covers the one-time migration of the AI command safety check from on-device
// Apple Intelligence to the configured model. The migration runs at launch and
// again (as a no-op) whenever an AI controller is created. A choice the user
// makes after it first ran must never be undone.
final class AISafetyCheckMigrationTests: XCTestCase {
    private let keys: [String] = [
        kPreferenceKeyAISafetyCheck,
        kPreferenceKeyAISafetyCheckUsesAppleIntelligence,
        kPreferenceKeyAISafetyCheckProviderSwitchPending,
        kPreferenceKeyAISafetyCheckProviderMigrationDone,
        kPreferenceKeyAISafetyCheckNagComplete,
    ]
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        let ud = iTermUserDefaults.userDefaults()
        for key in keys {
            if let value = ud.object(forKey: key) {
                saved[key] = value
            }
            ud.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        let ud = iTermUserDefaults.userDefaults()
        for key in keys {
            if let value = saved[key] {
                ud.set(value, forKey: key)
            } else {
                ud.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    private var ud: UserDefaults { iTermUserDefaults.userDefaults() }

    // A fresh install where Apple Intelligence is unavailable. The migration
    // runs at launch with the pref off (the launch call itself is in the app
    // delegate and is not exercised here). The user then enables the check
    // and an AI controller is created, which re-invokes the migration. The
    // later choice must survive.
    func testUserChoiceAfterLaunchMigrationSurvivesControllerCreation() {
        var probeCalls = 0
        let unavailable: () -> Bool = {
            probeCalls += 1
            return false
        }

        // Launch.
        iTermMigrationHelper.migrateAISafetyCheckProviderIfNeeded(availabilityProbe: unavailable)
        XCTAssertTrue(ud.bool(forKey: kPreferenceKeyAISafetyCheckProviderMigrationDone))
        XCTAssertFalse(iTermPreferences.bool(forKey: kPreferenceKeyAISafetyCheck))

        // User enables the check in Settings.
        iTermPreferences.setBool(true, forKey: kPreferenceKeyAISafetyCheck)

        // An AI controller is created.
        iTermMigrationHelper.migrateAISafetyCheckProviderIfNeeded(availabilityProbe: unavailable)

        // The Enable prompt is suppressed only while the key is present.
        XCTAssertNotNil(ud.object(forKey: kPreferenceKeyAISafetyCheck))
        XCTAssertTrue(iTermPreferences.bool(forKey: kPreferenceKeyAISafetyCheck))
        XCTAssertFalse(ud.bool(forKey: kPreferenceKeyAISafetyCheckUsesAppleIntelligence))
        XCTAssertFalse(ud.bool(forKey: kPreferenceKeyAISafetyCheckProviderSwitchPending))
        XCTAssertEqual(probeCalls, 0)
    }

    // F-084, order-independent: the user enables the check in Settings
    // before the migration has ever run. Settings records the explicit
    // choice, so the migration must leave it alone and never probe.
    func testSettingsChoiceBeforeMigrationIsNotUndone() {
        var probeCalls = 0
        iTermPreferences.setBool(true, forKey: kPreferenceKeyAISafetyCheck)
        iTermMigrationHelper.noteAISafetyCheckChosenByUser()

        iTermMigrationHelper.migrateAISafetyCheckProviderIfNeeded(availabilityProbe: {
            probeCalls += 1
            return false
        })

        XCTAssertNotNil(ud.object(forKey: kPreferenceKeyAISafetyCheck))
        XCTAssertTrue(iTermPreferences.bool(forKey: kPreferenceKeyAISafetyCheck))
        XCTAssertFalse(ud.bool(forKey: kPreferenceKeyAISafetyCheckUsesAppleIntelligence))
        XCTAssertFalse(ud.bool(forKey: kPreferenceKeyAISafetyCheckProviderSwitchPending))
        XCTAssertEqual(probeCalls, 0)
    }

    // Upgrading straight from 3.6 with the check on and Apple Intelligence
    // unavailable: the no-op 3.6 setting is cleared exactly once so the opt-in
    // nag re-fires. Re-enabling afterwards sticks.
    func testUpgradeFrom36WithoutAppleIntelligenceClearsOnce() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyAISafetyCheck)
        ud.set(true, forKey: kPreferenceKeyAISafetyCheckNagComplete)

        iTermMigrationHelper.migrateAISafetyCheckProviderIfNeeded(availabilityProbe: { false })

        XCTAssertFalse(iTermPreferences.bool(forKey: kPreferenceKeyAISafetyCheck))
        XCTAssertNil(ud.object(forKey: kPreferenceKeyAISafetyCheckNagComplete))
        XCTAssertTrue(ud.bool(forKey: kPreferenceKeyAISafetyCheckProviderMigrationDone))

        iTermPreferences.setBool(true, forKey: kPreferenceKeyAISafetyCheck)
        iTermMigrationHelper.migrateAISafetyCheckProviderIfNeeded(availabilityProbe: { false })
        XCTAssertTrue(iTermPreferences.bool(forKey: kPreferenceKeyAISafetyCheck))
    }

    // Upgrading straight from 3.6 with the check on and Apple Intelligence
    // working: keep the on-device behavior and owe the user the switch prompt.
    func testUpgradeFrom36WithAppleIntelligenceGrandfathers() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyAISafetyCheck)

        iTermMigrationHelper.migrateAISafetyCheckProviderIfNeeded(availabilityProbe: { true })

        XCTAssertTrue(iTermPreferences.bool(forKey: kPreferenceKeyAISafetyCheck))
        XCTAssertTrue(ud.bool(forKey: kPreferenceKeyAISafetyCheckUsesAppleIntelligence))
        XCTAssertTrue(ud.bool(forKey: kPreferenceKeyAISafetyCheckProviderSwitchPending))
        XCTAssertTrue(ud.bool(forKey: kPreferenceKeyAISafetyCheckProviderMigrationDone))
    }
}
