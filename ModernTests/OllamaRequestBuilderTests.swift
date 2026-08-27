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
