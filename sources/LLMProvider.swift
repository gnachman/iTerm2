//
//  LLMProvider.swift
//  iTerm2
//
//  Created by George Nachman on 6/6/25.
//

struct LLMProvider {
    // If you add new platforms update the advanced setting to give their names.
    enum Platform: String {
        case openAI = "OpenAI"
        case azure = "Azure"
        case gemini = "Gemini"
    }

    enum Version {
        case legacy
        case completions
        case gemini
        case o1
        case responses
    }

    var platform = Platform.openAI
    var model: String

    var version: Version {
        if hostIsGoogle(url: completionsURL) {
            return .gemini
        }
        if hostIsOpenAIAPI(url: completionsURL) {
            if iTermAdvancedSettingsModel.openAIResponsesAPI() {
                return .responses
            }
            if model.hasPrefix("o1") {
                return .o1
            }
            return openAIModelIsLegacy(model: model) ? .legacy : .completions
        }
        return iTermPreferences.bool(forKey: kPreferenceKeyAITermUseLegacyAPI) ? .legacy : .completions
    }

    private func openAIModelIsLegacy(model: String) -> Bool {
        return LLMMetadata.openAIModelIsLegacy(model: model)
    }

    var usingOpenAI: Bool {
        return hostIsOpenAIAPI(url: url(apiKey: "placeholder"))
    }

    // URL assuming the completions API is in use. This may be overridden for the legacy API.
    private var completionsURL: URL {
        var value = iTermPreferences.string(forKey: kPreferenceKeyAITermURL) ?? ""
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value = iTermPreferences.defaultObject(forKey: kPreferenceKeyAITermURL) as! String
        }
        return URL(string: value) ?? URL(string: "about:empty")!
    }

    func url(apiKey: String) -> URL {
        switch platform {
        case .gemini:
            let url = URL(string: iTermPreferences.string(forKey: kPreferenceKeyAITermURL) ?? "") ?? URL(string: "about:empty")!
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
            return components?.url ?? URL(string: "about:empty")!

        case .openAI, .azure:
            let completionsURL = self.completionsURL
            if hostIsOpenAIAPI(url: completionsURL) && version == .completions {
                // The default value for the setting is the legacy URL, so modernize it if needed.
                return URL(string: "https://api.openai.com/v1/chat/completions")!
            }
            return completionsURL
        }
    }

    func createVectorStoreURL(apiKey: String) -> URL? {
        switch platform {
        case .gemini, .azure:
            return nil
        case .openAI:
            return URL(string: "https://api.openai.com/v1/vector_stores")!
        }
    }

    func uploadURL(apiKey: String) -> URL? {
        switch platform {
        case .gemini, .azure:
            return nil
        case .openAI:
            return URL(string: "https://api.openai.com/v1/files")!
        }
    }

    func addFileToVectorStoreURL(apiKey: String, vectorStoreID: String) -> URL? {
        switch platform {
        case .gemini, .azure:
            return nil
        case .openAI:
            return URL(string: "https://api.openai.com/v1/vector_stores/\(vectorStoreID)/file_batches")!
        }
    }

    private func hostIsGoogle(url: URL?) -> Bool {
        return url?.host == "generativelanguage.googleapis.com"
    }

    private func hostIsOpenAIAPI(url: URL?) -> Bool {
        return LLMMetadata.hostIsOpenAIAPI(url: url)
    }

    var urlIsValid: Bool {
        return url(apiKey: "placeholder").scheme != "about"
    }

    var displayName: String {
        if usingOpenAI {
            return "OpenAI"
        }
        switch platform {
        case .openAI:
            return "OpenAI"
        case .azure:
            return "Microsoft"
        case .gemini:
            return "Google"
        }
    }

    var dynamicModelsSupported: Bool {
        switch platform {
        case .openAI:
            true
        case .azure, .gemini:
            false
        }
    }

    var temperatureSupported: Bool {
        switch platform {
        case .openAI:
            switch version {
            case .o1:
                false
            case .completions, .legacy, .responses:
                true
            case .gemini:
                it_fatalError()
            }
        case .azure, .gemini:
            false
        }
    }

    var functionsSupported: Bool {
        switch version {
        case .legacy:
            false
        case .completions, .responses:
            true
        case .o1:
            false
        case .gemini:
            false
        }
    }

    var supportsStreaming: Bool {
        switch version {
        case .legacy:
            false
        case .completions:
            true
        case .gemini:
            false
        case .o1:
            false
        case .responses:
            true
        }
    }

    var supportsHostedWebSearch: Bool {
        switch version {
        case .responses:
            true
        case .legacy, .completions, .o1, .gemini:
            false
        }
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
        let naiveLimit = Int(iTermPreferences.int(forKey: kPreferenceKeyAITokenLimit)) - OpenAIMetadata.instance.tokens(in: query) - OpenAIMetadata.instance.tokens(in: encodedFunctions)
        if let responseLimit = OpenAIMetadata.instance.maxResponseTokens(modelName: model) {
            return min(responseLimit, naiveLimit)
        }
        return naiveLimit
    }

    func requestIsTooLarge(body: String) -> Bool {
        return OpenAIMetadata.instance.tokens(in: body) >= Int(iTermPreferences.int(forKey: kPreferenceKeyAITokenLimit))
    }

    func responseParser(stream: Bool) -> LLMResponseParser {
        switch version {
        case .completions, .o1:
            return LLMModernResponseParser()
        case .responses:
            return ResponsesResponseParser()
        case .legacy:
            return LLMLegacyResponseParser()
        case .gemini:
            return LLMGeminiResponseParser()
        }
    }

    func streamingResponseParser(stream: Bool) -> LLMStreamingResponseParser {
        it_assert(stream)
        switch version {
        case .completions, .o1:
            return LLMModernStreamingResponseParser()

        case .responses:
            return ResponsesResponseStreamingParser()

        case .legacy:
            return LLMLegacyStreamingResponseParser()

        case .gemini:
            it_fatalError()
        }
    }
}

