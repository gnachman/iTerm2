//
//  CompletionsAnthropic.swift
//  iTerm2
//
//  Created by Claude on 6/17/25.
//

struct AnthropicMessage: Codable, Equatable {
    var role: AnthropicRole
    var content: AnthropicContent

    // Image MIME types Anthropic accepts as inline image content blocks.
    // The API rejects anything outside this set with a 400, so the
    // serializer must not send e.g. image/svg+xml here (SVG is XML text
    // and goes through the textual branch instead).
    static let anthropicSupportedImageMimeTypes: Set<String> = [
        "image/jpeg", "image/png", "image/gif", "image/webp"
    ]

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
                // Textual content (including image/svg+xml) goes through as a
                // plain string. Check this BEFORE the image-prefix branch so
                // SVGs don't get base64-wrapped as binary images — Anthropic's
                // image source only accepts jpeg/png/gif/webp.
                if MIMETypeIsTextual(file.mimeType) {
                    content = .string(file.content.lossyString)
                } else if Self.anthropicSupportedImageMimeTypes.contains(file.mimeType) {
                    let base64Data = file.content.base64EncodedString()
                    content = .array([
                        .image(.init(type: "base64",
                                   media_type: file.mimeType,
                                   data: base64Data))
                    ])
                } else if file.mimeType == "application/pdf" {
                    let base64Data = file.content.base64EncodedString()
                    content = .array([
                        .document(.init(type: "base64",
                                        media_type: file.mimeType,
                                        data: base64Data))
                    ])
                } else {
                    // Any remaining binary type is unsupported by Anthropic;
                    // the per-provider allowlist should already have rejected
                    // it at the input layer. Fall back to lossyString so the
                    // request is still well-formed, but the upstream gate is
                    // the real defense here.
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
                        // Textual content (including image/svg+xml) goes
                        // through as text. Check this BEFORE the image-prefix
                        // branch so SVGs aren't sent as binary images.
                        if MIMETypeIsTextual(file.mimeType) {
                            return .text(.init(text: file.content.lossyString))
                        } else if Self.anthropicSupportedImageMimeTypes.contains(file.mimeType) {
                            let base64Data = file.content.base64EncodedString()
                            return .image(.init(type: "base64",
                                              media_type: file.mimeType,
                                              data: base64Data))
                        } else if file.mimeType == "application/pdf" {
                            let base64Data = file.content.base64EncodedString()
                            return .document(.init(type: "base64",
                                                   media_type: file.mimeType,
                                                   data: base64Data))
                        } else {
                            // Non-PDF, non-image binaries should have been
                            // rejected by the provider allowlist upstream.
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
                    case .document(let document):
                        guard let data = Data(base64Encoded: document.data) else { return nil }
                        return .attachment(.init(inline: false,
                                               id: UUID().uuidString,
                                               type: .file(.init(name: "document",
                                                               content: data,
                                                               mimeType: document.media_type))))
                    case .toolUse(let toolUse):
                        let inputString = (try? JSONSerialization.data(withJSONObject: toolUse.input))?.lossyString ?? ""
                        let functionCall = LLM.FunctionCall(name: toolUse.name, arguments: inputString, id: toolUse.id)
                        // Populate the wrapper FunctionCallID alongside call.id
                        // so the serializer's .functionOutput branch can recover
                        // the tool_use_id when the function output round-trips
                        // back through Anthropic. itemID uses the tool_use id
                        // (not "") so LLM.Message.Body.tryAppend keeps distinct
                        // parallel tool_use blocks distinct instead of merging
                        // them on matching empty itemIDs.
                        return .functionCall(functionCall, id: .init(callID: toolUse.id, itemID: toolUse.id))
                    case .toolResult(let toolResult):
                        // itemID mirrors the .toolUse pattern above so the two
                        // halves of a tool round-trip carry symmetric wrapper
                        // ids. Functionally either value works here because
                        // .functionOutput's tryAppend predicate (LLM.swift)
                        // requires full FunctionCallID equality and distinct
                        // callIDs already prevent erroneous merging.
                        return .functionOutput(name: "", output: toolResult.content, id: .init(callID: toolResult.tool_use_id, itemID: toolResult.tool_use_id))
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
                case .document(let document):
                    return "[Document: \(document.media_type)]"
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
        case document(AnthropicDocumentContent)
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
            case .document(_):
                // PDFs are tokenized server-side; we don't have a useful local
                // estimate so report a conservative non-trivial number.
                return 2000
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
            case .document(let content):
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
            case "document":
                let documentContent = try AnthropicDocumentContent(from: decoder)
                self = .document(documentContent)
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

    // Anthropic document content block. Used for application/pdf (base64) and
    // text/plain (for citations). See
    // https://docs.anthropic.com/en/docs/build-with-claude/pdf-support.
    struct AnthropicDocumentContent: Codable, Equatable {
        let type: String = "document"
        let source: Source

        struct Source: Codable, Equatable {
            let type: String
            let media_type: String
            let data: String
        }

        init(type: String, media_type: String, data: String) {
            self.source = Source(type: type, media_type: media_type, data: data)
        }

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
            // Anthropic returns one assistant turn whose `content` array can
            // hold multiple blocks (`text`, `tool_use`, etc.). The framework
            // expects choiceMessages to surface at most one Message; collapse
            // sibling blocks into one multipart-bodied assistant message so
            // AITerm sees the same shape it gets from every other vendor.
            var bodies: [LLM.Message.Body] = []
            for contentItem in content {
                switch contentItem.type {
                case "text":
                    if let text = contentItem.text, !text.isEmpty {
                        bodies.append(.text(text))
                    }
                case "tool_use":
                    if let name = contentItem.name,
                       let toolID = contentItem.id,
                       let input = contentItem.input {
                        let inputString = (try? JSONSerialization.data(withJSONObject: input))?.lossyString ?? ""
                        let functionCall = LLM.FunctionCall(name: name, arguments: inputString, id: toolID)
                        bodies.append(.functionCall(functionCall, id: .init(callID: toolID, itemID: toolID)))
                    }
                default:
                    break
                }
            }

            let body: LLM.Message.Body
            switch bodies.count {
            case 0:
                let textContent = content.compactMap { $0.text }.joined(separator: "")
                body = .text(textContent)
            case 1:
                body = bodies[0]
            default:
                body = .multipart(bodies)
            }
            return [LLM.Message(responseID: id, role: .assistant, body: body)]
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
                    return [LLM.Message(responseID: nil, role: .assistant, body: .functionCall(functionCall, id: .init(callID: toolID, itemID: toolID)))]
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
        // Structured form `[{type: "text", text: ..., cache_control: ...}]`.
        // Anthropic accepts either the legacy bare string or the array
        // form on the wire; we use the array form unconditionally so we
        // can attach cache_control to the system text block. Nil when
        // the conversation carries no system message (renames, etc.).
        var system: [AnthropicSystemBlock]?
        var temperature: Double?
        var stream: Bool?
        var tools: [AnthropicTool]?
        var tool_choice: AnthropicToolChoice?
        var disable_parallel_tool_use: Bool?
    }

    // Ephemeral prompt-cache marker. Anthropic caches every token from
    // the start of the request up through this marker, keyed by exact
    // byte equivalence. Within a ~5-minute window, subsequent requests
    // with the same prefix pay 0.1x for those tokens (cache_read)
    // instead of the full input rate.
    private struct AnthropicCacheControl: Codable {
        var type: String  // "ephemeral"
        static let ephemeral = AnthropicCacheControl(type: "ephemeral")
    }

    private struct AnthropicSystemBlock: Codable {
        var type: String  // "text"
        var text: String
        var cache_control: AnthropicCacheControl?
    }

    private struct AnthropicTool: Codable {
        var name: String
        var description: String
        var input_schema: JSONSchema
        // Optional ephemeral marker on the LAST tool in the array — see
        // body() — so the entire tools array (and everything before it,
        // i.e. system) caches as one prefix segment. Earlier tools must
        // leave this nil; each cache_control burns one of the four
        // breakpoints Anthropic allows per request.
        var cache_control: AnthropicCacheControl?
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

        return Self.enforceToolUseAdjacency(convertedMessages)
    }

    // Anthropic requires that every tool_use block in an assistant message be
    // immediately followed by a user message containing the matching tool_result
    // block (or all of them, for parallel tool_use). Callers (notably the
    // orchestrator's racy persistence) may hand us a layout where a plain user-text message
    // got persisted between a tool_use and its matching tool_result. Reorder so
    // the tool_result lands immediately after the tool_use, bumping any
    // intervening messages to AFTER the tool_result while preserving their
    // relative order. Match tool_use to tool_result by tool_use_id, which is
    // reliably populated on both halves via FunctionCallID since 92c2c3f9b.
    static func enforceToolUseAdjacency(_ messages: [AnthropicMessage]) -> [AnthropicMessage] {
        var input = messages
        var output: [AnthropicMessage] = []
        var i = 0
        while i < input.count {
            let current = input[i]
            output.append(current)
            i += 1
            let expectedIds = toolUseIds(in: current)
            guard !expectedIds.isEmpty else { continue }

            // Walk forward gathering tool_result blocks for the expected ids.
            // Intervening messages stay in input and get processed by the outer
            // loop on the next iteration (so they land AFTER the synthesized
            // tool_result message we append below).
            var resultBlocks: [AnthropicMessage.AnthropicContentBlock] = []
            var pendingIds = expectedIds
            var k = i
            while k < input.count, !pendingIds.isEmpty {
                let candidate = input[k]
                guard candidate.role == .user,
                      case .array(let blocks) = candidate.content else {
                    k += 1
                    continue
                }
                var consumed: [AnthropicMessage.AnthropicContentBlock] = []
                var leftover: [AnthropicMessage.AnthropicContentBlock] = []
                for block in blocks {
                    if case .toolResult(let toolResult) = block,
                       let idx = pendingIds.firstIndex(of: toolResult.tool_use_id) {
                        consumed.append(block)
                        pendingIds.remove(at: idx)
                    } else {
                        leftover.append(block)
                    }
                }
                if consumed.isEmpty {
                    k += 1
                    continue
                }
                resultBlocks.append(contentsOf: consumed)
                if leftover.isEmpty {
                    input.remove(at: k)
                } else {
                    input[k] = AnthropicMessage(role: .user, content: .array(leftover))
                    k += 1
                }
            }
            if !resultBlocks.isEmpty {
                output.append(AnthropicMessage(role: .user, content: .array(resultBlocks)))
            }
        }
        return output
    }

    private static func toolUseIds(in message: AnthropicMessage) -> [String] {
        guard message.role == .assistant,
              case .array(let blocks) = message.content else {
            return []
        }
        return blocks.compactMap { block in
            if case .toolUse(let toolUse) = block { return toolUse.id }
            return nil
        }
    }

    func body() throws -> Data {
        let anthropicMessages = convertMessages(messages)
        let systemMessageText = messages.compactMap { message in
            switch message.role {
            case .system:
                return message.content
            default:
                return nil
            }
        }.first

        // Prompt-cache markers.
        //
        // Anthropic orders the cacheable prefix as tools → system →
        // messages. Each cache_control marker creates a breakpoint
        // that covers everything from the start of that order up to
        // and including the marked element. So:
        //
        //   - Marker on system: covers [tools + system]. This is the
        //     common-case win — both stable across the chat, the
        //     entire ~13KB prefix becomes one cache_read.
        //   - Marker on the LAST tool: covers [tools] only. This is
        //     the fallback that still hits if the system prompt
        //     changes (e.g. a future feature that injects a per-turn
        //     system addendum), because [tools] is a strict prefix of
        //     [tools + system] and the tools-only segment survives.
        //
        // Keep BOTH markers. Dropping the last-tool marker as
        // "redundant" because the system marker already covers tools
        // would silently destroy the fallback segment: any system
        // edit would invalidate everything, and we'd pay
        // cache_creation on tools again. The tools array (~5KB) is
        // worth the second breakpoint.
        //
        // Earlier tools intentionally carry no marker; each one would
        // burn a breakpoint, and Anthropic caps the request at four.
        // Body() with an empty conversation (no system, no tools)
        // emits no markers at all.
        let systemBlocks: [AnthropicSystemBlock]?
        if let systemMessageText {
            systemBlocks = [
                AnthropicSystemBlock(
                    type: "text",
                    text: systemMessageText,
                    cache_control: .ephemeral)
            ]
        } else {
            systemBlocks = nil
        }

        let anthropicTools: [AnthropicTool]?
        if functions.isEmpty {
            anthropicTools = nil
        } else {
            var tools: [AnthropicTool] = functions.map { function in
                AnthropicTool(
                    name: function.decl.name,
                    description: function.decl.description,
                    input_schema: function.decl.parameters,
                    cache_control: nil)
            }
            tools[tools.count - 1].cache_control = .ephemeral
            anthropicTools = tools
        }

        let body = Body(
            model: provider.model.name,
            messages: anthropicMessages,
            max_tokens: provider.maxTokens(functions: functions, messages: messages),
            system: systemBlocks,
            temperature: 0.0,
            stream: stream ? true : nil,
            tools: anthropicTools,
            tool_choice: functions.isEmpty ? nil : .auto
        )

        if body.max_tokens < 2 {
            throw AIError.requestTooLarge
        }

        let bodyEncoder = JSONEncoder()
        // Anthropic prompt caching is keyed on byte-exact prefix match.
        // Tool input_schema contains a [String: Property] dictionary,
        // and Swift's Dictionary iteration order is randomized per
        // process, so without .sortedKeys two requests built from the
        // same tool list can serialize their tools array with the same
        // bytes shuffled — making the cache_read path silently never
        // fire. sortedKeys also gives us reproducible request bodies
        // for tests. The wire shape is unaffected; Anthropic doesn't
        // care about key order, only the cache does.
        bodyEncoder.outputFormatting = [.sortedKeys]
        let bodyData = try bodyEncoder.encode(body)
        DLog("REQUEST:\n\(bodyData.lossyString)")
        return bodyData
    }
}
