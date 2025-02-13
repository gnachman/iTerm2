//
//  LLM.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/24.
//

import Foundation
import SwiftyMarkdown

enum LLM {
    protocol AnyResponse {
        var choiceMessages: [Message] { get }
    }

    struct Message: Codable, Equatable {
        var role = "user"
        var content: String?

        // For function calling
        var name: String?
        var function_call: FunctionCall?

        struct FunctionCall: Codable, Equatable {
            var name: String
            var arguments: String
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
        func invoke(json: Data, completion: @escaping (Result<String, Error>) -> ())
    }

    struct Function<T: Codable>: AnyFunction {
        typealias Impl = (T, @escaping (Result<String, Error>) -> ()) -> ()

        var decl: ChatGPTFunctionDeclaration
        var call: Impl
        var parameterType: T.Type

        var typeErasedParameterType: Any.Type { parameterType }
        func invoke(json: Data, completion: @escaping (Result<String, Error>) -> ()) {
            do {
                let value = try JSONDecoder().decode(parameterType, from: json)
                call(value, completion)
            } catch {
                DLog("\(error.localizedDescription)")
                completion(.failure(error))
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
        self.contents = messages.map { message in
            let role = if message.role == "user" {
                message.role
            } else {
                "model"
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

    private struct Body: Codable {
        var model: String?
        var messages = [LLM.Message]()
        var max_tokens: Int
        var temperature: Int? = 0
        var functions: [ChatGPTFunctionDeclaration]? = nil
        var function_call: String? = nil  // "none" and "auto" also allowed
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
                        function_call: functions.isEmpty ? nil : "auto")
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
                if message.role != "system" {
                    return message
                }
                var temp = message
                temp.role = "user"
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
                                     functions: functions).body()
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
        for prefix in iTermAdvancedSettingsModel.aiModernModelPrefixes().components(separatedBy: " ") {
            if model.hasPrefix(prefix) {
                return false
            }
        }
        return true
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
        return url?.host == "api.openai.com"
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

    func responseParser() -> LLMResponseParser {
        switch version {
        case .completions, .o1:
            return LLMModernResponseParser()
        case .legacy:
            return LLMLegacyResponseParser()
        case .gemini:
            return LLMGeminiResponseParser()
        }
    }
}

protocol LLMResponseParser {
    mutating func parse(data: Data) throws -> LLM.AnyResponse
}

struct LLMModernResponseParser: LLMResponseParser {
    struct ModernResponse: Codable, LLM.AnyResponse {
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

    mutating func parse(data: Data) throws -> LLM.AnyResponse {
        let decoder = JSONDecoder()
        let response =  try decoder.decode(ModernResponse.self, from: data)
        DLog("RESPONSE:\n\(response)")
        parsedResponse = response
        return response
    }
}

struct LLMLegacyResponseParser: LLMResponseParser {
    struct LegacyResponse: Codable, LLM.AnyResponse {
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
                LLM.Message(role: "model", content: $0.text)
            }
        }
    }

    private(set) var parsedResponse: LegacyResponse?

    mutating func parse(data: Data) throws -> LLM.AnyResponse {
        let decoder = JSONDecoder()
        let response = try decoder.decode(LegacyResponse.self, from: data)
        parsedResponse = response
        return response
    }
}

struct LLMGeminiResponseParser: LLMResponseParser {
    struct GeminiResponse: Codable, LLM.AnyResponse {
        var choiceMessages: [LLM.Message] {
            candidates.map {
                let role = if let content = $0.content {
                    content.role == "model" ? "assistant" : "user"
                } else {
                    "assistant"  // failed, probably because of safety
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

    mutating func parse(data: Data) throws -> LLM.AnyResponse {
        let decoder = JSONDecoder()
        let response = try decoder.decode(GeminiResponse.self, from: data)
        parsedResponse = response
        return response
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

fileprivate func sanitizeMarkdown(_ input: String) -> String {
    // Regular expression pattern to match leading spaces followed by ``` and optional lowercase letters till the end of the string
    let pattern = "^ *```[a-z]*$"

    // Create a regular expression object
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return input
    }

    // Check if the input matches the pattern
    let range = NSRange(input.startIndex..<input.endIndex, in: input)
    let matches = regex.matches(in: input, options: [], range: range)

    // If there's a match, remove the leading spaces
    if let match = matches.first, match.range.length > 0 {
        let result = input.replacingOccurrences(of: " ", with: "", options: [], range: input.startIndex..<input.index(input.startIndex, offsetBy: match.range.length))
        return result
    }

    // Return the original string if there's no match
    return input
}

func AttributedStringForGPTMarkdown(_ unsafeString: String,
                                    linkColor: NSColor? = nil,
                                    didCopy: @escaping () -> ()) -> NSAttributedString {
    let massagedValue = unsafeString.components(separatedBy: "\n").map { sanitizeMarkdown($0) }.joined(separator: "\n")

    let md = SwiftyMarkdown(string: massagedValue)
    let pointSize = NSFont.systemFontSize
    if let fixedPitchFontName = NSFont.userFixedPitchFont(ofSize: pointSize)?.fontName {
        md.code.fontName = fixedPitchFontName
    }
    md.setFontSizeForAllStyles(with: pointSize)

    md.h1.fontSize = max(4, round(pointSize * 2))
    md.h2.fontSize = max(4, round(pointSize * 1.5))
    md.h3.fontSize = max(4, round(pointSize * 1.3))
    md.h4.fontSize = max(4, round(pointSize * 1.0))
    md.h5.fontSize = max(4, round(pointSize * 0.8))
    md.h6.fontSize = max(4, round(pointSize * 0.7))

    md.setFontColorForAllStyles(with: NSColor.textColor)

    if let linkColor {
        md.link.color = linkColor
        md.link.underlineColor = linkColor
    }
    md.underlineLinks = true

    let attributedString = md.attributedString()
    if #available(macOS 11.0, *) {
        let image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")!
        let modified = attributedString.mutableCopy() as! NSMutableAttributedString
        var ranges = [NSRange]()
        let utf16String = attributedString.string.utf16
        attributedString.enumerateAttribute(
            NSAttributedString.Key.swiftyMarkdownLineStyle,
            in: NSRange(from: 0, to: attributedString.length)) { value, range, stopPtr in
            guard value as? String == "codeblock" else {
                return
            }
            if let previous = ranges.last {
                let startIndex = utf16String.index(utf16String.startIndex, offsetBy: previous.upperBound)
                let endIndex = utf16String.index(utf16String.startIndex, offsetBy: range.lowerBound)
                let utf16CodeUnits = Array(utf16String[startIndex..<endIndex])
                let substringToCheck = String(utf16CodeUnits: utf16CodeUnits, count: utf16CodeUnits.count)
                if substringToCheck.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // The area between this range and the last contains contains only whitespace characters
                    ranges.removeLast()
                    ranges.append(NSRange(location: previous.location,
                                          length: range.upperBound - previous.location))
                    return
                }
            }
            ranges.append(range)
        }
        for range in ranges.reversed() {
            modified.insertButton(withImage: DynamicImage(image: image, dark: .white, light: .black), at: range.location) { point in
                NSPasteboard.general.declareTypes([.string], owner: NSApp)
                NSPasteboard.general.setString(attributedString.string.substring(nsrange: range), forType: .string)
                ToastWindowController.showToast(withMessage: "Copied", duration: 1, screenCoordinate: point, pointSize: 12)
                didCopy()
            }
            modified.insert(
                NSAttributedString(
                    string: " ",
                    attributes: modified.attributes(
                        at: range.location + 1,
                        effectiveRange: nil)),
                at: range.location + 1)
        }
        return modified
    } else {
        return attributedString
    }
}
