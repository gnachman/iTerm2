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
                iTermWarning.show(withTitle: String(localized: "AITermGatekeeper.GenerativeAIDisabled", defaultValue: "Generative AI features have been disabled. Check with your system administrator.", comment: "Warning shown when generative AI is disabled by policy"),
                                  actions: [iTermLocalizedOK()],
                                  accessory: nil,
                                  identifier: nil,
                                  silenceable: .kiTermWarningTypePersistent,
                                  heading: String(localized: "AITermGatekeeper.FeatureUnavailable", defaultValue: "Feature Unavailable", comment: "Heading for a warning that an AI feature cannot be used"),
                                  window: nil)
            }
            return false
        }
        if !iTermAITermGatekeeper.pluginInstalled() {
            if !silent {
                let selection = iTermWarning.show(withTitle: String(localized: "AITermGatekeeper.MustInstallPlugin", defaultValue: "You must install the AI plugin before you can use this feature.", comment: "Warning shown when the AI plugin is not installed"),
                                                  actions: [String(localized: "AITermGatekeeper.RevealInSettings", defaultValue: "Reveal in Settings", comment: "Button that opens Settings to the relevant preference"), iTermLocalizedCancel()],
                                                  accessory: nil,
                                                  identifier: nil,
                                                  silenceable: .kiTermWarningTypePersistent,
                                                  heading: String(localized: "AITermGatekeeper.PluginMissing", defaultValue: "Plugin Missing", comment: "Heading for a warning that the AI plugin is not installed"),
                                                  window: nil)
                if selection == .kiTermWarningSelection0 {
                    PreferencePanel.sharedInstance().openToPreference(withKey: kPhonyPreferenceKeyInstallAIPlugin)
                }
            }
            return false
        }
        if !SecureUserDefaults.instance.enableAI.value {
            if !silent {
                let selection = iTermWarning.show(withTitle: String(localized: "AITermGatekeeper.MustEnableAI", defaultValue: "You must enable AI features in settings before you can use this feature.", comment: "Warning shown when AI features are not yet enabled in settings"),
                                                  actions: [String(localized: "AITermGatekeeper.Reveal", defaultValue: "Reveal", comment: "Button that reveals the relevant setting"), iTermLocalizedCancel()],
                                                  accessory: nil,
                                                  identifier: nil,
                                                  silenceable: .kiTermWarningTypePersistent,
                                                  heading: String(localized: "AITermGatekeeper.FeatureUnavailable", defaultValue: "Feature Unavailable", comment: "Heading for a warning that an AI feature cannot be used"),
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
                                  actions: [iTermLocalizedOK()],
                                  accessory: nil,
                                  identifier: nil,
                                  silenceable: .kiTermWarningTypePersistent,
                                  heading: String(localized: "AITermGatekeeper.FeatureUnavailable", defaultValue: "Feature Unavailable", comment: "Heading for a warning that an AI feature cannot be used"),
                                  window: nil)
            }
            return false
        } catch {
            if !silent {
                iTermWarning.show(withTitle: error.localizedDescription,
                                  actions: [iTermLocalizedOK()],
                                  accessory: nil,
                                  identifier: nil,
                                  silenceable: .kiTermWarningTypePersistent,
                                  heading: String(localized: "AITermGatekeeper.FeatureUnavailable", defaultValue: "Feature Unavailable", comment: "Heading for a warning that an AI feature cannot be used"),
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
