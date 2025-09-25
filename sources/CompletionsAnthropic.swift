//
//  CompletionsAnthropic.swift
//  iTerm2
//
//  Created by Claude on 6/17/25.
//

struct AnthropicMessage: Codable, Equatable {
    var role: AnthropicRole
    var content: AnthropicContent

    init(role: AnthropicRole, content: AnthropicContent) {
        self.role = role
        self.content = content
    }

    enum AnthropicRole: String, Codable {
        case user
        case assistant
    }

    var approximateTokenCount: Int {
        switch content {
        case .string(let string):
            return AIMetadata.instance.tokens(in: string) + 1
        case .array(let parts):
            return parts.map { $0.approximateTokenCount }.reduce(0, +) + 1
        }
    }

    init?(_ llmMessage: LLM.Message) {
        // Handle function output messages specially - they should be user messages with tool_result
        if case .functionOutput(_, _, let functionCallID) = llmMessage.body,
           functionCallID?.callID != nil {
            role = .user
        } else {
            switch llmMessage.role {
            case .user:
                role = .user
            case .assistant:
                role = .assistant
            case .system:
                return nil
            case .function:
                role = .user  // Function outputs should be user messages in Anthropic format
            case .none:
                return nil
            }
        }

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
                if file.mimeType.hasPrefix("image/") {
                    let base64Data = file.content.base64EncodedString()
                    content = .array([
                        .image(.init(type: "base64",
                                   media_type: file.mimeType,
                                   data: base64Data))
                    ])
                } else {
                    content = .string(file.content.lossyString)
                }
            case .fileID(_, let name):
                content = .string("A file named \(name) (content unavailable)")
            }
        case .functionCall(let call, _):
            if let toolID = call.id {
                content = .array([
                    .toolUse(.init(id: toolID,
                                  name: call.name ?? "",
                                  input: parseArguments(call.arguments)))
                ])
            } else {
                content = .string("Function call: \(call.name.d)")
            }
        case .functionOutput(name: let name, output: let output, id: let functionCallID):
            if let toolID = functionCallID?.callID {
                content = .array([
                    .toolResult(.init(tool_use_id: toolID, content: output))
                ])
            } else {
                content = .string("Function \(name) output: \(output)")
            }
        case .uninitialized:
            return nil
        case .multipart(let subparts):
            let parts = subparts.compactMap { subpart -> AnthropicContentBlock? in
                switch subpart {
                case .uninitialized:
                    return nil
                case .text(let string):
                    return .text(.init(text: string))
                case .functionCall(let call, _):
                    if let toolID = call.id {
                        return .toolUse(.init(id: toolID,
                                            name: call.name ?? "",
                                            input: parseArguments(call.arguments)))
                    }
                    return nil
                case .functionOutput(name: _, output: let output, id: let functionCallID):
                    if let toolID = functionCallID?.callID {
                        return .toolResult(.init(tool_use_id: toolID, content: output))
                    }
                    return .text(.init(text: output))
                case .multipart:
                    return nil
                case .attachment(let attachment):
                    switch attachment.type {
                    case .code(let string):
                        return .text(.init(text: string))
                    case .statusUpdate:
                        return nil
                    case .file(let file):
                        if file.mimeType.hasPrefix("image/") {
                            let base64Data = file.content.base64EncodedString()
                            return .image(.init(type: "base64",
                                              media_type: file.mimeType,
                                              data: base64Data))
                        } else {
                            return .text(.init(text: file.content.lossyString))
                        }
                    case .fileID(id: _, name: let name):
                        return .text(.init(text: "A file named \(name) (content unavailable)"))
                    }
                }
            }
            content = .array(parts)
        }
    }

    var llmMessage: LLM.Message {
        let llmRole: LLM.Role = role == .user ? .user : .assistant

        switch content {
        case .string(let string):
            return LLM.Message(responseID: nil, role: llmRole, body: .text(string))
        case .array(let array):
            if array.count == 1, case .text(let textContent) = array[0] {
                return LLM.Message(responseID: nil, role: llmRole, body: .text(textContent.text))
            } else {
                let subparts = array.compactMap { block -> LLM.Message.Body? in
                    switch block {
                    case .text(let text):
                        return .text(text.text)
                    case .image(let image):
                        guard let data = Data(base64Encoded: image.data) else { return nil }
                        return .attachment(.init(inline: false,
                                               id: UUID().uuidString,
                                               type: .file(.init(name: "image",
                                                               content: data,
                                                               mimeType: image.media_type))))
                    case .toolUse(let toolUse):
                        let inputString = (try? JSONSerialization.data(withJSONObject: toolUse.input))?.lossyString ?? ""
                        let functionCall = LLM.FunctionCall(name: toolUse.name, arguments: inputString, id: toolUse.id)
                        return .functionCall(functionCall, id: nil)
                    case .toolResult(let toolResult):
                        return .functionOutput(name: "", output: toolResult.content, id: .init(callID: toolResult.tool_use_id, itemID: ""))
                    }
                }
                return LLM.Message(responseID: nil, role: llmRole, body: .multipart(subparts))
            }
        }
    }

    var coercedContentString: String {
        switch content {
        case .string(let string):
            return string
        case .array(let array):
            return array.map { block -> String in
                switch block {
                case .text(let text):
                    return text.text
                case .image(let image):
                    return "[Image: \(image.media_type)]"
                case .toolUse(let toolUse):
                    return "[Tool Use: \(toolUse.name)]"
                case .toolResult(let toolResult):
                    return "[Tool Result: \(toolResult.content)]"
                }
            }.joined(separator: "\n")
        }
    }
}

extension AnthropicMessage {
    enum AnthropicContent: Codable, Equatable {
        case string(String)
        case array([AnthropicContentBlock])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let text):
                try container.encode(text)
            case .array(let blocks):
                try container.encode(blocks)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .string(text)
            } else if let blocks = try? container.decode([AnthropicContentBlock].self) {
                self = .array(blocks)
            } else {
                throw DecodingError.typeMismatch(
                    AnthropicContent.self,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected String or [AnthropicContentBlock]"
                    )
                )
            }
        }
    }

    enum AnthropicContentBlock: Codable, Equatable {
        case text(AnthropicTextContent)
        case image(AnthropicImageContent)
        case toolUse(AnthropicToolUseContent)
        case toolResult(AnthropicToolResultContent)

        private enum CodingKeys: String, CodingKey {
            case type
        }

        var approximateTokenCount: Int {
            switch self {
            case .text(let content):
                return AIMetadata.instance.tokens(in: content.text) + 1
            case .image(_):
                return 1000
            case .toolUse(_):
                return 100
            case .toolResult(let content):
                return AIMetadata.instance.tokens(in: content.content) + 1
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .text(let content):
                try content.encode(to: encoder)
            case .image(let content):
                try content.encode(to: encoder)
            case .toolUse(let content):
                try content.encode(to: encoder)
            case .toolResult(let content):
                try content.encode(to: encoder)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "text":
                let textContent = try AnthropicTextContent(from: decoder)
                self = .text(textContent)
            case "image":
                let imageContent = try AnthropicImageContent(from: decoder)
                self = .image(imageContent)
            case "tool_use":
                let toolUseContent = try AnthropicToolUseContent(from: decoder)
                self = .toolUse(toolUseContent)
            case "tool_result":
                let toolResultContent = try AnthropicToolResultContent(from: decoder)
                self = .toolResult(toolResultContent)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown content type: \(type)"
                )
            }
        }
    }

    struct AnthropicTextContent: Codable, Equatable {
        let type: String = "text"
        let text: String

        init(text: String) {
            self.text = text
        }

        enum CodingKeys: String, CodingKey {
            case type, text
        }
    }

    struct AnthropicImageContent: Codable, Equatable {
        let type: String = "image"
        let source: Source

        struct Source: Codable, Equatable {
            let type: String
            let media_type: String
            let data: String
        }

        init(type: String, media_type: String, data: String) {
            self.source = Source(type: type, media_type: media_type, data: data)
        }

        // For backward compatibility
        var media_type: String { source.media_type }
        var data: String { source.data }

        enum CodingKeys: String, CodingKey {
            case type, source
        }
    }

    struct AnthropicToolUseContent: Codable, Equatable {
        let type: String = "tool_use"
        let id: String
        let name: String
        let input: [String: Any]

        static func == (lhs: AnthropicToolUseContent, rhs: AnthropicToolUseContent) -> Bool {
            return lhs.type == rhs.type &&
                   lhs.id == rhs.id &&
                   lhs.name == rhs.name &&
                   NSDictionary(dictionary: lhs.input).isEqual(to: rhs.input)
        }

        enum CodingKeys: String, CodingKey {
            case type, id, name, input
        }

        init(id: String, name: String, input: [String: Any]) {
            self.id = id
            self.name = name
            self.input = input
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)

            // Decode input as Any and convert to [String: Any]
            if container.contains(.input) {
                let inputValue = try container.decode(AnyCodable.self, forKey: .input)
                if let dict = inputValue.value as? [String: Any] {
                    input = dict
                } else {
                    input = [:]
                }
            } else {
                input = [:]
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(AnyCodable(input), forKey: .input)
        }
    }

    struct AnthropicToolResultContent: Codable, Equatable {
        let type: String = "tool_result"
        let tool_use_id: String
        let content: String

        enum CodingKeys: String, CodingKey {
            case type, tool_use_id, content
        }

        init(tool_use_id: String, content: String) {
            self.tool_use_id = tool_use_id
            self.content = content
        }
    }
}



private func parseArguments(_ arguments: String?) -> [String: Any] {
    guard let arguments = arguments,
          let data = arguments.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return json
}

struct AnthropicResponseParser: LLMResponseParser {
    struct AnthropicResponse: Codable, LLM.AnyResponse {
        var isStreamingResponse: Bool { false }
        var id: String
        var type: String
        var role: String
        var content: [AnthropicResponseContent]
        var model: String
        var stop_reason: String?
        var stop_sequence: String?
        var usage: AnthropicUsage

        struct AnthropicResponseContent: Codable {
            let type: String
            let text: String?
            let id: String?
            let name: String?
            let input: [String: Any]?

            enum CodingKeys: String, CodingKey {
                case type, text, id, name, input
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                type = try container.decode(String.self, forKey: .type)
                text = try container.decodeIfPresent(String.self, forKey: .text)
                id = try container.decodeIfPresent(String.self, forKey: .id)
                name = try container.decodeIfPresent(String.self, forKey: .name)

                if container.contains(.input) {
                    let inputValue = try container.decode(AnyCodable.self, forKey: .input)
                    input = inputValue.value as? [String: Any]
                } else {
                    input = nil
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(type, forKey: .type)
                try container.encodeIfPresent(text, forKey: .text)
                try container.encodeIfPresent(id, forKey: .id)
                try container.encodeIfPresent(name, forKey: .name)

                if let input = input {
                    try container.encode(AnyCodable(input), forKey: .input)
                }
            }
        }

        struct AnthropicUsage: Codable {
            let input_tokens: Int
            let output_tokens: Int
        }

        var choiceMessages: [LLM.Message] {
            var messages: [LLM.Message] = []

            for contentItem in content {
                switch contentItem.type {
                case "text":
                    if let text = contentItem.text, !text.isEmpty {
                        messages.append(LLM.Message(responseID: id, role: .assistant, body: .text(text)))
                    }
                case "tool_use":
                    if let name = contentItem.name,
                       let toolID = contentItem.id,
                       let input = contentItem.input {
                        let inputString = (try? JSONSerialization.data(withJSONObject: input))?.lossyString ?? ""
                        let functionCall = LLM.FunctionCall(name: name, arguments: inputString, id: toolID)
                        messages.append(LLM.Message(responseID: id, role: .assistant, body: .functionCall(functionCall, id: nil)))
                    }
                default:
                    break
                }
            }

            if messages.isEmpty {
                let textContent = content.compactMap { $0.text }.joined(separator: "")
                return [LLM.Message(responseID: id, role: .assistant, body: .text(textContent))]
            }

            return messages
        }
    }

    var parsedResponse: AnthropicResponse?

    mutating func parse(data: Data) throws -> LLM.AnyResponse? {
        let decoder = JSONDecoder()
        let response = try decoder.decode(AnthropicResponse.self, from: data)
        DLog("RESPONSE:\n\(response)")
        parsedResponse = response
        return response
    }

    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return (nil, "")
    }
}

struct AnthropicStreamingResponseParser: LLMStreamingResponseParser {
    struct AnthropicStreamingResponse: Codable, LLM.AnyStreamingResponse {
        var newlyCreatedResponseID: String? { nil }
        var ignore: Bool { false }
        var isStreamingResponse: Bool { true }

        let type: String
        let message: StreamingMessage?
        let content_block: StreamingContentBlock?
        let delta: StreamingDelta?
        let index: Int?

        struct StreamingMessage: Codable {
            let id: String
            let type: String
            let role: String
            let content: [String]
            let model: String
            let stop_reason: String?
            let stop_sequence: String?
            let usage: AnthropicUsage
        }

        struct AnthropicUsage: Codable {
            let input_tokens: Int
            let output_tokens: Int
        }

        struct StreamingContentBlock: Codable {
            let type: String
            let text: String?
            let id: String?
            let name: String?
            let input: [String: Any]?

            enum CodingKeys: String, CodingKey {
                case type, text, id, name, input
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                type = try container.decode(String.self, forKey: .type)
                text = try container.decodeIfPresent(String.self, forKey: .text)
                id = try container.decodeIfPresent(String.self, forKey: .id)
                name = try container.decodeIfPresent(String.self, forKey: .name)

                if container.contains(.input) {
                    let inputValue = try container.decode(AnyCodable.self, forKey: .input)
                    input = inputValue.value as? [String: Any]
                } else {
                    input = nil
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(type, forKey: .type)
                try container.encodeIfPresent(text, forKey: .text)
                try container.encodeIfPresent(id, forKey: .id)
                try container.encodeIfPresent(name, forKey: .name)

                if let input = input {
                    try container.encode(AnyCodable(input), forKey: .input)
                }
            }
        }

        struct StreamingDelta: Codable {
            let type: String?
            let text: String?
            let stop_reason: String?
            let partial_json: String?

            enum CodingKeys: String, CodingKey {
                case type, text, stop_reason, partial_json
            }
        }

        var choiceMessages: [LLM.Message] {
            // Handle tool_use content blocks
            if let contentBlock = content_block, contentBlock.type == "tool_use" {
                if let name = contentBlock.name,
                   let toolID = contentBlock.id {
                    // According to clause, input is just a placeholder so it should be ignored.
                    let functionCall = LLM.FunctionCall(name: name, arguments: "", id: toolID)
                    return [LLM.Message(responseID: nil, role: .assistant, body: .functionCall(functionCall, id: nil))]
                }
                return []
            }

            // Handle text content and deltas
            var text = ""
            if let contentBlock = content_block, let blockText = contentBlock.text {
                text = blockText
            } else if let delta = delta {
                if let deltaText = delta.text {
                    text = deltaText
                } else if let partialJson = delta.partial_json {
                    // This is likely partial tool input, treat as text for now
                    text = partialJson
                }
            }

            if !text.isEmpty {
                return [LLM.Message(responseID: nil, role: .assistant, content: text)]
            }

            return []
        }
    }

    var parsedResponse: AnthropicStreamingResponse?

    mutating func parse(data: Data) throws -> LLM.AnyStreamingResponse? {
        let decoder = JSONDecoder()
        let response = try decoder.decode(AnthropicStreamingResponse.self, from: data)
        DLog("RESPONSE:\n\(data.lossyString)")
        parsedResponse = response
        return response
    }

    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return SplitServerSentEvents(from: rawInput)
    }
}

struct AnthropicRequestBuilder {
    var messages: [LLM.Message]
    var provider: LLMProvider
    var functions = [LLM.AnyFunction]()
    var stream: Bool

    private struct Body: Codable {
        var model: String
        var messages: [AnthropicMessage]
        var max_tokens: Int
        var system: String?
        var temperature: Double?
        var stream: Bool?
        var tools: [AnthropicTool]?
        var tool_choice: AnthropicToolChoice?
        var disable_parallel_tool_use: Bool?
    }

    private struct AnthropicTool: Codable {
        var name: String
        var description: String
        var input_schema: JSONSchema
    }

    private struct AnthropicToolChoice: Codable {
        var type: String
        var name: String?
        var disable_parallel_tool_use: Bool?

        static let auto = AnthropicToolChoice(type: "auto", name: nil, disable_parallel_tool_use: true)
    }

    // Convert messages ensuring tool_result blocks are properly formatted
    private func convertMessages(_ messages: [LLM.Message]) -> [AnthropicMessage] {
        var convertedMessages: [AnthropicMessage] = []
        var pendingToolIds: [String] = []

        for message in messages {
            // Skip system messages as they're handled separately
            if message.role == .system {
                continue
            }

            // Handle function role messages (these should become user messages with tool_result)
            if message.role == .function {
                if case .functionOutput(_, let output, _) = message.body {
                    // Use the most recent pending tool ID
                    if let pendingToolId = pendingToolIds.last {
                        let toolResultMessage = AnthropicMessage(
                            role: .user,
                            content: .array([
                                .toolResult(.init(tool_use_id: pendingToolId, content: output))
                            ])
                        )
                        convertedMessages.append(toolResultMessage)
                        pendingToolIds.removeLast() // Remove the used tool ID
                        continue
                    }
                }
            }

            if let anthropicMessage = AnthropicMessage(message) {
                // Track tool use IDs from assistant messages
                if anthropicMessage.role == .assistant {
                    if case .array(let blocks) = anthropicMessage.content {
                        for block in blocks {
                            if case .toolUse(let toolUse) = block {
                                pendingToolIds.append(toolUse.id)
                            }
                        }
                    }
                }

                // Handle user messages that might be function outputs disguised as text
                if anthropicMessage.role == .user {
                    if case .string(let text) = anthropicMessage.content,
                       text.hasPrefix("Function ") && text.contains(" output: ") {
                        // This is a function output disguised as text
                        if let pendingToolId = pendingToolIds.last {
                            // Extract the actual output
                            if let outputRange = text.range(of: " output: ") {
                                let actualOutput = String(text[outputRange.upperBound...])
                                // Create proper tool_result message
                                let toolResultMessage = AnthropicMessage(
                                    role: .user,
                                    content: .array([
                                        .toolResult(.init(tool_use_id: pendingToolId, content: actualOutput))
                                    ])
                                )
                                convertedMessages.append(toolResultMessage)
                                pendingToolIds.removeLast() // Remove the used tool ID
                                continue
                            }
                        }
                    }
                    // Clear pending tool IDs when we get a regular user message (but not tool results)
                    if case .string(_) = anthropicMessage.content {
                        pendingToolIds.removeAll()
                    }
                }

                convertedMessages.append(anthropicMessage)
            }
        }

        return convertedMessages
    }

    func body() throws -> Data {
        let anthropicMessages = convertMessages(messages)
        let systemMessage = messages.compactMap { message in
            switch message.role {
            case .system:
                return message.content
            default:
                return nil
            }
        }.first

        let anthropicTools = functions.isEmpty ? nil : functions.map { function in
            AnthropicTool(
                name: function.decl.name,
                description: function.decl.description,
                input_schema: function.decl.parameters
            )
        }

        let body = Body(
            model: provider.model.name,
            messages: anthropicMessages,
            max_tokens: provider.maxTokens(functions: functions, messages: messages),
            system: systemMessage,
            temperature: 0.0,
            stream: stream ? true : nil,
            tools: anthropicTools,
            tool_choice: functions.isEmpty ? nil : .auto
        )

        if body.max_tokens < 2 {
            throw AIError.requestTooLarge
        }

        let bodyEncoder = JSONEncoder()
        let bodyData = try bodyEncoder.encode(body)
        DLog("REQUEST:\n\(bodyData.lossyString)")
        return bodyData
    }
}
