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
        return settingEnabled && pluginAvailable ? .browser : .legacy
    }

    @objc static func currentEngine() -> iTermQuickLookEngine {
        return engine(settingEnabled: iTermPreferences.bool(forKey: kPreferenceKeyQuickLookUsesBrowserEngine),
                      pluginAvailable: iTermBrowserGateway.browserAllowed(checkIfNo: false))
    }
}
