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
        // Check if any modern model identifier appears anywhere in the model name.
        // This handles OpenRouter-style names like "openai/gpt-4o" where the
        // provider prefix comes before the model name.
        for identifier in iTermAdvancedSettingsModel.aiModernModelPrefixes().components(separatedBy: " ") {
            if model.contains(identifier) {
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

    static var effectiveVendor: iTermAIVendor {
        if iTermPreferences.bool(forKey: kPreferenceKeyUseRecommendedAIModel) {
            DLog("Use \(String(describing: currentVendor?.rawValue))")
            return currentVendor ?? .openAI
        }
        if let model = model(), let vendor = model.vendor {
            DLog("Use \(vendor)")
            return vendor
        }
        DLog("Fall back to openai")
        return .openAI
    }

    static var currentVendor: iTermAIVendor? {
        iTermAIVendor(rawValue: iTermPreferences.unsignedInteger(forKey: kPreferenceKeyAIVendor))
    }

    static var alternateModels: [AIMetadata.Model] {
        guard iTermPreferences.bool(forKey: kPreferenceKeyUseRecommendedAIModel) else {
            return []
        }
        switch currentVendor {
        case .openAI:
            return AIMetadata.alternateOpenAIModels
        case .deepSeek:
            return AIMetadata.alternateDeepSeekModels
        case .gemini:
            return AIMetadata.alternateGeminiModels
        case .llama:
            return AIMetadata.alternateLlamaModels
        case .anthropic:
            return AIMetadata.alternateAnthropicModels
        case .none:
            return []
        @unknown default:
            return []
        }
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
