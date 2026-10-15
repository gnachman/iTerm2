//
//  AICustomHeadersMigrationTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

// The one-time copy of the former global AI custom headers into each manual
// model must retire the global list, or another Mac sharing these prefs would
// copy it back into a model whose headers the user removed.
final class AICustomHeadersMigrationTests: XCTestCase {
    private let doneKey = "NoSyncAICustomHeadersPerModelMigrationDone"
    private var savedConfigurations: Any?
    private var savedEnabled = false
    private var savedHeaders: Any?
    private var savedDone: Any?

    override func setUp() {
        super.setUp()
        savedConfigurations = iTermPreferences.object(forKey: kPreferenceKeyAIManualModelConfigurations)
        savedEnabled = iTermPreferences.bool(forKey: kPreferenceKeyAICustomHeadersEnabled)
        savedHeaders = iTermPreferences.object(forKey: kPreferenceKeyAICustomHeaders)
        savedDone = iTermUserDefaults.userDefaults().object(forKey: doneKey)
    }

    override func tearDown() {
        iTermPreferences.setObject(savedConfigurations, forKey: kPreferenceKeyAIManualModelConfigurations)
        iTermPreferences.setBool(savedEnabled, forKey: kPreferenceKeyAICustomHeadersEnabled)
        iTermPreferences.setObject(savedHeaders, forKey: kPreferenceKeyAICustomHeaders)
        iTermUserDefaults.userDefaults().set(savedDone, forKey: doneKey)
        super.tearDown()
    }

    private func setLegacyGlobalHeaders() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyAICustomHeadersEnabled)
        iTermPreferences.setObject([["name": "X-Old", "value": "v"]], forKey: kPreferenceKeyAICustomHeaders)
    }

    private func headers(ofModelAt index: Int) -> [[String: String]]? {
        let configs = iTermPreferences.object(forKey: kPreferenceKeyAIManualModelConfigurations) as? [[String: Any]]
        return configs?[index]["customHeaders"] as? [[String: String]]
    }

    func testMigrationCopiesThenRetiresGlobalHeaders() {
        setLegacyGlobalHeaders()
        iTermPreferences.setObject([["name": "m", "url": "http://x/"]],
                                   forKey: kPreferenceKeyAIManualModelConfigurations)
        iTermUserDefaults.userDefaults().removeObject(forKey: doneKey)

        iTermMigrationHelper.migrateCustomHeadersToPerModelIfNeeded()

        XCTAssertEqual(headers(ofModelAt: 0), [["name": "X-Old", "value": "v"]])
        XCTAssertFalse(iTermPreferences.bool(forKey: kPreferenceKeyAICustomHeadersEnabled))
    }

    // A second Mac (done flag unset) must not re-add headers the user removed
    // after the first Mac migrated.
    func testRemovedHeadersStayRemovedOnSecondMac() {
        setLegacyGlobalHeaders()
        iTermPreferences.setObject([["name": "m", "url": "http://x/"]],
                                   forKey: kPreferenceKeyAIManualModelConfigurations)
        iTermUserDefaults.userDefaults().removeObject(forKey: doneKey)
        iTermMigrationHelper.migrateCustomHeadersToPerModelIfNeeded()

        // The user removes every header in the editor.
        iTermPreferences.setObject([["name": "m", "url": "http://x/", "customHeaders": []]],
                                   forKey: kPreferenceKeyAIManualModelConfigurations)
        // Another Mac sharing the prefs has never run the migration.
        iTermUserDefaults.userDefaults().removeObject(forKey: doneKey)
        iTermMigrationHelper.migrateCustomHeadersToPerModelIfNeeded()

        XCTAssertEqual(headers(ofModelAt: 0), [])
    }

    // Shared prefs last written by a build that migrated but didn't retire
    // the global list, on a Mac that has never run the migration: a model
    // whose headers the user removed (an empty list) must stay empty.
    func testEmptyHeaderListIsNotRemigrated() {
        setLegacyGlobalHeaders()
        iTermPreferences.setObject([["name": "m", "url": "http://x/", "customHeaders": []],
                                    ["name": "n", "url": "http://y/"]],
                                   forKey: kPreferenceKeyAIManualModelConfigurations)
        iTermUserDefaults.userDefaults().removeObject(forKey: doneKey)

        iTermMigrationHelper.migrateCustomHeadersToPerModelIfNeeded()

        XCTAssertEqual(headers(ofModelAt: 0), [])
        XCTAssertEqual(headers(ofModelAt: 1), [["name": "X-Old", "value": "v"]])
        XCTAssertFalse(iTermPreferences.bool(forKey: kPreferenceKeyAICustomHeadersEnabled))
    }

    // An earlier build ran the migration without retiring the global list.
    func testGlobalHeadersRetiredEvenWhenMigrationAlreadyDone() {
        setLegacyGlobalHeaders()
        iTermPreferences.setObject([["name": "m", "url": "http://x/", "customHeaders": []]],
                                   forKey: kPreferenceKeyAIManualModelConfigurations)
        iTermUserDefaults.userDefaults().set(true, forKey: doneKey)

        iTermMigrationHelper.migrateCustomHeadersToPerModelIfNeeded()

        XCTAssertEqual(headers(ofModelAt: 0), [])
        XCTAssertFalse(iTermPreferences.bool(forKey: kPreferenceKeyAICustomHeadersEnabled))
    }

    // The legacy single model (no configurations) still inherits the global list.
    func testLegacySingleModelKeepsGlobalHeaders() {
        setLegacyGlobalHeaders()
        iTermPreferences.setObject([], forKey: kPreferenceKeyAIManualModelConfigurations)
        iTermUserDefaults.userDefaults().removeObject(forKey: doneKey)

        iTermMigrationHelper.migrateCustomHeadersToPerModelIfNeeded()

        XCTAssertTrue(iTermPreferences.bool(forKey: kPreferenceKeyAICustomHeadersEnabled))
    }
}
