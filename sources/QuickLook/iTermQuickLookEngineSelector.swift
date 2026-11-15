//
//  iTermQuickLookEngineSelector.swift
//  iTerm2SharedARC
//
//  Chooses which engine renders web Quick Look: the legacy one, or the built-in browser’s.
//

import Foundation

@objc enum iTermQuickLookEngine: Int {
    case legacy
    case browser
}

@objc class iTermQuickLookEngineSelector: NSObject {
    @objc static func engine(settingEnabled: Bool, pluginAvailable: Bool) -> iTermQuickLookEngine {
        return engine(settingEnabled: settingEnabled, checkPluginAvailable: { pluginAvailable })
    }

    // Asks whether the plugin is available only when the setting is on. The check verifies a code
    // signature and posts iTermBrowserGateway.didChange, so it must not run for users who never
    // turned the setting on.
    static func engine(settingEnabled: Bool, checkPluginAvailable: () -> Bool) -> iTermQuickLookEngine {
        guard settingEnabled else {
            return .legacy
        }
        return checkPluginAvailable() ? .browser : .legacy
    }

    @objc static func currentEngine() -> iTermQuickLookEngine {
        return engine(settingEnabled: iTermPreferences.bool(forKey: kPreferenceKeyQuickLookUsesBrowserEngine),
                      checkPluginAvailable: { iTermBrowserGateway.browserAllowed(checkIfNo: false) })
    }
}
