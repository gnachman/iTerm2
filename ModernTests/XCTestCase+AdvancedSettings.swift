//
//  XCTestCase+AdvancedSettings.swift
//  ModernTests
//
//  Helpers for tests whose subject reads iTermAdvancedSettingsModel, so the result doesn't
//  depend on the advanced settings of the machine running the tests.
//

import XCTest
@testable import iTerm2SharedARC

extension XCTestCase {
    /// Sets the advanced setting stored under user defaults key `key` (the setting's name with
    /// its first letter capitalized) for the rest of the current test. The previous value is
    /// restored during teardown.
    func pinAdvancedSetting(_ key: String, to value: Any?) {
        let restore = Self.overrideAdvancedSetting(key, with: value)
        addTeardownBlock(restore)
    }

    /// Sets an advanced setting for the duration of `body`, then restores the previous value.
    func withAdvancedSetting(_ key: String, _ value: Any?, _ body: () throws -> Void) rethrows {
        let restore = Self.overrideAdvancedSetting(key, with: value)
        defer { restore() }
        try body()
    }

    /// Writes `value` to user defaults and reloads the model. Returns a closure that undoes it.
    private static func overrideAdvancedSetting(_ key: String, with value: Any?) -> () -> Void {
        let defaults = iTermUserDefaults.userDefaults()
        let previous = defaults.object(forKey: key)
        defaults.set(value, forKey: key)
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        return {
            defaults.set(previous, forKey: key)
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
    }
}
