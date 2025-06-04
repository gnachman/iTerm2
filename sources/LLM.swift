//
//  LLM.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/24.
//

import Foundation

enum LLM {
    enum Role: String, Codable {
        case user
        case assistant
        case system
        case function
    }
    struct FunctionCall: Codable, Equatable {
        // These are optional because they can be omitted when streaming. Otherwise they are always present.
        var name: String?
        var arguments: String?
    }


    protocol AnyResponse {
        var choiceMessages: [Message] { get }
        var isStreamingResponse: Bool { get }
    }

    protocol AnyStreamingResponse {
        // Streaming parsers will sometimes have to parse messages that are just status updates
        // nobody cares about. Set ignore to true in that case.
        var ignore: Bool { get }
        var choiceMessages: [Message] { get }
        var isStreamingResponse: Bool { get }
    }

    // This is a platform-independent representation of a message to or from an LLM.
    struct Message: Codable, Equatable {
        var role: Role? = .user

        enum StatusUpdate: Codable, Equatable {
            case webSearchStarted
            case webSearchFinished
            case codeInterpreterStarted
            case codeInterpreterFinished
        }

        struct FunctionCallID: Codable, Equatable {
            var callID: String
            var itemID: String
        }

        struct Attachment: Codable, Equatable {
            enum AttachmentType: Codable, Equatable {
                case code(String)
                case statusUpdate(StatusUpdate)

                struct File: Codable, Equatable {
                    var name: String
                    var content: Data
                    var mimeType: String
                    var localPath: String?
                }
                case file(File)
            }
            var inline: Bool
            var id: String //  e.g., ci_xxx for code interpreter
            var type: AttachmentType

            func appending(_ other: Attachment) -> Attachment? {
                if other.id != id {
                    return nil
                }
                switch type {
                case .code(let lhs):
                    switch other.type {
                    case .code(let rhs):
                        return .init(inline: inline, id: id, type: .code(lhs + rhs))
                    case .statusUpdate, .file:
                        return nil
                    }
                case .file(let lhs):
                    switch other.type {
                    case .statusUpdate, .code:
                        return nil
                    case .file(let rhs):
                        return .init(inline: inline,
                                     id: id,
                                     type: .file(.init(name: lhs.name + rhs.name,
                                                       content: lhs.content + rhs.content,
                                                       mimeType: lhs.mimeType + rhs.mimeType,
                                                       localPath: String?.concat(lhs.localPath, rhs.localPath))))
                    }
                case .statusUpdate:
                    return nil
                }
            }
        }

        enum Body: Codable, Equatable {
            case uninitialized
            case text(String)
            case functionCall(FunctionCall, id: FunctionCallID?)
            case functionOutput(name: String, output: String, id: FunctionCallID?)
            case attachment(Attachment)
            case multipart([Body])

            var maybeContent: String? {
                switch self {
                case .multipart(let bodies):
                    return bodies.compactMap { $0.maybeContent }.joined(separator: "\n")
                case .text(let content),
                        .functionOutput(name: _, output: let content, _):
                    return content
                case .attachment(let attachment):
                    switch attachment.type {
                    case .code(let string): return string
                    case .statusUpdate: return nil
                    case .file: return nil
                    }
                case .functionCall, .uninitialized:
                    return nil
                }
            }

            var content: String {
                maybeContent ?? ""
            }

            func appending(_ additionalContent: Body) -> Self {
                var result = self
                result.append(additionalContent)
                return result
            }

            mutating func append(_ additionalContent: Body) {
                if tryAppend(additionalContent) {
                    return
                }
                if self == .uninitialized {
                    self = additionalContent
                } else {
                    self = .multipart([self, additionalContent])
                }
            }

            // Will never create multipart, but if self is already multipart will always succeed.
            mutating func tryAppend(_ additionalContent: Body) -> Bool {
                switch self {
                case .uninitialized:
                    return false
                case .text(let original):
                    if case let .text(content) = additionalContent {
                        self = .text(original + content)
                        return true
                    }
                case .functionCall(let original, id: let originalID):
                    // Only compare item IDs because OpenAI doesn't give a call ID for arguments when streaming.
                    if case let .functionCall(content, id) = additionalContent,
                       id?.itemID == originalID?.itemID {
                        self = .functionCall(.init(name: (original.name ?? "") + (content.name ?? ""),
                                                   arguments: (original.arguments ?? "") + (content.arguments ?? "")),
                                             id: originalID)
                        return true
                    }
                case let .functionOutput(name: originalName,
                                         output: originalOutput,
                                         id: originalID):
                    if case let .functionOutput(name: name, output: output, id: id) = additionalContent,
                       id == originalID {
                        self = .functionOutput(name: originalName + name,
                                               output: originalOutput + output,
                                               id: id)
                        return true
                    }
                case .attachment(let originalAttachment):
                    if case let .attachment(additionalAttachment) = additionalContent,
                       let combined = originalAttachment.appending(additionalAttachment) {
                        self = .attachment(combined)
                        return true
                    }
                case .multipart(let original):
                    if original.isEmpty {
                        self = .multipart([additionalContent])
                    } else {
                        var last = original.last!
                        if last.tryAppend(additionalContent) {
                            self = .multipart(original.dropLast() + [last])
                        } else {
                            self = .multipart(original + [additionalContent])
                        }
                    }
                    return true
                }
                return false
            }
        }
        var body: Body

        // Backward-compatibility methods
        var function_call: FunctionCall? {
            switch body {
            case .functionCall(let call, _): call
            default: nil
            }
        }
        var functionCallID: FunctionCallID? {
            switch body {
            case .functionCall(_, let id), .functionOutput(_, _, id: let id): id
            case .text, .uninitialized, .attachment, .multipart: nil
            }
        }
        var content: String? {
            body.maybeContent
        }

        init(role: Role? = .user,
             content: String? = nil,
             name: String? = nil,
             functionCallID: FunctionCallID? = nil,
             function_call: FunctionCall? = nil) {
            self.role = role
            if let name, let content {
                body = .functionOutput(name: name, output: content, id: functionCallID)
            } else if let function_call {
                body = .functionCall(function_call, id: functionCallID)
            } else if let content {
                body = .text(content)
            } else {
                body = .uninitialized
            }
        }

        init(role: Role?, body: Body) {
            self.role = role
            self.body = body
        }

        var approximateTokenCount: Int { OpenAIMetadata.instance.tokens(in: (body.content)) + 1 }

        var trimmedString: String? {
            return String(body.content.trimmingLeadingCharacters(in: .whitespacesAndNewlines))
        }

        enum CodingKeys: String, CodingKey {
            case role, content, function_name, function_call_id, function_call, body
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let role = try container.decodeIfPresent(Role.self, forKey: .role)
            if let body = try container.decodeIfPresent(Body.self, forKey: .body) {
                self = Message(role: role, body: body)
            } else {
                // Legacy code path
                let content = try container.decodeIfPresent(String.self, forKey: .content)
                let functionName = try container.decodeIfPresent(String.self, forKey: .function_name)
                let functionCall = try container.decodeIfPresent(FunctionCall.self, forKey: .function_call)

                self = Message(role: role,
                               content: content,
                               name: functionName,
                               function_call: functionCall)
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encodeIfPresent(role, forKey: .role)
            try container.encode(body, forKey: .body)
        }

        mutating func tryAppend(_ additionalContent: Body) -> Bool {
            return body.tryAppend(additionalContent)
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
        let query = messages.compactMap { $0.body.content }.joined(separator: "\n")
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
        self.contents = messages.compactMap { message -> Content? in
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
                           parts: [Content.Part(text: message.body.content)])
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
        var messages = [CompletionsMessage]()
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
                        messages: messages.compactMap { CompletionsMessage($0) },
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
        var messages = [CompletionsMessage]()
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
        case .completions, .gemini, .legacy, .responses:
            messages
        }
        let body = Body(model: provider.dynamicModelsSupported ? provider.model : nil,
                        messages: modifiedMessages.compactMap { CompletionsMessage($0) },
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

struct HostedTools {
    struct FileSearch {
        var vectorstoreIDs: [String]  // cannot be empty
    }
    var fileSearch: FileSearch?
    var webSearch = false
    var codeInterpreter = false
}

struct LLMRequestBuilder {
    var provider: LLMProvider
    var apiKey: String
    var messages: [LLM.Message]
    var functions = [LLM.AnyFunction]()
    var stream = false
    var hostedTools: HostedTools

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
        case .responses:
            try ResponsesBodyRequestBuilder(messages: messages,
                                            provider: provider,
                                            functions: functions,
                                            stream: stream,
                                            hostedTools: hostedTools).body()
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

protocol LLMResponseParser {
    // Throw on error, return nil on EOF (used by streaming parsers where EOF is in the message, not in the metadata like OpenAI's modern API)
    mutating func parse(data: Data) throws -> LLM.AnyResponse?
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String)
}

protocol LLMStreamingResponseParser {
    // Throw on error, return nil on EOF (used by streaming parsers where EOF is in the message, not in the metadata like OpenAI's modern API)
    mutating func parse(data: Data) throws -> LLM.AnyStreamingResponse?
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String)
}


func SplitServerSentEvents(from rawInput: String) -> (json: String?, remainder: String) {
    let input = rawInput.trimmingLeadingCharacters(in: .whitespacesAndNewlines)
    guard let newlineRange = input.range(of: "\n") else {
        return (nil, String(input))
    }

    // Extract the first line (up to, but not including, the newline)
    let firstLine = input[..<newlineRange.lowerBound]
    // Everything after the newline is the remainder.
    let remainder = input[newlineRange.upperBound...]

    // Skip all SSE control lines that aren't data
    if firstLine.hasPrefix("event:") ||
       firstLine.hasPrefix("id:") ||
       firstLine.hasPrefix("retry:") ||
       firstLine.hasPrefix(":") ||  // Comments
       firstLine.trimmingCharacters(in: .whitespaces).isEmpty {
        return SplitServerSentEvents(from: String(remainder))
    }
    // Ensure the line starts with "data:".
    let prefix = "data:"
    guard firstLine.hasPrefix(prefix) else {
        // If not, we can't extract a valid JSON object.
        return (nil, String(input))
    }

    // Remove the prefix and trim whitespace to get the JSON object.
    let jsonPart = firstLine.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)

    return (String(jsonPart), String(remainder))
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

struct LLMLegacyStreamingResponseParser: LLMStreamingResponseParser {
    struct LegacyStreamingResponse: Codable, LLM.AnyStreamingResponse {
        var ignore: Bool { false }
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

    mutating func parse(data: Data) throws -> LLM.AnyStreamingResponse? {
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
                    content.role == "model" ? LLM.Role.assistant : LLM.Role.user
                } else {
                    LLM.Role.assistant  // failed, probably because of safety
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

extension Optional where Wrapped == String {
    static func concat(_ lhs: String?, _ rhs: String?) -> String? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case let (l?, r?):
            return l + r
        case let (l?, nil):
            return l
        case let (nil, r?):
            return r
        }
    }
}
