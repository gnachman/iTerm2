//
//  AIMetadata.swift
//  iTerm2
//
//  Created by George Nachman on 6/11/25.
//

@objc(iTermAIModel)
class AIModel: NSObject {
    private var model: AIMetadata.Model

    @objc(initWithModelName:url:legacy:)
    convenience init(modelName: String, url: String?, legacy: Bool) {
        let urlGuess: String
        let apiGuess: iTermAIAPI
        let featuresGuess: Set<AIMetadata.Model.Feature>
        let vendorGuess: iTermAIVendor?
        if modelName.contains("gemini") {
            urlGuess = "https://generativelanguage.googleapis.com/v1beta/models/{{MODEL}}"
            apiGuess = .gemini
            featuresGuess = [.functionCalling, .streaming]
            vendorGuess = .gemini
        } else if modelName.contains("deepseek") {
            urlGuess = "https://api.deepseek.com/v1/chat/completions"
            apiGuess = .deepSeek
            featuresGuess = [.functionCalling, .streaming]
            vendorGuess = .deepSeek
        } else if modelName.contains("llama") {
            urlGuess = "http://localhost:11434/api/chat"
            apiGuess = .llama
            featuresGuess = [.streaming, .functionCalling]
            vendorGuess = .llama
        } else if modelName.contains("claude") {
            urlGuess = "https://api.anthropic.com/v1/messages"
            apiGuess = .anthropic
            featuresGuess = [.streaming, .functionCalling]
            vendorGuess = .anthropic
        } else if modelName.contains("gpt") || modelName.hasPrefix("o") {
            if legacy {
                urlGuess = "https://api.openai.com/v1/completions"
                apiGuess = .completions
                featuresGuess = []
            } else {
                urlGuess = "https://api.openai.com/v1/chat/completions"
                apiGuess = .chatCompletions
                featuresGuess = [.functionCalling, .hostedFileSearch, .hostedWebSearch, .streaming, .hostedCodeInterpreter]
            }
            vendorGuess = .openAI
        } else {
            apiGuess = .chatCompletions
            urlGuess = "about:empty"
            featuresGuess = []
            vendorGuess = nil
        }
        let justURL = if let url, !url.isEmpty {
            url
        } else {
            urlGuess
        }
        self.init(AIMetadata.Model(name: modelName,
                                   contextWindowTokens: 8_192,
                                   maxResponseTokens: 8_192,
                                   url: justURL,
                                   api: apiGuess,
                                   features: featuresGuess,
                                   vendor: vendorGuess))
    }

    init(_ model: AIMetadata.Model) {
        self.model = model
    }

    @objc
    static func modelFromSettings() -> AIModel? {
        guard let model = LLMMetadata.model() else {
            return nil
        }
        return AIModel(model)
    }

    @objc var name: String { model.name }
    @objc var contextWindowTokens: Int { model.contextWindowTokens }
    @objc var maxResponseTokens: Int { model.maxResponseTokens }
    @objc var url: String { model.url }
    @objc var api: iTermAIAPI { model.api }
    @objc var functionCallingFeatureEnabled: Bool { model.features.contains(.functionCalling) }
    @objc var streamingFeatureEnabled: Bool { model.features.contains(.streaming) }
    @objc var hostedFileSearchFeatureEnabled: Bool { model.features.contains(.hostedFileSearch) }
    @objc var hostedWebSearchFeatureEnabled: Bool { model.features.contains(.hostedWebSearch) }
    @objc var hostedCodeInterpreterFeatureEnabled: Bool { model.features.contains(.hostedCodeInterpreter) }

    @objc var vectorStoreConfig: AIMetadata.Model.VectorStoreConfig { model.vectorStoreConfig }
}

@objc
class AIMetadata: NSObject {
    @objc static let instance = AIMetadata()
    @objc static var defaultModel: AIModel { AIModel(instance.models[0]) }

    struct Model: Equatable {
        var name: String
        var contextWindowTokens: Int
        var maxResponseTokens: Int
        var url: String
        var api: iTermAIAPI
        enum Feature: Hashable, Equatable {
            case functionCalling // Supports tool/function calling.
            case streaming // Can stream response tokens.
            case hostedFileSearch // Can search over files provided to the API (e.g., OpenAI Assistants).
            case hostedWebSearch // Can perform web searches (e.g., via a built-in tool).
            case hostedCodeInterpreter
            case configurableThinking
        }
        var features: Set<Feature>

        @objc enum VectorStoreConfig: Int {
            case disabled = 0
            case openAI = 1
        }
        var vectorStoreConfig: VectorStoreConfig = .disabled
        var vendor: iTermAIVendor?
    }

    static var recommendedOpenAIModel: Model {
        // TOOD: When gpt-5 doesn't require identification for streaming switch this over
        return AIMetadata.gpt4_1
    }

    static var recommendedDeepSeekModel: Model {
        return AIMetadata.deepseek_chat
    }

    static var recommendedGeminiModel: Model {
        return AIMetadata.gemini_2_0_flash
    }

    static var recommendedLlamaModel: Model {
        return AIMetadata.llama_3_3_latest
    }

    static var recommendedAnthropicModel: Model {
        return AIMetadata.claude_4_sonnet
    }

    static var alternateOpenAIModels: [Model] {
        return AIMetadata.instance.models.filter { candidate in
            candidate.vendor == .openAI
        }
    }

    static var alternateDeepSeekModels: [Model] {
        return AIMetadata.instance.models.filter { candidate in
            candidate.vendor == .deepSeek
        }
    }

    static var alternateGeminiModels: [Model] {
        return AIMetadata.instance.models.filter { candidate in
            candidate.vendor == .gemini
        }
    }

    static var alternateLlamaModels: [Model] {
        return AIMetadata.instance.models.filter { candidate in
            candidate.vendor == .llama
        }
    }

    static var alternateAnthropicModels: [Model] {
        return AIMetadata.instance.models.filter { candidate in
            candidate.vendor == .anthropic
        }
    }

    private static let gpt5 = Model(
        name: "gpt-5",
        contextWindowTokens: 400_000,
        maxResponseTokens: 128_000,
        url: "https://api.openai.com/v1/responses",
        api: .responses,
        features: [.functionCalling, .hostedFileSearch, .hostedWebSearch, .streaming, .hostedCodeInterpreter, .configurableThinking],
        vectorStoreConfig: .openAI,
        vendor: .openAI
    )
    private static let gpt5_mini = Model(
        name: "gpt-5-mini",
        contextWindowTokens: 400_000,
        maxResponseTokens: 128_000,
        url: "https://api.openai.com/v1/responses",
        api: .responses,
        features: [.functionCalling, .hostedFileSearch, .hostedWebSearch, .streaming, .hostedCodeInterpreter, .configurableThinking],
        vectorStoreConfig: .openAI,
        vendor: .openAI
    )
    private static let gpt5_nano = Model(
        name: "gpt-5-nano",
        contextWindowTokens: 400_000,
        maxResponseTokens: 128_000,
        url: "https://api.openai.com/v1/responses",
        api: .responses,
        features: [.functionCalling, .hostedFileSearch, .hostedWebSearch, .streaming, .hostedCodeInterpreter, .configurableThinking],
        vectorStoreConfig: .openAI,
        vendor: .openAI
    )
    private static let gpt4_1 = Model(
        name: "gpt-4.1",
        contextWindowTokens: 1_000_000,
        maxResponseTokens: 32_768,
        url: "https://api.openai.com/v1/responses",
        api: .responses,
        features: [.functionCalling, .hostedFileSearch, .hostedWebSearch, .streaming, .hostedCodeInterpreter],
        vectorStoreConfig: .openAI,
        vendor: .openAI
    )
    private static let deepseek_chat = Model(
        name: "deepseek-chat",
        contextWindowTokens: 65_536,
        maxResponseTokens: 8_000,
        url: "https://api.deepseek.com/v1/chat/completions",
        api: .deepSeek,
        features: [.functionCalling, .streaming],
        vendor: .deepSeek
    )
    private static let gemini_2_0_flash = Model(
        name: "gemini-2.0-flash",
        contextWindowTokens: 1_048_576,
        maxResponseTokens: 8_192,
        url: "https://generativelanguage.googleapis.com/v1beta/models/{{MODEL}}",
        api: .gemini,
        features: [.functionCalling, .streaming],
        vendor: .gemini
    )
    static private let llama_3_3_latest = Model(
        name: "llama3.3:latest",
        contextWindowTokens: 131_072,
        maxResponseTokens: 131_072,
        url: "http://localhost:11434/api/chat",
        api: .llama,
        features: [.streaming, .functionCalling],
        vendor: .llama
    )

    // Latest Claude 4 models with official aliases
    private static let claude_4_sonnet = Model(
        name: "claude-sonnet-4-0",
        contextWindowTokens: 200_000,
        maxResponseTokens: 64_000,
        url: "https://api.anthropic.com/v1/messages",
        api: .anthropic,
        features: [.functionCalling, .streaming],
        vendor: .anthropic
    )

    private static let claude_4_1_opus = Model(
        name: "claude-opus-4-1",
        contextWindowTokens: 200_000,
        maxResponseTokens: 32_000,
        url: "https://api.anthropic.com/v1/messages",
        api: .anthropic,
        features: [.functionCalling, .streaming],
        vendor: .anthropic
    )
    private static let claude_4_opus = Model(
        name: "claude-opus-4-0",
        contextWindowTokens: 200_000,
        maxResponseTokens: 32_000,
        url: "https://api.anthropic.com/v1/messages",
        api: .anthropic,
        features: [.functionCalling, .streaming],
        vendor: .anthropic
    )
    let models: [Model] = [
        // The first model will be the default.
        AIMetadata.gpt5,
        AIMetadata.gpt5_mini,
        AIMetadata.gpt5_nano,
        AIMetadata.gpt4_1,
        Model(
            name: "gpt-4o",
            contextWindowTokens: 128_000,
            maxResponseTokens: 16_384,
            url: "https://api.openai.com/v1/responses",
            api: .responses,
            features: [.functionCalling, .hostedFileSearch, .hostedWebSearch, .streaming, .hostedCodeInterpreter],
            vectorStoreConfig: .openAI,
            vendor: .openAI
        ),
        Model(
            name: "gpt-4o-mini",
            contextWindowTokens: 128_000,
            maxResponseTokens: 16_384,
            url: "https://api.openai.com/v1/responses",
            api: .responses,
            features: [.functionCalling, .hostedFileSearch, .hostedWebSearch, .streaming, .hostedCodeInterpreter],
            vectorStoreConfig: .openAI,
            vendor: .openAI
        ),
        Model(
            name: "gpt-4.1-mini",
            contextWindowTokens: 1_000_000,
            maxResponseTokens: 16_384,
            url: "https://api.openai.com/v1/responses",
            api: .responses,
            features: [.functionCalling, .hostedFileSearch, .hostedWebSearch, .streaming, .hostedCodeInterpreter],
            vectorStoreConfig: .openAI,
            vendor: .openAI
        ),

        // O-series reasoning models
        Model(
            name: "o3",
            contextWindowTokens: 200_000,
            maxResponseTokens: 100_000,
            url: "https://api.openai.com/v1/responses",
            api: .responses,
            features: [.hostedFileSearch, .hostedCodeInterpreter, .configurableThinking],
            vectorStoreConfig: .openAI,
            vendor: .openAI
        ),
        Model(
            name: "o3-pro",
            contextWindowTokens: 200_000,
            maxResponseTokens: 100_000,
            url: "https://api.openai.com/v1/responses",
            api: .responses,
            features: [.functionCalling, .hostedCodeInterpreter, .configurableThinking],
            vectorStoreConfig: .openAI,
            vendor: .openAI
        ),
        Model(
            name: "o4-mini",
            contextWindowTokens: 200_000,
            maxResponseTokens: 100_000,
            url: "https://api.openai.com/v1/responses",
            api: .responses,
            features: [.hostedFileSearch, .streaming, .functionCalling, .hostedCodeInterpreter, .configurableThinking],
            vectorStoreConfig: .openAI,
            vendor: .openAI
        ),

        // MARK: - Google Models

        Model(
            name: "gemini-2.0-flash-lite",
            contextWindowTokens: 1_048_576,
            maxResponseTokens: 8_192,
            url: "https://generativelanguage.googleapis.com/v1beta/models/{{MODEL}}",
            api: .gemini,
            features: [.functionCalling, .streaming],
            vendor: .gemini
        ),
        AIMetadata.gemini_2_0_flash,
        Model(
            name: "gemini-1.5-pro",
            contextWindowTokens: 1_048_576,
            maxResponseTokens: 8_192,
            url: "https://generativelanguage.googleapis.com/v1beta/models/{{MODEL}}",
            api: .gemini,
            features: [.functionCalling, .streaming],
            vendor: .gemini
        ),

        // MARK: - DeepSeek Models

        AIMetadata.deepseek_chat,
        Model(
            name: "deepseek-coder",
            contextWindowTokens: 65_536,
            maxResponseTokens: 8_000,
            url: "https://api.deepseek.com/v1/chat/completions",
            api: .deepSeek,
            features: [.functionCalling, .streaming],
            vendor: .deepSeek
        ),
        Model(
            name: "deepseek-reasoner",
            contextWindowTokens: 64_000,
            maxResponseTokens: 8_000,
            url: "https://api.deepseek.com/v1/chat/completions",
            api: .deepSeek,
            features: [.functionCalling, .streaming],
            vendor: .deepSeek
        ),

        // MARK: - Anthropic Models

        AIMetadata.claude_4_sonnet,
        AIMetadata.claude_4_1_opus,
        AIMetadata.claude_4_opus,

        // MARK: - Local Models (via Ollama)

        // Llama models
        // Llama supports function calling only without streaming. I dont want
        // to expose a "streamingFunctionCalling" feature and add that to the
        // UI. Some day this restriction may go away. For now, we'll have to
        // silently offer no tools whwn streaming is on :(
        // Per https://ollama.readthedocs.io/en/api/#generate-a-chat-completion:
        //   "tools: tools for the model to use if supported. Requires stream to be set
        //    to false"
        // To find places where you need to make changes to adjust this logic search for
        // #llama-streaming-functions
        AIMetadata.llama_3_3_latest,
    ]

    @objc(enumerateModels:) func enumerateModels(_ closure: (String, Int, String?) -> ()) {
        for model in models {
            closure(model.name, model.contextWindowTokens, model.url)
        }
    }

    @objc(contextWindowTokensForModelName:) func objc_contextWindowTokens(modelName: String) -> NSNumber? {
        if let model = models.first(where: { $0.name == modelName}) {
            return NSNumber(value: model.contextWindowTokens)
        }
        return nil
    }

    @objc(responseTokenLimitForModelName:)
    func objc_responseTokenLimit(modelName: String) -> NSNumber? {
        if let model = models.first(where: { $0.name == modelName}) {
            return NSNumber(value: model.maxResponseTokens)
        }
        return nil
    }

    @objc(apiForModel:fallback:)
    func api(for model: String, fallback: iTermAIAPI) -> iTermAIAPI {
        if let modelIndex = models.firstIndex(where: { $0.name == model }) {
            return models[modelIndex].api
        }
        if model.contains("gpt") {
            return .responses
        }
        if model.contains("gemini") {
            return .gemini
        }
        if model.contains("deepseek") {
            return .completions
        }
        if model.contains("llama") {
            return .completions
        }
        if model.contains("claude") {
            return .anthropic
        }
        return fallback
    }

    @objc(urlForModelName:)
    func objc_url(modelName: String) -> String? {
        return models.first(where: { $0.name == modelName })?.url
    }

    func maxResponseTokens(modelName: String) -> Int? {
        guard let model = models.first(where: { $0.name == modelName}) else {
            return nil
        }
        return model.maxResponseTokens
    }

    func tokens(in string: String) -> Int {
        return string.utf8.count / 2
    }


    @objc(modelHasDefaults:)
    func modelHasDefaults(_ model: String) -> Bool {
        return models.contains {
            $0.name == model
        }
    }
    @objc(modelSupportsHostedCodeInterpreter:)
    func modelSupportsHostedCodeInterpreter(_ model: String) -> Bool {
        guard let obj = models.first(where: { $0.name == model }) else {
            return false
        }
        return obj.features.contains(.hostedCodeInterpreter)
    }

    @objc(modelSupportsHostedFileSearch:)
    func modelSupportsHostedFileSearch(_ model: String) -> Bool {
        guard let obj = models.first(where: { $0.name == model }) else {
            return false
        }
        return obj.features.contains(.hostedFileSearch)
    }

    @objc(vectorStoreForModel:)
    func vectorStore(for model: String) -> Int {
        guard let obj = models.first(where: { $0.name == model }) else {
            return Model.VectorStoreConfig.disabled.rawValue
        }
        return obj.vectorStoreConfig.rawValue
    }

    @objc(modelSupportsHostedWebSearch:)
    func modelSupportsHostedWebSearch(_ model: String) -> Bool {
        guard let obj = models.first(where: { $0.name == model }) else {
            return false
        }
        return obj.features.contains(.hostedWebSearch)
    }

    @objc(modelSupportsFunctionCalling:)
    func modelSupportsFunctionCalling(_ model: String) -> Bool {
        guard let obj = models.first(where: { $0.name == model }) else {
            return false
        }
        return obj.features.contains(.functionCalling)
    }

    @objc(modelSupportsStreamingResponses:)
    func modelSupportsStreamingResponses(_ model: String) -> Bool {
        guard let obj = models.first(where: { $0.name == model }) else {
            return false
        }
        return obj.features.contains(.streaming)
    }




}
