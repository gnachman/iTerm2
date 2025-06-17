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

    @objc(hostIsOpenGoogleAPIForURL:)
    static func hostIsGoogleAIAPI(url: URL?) -> Bool {
        return url?.host == "generativelanguage.googleapis.com"
    }

    @objc(hostIsAzureAPIForURL:)
    static func hostIsAzureAIAPI(url: URL?) -> Bool {
        return (url?.host ?? "").hasSuffix(".azure.com")
    }

    @objc(hostIsDeepSeekAIAPIForURL:)
    static func hostIsDeepSeekAIAPI(url: URL?) -> Bool {
        return (url?.host ?? "").hasSuffix(".deepseek.com")
    }

    @objc(hostIsAnthropicAIAPIForURL:)
    static func hostIsAnthropicAIAPI(url: URL?) -> Bool {
        return (url?.host ?? "").hasSuffix(".anthropic.com")
    }

    static func model() -> AIMetadata.Model? {
        if iTermPreferences.bool(forKey: kPreferenceKeyUseRecommendedAIModel),
           let vendor = iTermAIVendor(rawValue: iTermPreferences.unsignedInteger(forKey: kPreferenceKeyAIVendor)) {
            switch vendor {
            case .openAI:
                return AIMetadata.recommendedOpenAIModel
            case .deepSeek:
                return AIMetadata.recommendedDeepSeekModel
            case .gemini:
                return AIMetadata.recommendedGeminiModel
            case .llama:
                return AIMetadata.recommendedLlamaModel
            case .anthropic:
                return AIMetadata.recommendedAnthropicModel
            @unknown default:
                return nil
            }
        }
        var features = Set<AIMetadata.Model.Feature>()
        if iTermPreferences.bool(forKey: kPreferenceKeyAIFeatureFunctionCalling) {
            features.insert(.functionCalling)
        }
        if iTermPreferences.bool(forKey: kPreferenceKeyAIFeatureHostedWebSearch) {
            features.insert(.hostedWebSearch)
        }
        if iTermPreferences.bool(forKey: kPreferenceKeyAIFeatureHostedFileSearch) {
            features.insert(.hostedFileSearch)
        }
        if iTermPreferences.bool(forKey: kPreferenceKeyAIFeatureStreamingResponses) {
            features.insert(.streaming)
        }
        if iTermPreferences.bool(forKey: kPreferenceKeyAIFeatureHostedCodeInterpreter) {
            features.insert(.hostedCodeInterpreter)
        }
        let url = iTermPreferences.string(forKey: kPreferenceKeyAITermURL)
        guard let url, !url.isEmpty else {
            return nil
        }

        return AIMetadata.Model(
            name: iTermPreferences.string(forKey: kPreferenceKeyAIModel) ?? "gpt-4o-mini",
            contextWindowTokens: iTermPreferences.integer(
                forKey: kPreferenceKeyAITokenLimit),
            maxResponseTokens: iTermPreferences.integer(
                forKey: kPreferenceKeyAIResponseTokenLimit),
            url: url,
            api: iTermAIAPI(rawValue: iTermPreferences.unsignedInteger(
                forKey: kPreferenceKeyAITermAPI)) ?? .chatCompletions,
            features: features,
            vectorStoreConfig: .init(rawValue: iTermPreferences.integer(forKey: kPreferenceKeyAIVectorStore)) ?? .disabled)
    }
}
