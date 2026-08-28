//
//  Llama.swift
//  iTerm2
//
//  Created by George Nachman on 6/11/25.
//

import ImageIO

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
        let thinking: String? = {
            guard let t = message.thinking, !t.isEmpty else { return nil }
            return t
        }()
        let functionCall: LLM.FunctionCall? = message.tool_calls?.first.map {
            .init(name: $0.function.name,
                  arguments: try? JSONEncoder().encode($0.function.arguments).lossyString)
        }

        if !Streaming.streaming {
            // Non-streaming: parseNonStreamingResponse consumes only .first, so a
            // single assistant message must carry the answer/tool with reasoning
            // folded in as a scalar (matching the modern/DeepSeek non-streaming
            // shape). Emitting a separate LEADING reasoning message would make
            // .first an empty reasoning attachment and drop the real answer/tool.
            // When a preamble AND a tool call co-arrive, keep BOTH via a multipart
            // body so the text isn't dropped (again matching the modern shape).
            let body: LLM.Message.Body
            var scalarReasoning = thinking
            if let functionCall {
                body = message.content.isEmpty
                    ? .functionCall(functionCall, id: nil)
                    : .multipart([.text(message.content), .functionCall(functionCall, id: nil)])
            } else if !message.content.isEmpty {
                body = .text(message.content)
            } else if let thinking {
                // A thinking model returned its answer only in `thinking` (small
                // models do this). Surface it as the visible answer instead of a
                // blank reply, and don't ALSO deliver it as reasoning (avoid
                // showing the same text twice; Ollama doesn't require reasoning on
                // round-trip the way DeepSeek does).
                body = .text(thinking)
                scalarReasoning = nil
            } else {
                body = .text(message.content)
            }
            return [LLM.Message(responseID: nil,
                                role: .assistant,
                                body: body,
                                reasoningContent: scalarReasoning)]
        }

        // Streaming: AITerm iterates every choice, so reasoning arrives as its own
        // delta message and renders live via the reasoningSummaryUpdate path.
        var messages = [LLM.Message]()
        if let thinking {
            var msg = LLM.Message(
                role: .assistant,
                body: .attachment(.init(
                    inline: true,
                    id: "ollama-reasoning",
                    type: .statusUpdate(.reasoningSummaryUpdate(thinking)))))
            msg.reasoningContent = thinking
            messages.append(msg)
        }
        if let functionCall {
            messages.append(LLM.Message(responseID: nil, role: .assistant,
                                        body: .functionCall(functionCall, id: nil)))
        } else if messages.isEmpty || !message.content.isEmpty {
            messages.append(LLM.Message(responseID: nil, role: .assistant,
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
    // Below this many tokens of room left inside num_ctx, the response would be
    // uselessly short (or a degenerate single token), so the prompt is treated as
    // too large rather than sent with a silently truncated context.
    private static let minResponseBudget = 128
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
        // A non-positive context window (a blank/0 manual field, which the editor
        // writes for an empty box) is unknown, not "zero tokens": treat it as the
        // floor so we never emit num_ctx 0 and hard-fail every request.
        let window = contextWindow > 0 ? contextWindow : minNumCtx
        let reserve = min(max(numPredict, 512), maxResponseReserve)
        let desired = promptTokens + reserve + numCtxHeadroom
        let sized = roundUpToPowerOfTwo(max(desired, minNumCtx))
        return min(sized, window)
    }

    private static func estimatedPromptTokens(messages: [CompletionsMessage],
                                              tools: [LlamaFunctionDeclaration]?) -> Int {
        // Reuse CompletionsMessage.approximateTokenCount rather than
        // re-serializing the whole (potentially multi-hundred-KB) prompt to a
        // JSON string just to feed tokens(in:). Only the small tools array is
        // encoded.
        var total = messages.map { estimatedTokens(for: $0) }.reduce(0, +)
        if let tools, let data = try? JSONEncoder().encode(tools) {
            total += AIMetadata.instance.tokens(in: data.lossyString)
        }
        return total
    }

    // Per-message token estimate for num_ctx sizing. Same as
    // approximateTokenCount EXCEPT an inline image is charged by PIXEL AREA, not
    // by the length of its base64 data URL. Charging the base64 length (as
    // approximateTokenCount does, via tokens(in: url) = utf8.count/2) over-counts
    // a ~500 KB image by ~100x, which either throws requestTooLarge on a valid
    // vision request or over-allocates the KV cache. Image cost depends on the
    // loaded model's projector; we use a conservative upper bound.
    private static func estimatedTokens(for message: CompletionsMessage) -> Int {
        guard case .array(let parts) = message.content else {
            return message.approximateTokenCount
        }
        return parts.reduce(1) { subtotal, part in
            switch part {
            case .imageURL(let image):
                return subtotal + imageTokenEstimate(dataURL: image.url)
            default:
                return subtotal + part.approximateTokenCount
            }
        }
    }

    static let imageTokenFloor = 85
    static let imageTokenCap = 2048

    // A conservative per-image token estimate from pixel area (Anthropic-style
    // w*h/750, the highest of the common estimates, so it errs toward not
    // truncating), floored and capped so one giant image can't re-inflate the
    // estimate the way base64 length does. Falls back to the floor when the
    // dimensions can't be read (never the base64 length).
    static func imageTokenEstimate(dataURL: String) -> Int {
        guard let (width, height) = imagePixelSize(dataURL: dataURL), width > 0, height > 0 else {
            return imageTokenFloor
        }
        let estimate = Int((Double(width) * Double(height) / 750.0).rounded(.up))
        return min(max(estimate, imageTokenFloor), imageTokenCap)
    }

    // Read pixel dimensions cheaply from the image header (no full pixel decode)
    // via CGImageSource. nil if the payload isn't a decodable image.
    private static func imagePixelSize(dataURL: String) -> (Int, Int)? {
        guard let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) else {
            return nil
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (width, height)
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
        // If the prompt leaves no room for a usable response inside num_ctx, the
        // request is too large for this model's window (or for a too-small
        // ollamaNumCtx override). The numPredict<2 guard above misses this because
        // it budgets against the AI token-limit pref, which is independent of the
        // model's contextWindowTokens. Fail loudly instead of sending num_predict:1
        // with a truncated prompt and a silent one-token reply.
        let responseBudget = numCtx - promptTokens
        if responseBudget < Self.minResponseBudget {
            throw AIError.requestTooLarge
        }
        // Never let num_predict exceed the room left in the window, or Ollama
        // truncates the answer mid-stream once generation reaches num_ctx.
        let effectiveNumPredict = max(1, min(numPredict, responseBudget - 64))

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
        let bodyData = try bodyEncoder.encode(body)
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
