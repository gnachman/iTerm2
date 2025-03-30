//
//  LLM.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/24.
//

import Foundation

enum LLM {
    protocol AnyResponse {
        var choiceMessages: [Message] { get }
        var isStreamingResponse: Bool { get }
    }

    struct Message: Codable, Equatable {
        enum Role: String, Codable {
            case user
            case assistant
            case system
            case function
        }
        var role: Role? = .user
        var content: String?

        // For function calling
        var name: String?  // in the response only
        var function_call: FunctionCall?

        struct FunctionCall: Codable, Equatable {
            // These are optional because they can be omitted when streaming. Otherwise they are always present.
            var name: String?
            var arguments: String?
        }

        enum CodingKeys: String, CodingKey {
            case role
            case name
            case content
            case function_call
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(role, forKey: .role)

            if let name {
                try container.encode(name, forKey: .name)
            }

            try container.encode(content, forKey: .content)

            if let function_call {
                try container.encode(function_call, forKey: .function_call)
            }
        }

        var approximateTokenCount: Int { OpenAIMetadata.instance.tokens(in: (content ?? "")) + 1 }

        var trimmedString: String? {
            guard let content else {
                return nil
            }
            return String(content.trimmingLeadingCharacters(in: .whitespacesAndNewlines))
        }
    }

    struct ErrorResponse: Codable {
        var error: Error

        struct Error: Codable {
            var message: String
            var type: String?
            var code: String?
        }
    }

    protocol AnyFunction {
        var typeErasedParameterType: Any.Type { get }
        var decl: ChatGPTFunctionDeclaration { get }
        func invoke(message: LLM.Message,
                    json: Data,
                    completion: @escaping (Result<String, Error>) -> ())
    }

    struct Function<T: Codable>: AnyFunction {
        typealias Impl = (LLM.Message, T, @escaping (Result<String, Error>) -> ()) -> ()

        var decl: ChatGPTFunctionDeclaration
        var call: Impl
        var parameterType: T.Type

        var typeErasedParameterType: Any.Type { parameterType }
        func invoke(message: Message,
                    json: Data,
                    completion: @escaping (Result<String, Error>) -> ()) {
            do {
                let value = try JSONSerialization.parseTruncatedJSON(json.lossyString, as: parameterType)
                call(message, value, completion)
            } catch {
                DLog("\(error.localizedDescription)")
                completion(.failure(AIError.wrapping(
                    error: error,
                    context: "While parsing a function call request")))
            }
        }
    }
}

fileprivate struct LegacyBodyRequestBuilder {
    var messages: [LLM.Message]
    var provider: LLMProvider

    private struct LegacyBody: Codable {
        var model: String?
        var prompt: String
        var max_tokens: Int
        var temperature: Int?
    }

    func body() throws -> Data {
        let query = messages.compactMap { $0.content }.joined(separator: "\n")
        let body = LegacyBody(model: provider.dynamicModelsSupported ? provider.model : nil,
                              prompt: query,
                              max_tokens: provider.maxTokens(functions: [], messages: messages),
                              temperature: provider.temperatureSupported ? 0 : nil)
        if body.max_tokens < 2 {
            throw AIError.requestTooLarge
        }
        let bodyEncoder = JSONEncoder()
        let bodyData = try! bodyEncoder.encode(body)
        return bodyData
    }
}

fileprivate struct GeminiRequestBuilder: Codable {
    let contents: [Content]

    struct Content: Codable {
        var role: String
        var parts: [Part]

        struct Part: Codable {
            let text: String
        }
    }

    init(messages: [LLM.Message]) {
        self.contents = messages.compactMap { message in
            // NOTE: role changed when AI chat was added but I am not able to test it, so if someone complains it's probably a bug here.
            let role: String? = switch message.role {
            case .user: "user"
            case .assistant: "model"
            case .system: "system"
            case .function, .none: nil
            }
            guard let role else {
                return nil
            }
            return Content(role: role,
                           parts: [Content.Part(text: message.content ?? "")])
        }
    }

    func body() throws -> Data {
        return try! JSONEncoder().encode(self)
    }
}

fileprivate struct ModernBodyRequestBuilder {
    var messages: [LLM.Message]
    var provider: LLMProvider
    var functions = [LLM.AnyFunction]()
    var stream: Bool

    private struct Body: Codable {
        var model: String?
        var messages = [LLM.Message]()
        var max_tokens: Int
        var temperature: Int? = 0
        var functions: [ChatGPTFunctionDeclaration]? = nil
        var function_call: String? = nil  // "none" and "auto" also allowed
        var stream: Bool
    }

    func body() throws -> Data {
        // Tokens are about 4 letters each. Allow enough tokens to include both the query and an
        // answer the same length as the query.
        let maybeDecls = functions.isEmpty ? nil : functions.map { $0.decl }
        let body = Body(model: provider.dynamicModelsSupported ? provider.model : nil,
                        messages: messages,
                        max_tokens: provider.maxTokens(functions: functions, messages: messages),
                        temperature: provider.temperatureSupported ? 0 : nil,
                        functions: maybeDecls,
                        function_call: functions.isEmpty ? nil : "auto",
                        stream: stream)
        DLog("REQUEST:\n\(body)")
        if body.max_tokens < 2 {
            throw AIError.requestTooLarge
        }
        let bodyEncoder = JSONEncoder()
        let bodyData = try! bodyEncoder.encode(body)
        return bodyData

    }
}

// There were minor changes to the API for O1 and it doesn't support functions.
fileprivate struct O1BodyRequestBuilder {
    var messages: [LLM.Message]
    var provider: LLMProvider

    private struct Body: Codable {
        var model: String?
        var messages = [LLM.Message]()
        var max_completion_tokens: Int
    }

    func body() throws -> Data {
        // O1 doesn't support "system", so replace it with user.
        let modifiedMessages = switch provider.version {
        case .o1:
            messages.map { message in
                if message.role != .system {
                    return message
                }
                var temp = message
                temp.role = .user
                return temp
            }
        case .completions, .gemini, .legacy:
            messages
        }
        let body = Body(model: provider.dynamicModelsSupported ? provider.model : nil,
                        messages: modifiedMessages,
                        max_completion_tokens: provider.maxTokens(functions: [], messages: messages))
        if body.max_completion_tokens < 2 {
            throw AIError.requestTooLarge
        }
        DLog("REQUEST:\n\(body)")
        let bodyEncoder = JSONEncoder()
        let bodyData = try! bodyEncoder.encode(body)
        return bodyData

    }
}

struct LLMRequestBuilder {
    var provider: LLMProvider
    var apiKey: String
    var messages: [LLM.Message]
    var functions = [LLM.AnyFunction]()
    var stream = false

    var headers: [String: String] {
        switch provider.platform {
        case .openAI:
            ["Content-Type": "application/json",
             "Authorization": "Bearer " + apiKey.trimmingCharacters(in: .whitespacesAndNewlines)]
        case .azure:
            [ "Content-Type": "application/json",
              "api-key": apiKey.trimmingCharacters(in: .whitespacesAndNewlines) ]
        case .gemini:
            ["Content-Type": "application/json"]
        }
    }

    var method: String { "POST" }

    func body() throws -> Data {
        switch provider.version {
        case .legacy:
            try LegacyBodyRequestBuilder(messages: messages,
                                         provider: provider).body()
        case .completions:
            try ModernBodyRequestBuilder(messages: messages,
                                         provider: provider,
                                         functions: functions,
                                         stream: stream).body()
        case .o1:
            try O1BodyRequestBuilder(messages: messages,
                                     provider: provider).body()

        case .gemini:
            try GeminiRequestBuilder(messages: messages).body()
        }
    }

    func webRequest() throws -> WebRequest {
        WebRequest(headers: headers,
                   method: method,
                   body: try body().lossyString,
                   url: provider.url(apiKey: apiKey).absoluteString)
    }
}

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
    }

    var platform = Platform.openAI
    var model: String

    var version: Version {
        if hostIsGoogle(url: completionsURL) {
            return .gemini
        }
        if hostIsOpenAIAPI(url: completionsURL) {
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
            case .completions, .legacy:
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
        case .completions:
            true
        case .o1:
            false
        case .gemini:
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
        let query = messages.compactMap { $0.content }.joined(separator: "\n")
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
            if stream {
                return LLMModernStreamingResponseParser()
            } else {
                return LLMModernResponseParser()
            }
        case .legacy:
            return stream ? LLMLegacyStreamingResponseParser() : LLMLegacyResponseParser()
        case .gemini:
            return LLMGeminiResponseParser()
        }
    }
}

protocol LLMResponseParser {
    // Throw on error, return nil on EOF (used by streaming parsers where EOF is in the message, not in the metadata like OpenAI's modern API)
    mutating func parse(data: Data) throws -> LLM.AnyResponse?
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String)
}

struct LLMModernResponseParser: LLMResponseParser {
    struct ModernResponse: Codable, LLM.AnyResponse {
        var isStreamingResponse: Bool { false }
        var id: String
        var object: String
        var created: Int
        var model: String?
        var choices: [Choice]
        var usage: Usage?  // see issue 12134

        struct Choice: Codable {
            var index: Int
            var message: LLM.Message
            var finish_reason: String
        }

        struct Usage: Codable {
            var prompt_tokens: Int
            var completion_tokens: Int?
            var total_tokens: Int
        }

        var choiceMessages: [LLM.Message] {
            return choices.map { $0.message }
        }
    }

    var parsedResponse: ModernResponse?

    mutating func parse(data: Data) throws -> LLM.AnyResponse? {
        let decoder = JSONDecoder()
        let response =  try decoder.decode(ModernResponse.self, from: data)
        DLog("RESPONSE:\n\(response)")
        parsedResponse = response
        return response
    }

    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return (nil, "")
    }
}

struct LLMModernStreamingResponseParser: LLMResponseParser {
    struct ModernStreamingResponse: Codable, LLM.AnyResponse {
        var isStreamingResponse: Bool { true }

        let id: String?
        let object: String?
        let created: TimeInterval?
        let model: String?
        let choices: [UpdateChoice]

        struct UpdateChoice: Codable {
            // The delta holds the incremental text update.
            let delta: LLM.Message
            let index: Int
            // For update chunks, finish_reason is nil.
            let finish_reason: String?
        }

        var choiceMessages: [LLM.Message] {
            return choices.map {
                LLM.Message(role: .assistant,
                            content: $0.delta.content ?? "",
                            function_call: $0.delta.function_call)
            }
        }
    }
    var parsedResponse: ModernStreamingResponse?

    mutating func parse(data: Data) throws -> LLM.AnyResponse? {
        let decoder = JSONDecoder()
        let response =  try decoder.decode(ModernStreamingResponse.self, from: data)
        DLog("RESPONSE:\n\(response)")
        parsedResponse = response
        return response
    }
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        let input = rawInput.trimmingLeadingCharacters(in: .whitespacesAndNewlines)
        guard let newlineRange = input.range(of: "\n") else {
            return (nil, String(input))
        }

        // Extract the first line (up to, but not including, the newline)
        let firstLine = input[..<newlineRange.lowerBound]
        // Everything after the newline is the remainder.
        let remainder = input[newlineRange.upperBound...]

        // Ensure the line starts with "data:".
        let prefix = "data:"
        guard firstLine.hasPrefix(prefix) else {
            // If not, we can't extract a valid JSON object.
            return (nil, String(input))
        }

        // Remove the prefix and trim whitespace to get the JSON object.
        let jsonPart = firstLine.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)

        return (String(jsonPart.removing(prefix: "data:")), String(remainder))
    }

}

struct LLMLegacyResponseParser: LLMResponseParser {
    struct LegacyResponse: Codable, LLM.AnyResponse {
        var isStreamingResponse: Bool { false }
        var id: String
        var object: String
        var created: Int
        var model: String
        var choices: [Choice]
        var usage: Usage?

        struct Choice: Codable {
            var text: String
            var index: Int?
            var logprobs: Int?
            var finish_reason: String
        }

        struct Usage: Codable {
            var prompt_tokens: Int
            var completion_tokens: Int?
            var total_tokens: Int
        }

        var choiceMessages: [LLM.Message] {
            return choices.map {
                #warning("TODO: This used to use 'model', not sure why. I changed it to an enum that combines .assistant and .model")
                return LLM.Message(role: .assistant, content: $0.text)
            }
        }
    }

    private(set) var parsedResponse: LegacyResponse?

    mutating func parse(data: Data) throws -> LLM.AnyResponse? {
        let decoder = JSONDecoder()
        let response = try decoder.decode(LegacyResponse.self, from: data)
        parsedResponse = response
        return response
    }
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return (nil, "")
    }
}

struct LLMLegacyStreamingResponseParser: LLMResponseParser {
    struct LegacyStreamingResponse: Codable, LLM.AnyResponse {
        var isStreamingResponse: Bool { true }
        var model: String
        var created_at: String
        var response: String
        var done: Bool

        var choiceMessages: [LLM.Message] {
            return [LLM.Message(role: .assistant, content: response)]
        }
    }

    private(set) var parsedResponse: LegacyStreamingResponse?

    mutating func parse(data: Data) throws -> LLM.AnyResponse? {
        let decoder = JSONDecoder()
        let response = try decoder.decode(LegacyStreamingResponse.self, from: data)
        if response.done {
            return nil
        }
        parsedResponse = response
        return response
    }
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        let input = rawInput.trimmingLeadingCharacters(in: .whitespacesAndNewlines)
        guard let newlineRange = input.range(of: "\n") else {
            return (nil, String(input))
        }

        // Extract the first line (up to, but not including, the newline)
        let firstLine = input[..<newlineRange.lowerBound]
        // Everything after the newline is the remainder.
        let remainder = input[newlineRange.upperBound...]

        // The line can optionally start with data:
        let prefixCandidates = ["data:", ""]
        var prefix = ""
        for candidate in prefixCandidates {
            if firstLine.hasPrefix(candidate) {
                prefix = candidate
                break
            }
        }

        // Remove the prefix and trim whitespace to get the JSON object.
        let jsonPart = firstLine.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)

        return (String(jsonPart.removing(prefix: prefix)), String(remainder))
    }
}

struct LLMGeminiResponseParser: LLMResponseParser {
    struct GeminiResponse: Codable, LLM.AnyResponse {
        var isStreamingResponse: Bool { false }
        var choiceMessages: [LLM.Message] {
            candidates.map {
                let role = if let content = $0.content {
                    content.role == "model" ? LLM.Message.Role.assistant : LLM.Message.Role.user
                } else {
                    LLM.Message.Role.assistant  // failed, probably because of safety
                }
                return if let text = $0.content?.parts.first?.text {
                    LLM.Message(role: role, content: text)
                } else {
                    if $0.finishReason == "SAFETY" {
                        LLM.Message(role: role, content: "The request violated Gemini's safety rules.")
                    } else if let reason = $0.finishReason {
                        LLM.Message(role: role, content: "Failed to generate a response with reason: \(reason).")
                    } else {
                        LLM.Message(role: role, content: "Failed to generate a response for an unknown reason.")
                    }
                }
            }
        }

        let candidates: [Candidate]

        struct Candidate: Codable {
            var content: Content?

            struct Content: Codable {
                var parts: [Part]
                var role: String

                struct Part: Codable {
                    var text: String
                }
            }
            var finishReason: String?
        }
    }
    private(set) var parsedResponse: GeminiResponse?

    mutating func parse(data: Data) throws -> LLM.AnyResponse? {
        let decoder = JSONDecoder()
        let response = try decoder.decode(GeminiResponse.self, from: data)
        parsedResponse = response
        return response
    }
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        // Streaming not implemented
        return (nil, "")
    }
}

struct LLMErrorParser {
    private(set) var error: LLM.ErrorResponse?

    mutating func parse(data: Data) -> String? {
        let decoder = JSONDecoder()
        error = try? decoder.decode(LLM.ErrorResponse.self, from: data)
        return error?.error.message
    }

    static func errorReason(data: Data) -> String? {
        var parser = LLMErrorParser()
        return parser.parse(data: data)
    }
}

