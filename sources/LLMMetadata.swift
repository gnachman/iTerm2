//
//  LLMMetadata.swift
//  iTerm2
//
//  Created by George Nachman on 6/6/25.
//

@objc(iTermLLMMetadata)
class LLMMetadata: NSObject {
    @objc(openAIModelIsLegacy:)
    static func openAIModelIsLegacy(model: String) -> Bool {
        for prefix in iTermAdvancedSettingsModel.aiModernModelPrefixes().components(separatedBy: " ") {
            if model.hasPrefix(prefix) {
                return false
            }
        }
        return true
    }

    @objc(hostIsOpenAIAPIForURL:)
    static func hostIsOpenAIAPI(url: URL?) -> Bool {
        return url?.host == "api.openai.com"
    }

    @objc(iTermLLMPlatform)
    enum LLMPlatform: UInt {
        case openAI
        case azure
        case gemini

        init(_ platform: LLMProvider.Platform) {
            switch platform {
            case .openAI:
                self = .openAI
            case .azure:
                self = .azure
            case .gemini:
                self = .gemini
            }
        }
    }

    @objc(platform)
    static func objcPlatform() -> LLMPlatform {
        LLMPlatform(platform())
    }

    static func platform() -> LLMProvider.Platform {
        let urlString = iTermPreferences.string(forKey: kPreferenceKeyAITermURL) ?? ""
        if URL(string: urlString)?.host == "generativelanguage.googleapis.com" {
            return .gemini
        } else if let platform = LLMProvider.Platform(rawValue: iTermAdvancedSettingsModel.llmPlatform()) {
            return platform
        } else {
            return .openAI
        }
    }

    static func model() -> String {
        return iTermPreferences.string(forKey: kPreferenceKeyAIModel) ?? "gpt-4o-mini"
    }
}
