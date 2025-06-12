//
//  LLMProvider.swift
//  iTerm2
//
//  Created by George Nachman on 6/6/25.
//

struct LLMProvider {
    var model: AIMetadata.Model

    // URL assuming the completions API is in use.
    private var completionsURL: URL {
        var value = iTermPreferences.string(forKey: kPreferenceKeyAITermURL) ?? ""
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value = "https://api.openai.com/v1/completions"
        }
        return URL(string: value) ?? URL(string: "about:empty")!
    }

    // URL assuming the responses API is in use.
    private var responsesURL: URL {
        var value = iTermPreferences.string(forKey: kPreferenceKeyAITermURL) ?? ""
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value = "https://api.openai.com/v1/responses"
        }
        return URL(string: value) ?? URL(string: "about:empty")!
    }

    func url(apiKey: String, streaming: Bool) -> URL {
        switch model.api {
        case .gemini:
            let url = URL(string: model.url) ?? URL(string: "about:empty")!
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return URL(string: "about:empty")!
            }
            components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
            components.path = String(components.path.removing(suffix: ":streamGenerateContent"))
            components.path = String(components.path.removing(suffix: ":generateContent"))
            components.path = components.path.replacingOccurrences(of: "{{MODEL}}", with: model.name)
            if streaming {
                components.path += ":streamGenerateContent"
                components.queryItems?.append(URLQueryItem(name: "alt", value: "sse"))
            } else {
                components.path += ":generateContent"
            }
            return components.url ?? URL(string: "about:empty")!
        default:
            return URL(string: model.url) ?? URL(string: "about:empty")!
        }
    }

    func createVectorStoreURL(apiKey: String) -> URL? {
        return model.vectorStoreURL.compactMap { URL(string: $0) }
    }

    func uploadURL() -> URL? {
        return model.fileUploadURL.compactMap { URL(string: $0) }
    }

    func addFileToVectorStoreURL(apiKey: String, vectorStoreID: String) -> URL? {
        guard let url = model.addToVectorStoreURL?(vectorStoreID) else {
            return nil
        }
        return URL(string: url)
    }

    var urlIsValid: Bool {
        return url(apiKey: "placeholder", streaming: false).scheme != "about"
    }

    var displayName: String {
        if LLMMetadata.hostIsOpenAIAPI(url: url(apiKey: "placeholder",
                                                streaming: false)) {
            return "OpenAI"
        }
        if LLMMetadata.hostIsGoogleAIAPI(url: url(apiKey: "placeholder",
                                                  streaming: false)) {
            return "Google"
        }
        if LLMMetadata.hostIsAzureAIAPI(url: url(apiKey: "placeholder",
                                                 streaming: false)) {
            return "Azure"
        }
        if model.name.contains("llama") {
            return "LLaMa"
        }
        return "Unknown Platform"
    }

    var dynamicModelsSupported: Bool {
        if LLMMetadata.hostIsAzureAIAPI(url: url(apiKey: "placeholder", streaming: false)) {
            return false
        }
        switch model.api {
        case .gemini:
            return false
        default:
            return true
        }
    }

    var functionsSupported: Bool {
        return model.features.contains(.functionCalling)
    }

    var supportsStreaming: Bool {
        return model.features.contains(.streaming)
    }

    var supportsUserAttachments: Bool {
        switch model.api {
        case .responses, .chatCompletions, .llama: true
        case .completions, .gemini, .earlyO1: false
        @unknown default: false
        }
    }

    var supportsHostedWebSearch: Bool {
        return model.features.contains(.hostedWebSearch)
    }

    func maxTokens(functions: [LLM.AnyFunction],
                   messages: [LLM.Message]) -> Int {
        let encodedFunctions = {
            if functions.isEmpty || !functionsSupported {
                return ""
            }
            guard let data = try? JSONEncoder().encode(functions.map { $0.decl }) else {
                return ""
            }
            return String(data: data, encoding: .utf8) ?? ""
        }()
        let query = messages.compactMap { $0.body.content }.joined(separator: "\n")
        let naiveLimit = Int(iTermPreferences.int(forKey: kPreferenceKeyAITokenLimit)) - AIMetadata.instance.tokens(in: query) - AIMetadata.instance.tokens(in: encodedFunctions)
        return min(model.maxResponseTokens, naiveLimit)
    }

    func requestIsTooLarge(body: String) -> Bool {
        return AIMetadata.instance.tokens(in: body) >= Int(iTermPreferences.int(forKey: kPreferenceKeyAITokenLimit))
    }

    func responseParser() -> LLMResponseParser {
        switch model.api {
        case .chatCompletions, .earlyO1:
            return LLMModernResponseParser()
        case .responses:
            return ResponsesResponseParser()
        case .completions:
            return LLMLegacyResponseParser()
        case .gemini:
            return LLMGeminiResponseParser()
        case .llama:
            return LlamaResponseParser()
        @unknown default:
            it_fatalError()
        }
    }

    func streamingResponseParser(stream: Bool) -> LLMStreamingResponseParser? {
        it_assert(stream)
        switch model.api {
        case .chatCompletions, .earlyO1:
            return LLMModernStreamingResponseParser()

        case .responses:
            return ResponsesResponseStreamingParser()

        case .completions:
            return LLMLegacyStreamingResponseParser()

        case .llama:
            return LlamaStreamingResponseParser()

        case .gemini:
            return LLMGeminiStreamingResponseParser()

        @unknown default:
            return nil
        }
    }
}

