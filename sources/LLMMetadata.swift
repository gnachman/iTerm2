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

    static func model() -> AIMetadata.Model? {
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
