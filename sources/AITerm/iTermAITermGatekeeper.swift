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
                iTermWarning.show(withTitle: String(localized: "AiTermGatekeeper_GenerativeAiFeaturesHaveBeenDisabledCheck", defaultValue: "Generative AI features have been disabled. Check with your system administrator.", comment: "Alert title in check"),
                                  actions: [String(localized: "COMMON_OK", defaultValue: "OK", comment: "Action title in check")],
                                  accessory: nil,
                                  identifier: nil,
                                  silenceable: .kiTermWarningTypePersistent,
                                  heading: String(localized: "AiTermGatekeeper_FeatureUnavailable", defaultValue: "Feature Unavailable", comment: "Alert heading in check"),
                                  window: nil)
            }
            return false
        }
        if !iTermAITermGatekeeper.pluginInstalled() {
            if !silent {
                let selection = iTermWarning.show(withTitle: String(localized: "AiTermGatekeeper_YouMustInstallTheAiPluginBefore", defaultValue: "You must install the AI plugin before you can use this feature.", comment: "Alert title in check"),
                                                  actions: [String(localized: "AiTermGatekeeper_RevealInSettings", defaultValue: "Reveal in Settings", comment: "Action title in check"), String(localized: "COMMON_CANCEL", defaultValue: "Cancel", comment: "Action title in check")],
                                                  accessory: nil,
                                                  identifier: nil,
                                                  silenceable: .kiTermWarningTypePersistent,
                                                  heading: String(localized: "AiTermGatekeeper_PluginMissing", defaultValue: "Plugin Missing", comment: "Alert heading in check"),
                                                  window: nil)
                if selection == .kiTermWarningSelection0 {
                    PreferencePanel.sharedInstance().openToPreference(withKey: kPhonyPreferenceKeyInstallAIPlugin)
                }
            }
            return false
        }
        if !SecureUserDefaults.instance.enableAI.value {
            if !silent {
                let selection = iTermWarning.show(withTitle: String(localized: "AiTermGatekeeper_YouMustEnableAiFeaturesInSettings", defaultValue: "You must enable AI features in settings before you can use this feature.", comment: "Alert title in check"),
                                                  actions: [String(localized: "AiTermGatekeeper_Reveal", defaultValue: "Reveal", comment: "Action title in check"), String(localized: "COMMON_CANCEL", defaultValue: "Cancel", comment: "Action title in check")],
                                                  accessory: nil,
                                                  identifier: nil,
                                                  silenceable: .kiTermWarningTypePersistent,
                                                  heading: String(localized: "AiTermGatekeeper_FeatureUnavailable", defaultValue: "Feature Unavailable", comment: "Alert heading in check"),
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
            RLog("\(error.reason)")
            if !silent {
                iTermWarning.show(withTitle: error.reason,
                                  actions: [String(localized: "COMMON_OK", defaultValue: "OK", comment: "Action title in check")],
                                  accessory: nil,
                                  identifier: nil,
                                  silenceable: .kiTermWarningTypePersistent,
                                  heading: String(localized: "AiTermGatekeeper_FeatureUnavailable", defaultValue: "Feature Unavailable", comment: "Alert heading in check"),
                                  window: nil)
            }
            return false
        } catch {
            if !silent {
                iTermWarning.show(withTitle: error.localizedDescription,
                                  actions: [String(localized: "COMMON_OK", defaultValue: "OK", comment: "Action title in check")],
                                  accessory: nil,
                                  identifier: nil,
                                  silenceable: .kiTermWarningTypePersistent,
                                  heading: String(localized: "AiTermGatekeeper_FeatureUnavailable", defaultValue: "Feature Unavailable", comment: "Alert heading in check"),
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
