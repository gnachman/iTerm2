//
//  iTermAITermGatekeeper.swift
//  iTerm2
//
//  Created by George Nachman on 6/5/25.
//

@objc
class iTermAITermGatekeeper: NSObject {
    @objc
    static func validatePlugin(_ completion: @escaping (String?) -> ()) {
        DLog("validatePlugin")
        iTermAIClient.instance.validate(completion)
    }

    @objc
    static func reloadPlugin(_ completion: @escaping () -> ()) {
        DLog("reloadPlugin")
        iTermAIClient.instance.reload(completion)
    }

    @objc(checkSilently:)
    static func check(silent: Bool = false) -> Bool {
        DLog("check")
        if !iTermAdvancedSettingsModel.generativeAIAllowed() {
            if !silent {
                iTermWarning.show(withTitle: "Generative AI features have been disabled. Check with your system administrator.",
                                  actions: ["OK"],
                                  accessory: nil,
                                  identifier: nil,
                                  silenceable: .kiTermWarningTypePersistent,
                                  heading: "Feature Unavailable",
                                  window: nil)
            }
            return false
        }
        if !iTermAITermGatekeeper.pluginInstalled() {
            if !silent {
                let selection = iTermWarning.show(withTitle: "You must install the AI plugin before you can use this feature.",
                                                  actions: ["Reveal in Settings", "Cancel"],
                                                  accessory: nil,
                                                  identifier: nil,
                                                  silenceable: .kiTermWarningTypePersistent,
                                                  heading: "Plugin Missing",
                                                  window: nil)
                if selection == .kiTermWarningSelection0 {
                    PreferencePanel.sharedInstance().openToPreference(withKey: kPhonyPreferenceKeyInstallAIPlugin)
                }
            }
            return false
        }
        if !SecureUserDefaults.instance.enableAI.value {
            if !silent {
                let selection = iTermWarning.show(withTitle: "You must enable AI features in settings before you can use this feature.",
                                                  actions: ["Reveal", "Cancel"],
                                                  accessory: nil,
                                                  identifier: nil,
                                                  silenceable: .kiTermWarningTypePersistent,
                                                  heading: "Feature Unavailable",
                                                  window: nil)
                if selection == .kiTermWarningSelection0 {
                    PreferencePanel.sharedInstance().openToPreference(withKey: kPreferenceKeyEnableAI)
                }
            }
            return false
        }
        do {
            try iTermAIClient.instance.validate()
        } catch let error as PluginError {
            DLog("\(error.reason)")
            if !silent {
                iTermWarning.show(withTitle: error.reason,
                                  actions: ["OK"],
                                  accessory: nil,
                                  identifier: nil,
                                  silenceable: .kiTermWarningTypePersistent,
                                  heading: "Feature Unavailable",
                                  window: nil)
            }
            return false
        } catch {
            if !silent {
                iTermWarning.show(withTitle: error.localizedDescription,
                                  actions: ["OK"],
                                  accessory: nil,
                                  identifier: nil,
                                  silenceable: .kiTermWarningTypePersistent,
                                  heading: "Feature Unavailable",
                                  window: nil)
            }
            return false
        }
        return true
    }

    @objc
    static func pluginInstalled() -> Bool {
        switch Plugin.instance() {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    @objc
    static var allowed: Bool {
        DLog("allowed")
        return iTermAdvancedSettingsModel.generativeAIAllowed() && SecureUserDefaults.instance.enableAI.value
    }
}
