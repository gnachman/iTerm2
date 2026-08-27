//
//  Llama.swift
//  iTerm2
//
//  Created by George Nachman on 6/11/25.
//

struct LlamaResponseParser: LLMResponseParser {
    var parsedResponse: LlamaResponse<LlamaNonStreamingValue>?

    mutating func parse(data: Data) throws -> LLM.AnyResponse? {
        let decoder = JSONDecoder()
        let response = try decoder.decode(LlamaResponse<LlamaNonStreamingValue>.self,
                                          from: data)
        // Model reply (chat content): keep out of the always-on ring.
        RLog("RESPONSE:\n\(redacted: response)")
        parsedResponse = response
        return response
    }

    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return (nil, "")
    }
}

struct LlamaStreamingResponseParser: LLMStreamingResponseParser {
    var parsedResponse: LlamaResponse<LlamaStreamingValue>?

    mutating func parse(data: Data) throws -> (any LLM.AnyStreamingResponse)? {
        let decoder = JSONDecoder()
        let response = try decoder.decode(LlamaResponse<LlamaStreamingValue>.self,
                                          from: data)
        DLog("RESPONSE:\n\(response)")
        parsedResponse = response
        return response
    }

    func splitFirstJSONEvent(from rawInput: String) -> (json: String?, remainder: String) {
        return SplitNDJSON(from: rawInput)
    }
}

protocol LlamaStreaming {
    static var streaming: Bool { get }
}

struct LlamaStreamingValue: LlamaStreaming {
    static var streaming: Bool { true }
}

struct LlamaNonStreamingValue: LlamaStreaming {
    static var streaming: Bool { false }
}

struct LlamaResponse<Streaming: LlamaStreaming>: Codable {
    var model: String  // llama3.2
    var message: Message
    struct Message: Codable {
        var role: String  // assistant
        var content: String
        // Ollama native /api/chat returns reasoning text in its own `thinking`
        // field (distinct from `content`) when the request enabled thinking.
        // Streamed incrementally, like content. nil/absent when the model isn't
        // thinking or the field predates this decoder.
        var thinking: String?
        var tool_calls: [ToolCall]?

        struct ToolCall: Codable {
            var function: Function

            struct Function: Codable {
                var name: String  // get_current_weather
                // AnyCodable, not String: Ollama echoes tool arguments back with
                // the JSON types the tool's own schema declared, so a parameter
                // typed integer|null arrives as a number or null and a
                // String-valued dictionary fails to decode the whole response.
                var arguments: [String: AnyCodable]
            }
        }
    }

    var done: Bool  // false while streaming
}

extension LlamaResponse: LLM.AnyResponse {
    var choiceMessages: [LLM.Message] {
        if done && Streaming.streaming {
            return []
        }
        var messages = [LLM.Message]()
        // Surface Ollama's native `thinking` via the reasoningSummaryUpdate
        // status path (same as DeepSeek/OpenAI) so the chat renders it, and stash
        // it on reasoningContent so the accumulator in AITerm.swift can fold it
        // into the final assistant turn.
        if let thinking = message.thinking, !thinking.isEmpty {
            var msg = LLM.Message(
                role: .assistant,
                body: .attachment(.init(
                    inline: true,
                    id: "ollama-reasoning",
                    type: .statusUpdate(.reasoningSummaryUpdate(thinking)))))
            msg.reasoningContent = thinking
            messages.append(msg)
        }
        if let toolCall = message.tool_calls?.first {
            messages.append(LLM.Message(
                responseID: nil,
                role: .assistant,
                body: .functionCall(
                    .init(
                        name: toolCall.function.name,
                        arguments: try? JSONEncoder().encode(
                            toolCall.function.arguments).lossyString),
                    id: nil)))
        } else if messages.isEmpty || !message.content.isEmpty {
            messages.append(LLM.Message(responseID: nil,
                                        role: .assistant,
                                        body: .text(message.content)))
        }
        return messages
    }
    var isStreamingResponse: Bool {
        Streaming.streaming
    }
    // Explicit (not the protocol default) because LlamaResponse conforms to both
    // AnyResponse and AnyStreamingResponse, whose defaults would otherwise be
    // ambiguous. Llama's response carries no usage, so there is no token count.
    var promptTokens: Int? { nil }
}

extension LlamaResponse: LLM.AnyStreamingResponse {
    var ignore: Bool {
        message.content == "" && message.tool_calls == nil && (message.thinking?.isEmpty ?? true)
    }
    
    var newlyCreatedResponseID: String? {
        nil
    }
}

func SplitNDJSON(from rawInput: String) -> (json: String?, remainder: String) {
    let input = rawInput.trimmingLeadingCharacters(in: .whitespacesAndNewlines)
    guard let newlineRange = input.range(of: "\n") else {
        return (nil, String(input))
    }

    // Extract the first line (up to, but not including, the newline)
    let firstLine = input[..<newlineRange.lowerBound]
    // Everything after the newline is the remainder.
    let remainder = input[newlineRange.upperBound...]

    return (String(firstLine), String(remainder))
}

// MARK: - Request

struct LlamaBodyRequestBuilder {
    var messages: [LLM.Message]
    var provider: LLMProvider
    var functions = [LLM.AnyFunction]()
    var stream: Bool
    // nil: no opinion, omit `think` so the model's own default applies. true/false:
    // the chat's Think toggle. Only meaningful for thinking-capable local models.
    var shouldThink: Bool? = nil
    var frozenHistoryElements: Data? = nil  // blob-native replay; see LLMRequestBuilder

    // Ollama's native /api/chat request. The `messages` array stays
    // CompletionsMessage-shaped (collapsed by joinText) so the blob-replay wire
    // format keeps matching what this builder sends; the native-only knobs
    // (think, options, keep_alive) live in the outer body, which the blob encoder
    // never touches.
    private struct Body: Codable {
        var model: String?
        var messages = [CompletionsMessage]()
        var tools: [LlamaFunctionDeclaration]? = nil
        var stream: Bool
        var think: Bool? = nil
        var keep_alive: String? = nil
        var options: Options? = nil

        struct Options: Codable {
            // Ollama defaults num_ctx to a small value (~4096) regardless of the
            // model and silently truncates a longer prompt. num_predict is the
            // native response-token budget (max_tokens is ignored by /api/chat).
            var num_ctx: Int?
            var num_predict: Int?
        }
    }

    // num_ctx is the TOTAL KV window (prompt + generated). Size it to this
    // request rather than the model's full window: over-allocating wastes memory
    // and can force a CPU fallback on a small machine.
    private static let numCtxHeadroom = 256
    private static let minNumCtx = 4096
    // Cap the response space reserved inside num_ctx. Terminal-assistant answers
    // fit comfortably; without a cap a model whose maxResponseTokens equals its
    // context window would always request the full window.
    private static let maxResponseReserve = 8192

    private static func roundUpToPowerOfTwo(_ n: Int) -> Int {
        guard n > 1 else { return 1 }
        var p = 1
        while p < n {
            p <<= 1
        }
        return p
    }

    // Dynamic sizing with a cap (and an advanced-settings override). A positive
    // ollamaNumCtx override is sent verbatim so power users can pin it; otherwise
    // fit prompt + a reserved response budget, round up to a power of two, floor
    // at minNumCtx, and cap at the model's real context window.
    private static func computedNumCtx(promptTokens: Int,
                                       numPredict: Int,
                                       contextWindow: Int) -> Int {
        let override = Int(iTermAdvancedSettingsModel.ollamaNumCtx())
        if override > 0 {
            return override
        }
        let reserve = min(max(numPredict, 512), maxResponseReserve)
        let desired = promptTokens + reserve + numCtxHeadroom
        let sized = roundUpToPowerOfTwo(max(desired, minNumCtx))
        return min(sized, contextWindow)
    }

    private static func estimatedPromptTokens(messages: [CompletionsMessage],
                                              tools: [LlamaFunctionDeclaration]?) -> Int {
        let encoder = JSONEncoder()
        var text = (try? encoder.encode(messages).lossyString) ?? ""
        if let tools, let data = try? encoder.encode(tools) {
            text += data.lossyString
        }
        return AIMetadata.instance.tokens(in: text)
    }

    // Llama doesn't like multiple text parts.
    //
    // Static so the blob wire-encoder can reuse the EXACT same per-message pass:
    // llama's frozen round bytes must match what this builder actually sends, or a
    // replayed blob could emit the multiple text parts llama rejects.
    static func joinText(_ message: CompletionsMessage) -> CompletionsMessage {
        switch message.content {
        case .string, .none:
            return message
        case .array(let parts):
            var temp = message
            var combined = Array<CompletionsMessage.ContentPart>()
            for part in parts {
                switch part {
                case .text(let textContent):
                    switch combined.last {
                    case .none, .file, .imageURL, .inputAudio:
                        combined.append(part)
                    case .text(let existingTextContent):
                        combined[combined.count - 1] = .text(.init(text: existingTextContent.text + "\n" + textContent.text))
                    }
                case .file, .imageURL, .inputAudio:
                    combined.append(part)
                }
            }
            if combined.count == 1, case .text(let text) = combined[0] {
                temp.content = .string(text.text)
            } else {
                temp.content = .array(combined)
            }
            return temp
        }
    }

    func body() throws -> Data {
        let maybeDecls = functions.isEmpty ? nil : functions.map { LlamaFunctionDeclaration($0.decl) }

        let llamaMessages = messages.compactMap {
            CompletionsMessage($0)
        }.map { message -> CompletionsMessage in
            var m = Self.joinText(message)
            // Emit tool messages in Ollama's native shape (role:tool/tool_name,
            // idless tool_calls); non-tool messages are unaffected.
            m.ollamaToolFormat = true
            return m
        }

        let numPredict = provider.maxTokens(functions: functions, messages: messages)
        if numPredict < 2 {
            throw AIError.requestTooLarge
        }
        // See the note about streaming function calling in Llama in AIMetadata.swift
        // #llama-streaming-functions
        let tools = stream ? nil : maybeDecls
        // llamaMessages is only the CURRENT round. On the blob-native replay path
        // the frozen prior rounds are spliced into `messages` below, AFTER this,
        // so they must be counted here too or num_ctx is sized for just the latest
        // round and Ollama silently truncates the replayed history.
        var promptTokens = Self.estimatedPromptTokens(messages: llamaMessages, tools: tools)
        if let frozenHistoryElements, !frozenHistoryElements.isEmpty {
            promptTokens += AIMetadata.instance.tokens(in: frozenHistoryElements.lossyString)
        }
        let numCtx = Self.computedNumCtx(promptTokens: promptTokens,
                                         numPredict: numPredict,
                                         contextWindow: provider.model.contextWindowTokens)
        // Never let num_predict exceed the room left in the window, or Ollama
        // truncates the answer mid-stream once generation reaches num_ctx.
        let effectiveNumPredict = max(1, min(numPredict, numCtx - promptTokens - 64))

        let keepAliveSetting = iTermAdvancedSettingsModel.ollamaKeepAlive()
        let keepAlive = (keepAliveSetting?.isEmpty ?? true) ? nil : keepAliveSetting

        let body = Body(
            model: provider.dynamicModelsSupported ? provider.model.name : nil,
            messages: llamaMessages,
            tools: tools,
            stream: stream,
            think: shouldThink,
            keep_alive: keepAlive,
            options: Body.Options(num_ctx: numCtx, num_predict: effectiveNumPredict))
        // Request body carries the user's prompts/messages; keep it out of the ring.
        RLog("REQUEST:\n\(redacted: body)")
        let bodyEncoder = JSONEncoder()
        let bodyData = try! bodyEncoder.encode(body)
        return try ChatBlobAssembler.spliceFrozenHistory(
            frozenHistoryElements, into: bodyData, arrayKey: "messages",
            afterCount: messages.filter { $0.role == .system }.count)

    }
}

struct LlamaFunctionDeclaration: Codable {
    var type = "function"
    var function: ChatGPTFunctionDeclaration

    init(_ decl: ChatGPTFunctionDeclaration) {
        self.function = decl
    }
}
