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
    // Modern OpenAI-compatible chat-completions servers (incl. DeepSeek) emit
    // function calls as tool_calls.
    var tool_calls: [ToolCall]?
    // Modern format: tool output messages use role="tool" with tool_call_id
    // referring back to the assistant's tool_calls[i].id. Legacy format used
    // role="function" with name and no id.
    var tool_call_id: String?
    // DeepSeek v4 thinking mode: present only on assistant responses. Other
    // chat-completions vendors don't emit it. This field is decode-only by
    // construction: it is NOT in CodingKeys (the wire key set used by
    // encode(to:)), so there is no path through which it can be serialized
    // back to a server that doesn't accept it (e.g. OpenAI's chat-completions
    // would reject the unknown field). DeepSeek's round-trip goes through
    // DeepSeekRequestBuilder.Body.Message, not this type. To read it off the
    // wire we use a separate single-case ReasoningKey in init(from:).
    var reasoning_content: String?

    struct ToolCall: Codable, Equatable {
        var index: Int?
        var id: String?
        var type: String?  // "function"
        var function: LLM.FunctionCall?
    }

    init(role: LLM.Role? = .user,
         content: Content? = nil,
         name: String? = nil,
         function_call: LLM.FunctionCall? = nil) {
        self.role = role
        self.content = content
        self.functionName = name
        self.function_call = function_call
    }

    // Wire keys consumed by both encode(to:) and init(from:). Deliberately
    // does NOT include reasoning_content — see ReasoningKey below.
    enum CodingKeys: String, CodingKey {
        case role
        case functionName = "name"
        case content
        case function_call
        case tool_calls
        case tool_call_id
    }

    // Read-only side channel for DeepSeek's reasoning_content. Kept out of
    // CodingKeys so a future maintainer adding `try container.encodeIfPresent
    // (reasoning_content, ...)` "for symmetry" would get a compile error
    // (.reasoning_content isn't a CodingKey member) — making the OpenAI-safe
    // invariant structural rather than convention.
    private enum ReasoningKey: String, CodingKey {
        case reasoning_content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.role = try container.decodeIfPresent(LLM.Role.self, forKey: .role)
        self.content = try container.decodeIfPresent(Content.self, forKey: .content)
        self.functionName = try container.decodeIfPresent(String.self, forKey: .functionName)
        self.function_call = try container.decodeIfPresent(LLM.FunctionCall.self, forKey: .function_call)
        self.tool_calls = try container.decodeIfPresent([ToolCall].self, forKey: .tool_calls)
        self.tool_call_id = try container.decodeIfPresent(String.self, forKey: .tool_call_id)
        let reasoningContainer = try decoder.container(keyedBy: ReasoningKey.self)
        self.reasoning_content = try reasoningContainer.decodeIfPresent(
            String.self, forKey: .reasoning_content)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Modern format requires role="tool" with tool_call_id for function
        // outputs; legacy used role="function" with name. Pick based on
        // whether we have a tool_call_id (we do iff the call originally came
        // back as tool_calls, i.e. a modern server).
        if tool_call_id != nil {
            try container.encode("tool", forKey: .role)
        } else {
            try container.encode(role, forKey: .role)
        }

        if tool_call_id == nil, let functionName {
            try container.encode(functionName, forKey: .functionName)
        }

        try container.encode(content, forKey: .content)

        if let function_call {
            try container.encode(function_call, forKey: .function_call)
        }

        // Echo tool_calls back when present. Modern OpenAI-compatible servers
        // expect tool_calls (function_call has been deprecated since
        // mid-2023). Without this, an assistant turn captured via tool_calls
        // gets re-emitted as the legacy function_call field, which servers
        // that drop legacy support would refuse on round-trip.
        if let tool_calls, !tool_calls.isEmpty {
            try container.encode(tool_calls, forKey: .tool_calls)
        }

        if let tool_call_id {
            try container.encode(tool_call_id, forKey: .tool_call_id)
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
                // Binary images and audio become typed content parts (vision /
                // input_audio); textual (incl. image/svg+xml) and everything
                // else keep the legacy string body.
                if !MIMETypeIsTextual(file.mimeType),
                   file.mimeType.hasPrefix("image/") || Self.openAIAudioFormat(forMime: file.mimeType) != nil {
                    content = .array([Self.contentPart(forFile: file)])
                } else {
                    content = .string(file.content.lossyString)
                }
            case .fileID(_, let name):
                content = .string("A file named \(name) (content unavailable)")
            }
        case .functionCall(let call, let id):
            // Modern servers want tool_calls with an explicit id; legacy
            // servers want the older function_call field. Prefer modern when
            // we captured an id (server gave us one); fall back to legacy
            // when we don't have one (very old conversation history).
            if let callID = id?.callID ?? call.id {
                tool_calls = [.init(index: nil, id: callID, type: "function", function: call)]
            } else {
                functionName = call.name
                function_call = call
            }
            content = nil
        case .functionOutput(name: let name, output: let output, id: let id):
            // Modern servers want role="tool" with tool_call_id; legacy
            // servers want role="function" with name. The custom encode
            // above picks based on whether tool_call_id is set.
            if let callID = id?.callID {
                tool_call_id = callID
            } else {
                functionName = name
            }
            content = .string(output)
        case .uninitialized:
            return nil
        case .multipart(let subparts):
            // Multipart bodies can now reach this serializer when AITermController
            // collapses a [text-preamble, functionCall] response into one history
            // entry (see parseNonStreamingResponse). Surface text + the first
            // function call onto the same CompletionsMessage so neither is dropped.
            // Function outputs and nested multipart aren't expected from any
            // current parser; ignore them rather than crashing.
            var contentParts: [ContentPart] = []
            for subpart in subparts {
                switch subpart {
                case .uninitialized:
                    break
                case .text(let string):
                    contentParts.append(.text(.init(text: string)))
                case .functionCall(let call, let id):
                    // Mirror the top-level functionCall encode logic: prefer
                    // modern tool_calls when we have an id, fall back to
                    // legacy function_call otherwise.
                    if tool_calls == nil && function_call == nil {
                        if let callID = id?.callID ?? call.id {
                            tool_calls = [.init(index: nil, id: callID, type: "function", function: call)]
                        } else {
                            function_call = call
                            functionName = call.name
                        }
                    }
                case .functionOutput, .multipart:
                    // Not expected from any current parser. Log so future regressions
                    // (e.g. nested multipart bodies, or function output siblings) are
                    // visible instead of silently dropped.
                    DLog("CompletionsMessage: ignoring unsupported subpart in multipart body: \(subpart)")
                case .attachment(let attachment):
                    switch attachment.type {
                    case .code(let string):
                        contentParts.append(.text(.init(text: string)))
                    case .statusUpdate:
                        break
                    case .file(let file):
                        contentParts.append(Self.contentPart(forFile: file))
                    case .fileID(id: _, name: let name):
                        contentParts.append(.text(.init(text: "A file named \(name) (content unavailable)")))
                    }
                }
            }
            content = contentParts.isEmpty ? nil : .array(contentParts)
        }
    }
    var llmMessage: LLM.Message {
        if let functionName, let content, case let .string(string) = content {
            return LLM.Message(responseID: nil,
                               role: role,
                               body: .functionOutput(name: functionName,
                                                     output: string,
                                                     id: nil),
                               reasoningContent: reasoning_content)
        }
        // Build the assistant turn's body from whatever combination of text,
        // legacy function_call, and modern tool_calls the server returned.
        // Modern chat-completions can deliver a turn that includes both
        // preamble content AND tool_calls; surface them as a multipart so
        // neither is dropped, matching the platform-neutral shape that the
        // other vendors' parsers now produce.
        // TODO: parallel_tool_calls (multiple entries in tool_calls) are not
        // yet surfaced; only the first call is propagated. Modeling parallel
        // calls would require multipart with several .functionCall parts and
        // dispatching multiple function executions before continuing, which
        // the framework does not do today.
        var bodies: [LLM.Message.Body] = []
        if let content {
            switch content {
            case .string(let string) where !string.isEmpty:
                bodies.append(.text(string))
            case .string:
                break
            case .array(let array):
                let parts: [LLM.Message.Body] = array.map { part in
                    switch part {
                    case .text(let text):
                        return .text(text.text)
                    case .file(let file):
                        return .attachment(.init(inline: false,
                                                 id: UUID().uuidString,
                                                 type: .file(.init(name: file.filename,
                                                                   content: Data(base64Encoded: file.file_data) ?? Data(),
                                                                   mimeType: "application/octet-stream"))))
                    case .imageURL(let image):
                        // Responses don't normally carry image_url; keep the
                        // mapping total and round-trip the bytes when we can.
                        if let (mime, data) = Self.decodeDataURL(image.url) {
                            return .attachment(.init(inline: false,
                                                     id: UUID().uuidString,
                                                     type: .file(.init(name: "image",
                                                                       content: data,
                                                                       mimeType: mime))))
                        }
                        return .text(image.url)
                    case .inputAudio(let audio):
                        let mime = audio.format == "wav" ? "audio/wav" : "audio/mpeg"
                        return .attachment(.init(inline: false,
                                                 id: UUID().uuidString,
                                                 type: .file(.init(name: "audio",
                                                                   content: Data(base64Encoded: audio.data) ?? Data(),
                                                                   mimeType: mime))))
                    }
                }
                if parts.count == 1 {
                    bodies.append(parts[0])
                } else if !parts.isEmpty {
                    bodies.append(.multipart(parts))
                }
            }
        }
        if let function_call {
            bodies.append(.functionCall(function_call, id: nil))
        } else if let toolCall = tool_calls?.first, let function = toolCall.function {
            let id: LLM.Message.FunctionCallID? = toolCall.id.map {
                LLM.Message.FunctionCallID(callID: $0, itemID: $0)
            }
            bodies.append(.functionCall(function, id: id))
        }
        let body: LLM.Message.Body
        switch bodies.count {
        case 0: body = .uninitialized
        case 1: body = bodies[0]
        default: body = .multipart(bodies)
        }
        return LLM.Message(responseID: nil, role: role, body: body, reasoningContent: reasoning_content)
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
                case .imageURL:
                    return "[image]"
                case .inputAudio:
                    return "[audio]"
                }
            }.joined(separator: "\n")
        }
    }

    // Map a user attachment file to the right chat-completions content part:
    // image/* -> image_url (vision), wav/mp3 -> input_audio, PDF -> file,
    // anything else -> the legacy <iterm2:attachment> text wrapper. Used by
    // both the multipart and top-level attachment encode paths.
    static func contentPart(forFile file: LLM.Message.Attachment.AttachmentType.File) -> ContentPart {
        let mime = file.mimeType
        // Textual content (including image/svg+xml and application/xml) must
        // NOT take the image/audio binary branches. SVG starts with image/
        // but is XML text; OpenAI's image_url 400s it ("unsupported image").
        // Send it (and any other text) through the wrapper text part.
        if !MIMETypeIsTextual(mime) {
            if mime.hasPrefix("image/") {
                let base64 = file.content.base64EncodedString()
                return .imageURL(.init(url: "data:\(mime);base64,\(base64)"))
            }
            if let format = openAIAudioFormat(forMime: mime) {
                return .inputAudio(.init(data: file.content.base64EncodedString(), format: format))
            }
            if mime == "application/pdf" {
                let base64 = file.content.base64EncodedString()
                return .file(.init(file_data: "data:\(mime);base64,\(base64)", filename: file.name))
            }
        }
        var value = "<iterm2:attachment file=\"\(file.name)\" type=\"\(mime)\">\n"
        value += file.content.lossyString
        value += "\n</iterm2:attachment>"
        return .text(.init(text: value))
    }

    // OpenAI's input_audio.format is a closed enum of "wav" / "mp3"; returns
    // nil for any other audio MIME (those are refused by the provider gate).
    static func openAIAudioFormat(forMime mime: String) -> String? {
        switch mime {
        case "audio/wav", "audio/x-wav":
            return "wav"
        case "audio/mpeg", "audio/mp3":
            return "mp3"
        default:
            return nil
        }
    }

    // Parse "data:<mime>;base64,<payload>" back into its MIME and bytes.
    static func decodeDataURL(_ string: String) -> (String, Data)? {
        guard string.hasPrefix("data:"), let comma = string.firstIndex(of: ",") else {
            return nil
        }
        let meta = string[string.index(string.startIndex, offsetBy: 5)..<comma]
        let payload = String(string[string.index(after: comma)...])
        let mime = meta.split(separator: ";").first.map(String.init) ?? "application/octet-stream"
        guard let data = Data(base64Encoded: payload) else {
            return nil
        }
        return (mime, data)
    }
}

struct LLMModernResponseParser: LLMResponseParser {
    struct ModernResponse: Codable, LLM.AnyResponse {
        var isStreamingResponse: Bool { false }
        var id: String?
        var object: String?
        var created: Int?
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
            // `choices` is the n-sampling alternatives array; iTerm2 never
            // requests n > 1, so surface only the first.
            guard let first = choices.first else { return [] }
            return [first.message.llmMessage]
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
            // `choices` is the n-sampling alternatives axis; iTerm2 never
            // requests n > 1, so surface only the first.
            guard let choice = choices.first else { return [] }
            return [choice].compactMap { choice -> LLM.Message? in
                let delta = choice.delta
                let trailerForLegacyFunctionCall =
                    (choice.finish_reason == "function_call" || choice.finish_reason == "tool_calls") &&
                    delta.role == nil &&
                    delta.content == nil &&
                    delta.functionName == nil &&
                    delta.function_call == nil &&
                    (delta.tool_calls?.isEmpty ?? true)
                if trailerForLegacyFunctionCall {
                    // Sent at the end of a function call: a delta carrying only the
                    // finish_reason. Nothing to surface.
                    return nil
                }
                // Modern OpenAI-compatible servers stream function calls as tool_calls
                // deltas; the legacy `function_call` field is only used by very old
                // chat-completions endpoints. Prefer tool_calls when present.
                // TODO: parallel tool_calls in a single assistant turn are not yet
                // surfaced; only the first tool_call is propagated, matching the
                // single-call shape the rest of the framework assumes. Both this
                // streaming path and the non-streaming counterpart above need to
                // be updated together if parallel calls become a requirement.
                // OpenAI today streams text deltas and tool_calls deltas in
                // separate chunks, but the protocol doesn't forbid combining
                // them. If a single delta carries both, surface them together
                // as a multipart so neither is silently dropped.
                let textContent = delta.coercedContentString
                if let toolCall = delta.tool_calls?.first, let function = toolCall.function {
                    let id: LLM.Message.FunctionCallID? = toolCall.id.map {
                        LLM.Message.FunctionCallID(callID: $0, itemID: $0)
                    }
                    let body: LLM.Message.Body
                    if textContent.isEmpty {
                        body = .functionCall(function, id: id)
                    } else {
                        body = .multipart([
                            .text(textContent),
                            .functionCall(function, id: id),
                        ])
                    }
                    return LLM.Message(responseID: nil, role: .assistant, body: body)
                }
                if let function_call = delta.function_call {
                    let body: LLM.Message.Body
                    if textContent.isEmpty {
                        body = .functionCall(function_call, id: nil)
                    } else {
                        body = .multipart([
                            .text(textContent),
                            .functionCall(function_call, id: nil),
                        ])
                    }
                    return LLM.Message(responseID: nil, role: .assistant, body: body)
                }
                return LLM.Message(role: .assistant, content: textContent)
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
        // OpenAI chat-completions vision: {"type":"image_url","image_url":{"url":"data:..."}}
        case imageURL(ImageURLContent)
        // OpenAI chat-completions audio (audio models only):
        // {"type":"input_audio","input_audio":{"data":"<base64>","format":"wav"|"mp3"}}
        case inputAudio(InputAudioContent)

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case file
            case imageURL = "image_url"
            case inputAudio = "input_audio"
        }

        var approximateTokenCount: Int {
            switch self {
            case .text(let content): return AIMetadata.instance.tokens(in: content.text) + 1
            case .file(let file): return AIMetadata.instance.tokens(in: file.file_data + file.filename) + 1
            case .imageURL(let content): return AIMetadata.instance.tokens(in: content.url) + 1
            case .inputAudio(let content): return AIMetadata.instance.tokens(in: content.data) + 1
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
            case .imageURL(let content):
                try container.encode("image_url", forKey: .type)
                try container.encode(content, forKey: .imageURL)
            case .inputAudio(let content):
                try container.encode("input_audio", forKey: .type)
                try container.encode(content, forKey: .inputAudio)
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
            case "image_url":
                self = .imageURL(try container.decode(ImageURLContent.self, forKey: .imageURL))
            case "input_audio":
                self = .inputAudio(try container.decode(InputAudioContent.self, forKey: .inputAudio))
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

    struct ImageURLContent: Codable, Equatable {
        let url: String  // data:<mime>;base64,<...> or a remote URL
    }

    struct InputAudioContent: Codable, Equatable {
        let data: String    // base64 encoded bytes
        let format: String  // "wav" or "mp3"
    }

}
