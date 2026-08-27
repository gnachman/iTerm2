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
