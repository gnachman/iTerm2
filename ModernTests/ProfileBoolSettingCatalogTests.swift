//
//  ProfileBoolSettingCatalogTests.swift
//  ModernTests
//
//  Tests that the "Set Profile Setting" catalog is populated even when the shared Preferences
//  window has never been opened this launch (F18): the catalog force-loads the panel nib so
//  allSettings() is not empty. Also checks that every control in the prefs panel is wired to
//  settingChanged: (F-210).
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

// Every control registered with defineControl must send settingChanged: or clicking it does
// nothing (F-210: the Prevent Sleep checkbox was never connected in PreferencePanel.xib).
final class PreferenceControlWiringTests: XCTestCase {
    func testEveryDefinedControlSendsSettingChanged() {
        let panel = PreferencePanel.sharedInstance()
        _ = panel.window
        let settings = panel.allSettings()
        XCTAssertFalse(settings.isEmpty, "Precondition: the panel nib loaded")
        var unwired = [String]()
        for setting in settings {
            guard let control = setting.info.control as? NSControl, !(control is NSTextField) else {
                continue
            }
            let action = control.action.map { NSStringFromSelector($0) } ?? "nil"
            let targetIsController = control.target is iTermPreferencesBaseViewController
            if control.action != #selector(iTermPreferencesBaseViewController.settingChanged(_:)) ||
                !targetIsController {
                let path = setting.pathComponents.joined(separator: " > ")
                unwired.append("\(path): \(setting.info.key ?? "nil") (\(type(of: control))): action=\(action) " +
                               "targetIsController=\(targetIsController)")
            }
        }
        XCTAssertEqual(unwired, [], "These controls do nothing when clicked")
    }
}
