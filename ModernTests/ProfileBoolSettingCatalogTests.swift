//
//  ProfileBoolSettingCatalogTests.swift
//  ModernTests
//
//  Tests that the "Set Profile Setting" catalog is populated even when the shared Preferences
//  window has never been opened this launch (F18): the catalog force-loads the panel nib so
//  allSettings() is not empty.
//

import XCTest
@testable import iTerm2SharedARC

final class ProfileBoolSettingCatalogTests: XCTestCase {
    func testEntriesPopulatedWithoutOpeningPreferences() {
        // The shared Preferences window has not been opened in this test process. Without the
        // force-load, allSettings() (and hence entries()) would be empty and the picker would offer
        // no settings.
        let entries = ProfileBoolSettingCatalog.entries()
        XCTAssertFalse(entries.isEmpty, "catalog should force-load the prefs panel")
        XCTAssertTrue(entries.contains { $0.key == "Prevent Sleep" },
                      "Prevent Sleep should be an offered setting")
    }
}
