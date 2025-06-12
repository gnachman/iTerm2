//
//  AIMetadata.swift
//  iTerm2
//
//  Created by George Nachman on 6/11/25.
//

@objc
class AIMetadata: NSObject {
    @objc static let instance = AIMetadata()

    struct Model {
        var name: String
        var contextWindowTokens: Int
        var maxResponseTokens: Int
        var url: String
        var api: iTermAIAPI
        enum Feature: Hashable, Equatable {
            case systemMessage // Supports a separate system prompt.
            case functionCalling // Supports tool/function calling.
            case streaming // Can stream response tokens.
            case jsonMode // Can be constrained to output valid JSON.
            case imageInput // Can process and understand images (multimodal).
            case hostedFileSearch // Can search over files provided to the API (e.g., OpenAI Assistants).
            case hostedWebSearch // Can perform web searches (e.g., via a built-in tool).
        }
        var features: Set<Feature>

        enum VectorStoreConfig: Int {
            case disabled = 0
            case openAI = 1
        }
        var vectorStoreConfig: VectorStoreConfig = .disabled
    }

    private let models: [Model] = [
        Model(
            name: "gpt-4o",
            contextWindowTokens: 128_000,
            maxResponseTokens: 16_384,
            url: "https://api.openai.com/v1/responses",
            api: .responses,
            features: [.systemMessage, .functionCalling, .hostedFileSearch, .hostedWebSearch, .streaming],
            vectorStoreConfig: .openAI
        ),
        Model(
            name: "gpt-4o-mini",
            contextWindowTokens: 128_000,
            maxResponseTokens: 16_384,
            url: "https://api.openai.com/v1/responses",
            api: .responses,
            features: [.systemMessage, .functionCalling, .hostedFileSearch, .hostedWebSearch, .streaming],
            vectorStoreConfig: .openAI
        ),
        Model(
            name: "gpt-4.1",
            contextWindowTokens: 1_000_000,
            maxResponseTokens: 32_768,
            url: "https://api.openai.com/v1/responses",
            api: .responses,
            features: [.systemMessage, .functionCalling, .hostedFileSearch, .hostedWebSearch, .streaming],
            vectorStoreConfig: .openAI
        ),
        Model(
            name: "gpt-4.1-mini",
            contextWindowTokens: 1_000_000,
            maxResponseTokens: 16_384,
            url: "https://api.openai.com/v1/responses",
            api: .responses,
            features: [.systemMessage, .functionCalling, .hostedFileSearch, .hostedWebSearch, .streaming],
            vectorStoreConfig: .openAI
        ),

        // O-series reasoning models
        Model(
            name: "o3",
            contextWindowTokens: 200_000,
            maxResponseTokens: 100_000,
            url: "https://api.openai.com/v1/responses",
            api: .responses,
            features: [.hostedFileSearch],
            vectorStoreConfig: .openAI
        ),
        Model(
            name: "o3-pro",
            contextWindowTokens: 200_000,
            maxResponseTokens: 100_000,
            url: "https://api.openai.com/v1/responses",
            api: .responses,
            features: [.functionCalling],
            vectorStoreConfig: .openAI
        ),
        Model(
            name: "o4-mini",
            contextWindowTokens: 200_000,
            maxResponseTokens: 100_000,
            url: "https://api.openai.com/v1/responses",
            api: .responses,
            features: [.hostedFileSearch, .streaming, .functionCalling],
            vectorStoreConfig: .openAI
        ),

        // MARK: - Google Models

        Model(
            name: "gemini-2.0-flash-lite",
            contextWindowTokens: 1_048_576,
            maxResponseTokens: 8_192,
            url: "https://generativelanguage.googleapis.com/v1beta/models/{{MODEL}}",
            api: .gemini,
            features: [.systemMessage, .functionCalling, .streaming]
        ),
        Model(
            name: "gemini-2.0-flash",
            contextWindowTokens: 1_048_576,
            maxResponseTokens: 8_192,
            url: "https://generativelanguage.googleapis.com/v1beta/models/{{MODEL}}",
            api: .gemini,
            features: [.systemMessage, .functionCalling, .streaming]
        ),
        Model(
            name: "gemini-1.5-pro",
            contextWindowTokens: 1_048_576,
            maxResponseTokens: 8_192,
            url: "https://generativelanguage.googleapis.com/v1beta/models/{{MODEL}}",
            api: .gemini,
            features: [.systemMessage, .functionCalling, .streaming]
        ),

        // MARK: - DeepSeek Models

        Model(
            name: "deepseek-chat",
            contextWindowTokens: 65_536,
            maxResponseTokens: 8_000,
            url: "https://api.deepseek.com/v1/chat/completions",
            api: .deepSeek,
            features: [.systemMessage, .functionCalling, .streaming]
        ),
        Model(
            name: "deepseek-coder",
            contextWindowTokens: 65_536,
            maxResponseTokens: 8_000,
            url: "https://api.deepseek.com/v1/chat/completions",
            api: .deepSeek,
            features: [.systemMessage, .functionCalling, .streaming]
        ),
        Model(
            name: "deepseek-reasoner",
            contextWindowTokens: 64_000,
            maxResponseTokens: 8_000,
            url: "https://api.deepseek.com/v1/chat/completions",
            api: .deepSeek,
            features: [.systemMessage, .functionCalling, .streaming]
        ),

        // MARK: - Local Models (via Ollama)

        // Llama models
        // Llama supports function calling only without streaming. I dont want to expose a "streamingFunctionCalling" feature and add that to the UI. Some day this restriction may go away. For now, we'll have to silently offer no tools whwn streaming is on :(
        // Per https://ollama.readthedocs.io/en/api/#generate-a-chat-completion:
        //   "tools: tools for the model to use if supported. Requires stream to be set
        //    to false"
        Model(
            name: "llama3.3:latest",
            contextWindowTokens: 131_072,
            maxResponseTokens: 131_072,
            url: "http://localhost:11434/api/chat",
            api: .llama,
            features: [.systemMessage, .streaming, .functionCalling]
        ),
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
