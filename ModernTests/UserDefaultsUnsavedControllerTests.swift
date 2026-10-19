//
//  UserDefaultsUnsavedControllerTests.swift
//  ModernTests
//
//  With settings loaded from a custom folder and saved manually, the red “!” in the Settings title
//  bar shows that local settings differ from the folder's. It was rechecked only when a user default
//  changed, and Save Now writes the folder without changing one, so the “!” stayed after saving
//  until the Settings window was reopened.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class UserDefaultsUnsavedControllerTests: XCTestCase {
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 5)
    }

    func testIndicatorClearsWhenSavedPrefsChange() {
        let controller = UserDefaultsUnsavedController()
        var differs = true
        controller.localPrefsDiffer = { differs }
        _ = controller.view
        XCTAssertTrue(controller.isShowingIndicator, "Precondition: unsaved changes show the indicator")

        // Save Now: the folder now matches, but no local default changed.
        differs = false
        NotificationCenter.default.post(name: .iTermRemotePreferencesSavedPrefsDidChange,
                                        object: nil)
        drainMainQueue()

        XCTAssertFalse(controller.isShowingIndicator)
    }

    // An automatic save snapshots the defaults off the main thread, so a setting edited since then
    // differs for a moment. That must not flash the indicator after every autosave.
    func testAutomaticSaveDoesNotShowIndicator() {
        let controller = UserDefaultsUnsavedController()
        var differs = false
        controller.localPrefsDiffer = { differs }
        controller.savesAutomatically = { true }
        _ = controller.view
        XCTAssertFalse(controller.isShowingIndicator, "Precondition: nothing unsaved")

        differs = true
        NotificationCenter.default.post(name: .iTermRemotePreferencesSavedPrefsDidChange,
                                        object: nil)
        drainMainQueue()

        XCTAssertFalse(controller.isShowingIndicator)
    }

    func testReplacingSavedPrefsPostsNotification() {
        let prefs = iTermRemotePreferences()
        let posted = expectation(forNotification: .iTermRemotePreferencesSavedPrefsDidChange,
                                 object: prefs)
        // savedRemotePrefs is private; it is what a save assigns once the folder's file is written.
        prefs.setValue(["Key": "Value"], forKey: "savedRemotePrefs")
        wait(for: [posted], timeout: 5)
    }
}
