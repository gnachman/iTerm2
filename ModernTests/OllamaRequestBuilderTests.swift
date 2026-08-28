//
//  OllamaRequestBuilderTests.swift
//  iTerm2 ModernTests
//
//  The .llama API type targets Ollama's native /api/chat dialect. These tests
//  pin the request body that dialect needs and that the OpenAI-compatible
//  endpoint cannot express:
//
//    - `think`: control the reasoning mode of thinking-capable local models
//      (qwen3, deepseek-r1, gpt-oss). Omitted when the caller has no opinion,
//      true/false when the chat's Think toggle is set. Without it, reasoning
//      models default to thinking, which is slow and usually unwanted for
//      terminal Q&A (issue #12995).
//    - `options.num_ctx`: Ollama defaults the context window to a small value
//      (~4096) regardless of the model's real window, silently truncating a
//      long prompt with no error. We size it to fit this request, capped at the
//      model's real window.
//    - `options.num_predict`: the response-token budget (native equivalent of
//      max_tokens, which native /api/chat ignores).
//    - `keep_alive`: keep the model resident between turns to avoid cold-reload
//      latency.
//
//  The messages array serialization is deliberately NOT changed here: it stays
//  CompletionsMessage + joinText so the blob-replay wire format (see
//  ChatBlobWireEncoder.case .llama) keeps matching what the builder sends.
//

import XCTest
import AppKit
@testable import iTerm2SharedARC

@MainActor
final class OllamaRequestBuilderTests: XCTestCase {

    // A synthetic native-Ollama model. Cloned from a real catalog entry so
    // every unrelated field is realistic; only the api and the sizing-relevant
    // fields are pinned.
    private func ollamaModel(contextWindow: Int = 131_072,
                             maxResponse: Int = 8_192) throws -> AIMetadata.Model {
        guard var model = AIMetadata.instance.models.first else {
            throw XCTSkip("empty AIMetadata catalog")
        }
        model.name = "qwen3.5:test"
        model.api = .llama
        model.url = "http://localhost:11434/api/chat"
        model.contextWindowTokens = contextWindow
        model.maxResponseTokens = maxResponse
        model.features = [.streaming, .functionCalling, .configurableThinking]
        return model
    }

    private func body(shouldThink: Bool?,
                      contextWindow: Int = 131_072,
                      maxResponse: Int = 8_192,
                      messages: [LLM.Message]? = nil) throws -> [String: Any] {
        let model = try ollamaModel(contextWindow: contextWindow, maxResponse: maxResponse)
        let builder = LLMRequestBuilder(
            provider: LLMProvider(model: model),
            apiKey: "test-key",
            messages: messages ?? [LLM.Message(role: .system, content: "S"),
                                   LLM.Message(role: .user, content: "hello")],
            functions: [],
            stream: false,
            hostedTools: HostedTools(),
            previousResponseID: nil,
            shouldThink: shouldThink,
            reasoningEffort: nil,
            serviceTier: nil,
            trailingVolatileText: nil)
        let data = try builder.body()
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError("Ollama body was not a JSON object")
        }
        return json
    }

    private func options(_ json: [String: Any]) throws -> [String: Any] {
        guard let options = json["options"] as? [String: Any] else {
            throw AIError("Ollama body has no options object: \(json)")
        }
        return options
    }

    // MARK: - think

    func test_shouldThinkTrue_emitsThinkTrue() throws {
        let json = try body(shouldThink: true)
        XCTAssertEqual(json["think"] as? Bool, true,
                       "think:true must be sent so a thinking-capable local model reasons; body=\(json)")
    }

    func test_shouldThinkFalse_emitsThinkFalse() throws {
        let json = try body(shouldThink: false)
        XCTAssertEqual(json["think"] as? Bool, false,
                       "think:false must be sent to suppress slow default thinking (issue #12995); body=\(json)")
    }

    func test_shouldThinkNil_omitsThink() throws {
        let json = try body(shouldThink: nil)
        XCTAssertNil(json["think"],
                     "with no opinion the think field must be omitted so the model's own default applies; body=\(json)")
    }

    // MARK: - options.num_ctx

    func test_emitsNumCtx() throws {
        let json = try body(shouldThink: nil)
        let numCtx = try options(json)["num_ctx"] as? Int
        XCTAssertNotNil(numCtx, "options.num_ctx must be set or Ollama silently truncates long prompts")
        XCTAssertGreaterThan(numCtx ?? 0, 0)
    }

    // A generous window leaves num_ctx uncapped, so it lands on a power of two
    // sized to the request rather than the model's full window.
    func test_numCtx_isPowerOfTwo_whenUncapped() throws {
        let json = try body(shouldThink: nil, contextWindow: 131_072)
        let numCtx = try XCTUnwrap(try options(json)["num_ctx"] as? Int)
        XCTAssertTrue((numCtx & (numCtx - 1)) == 0,
                      "uncapped num_ctx should be a power of two, was \(numCtx)")
        XCTAssertLessThanOrEqual(numCtx, 131_072)
    }

    // The cap: num_ctx must never exceed the model's real context window even
    // when the request would round up past it.
    func test_numCtx_cappedAtContextWindow() throws {
        let window = 4_096
        let json = try body(shouldThink: nil, contextWindow: window, maxResponse: window)
        let numCtx = try XCTUnwrap(try options(json)["num_ctx"] as? Int)
        XCTAssertLessThanOrEqual(numCtx, window,
                                 "num_ctx exceeded the model's context window (\(window)); would over-allocate KV cache")
    }

    // A large prompt must push num_ctx above Ollama's ~4096 default, or the
    // prompt tail is silently dropped. This is the invisible-quality regression
    // the whole feature exists to prevent.
    func test_numCtx_growsWithLargePrompt() throws {
        let big = String(repeating: "terminal output line with several tokens of content\n", count: 400)
        let messages = [LLM.Message(role: .system, content: "S"),
                        LLM.Message(role: .user, content: big)]
        let json = try body(shouldThink: nil, contextWindow: 131_072, messages: messages)
        let numCtx = try XCTUnwrap(try options(json)["num_ctx"] as? Int)
        XCTAssertGreaterThan(numCtx, 4_096,
                             "a large prompt must raise num_ctx above the 4096 default so the prompt is not truncated, was \(numCtx)")
    }

    // Blob-native replay splices the frozen history (all prior rounds) into the
    // messages array AFTER num_ctx is computed. If the estimate omits that
    // prefix, num_ctx is sized only for [system + latest round] and Ollama
    // silently truncates the replayed history: the exact regression this feature
    // exists to prevent, on the normal multi-turn path.
    func test_numCtx_coversFrozenHistory() throws {
        // ~50k tokens of frozen prior rounds, spliced after the system message.
        // Plain letters/spaces so the JSON needs no escaping.
        let bigContent = String(repeating: "frozen history token content here ", count: 6_000)
        let frozen = Data("{\"role\":\"user\",\"content\":\"\(bigContent)\"}".utf8)

        let model = try ollamaModel(contextWindow: 262_144, maxResponse: 8_192)
        let builder = LLMRequestBuilder(
            provider: LLMProvider(model: model),
            apiKey: "test-key",
            messages: [LLM.Message(role: .system, content: "S"),
                       LLM.Message(role: .user, content: "hi")],
            functions: [],
            stream: false,
            hostedTools: HostedTools(),
            previousResponseID: nil,
            shouldThink: nil,
            reasoningEffort: nil,
            serviceTier: nil,
            trailingVolatileText: nil,
            frozenHistoryElements: frozen)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: try builder.body()) as? [String: Any])
        let numCtx = try XCTUnwrap((json["options"] as? [String: Any])?["num_ctx"] as? Int)

        let frozenTokens = AIMetadata.instance.tokens(in: String(decoding: frozen, as: UTF8.self))
        XCTAssertGreaterThan(numCtx, frozenTokens,
                             "num_ctx (\(numCtx)) does not cover the spliced frozen history (~\(frozenTokens) tokens); Ollama will truncate it")
    }

    // A blank/0 context-window field (the manual editor writes 0 for an empty
    // field) must not make num_ctx 0 and throw requestTooLarge on every turn.
    func test_contextWindowZero_fallsBackToUsableFloor() throws {
        let json = try body(shouldThink: nil, contextWindow: 0, maxResponse: 8_192)
        let numCtx = try XCTUnwrap((json["options"] as? [String: Any])?["num_ctx"] as? Int)
        XCTAssertGreaterThanOrEqual(numCtx, 4_096,
                                    "a 0/blank context window must fall back to a usable floor, was \(numCtx)")
    }

    // MARK: - options.num_predict

    func test_emitsNumPredict() throws {
        let json = try body(shouldThink: nil)
        let numPredict = try options(json)["num_predict"] as? Int
        XCTAssertNotNil(numPredict, "options.num_predict must bound the response length")
        XCTAssertGreaterThan(numPredict ?? 0, 0)
    }

    // MARK: - keep_alive

    func test_emitsKeepAlive() throws {
        let json = try body(shouldThink: nil)
        let keepAlive = json["keep_alive"]
        XCTAssertNotNil(keepAlive,
                        "keep_alive must be sent to keep the model resident and avoid cold-reload latency")
    }

    // keep_alive on the wire must reflect the configured advanced setting.
    func test_keepAlive_reflectsSetting() throws {
        let json = try body(shouldThink: nil)
        XCTAssertEqual(json["keep_alive"] as? String,
                       iTermAdvancedSettingsModel.ollamaKeepAlive(),
                       "keep_alive must carry the configured value")
    }

    // MARK: - native tool round-trip

    // Ollama's /api/chat honors a tool RESULT only as
    // {"role":"tool","tool_name":...}; the legacy OpenAI {"role":"function",
    // "name":...} shape is silently ignored, so the model never sees the tool
    // output. (Verified live: legacy -> model confabulates a different answer;
    // native -> model echoes the real value.)
    func test_toolResult_serializesAsNativeToolRole() throws {
        let messages = [
            LLM.Message(role: .user, content: "get a word"),
            LLM.Message(role: .assistant,
                        body: .functionCall(.init(name: "get_random_word", arguments: "{}"), id: nil)),
            // name + content builds a .functionOutput body.
            LLM.Message(role: .user, content: "zzq-42", name: "get_random_word"),
        ]
        let json = try body(shouldThink: nil, messages: messages)
        let msgs = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let toolMsg = try XCTUnwrap(msgs.last)
        XCTAssertEqual(toolMsg["role"] as? String, "tool",
                       "tool result must use role:tool; body=\(toolMsg)")
        XCTAssertEqual(toolMsg["tool_name"] as? String, "get_random_word")
        XCTAssertEqual(toolMsg["content"] as? String, "zzq-42")
        XCTAssertNil(toolMsg["name"],
                     "must not emit the legacy function `name` field Ollama ignores")
    }

    // The assistant tool-call turn must round-trip as native tool_calls (no id;
    // Ollama returns tool_calls without ids), not the legacy function_call field.
    func test_toolCall_assistantTurn_usesNativeToolCalls() throws {
        let messages = [
            LLM.Message(role: .user, content: "get weather"),
            LLM.Message(role: .assistant,
                        body: .functionCall(.init(name: "get_weather", arguments: "{\"city\":\"Paris\"}"), id: nil)),
        ]
        let json = try body(shouldThink: nil, messages: messages)
        let msgs = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let assistant = try XCTUnwrap(msgs.last)
        let toolCalls = try XCTUnwrap(assistant["tool_calls"] as? [[String: Any]],
                                      "assistant tool call must serialize as tool_calls; body=\(assistant)")
        XCTAssertNil(assistant["function_call"],
                     "native Ollama uses tool_calls, not the legacy function_call field")
        let function = try XCTUnwrap(toolCalls.first?["function"] as? [String: Any])
        // arguments must be a JSON OBJECT, not a JSON-in-a-string. Ollama 400s on
        // a string ("Value looks like object, but can't find closing '}'").
        let arguments = function["arguments"]
        XCTAssertTrue(arguments is [String: Any],
                      "arguments must be an object, not a string; got \(String(describing: arguments))")
        XCTAssertEqual((arguments as? [String: Any])?["city"] as? String, "Paris")
    }

    // Ollama returns tool-call arguments as typed JSON (numbers/bools/objects),
    // e.g. {"a":4,"b":5}. Decoding them as [String: String] crashes the whole
    // response. The parser must accept the full JSON value space.
    func test_response_toolCallWithTypedArguments_decodes() throws {
        let wire = """
        {"model":"m","message":{"role":"assistant","content":"","tool_calls":\
        [{"function":{"name":"add","arguments":{"a":4,"b":5}}}]},"done":true}
        """
        var parser = LlamaResponseParser()
        let response = try parser.parse(data: Data(wire.utf8))
        let call: LLM.FunctionCall? = response?.choiceMessages.compactMap {
            if case .functionCall(let c, _) = $0.body { return c }
            return nil
        }.first
        let arguments = try XCTUnwrap(call?.arguments, "no function call decoded")
        // Re-encoded arguments must preserve the numeric values.
        XCTAssertTrue(arguments.contains("\"a\"") && arguments.contains("4"),
                      "typed argument a=4 was lost: \(arguments)")
        XCTAssertTrue(arguments.contains("\"b\"") && arguments.contains("5"),
                      "typed argument b=5 was lost: \(arguments)")
    }

    // MARK: - image token estimate (num_ctx sizing)

    // A byte-heavy image whose base64 is large but whose pixel area is modest.
    private func noisyPNG(_ dim: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: dim, pixelsHigh: dim,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        if let ptr = rep.bitmapData {
            let count = rep.bytesPerRow * dim
            // Deterministic pseudo-noise so PNG can't compress it away (keeps the
            // base64 large), no RNG.
            for i in 0..<count { ptr[i] = UInt8((i &* 2654435761) & 0xff) }
        }
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    // The per-image estimate must come from pixel area, capped, and must NOT
    // scale with the (far larger) base64 length the way the old path did.
    func test_imageTokenEstimate_boundedByPixelArea_notBase64Length() throws {
        let png = noisyPNG(1_500)
        let dataURL = "data:image/png;base64,\(png.base64EncodedString())"
        let estimate = LlamaBodyRequestBuilder.imageTokenEstimate(dataURL: dataURL)
        XCTAssertLessThanOrEqual(estimate, LlamaBodyRequestBuilder.imageTokenCap)
        XCTAssertGreaterThanOrEqual(estimate, LlamaBodyRequestBuilder.imageTokenFloor)
        let base64Tokens = dataURL.utf8.count / 2
        XCTAssertLessThan(estimate, base64Tokens / 10,
                          "estimate still scales with base64 length (\(estimate) vs \(base64Tokens))")
    }

    // A large-BYTE image must not be charged its base64 length, which would blow
    // past the window and throw requestTooLarge on a valid vision request.
    func test_largeImage_doesNotInflateNumCtxOrThrow() throws {
        let png = noisyPNG(800)
        let attachment = LLM.Message.Attachment(
            inline: true, id: "big",
            type: .file(.init(name: "big.png", content: png, mimeType: "image/png", localPath: nil)))
        let messages = [LLM.Message(responseID: nil, role: .user,
                                    body: .multipart([.text("Describe this."), .attachment(attachment)]))]
        let json = try body(shouldThink: nil, contextWindow: 262_144, messages: messages)
        let numCtx = try XCTUnwrap((json["options"] as? [String: Any])?["num_ctx"] as? Int)
        XCTAssertLessThan(numCtx, 32_768,
                          "num_ctx inflated as if charging base64 length: \(numCtx)")
    }

    // Frozen blob-replay history for a vision round carries the image inline as
    // native images[] base64. Sizing that by byte length (~100x its token cost)
    // throws requestTooLarge on the next turn of a vision chat; the frozen path
    // must charge images by pixel area like the live path.
    func test_numCtx_frozenVisionHistory_chargedByPixelArea() throws {
        let png = noisyPNG(800)
        let frozen = Data("{\"role\":\"user\",\"content\":\"look\",\"images\":[\"\(png.base64EncodedString())\"]}".utf8)
        let model = try ollamaModel(contextWindow: 262_144, maxResponse: 8_192)
        let builder = LLMRequestBuilder(
            provider: LLMProvider(model: model), apiKey: "k",
            messages: [LLM.Message(role: .system, content: "S"),
                       LLM.Message(role: .user, content: "hi")],
            functions: [], stream: false, hostedTools: HostedTools(),
            previousResponseID: nil, shouldThink: nil, reasoningEffort: nil,
            serviceTier: nil, trailingVolatileText: nil, frozenHistoryElements: frozen)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: try builder.body()) as? [String: Any])
        let numCtx = try XCTUnwrap((json["options"] as? [String: Any])?["num_ctx"] as? Int)
        XCTAssertLessThan(numCtx, 32_768,
                          "frozen image sized by base64 length inflated num_ctx: \(numCtx)")
    }

    // A zero-argument tool call may omit the arguments key entirely; a required
    // key would make JSONDecoder throw and drop the whole assistant turn.
    func test_response_toolCallWithoutArguments_decodes() throws {
        let wire = """
        {"model":"m","message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"now"}}]},"done":true}
        """
        var parser = LlamaResponseParser()
        let response = try parser.parse(data: Data(wire.utf8))
        let first = try XCTUnwrap(response?.choiceMessages.first)
        XCTAssertNotNil(first.function_call, "an arguments-less tool call must still dispatch")
    }

    // Non-image binaries can't reach the native Ollama builder, so the
    // estimatedTokens default branch never over-counts them (see the invariant
    // comment there). This pins that gate.
    func test_visionGate_rejectsNonImageBinariesForOllama() throws {
        var model = try ollamaModel()
        model.features = [.streaming, .vision]
        let provider = LLMProvider(model: model)
        XCTAssertFalse(provider.accepts(mimeType: "application/pdf"), "native Ollama has no PDF path")
        XCTAssertFalse(provider.accepts(mimeType: "audio/wav"), "native Ollama has no audio path")
    }

    // A valid image whose base64 has embedded whitespace (MIME line wrapping)
    // must still decode to real dimensions, not silently floor and undersize.
    func test_imageTokenEstimate_toleratesWhitespaceInBase64() throws {
        let raw = noisyPNG(600).base64EncodedString()
        var chunked = ""
        var i = raw.startIndex
        while i < raw.endIndex {
            let end = raw.index(i, offsetBy: 76, limitedBy: raw.endIndex) ?? raw.endIndex
            chunked += raw[i..<end] + "\n"
            i = end
        }
        let estimate = LlamaBodyRequestBuilder.imageTokenEstimate(dataURL: "data:image/png;base64,\(chunked)")
        XCTAssertGreaterThan(estimate, LlamaBodyRequestBuilder.imageTokenFloor,
                             "whitespace in base64 defeated pixel-size decoding (fell back to the floor)")
    }

    // MARK: - .llama parser is native-only (finding #5 validity)

    // Proves the .llama type was never functional against an OpenAI-compatible
    // endpoint: its parser only decodes Ollama's native {message,done} shape, so
    // a compat {choices:[...]} response fails. Hence there is no previously
    // working manual .llama + /v1 config for the native-body change to break.
    func test_llamaResponseParser_rejectsOpenAICompatShape() throws {
        let openAIShape = Data("""
        {"choices":[{"message":{"role":"assistant","content":"hi"}}],"model":"m"}
        """.utf8)
        var parser = LlamaResponseParser()
        XCTAssertThrowsError(try parser.parse(data: openAIShape),
                             ".llama parser must reject the OpenAI-compatible response shape")
    }

    // MARK: - vision (native images[])

    // An image attachment must serialize as Ollama's native message.images array
    // of raw base64, with the prompt text as `content` and NO OpenAI image_url
    // block (which /api/chat does not accept).
    func test_imageAttachment_serializesAsNativeImagesArray() throws {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])  // PNG-ish bytes
        let attachment = LLM.Message.Attachment(
            inline: true, id: "img",
            type: .file(.init(name: "x.png", content: bytes, mimeType: "image/png", localPath: nil)))
        let messages = [LLM.Message(responseID: nil, role: .user,
                                    body: .multipart([.text("What is this?"), .attachment(attachment)]))]
        let json = try body(shouldThink: nil, messages: messages)
        let msgs = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let user = try XCTUnwrap(msgs.last)
        let images = try XCTUnwrap(user["images"] as? [String],
                                   "native Ollama vision message must carry images[]; got \(user)")
        XCTAssertEqual(images.first, bytes.base64EncodedString(),
                       "images[] must be raw base64, not a data: URL")
        XCTAssertEqual(user["content"] as? String, "What is this?")
        let wholeBody = String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)
        XCTAssertFalse(wholeBody.contains("image_url"),
                       "must not emit the OpenAI image_url block on the native path")
    }

    // Image attachments are gated on the model's Vision capability, since a local
    // runner's capability can't be inferred from the host.
    func test_visionGate_onlyAcceptsImagesWhenVisionEnabled() throws {
        var noVision = try ollamaModel()
        noVision.features = [.streaming]
        XCTAssertFalse(LLMProvider(model: noVision).accepts(mimeType: "image/png"),
                       "a non-vision Ollama model must refuse images")

        var vision = try ollamaModel()
        vision.features = [.streaming, .vision]
        XCTAssertTrue(LLMProvider(model: vision).accepts(mimeType: "image/png"),
                      "a vision Ollama model must accept images")
    }

    // MARK: - non-streaming thinking (answer/tool must survive)

    // parseNonStreamingResponse consumes only choiceMessages.first, so on the
    // non-streaming path a thinking response must put the ANSWER first (with
    // reasoning folded in as a scalar), not a leading reasoning attachment that
    // would deliver an empty answer.
    func test_nonStreamingResponse_withThinking_keepsAnswerAndReasoning() throws {
        let wire = """
        {"model":"m","message":{"role":"assistant","content":"The answer is 42.",\
        "thinking":"let me reason about it"},"done":true}
        """
        var parser = LlamaResponseParser()
        let response = try parser.parse(data: Data(wire.utf8))
        let first = try XCTUnwrap(response?.choiceMessages.first)
        XCTAssertEqual(first.trimmedString, "The answer is 42.",
                       "non-streaming .first must carry the answer, not an empty reasoning message")
        XCTAssertEqual(first.reasoningContent, "let me reason about it",
                       "reasoning must be folded onto the answer message as a scalar")
    }

    // A tool call under thinking on the non-streaming path must be the FIRST
    // message so parseNonStreamingResponse dispatches it (the agentic loop).
    func test_nonStreamingResponse_withThinking_dispatchesToolCall() throws {
        let wire = """
        {"model":"m","message":{"role":"assistant","content":"","thinking":"reasoning",\
        "tool_calls":[{"function":{"name":"add","arguments":{"a":1,"b":2}}}]},"done":true}
        """
        var parser = LlamaResponseParser()
        let response = try parser.parse(data: Data(wire.utf8))
        let first = try XCTUnwrap(response?.choiceMessages.first)
        XCTAssertNotNil(first.function_call,
                        "the tool call must be .first so non-streaming dispatch fires it")
    }

    // When a non-streaming reply carries BOTH preamble text and a tool call, the
    // text must not be dropped: emit a multipart body so the tool is dispatchable
    // and the preamble survives (matching the modern/DeepSeek shape).
    func test_nonStreamingResponse_preambleWithToolCall_keepsBoth() throws {
        let wire = """
        {"model":"m","message":{"role":"assistant","content":"Let me look that up.",\
        "tool_calls":[{"function":{"name":"get_weather","arguments":{"city":"Paris"}}}]},"done":true}
        """
        var parser = LlamaResponseParser()
        let response = try parser.parse(data: Data(wire.utf8))
        let first = try XCTUnwrap(response?.choiceMessages.first)
        XCTAssertNotNil(first.function_call, "the tool call must remain dispatchable")
        XCTAssertTrue((first.trimmedString ?? "").contains("Let me look that up"),
                      "the preamble text was dropped; got: \(String(describing: first.trimmedString))")
    }

    // When a thinking model puts its whole answer in `thinking` and leaves
    // content empty (small models do this), the non-streaming path must not
    // deliver a blank visible reply: surface the reasoning as the answer.
    func test_nonStreamingResponse_thinkingOnlyEmptyContent_surfacesReasoning() throws {
        let wire = """
        {"model":"m","message":{"role":"assistant","content":"","thinking":"The answer is 42."},"done":true}
        """
        var parser = LlamaResponseParser()
        let response = try parser.parse(data: Data(wire.utf8))
        let first = try XCTUnwrap(response?.choiceMessages.first)
        XCTAssertFalse((first.trimmedString ?? "").isEmpty,
                       "a thinking-only reply delivered an empty visible answer")
        XCTAssertTrue((first.trimmedString ?? "").contains("42"))
    }

    // Streaming must still surface reasoning as its own message for live display.
    func test_streamingResponse_withThinking_emitsReasoningMessage() throws {
        let wire = """
        {"model":"m","message":{"role":"assistant","content":"","thinking":"partial"},"done":false}
        """
        var parser = LlamaStreamingResponseParser()
        let response = try parser.parse(data: Data(wire.utf8))
        let msgs = try XCTUnwrap(response?.choiceMessages)
        XCTAssertTrue(msgs.contains { $0.reasoningContent == "partial" },
                      "streaming must deliver reasoning as a delta message for live rendering")
    }

    // MARK: - prompt that does not fit the model window

    // When the prompt approaches/exceeds the model's context window, the old code
    // silently clamped num_predict to 1 (a one-token/empty reply, prompt
    // truncated, no error). It must surface requestTooLarge instead.
    func test_promptExceedingContextWindow_throwsInsteadOfCollapsing() throws {
        // ~10k-token prompt against an 8192 window, but under the 128k AI token
        // limit so the existing numPredict<2 guard does not fire.
        let bigPrompt = String(repeating: "word word word word word ", count: 2_000)
        let model = try ollamaModel(contextWindow: 8_192, maxResponse: 8_192)
        let builder = LLMRequestBuilder(
            provider: LLMProvider(model: model),
            apiKey: "test-key",
            messages: [LLM.Message(role: .system, content: "S"),
                       LLM.Message(role: .user, content: bigPrompt)],
            functions: [],
            stream: false,
            hostedTools: HostedTools(),
            previousResponseID: nil,
            shouldThink: nil,
            reasoningEffort: nil,
            serviceTier: nil,
            trailingVolatileText: nil)
        XCTAssertThrowsError(try builder.body(),
                             "a prompt that leaves no room for a response must throw, not emit num_predict:1") { error in
            XCTAssertEqual((error as? AIError)?.type, .requestTooLarge,
                           "expected requestTooLarge, got \(error)")
        }
    }

    // MARK: - blob-replay compatibility

    // The messages array must keep collapsing a single text part to a plain
    // string. ChatBlobWireEncoder.case .llama reuses joinText and stores the
    // same bytes; if the builder emitted array content here, a replayed blob
    // would not match. Guards the wire format the blob system depends on.
    func test_singleTextMessage_contentIsString() throws {
        let json = try body(shouldThink: nil)
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let user = try XCTUnwrap(messages.last)
        XCTAssertTrue(user["content"] is String,
                      "single-text user message content must serialize as a string, was \(String(describing: user["content"]))")
    }
}
