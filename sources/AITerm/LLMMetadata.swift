//
//  LLMMetadata.swift
//  iTerm2
//
//  Created by George Nachman on 6/6/25.
//

@objc(iTermLLMMetadata)
class LLMMetadata: NSObject {
    private enum ManualModelKey {
        static let identifier = "id"
        static let name = "name"
        static let url = "url"
        static let api = "api"
        static let contextWindowTokens = "contextWindowTokens"
        static let maxResponseTokens = "maxResponseTokens"
        static let hostedCodeInterpreter = "hostedCodeInterpreter"
        static let hostedFileSearch = "hostedFileSearch"
        static let hostedWebSearch = "hostedWebSearch"
        static let functionCalling = "functionCalling"
        static let streaming = "streaming"
        static let vectorStore = "vectorStore"
    }

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
            return manualModels()
        }
        guard let currentVendor else {
            return []
        }
        return alternateModels(for: currentVendor)
    }

    static func alternateModels(for vendor: iTermAIVendor) -> [AIMetadata.Model] {
        switch vendor {
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
        case .apple:
            return AIMetadata.alternateAppleModels
        @unknown default:
            return []
        }
    }

    static func recommendedModel(for vendor: iTermAIVendor) -> AIMetadata.Model? {
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
        case .apple:
            return AIMetadata.recommendedAppleModel
        @unknown default:
            return nil
        }
    }

    static func manualModels() -> [AIMetadata.Model] {
        let configuredModels = manualConfiguredModels()
        if !configuredModels.isEmpty {
            return configuredModels
        }
        if iTermPreferences.bool(forKey: kPreferenceKeyUseRecommendedAIModel) {
            return []
        }
        if let model = legacyManualModel() {
            return [model]
        }
        return []
    }

    static func model() -> AIMetadata.Model? {
        if iTermPreferences.bool(forKey: kPreferenceKeyUseRecommendedAIModel),
           let vendor = iTermAIVendor(rawValue: iTermPreferences.unsignedInteger(forKey: kPreferenceKeyAIVendor)) {
            return recommendedModel(for: vendor)
        }
        let manualModels = manualModels()
        if let name = iTermPreferences.string(forKey: kPreferenceKeyAIModel),
           let model = manualModels.first(where: { $0.name == name }) {
            return model
        }
        if let model = manualModels.first {
            return model
        }
        return nil
    }

    private static func manualConfiguredModels() -> [AIMetadata.Model] {
        guard let raw = iTermPreferences.object(forKey: kPreferenceKeyAIManualModelConfigurations) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { manualModel(configuration: $0) }
    }

    private static func legacyManualModel() -> AIMetadata.Model? {
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
        let name = iTermPreferences.string(forKey: kPreferenceKeyAIModel) ?? "gpt-4o-mini"
        let api = iTermAIAPI(rawValue: iTermPreferences.unsignedInteger(
            forKey: kPreferenceKeyAITermAPI)) ?? .chatCompletions

        return AIMetadata.Model(
            name: name,
            contextWindowTokens: iTermPreferences.integer(
                forKey: kPreferenceKeyAITokenLimit),
            maxResponseTokens: iTermPreferences.integer(
                forKey: kPreferenceKeyAIResponseTokenLimit),
            url: url,
            api: api,
            features: features,
            vectorStoreConfig: .init(rawValue: iTermPreferences.integer(forKey: kPreferenceKeyAIVectorStore)) ?? .disabled,
            vendor: manualVendor(api: api, url: url, modelName: name))
    }

    private static func manualModel(configuration: [String: Any]) -> AIMetadata.Model? {
        guard let name = configuration[ManualModelKey.name] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = configuration[ManualModelKey.url] as? String,
              !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let api = iTermAIAPI(rawValue: unsignedInteger(configuration,
                                                       key: ManualModelKey.api,
                                                       fallback: UInt(iTermAIAPI.chatCompletions.rawValue))) ?? .chatCompletions
        var features = Set<AIMetadata.Model.Feature>()
        if bool(configuration, key: ManualModelKey.functionCalling) {
            features.insert(.functionCalling)
        }
        if bool(configuration, key: ManualModelKey.hostedWebSearch) {
            features.insert(.hostedWebSearch)
        }
        if bool(configuration, key: ManualModelKey.hostedFileSearch) {
            features.insert(.hostedFileSearch)
        }
        if bool(configuration, key: ManualModelKey.streaming) {
            features.insert(.streaming)
        }
        if bool(configuration, key: ManualModelKey.hostedCodeInterpreter) {
            features.insert(.hostedCodeInterpreter)
        }
        return AIMetadata.Model(
            name: name,
            contextWindowTokens: integer(configuration,
                                         key: ManualModelKey.contextWindowTokens,
                                         fallback: 8_192),
            maxResponseTokens: integer(configuration,
                                       key: ManualModelKey.maxResponseTokens,
                                       fallback: 8_192),
            url: url,
            api: api,
            features: features,
            vectorStoreConfig: .init(rawValue: integer(configuration,
                                                       key: ManualModelKey.vectorStore,
                                                       fallback: AIMetadata.Model.VectorStoreConfig.disabled.rawValue)) ?? .disabled,
            vendor: manualVendor(api: api, url: url, modelName: name))
    }

    private static func bool(_ dictionary: [String: Any], key: String) -> Bool {
        if let value = dictionary[key] as? Bool {
            return value
        }
        if let value = dictionary[key] as? NSNumber {
            return value.boolValue
        }
        return false
    }

    private static func integer(_ dictionary: [String: Any], key: String, fallback: Int) -> Int {
        if let value = dictionary[key] as? Int {
            return value
        }
        if let value = dictionary[key] as? NSNumber {
            return value.intValue
        }
        return fallback
    }

    private static func unsignedInteger(_ dictionary: [String: Any], key: String, fallback: UInt) -> UInt {
        if let value = dictionary[key] as? UInt {
            return value
        }
        if let value = dictionary[key] as? NSNumber {
            return value.uintValue
        }
        return fallback
    }

    private static func manualVendor(api: iTermAIAPI, url: String, modelName: String) -> iTermAIVendor? {
        switch api {
        case .anthropic:
            return .anthropic
        case .deepSeek:
            return .deepSeek
        case .gemini:
            return .gemini
        case .llama:
            return .llama
        case .appleIntelligence:
            return .apple
        case .chatCompletions, .completions, .responses, .earlyO1:
            break
        @unknown default:
            break
        }

        let lowercasedModelName = modelName.lowercased()
        if lowercasedModelName.contains("claude") {
            return .anthropic
        }
        if lowercasedModelName.contains("gemini") {
            return .gemini
        }
        if lowercasedModelName.contains("deepseek") {
            return .deepSeek
        }
        if lowercasedModelName.contains("llama") {
            return .llama
        }

        let parsedURL = URL(string: url)
        if hostIsAnthropicAIAPI(url: parsedURL) {
            return .anthropic
        }
        if hostIsGoogleAIAPI(url: parsedURL) {
            return .gemini
        }
        if hostIsDeepSeekAIAPI(url: parsedURL) {
            return .deepSeek
        }
        if hostIsOpenAIAPI(url: parsedURL) || hostIsAzureAIAPI(url: parsedURL) {
            return .openAI
        }
        return .openAI
    }
}
