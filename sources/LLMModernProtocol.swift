//
//  LLMModernProtocol.swift
//  iTerm2
//
//  Created by George Nachman on 5/31/25.
//
// This file relates to OpenAI's second API, also called "chat completions" (NOT "completions", which is even older).

struct CompletionsMessage: Codable, Equatable {
    var role: LLM.Role? = .user
    var content: Content?
    // For function calling
    var functionName: String?  // in the response only
    var function_call: LLM.FunctionCall?

    init(role: LLM.Role? = .user,
         content: Content? = nil,
         name: String? = nil,
         function_call: LLM.FunctionCall? = nil) {
        self.role = role
        self.content = content
        self.functionName = name
        self.function_call = function_call
    }

    enum CodingKeys: String, CodingKey {
        case role
        case functionName = "name"
        case content
        case function_call
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(role, forKey: .role)

        if let functionName {
            try container.encode(functionName, forKey: .functionName)
        }

        try container.encode(content, forKey: .content)

        if let function_call {
            try container.encode(function_call, forKey: .function_call)
        }
    }

    var approximateTokenCount: Int {
        switch content {
        case .string(let string): return AIMetadata.instance.tokens(in: string) + 1
        case .array(let parts): return parts.map { $0.approximateTokenCount }.reduce(0, +) + 1
        case .none: return 0
        }
    }

    init?(_ llmMessage: LLM.Message) {
        role = llmMessage.role
        switch llmMessage.body {
        case .text(let text):
            content = .string(text)
        case .attachment(let attachment):
            switch attachment.type {
            case .code(let string):
                content = .string(string)
            case .statusUpdate(let statusUpdate):
                content = .string(statusUpdate.displayString)
            case .file(let file):
                content = .string(file.content.lossyString)
            case .fileID(_, let name):
                content = .string("A file named \(name) (content unavailable)")
            }
        case .functionCall(let call, _):
            functionName = call.name
            function_call = call
            content = nil
        case .functionOutput(name: let name, output: let output, id: _):
            functionName = name
            content = .string(output)
        case .uninitialized:
            return nil
        case .multipart(let subparts):
            // This is pretty crappy but I don't think it'll happen unless you continue an
            // existing conversation in an older API.
            content = .array(subparts.compactMap({ subpart -> ContentPart? in
                switch subpart {
                case .uninitialized:
                    return nil
                case .text(let string):
                    return .text(.init(text: string))
                case .functionCall, .functionOutput, .multipart:
                    it_fatalError()
                case .attachment(let attachment):
                    switch attachment.type {
                    case .code(let string):
                        return .text(.init(text: string))
                    case .statusUpdate:
                        return nil
                    case .file(let file):
                        if file.mimeType == "application/pdf" {
                            let base64Data = file.content.base64EncodedString()
                            return .file(.init(file_data: "data:\(file.mimeType);base64,\(base64Data)",
                                               filename: file.name))
                        } else {
                            var value = "<iterm2:attachment file=\"\(file.name)\" type=\"\(file.mimeType)\">\n"
                            value += file.content.lossyString
                            value += "\n</iterm2:attachment>"
                            return .text(.init(text: value))
                        }
                    case .fileID(id: _, name: let name):
                        return .text(.init(text: "A file named \(name) (content unavailable)"))
                    }
                }
            }))
        }
    }
    var llmMessage: LLM.Message {
        if let functionName, let content, case let .string(string) = content {
            return LLM.Message(role: role,
                               body: .functionOutput(name: functionName,
                                                     output: string,
                                                     id: nil))
        }
        if let function_call {
            return LLM.Message(role: role,
                               body: .functionCall(function_call, id: nil))
        }
        if let content {
            switch content {
            case .string(let string):
                return LLM.Message(role: role,
                                   body: .text(string))
            case .array(let array):
                return LLM.Message(role: role,
                                   body: .multipart(array.compactMap { part in
                    switch part {
                    case .text(let text):
                        return .text(text.text)
                    case .file(let file):
                        return .attachment(.init(inline: false,
                                                 id: UUID().uuidString,
                                                 type: .file(.init(name: file.filename,
                                                                   content: Data(base64Encoded: file.file_data) ?? Data(),
                                                                   mimeType: "application/octet-stream"))))
                    }
                }))
            }
        }
        return LLM.Message(role: role, body: .uninitialized)
    }

    var coercedContentString: String {
        switch content {
        case .none: return ""
        case .string(let string): return string
        case .array(let array):
            return array.map { part -> String in
                switch part {
                case .text(let text):
                    return text.text
                case .file(let file):
                    var value = "<iterm2:attachment file=\"\(file.filename)\">\n"
                    value += (Data(base64Encoded: file.file_data) ?? Data()).lossyString
                    value += "\n</iterm2:attachment>"
                    return value
                }
            }.joined(separator: "\n")
        }
    }
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
            var message: CompletionsMessage
            var finish_reason: String
        }

        struct Usage: Codable {
            var prompt_tokens: Int
            var completion_tokens: Int?
            var total_tokens: Int
        }

        var choiceMessages: [LLM.Message] {
            return choices.map {
                $0.message.llmMessage
            }
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

struct LLMModernStreamingResponseParser: LLMStreamingResponseParser {
    struct ModernStreamingResponse: Codable, LLM.AnyStreamingResponse {
        var newlyCreatedResponseID: String? { nil }
        var ignore: Bool { false }
        var isStreamingResponse: Bool { true }

        let id: String?
        let object: String?
        let created: TimeInterval?
        let model: String?
        let choices: [UpdateChoice]

        struct UpdateChoice: Codable {
            // The delta holds the incremental text update.
            let delta: CompletionsMessage
            let index: Int
            // For update chunks, finish_reason is nil.
            let finish_reason: String?
        }

        var choiceMessages: [LLM.Message] {
            return choices.compactMap { choice -> LLM.Message? in
                if choice.finish_reason == "function_call" &&
                    choice.delta.role == nil &&
                    choice.delta.content == nil &&
                    choice.delta.functionName == nil &&
                    choice.delta.function_call == nil {
                    // Sent at the end of a function call
                    return nil
                }
                return LLM.Message(role: .assistant,
                                   content: choice.delta.coercedContentString,
                                   function_call: choice.delta.function_call)
            }
        }
    }
    var parsedResponse: ModernStreamingResponse?

    mutating func parse(data: Data) throws -> LLM.AnyStreamingResponse? {
        let decoder = JSONDecoder()
        let response =  try decoder.decode(ModernStreamingResponse.self, from: data)
        DLog("RESPONSE:\n\(response)")
        parsedResponse = response
        return response
    }
    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return SplitServerSentEvents(from: rawInput)
    }
}

extension CompletionsMessage {
    // Content can be either a string or an array of content parts
    enum Content: Codable, Equatable {
        case string(String)
        case array([ContentPart])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let text):
                try container.encode(text)
            case .array(let parts):
                try container.encode(parts)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .string(text)
            } else if let parts = try? container.decode([ContentPart].self) {
                self = .array(parts)
            } else {
                throw DecodingError.typeMismatch(
                    Content.self,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected String or [ContentPart]"
                    )
                )
            }
        }
    }

    // Content part types
    enum ContentPart: Codable, Equatable {
        case text(TextContent)
        case file(FileContent)

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case file
        }

        var approximateTokenCount: Int {
            switch self {
            case .text(let content): return AIMetadata.instance.tokens(in: content.text) + 1
            case .file(let file): return AIMetadata.instance.tokens(in: file.file_data + file.filename) + 1
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let content):
                try container.encode("text", forKey: .type)
                try container.encode(content.text, forKey: .text)
            case .file(let content):
                try container.encode("file", forKey: .type)
                try container.encode(content, forKey: .file)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "text":
                let text = try container.decode(String.self, forKey: .text)
                self = .text(TextContent(text: text))
            case "file":
                let fileContent = try container.decode(FileContent.self, forKey: .file)
                self = .file(fileContent)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown content type: \(type)"
                )
            }
        }
    }

    struct TextContent: Codable, Equatable {
        let text: String

        var trimmedString: String? {
            return String(text.trimmingLeadingCharacters(in: .whitespacesAndNewlines))
        }

    }

    struct FileContent: Codable, Equatable {
        let file_data: String  // base64 encoded bytes
        let filename: String

        private enum CodingKeys: String, CodingKey {
            case file_data
            case filename
        }
    }

}
