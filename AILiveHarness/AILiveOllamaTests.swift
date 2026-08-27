//
//  AILiveOllamaTests.swift
//  iTerm2 AI live harness
//
//  End-to-end tests for the native Ollama /api/chat dialect (the .llama API
//  type) against a REAL local Ollama server. These exercise the whole stack
//  the unit tests can't: the request the builder emits, the NDJSON the server
//  streams back, and how AITermController assembles it.
//
//  What they pin (the reasons the native protocol exists, issue #12995):
//    - think:false actually suppresses a thinking-capable model's reasoning,
//      so terminal Q&A is fast instead of spending a minute thinking.
//    - think:true actually produces reasoning.
//    - options.num_ctx is sent and sized to the request, so a long prompt is
//      not silently truncated at Ollama's ~4096 default (the invisible bug).
//    - native tool calls round-trip.
//
//  Gating: these run only when LLAMA_API_KEY is set (any non-empty value; Ollama
//  needs no real key) AND a local Ollama server is reachable with the test
//  model pulled. Otherwise every method XCTSkips, so a normal sweep with no
//  Ollama is silent. Run them with:
//
//    LLAMA_API_KEY=ollama tools/run_ai_live.sh ollama
//
//  The test model is qwen3.5:4b: small enough to run without swapping, and it
//  advertises thinking + tools + vision so one model covers every dimension.
//  Override by adding an OLLAMA_MODEL entry to the live-harness config if you
//  have a different thinking-capable tag pulled.
//

import XCTest
@testable import iTerm2SharedARC

extension AILiveHarness {

    // MARK: - Gating & model

    private static var ollamaBaseURL: String { "http://127.0.0.1:11434" }

    private func ollamaConfig() -> [String: String]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: AILiveHarness.configFilePath())),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return json
    }

    /// The key that gates the lane, or XCTSkip. Ollama ignores the value; it
    /// only has to be non-empty to satisfy the driver's Registration.
    private func ollamaKeyOrSkip() throws -> String {
        guard let value = ollamaConfig()?["LLAMA_API_KEY"], !value.isEmpty else {
            throw XCTSkip("LLAMA_API_KEY not set; skipping native Ollama lane. Run with LLAMA_API_KEY=ollama and a local Ollama server.")
        }
        return value
    }

    private var ollamaModelName: String {
        ollamaConfig()?["OLLAMA_MODEL"] ?? "qwen3.5:4b"
    }

    /// Hit /api/tags to confirm the server is up and the model is pulled;
    /// otherwise skip loudly with the exact remedy. Synchronous by design: the
    /// harness drives everything on one thread.
    private func requireReachableOllama(model: String) throws {
        guard let url = URL(string: "\(AILiveHarness.ollamaBaseURL)/api/tags") else {
            throw XCTSkip("bad Ollama URL")
        }
        let sem = DispatchSemaphore(value: 0)
        var tags: Data?
        var failure: String?
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let error { failure = "\(error)" }
            tags = data
            sem.signal()
        }
        task.resume()
        if sem.wait(timeout: .now() + 5) == .timedOut {
            throw XCTSkip("Ollama server did not respond at \(AILiveHarness.ollamaBaseURL); is `ollama serve` running?")
        }
        if let failure {
            throw XCTSkip("Ollama server unreachable at \(AILiveHarness.ollamaBaseURL): \(failure)")
        }
        guard let tags,
              let body = String(data: tags, encoding: .utf8) else {
            throw XCTSkip("Ollama /api/tags returned no body")
        }
        // The tag list embeds names as "qwen3.5:35b"; a substring match is
        // enough to confirm the model is present without parsing the JSON.
        guard body.contains(model) else {
            throw XCTSkip("Ollama model \(model) not pulled. Run `ollama pull \(model)` (or set ITERM2_AI_LIVE_OLLAMA_MODEL to a thinking-capable tag you have).")
        }
    }

    private func ollamaModel(contextWindow: Int = 262_144,
                             maxResponse: Int = 8_192) throws -> AIMetadata.Model {
        guard var model = AIMetadata.instance.models.first else {
            throw XCTSkip("empty AIMetadata catalog")
        }
        model.name = ollamaModelName
        model.api = .llama
        model.vendor = .llama
        model.url = "\(AILiveHarness.ollamaBaseURL)/api/chat"
        model.contextWindowTokens = contextWindow
        model.maxResponseTokens = maxResponse
        model.features = [.streaming, .functionCalling, .configurableThinking]
        model.fixtureExempt = true
        return model
    }

    private func runOllama(thinking: Bool?,
                           messages: [LLM.Message],
                           streaming: Bool = true,
                           function: AILiveFunctionSpec<EmptyArgs>? = nil,
                           contextWindow: Int = 262_144,
                           timeout: TimeInterval = 240,
                           scenario: String) throws -> AILiveRunResult {
        let apiKey = try ollamaKeyOrSkip()
        let model = try ollamaModel(contextWindow: contextWindow)
        try requireReachableOllama(model: model.name)
        return try AILiveDriver.run(model: model,
                                    apiKey: apiKey,
                                    messages: messages,
                                    streaming: streaming,
                                    thinking: thinking,
                                    function: function,
                                    scenarioTag: scenario,
                                    timeout: timeout,
                                    test: self)
    }

    private func lastRequestBody(_ result: AILiveRunResult) -> [String: Any]? {
        guard let raw = result.capturedRequestBodies.last,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    // MARK: - think

    // think:false must reach the wire AND actually suppress reasoning. This is
    // the fix for the reported hang: a thinking-capable model that would
    // otherwise spend ~a minute reasoning answers directly.
    func test_ollama_thinkFalse_setsThinkFalseAndSuppressesReasoning() throws {
        let messages = [LLM.Message(role: .user, content: "What is 2+2? Reply with just the number.")]
        let result = try runOllama(thinking: false, messages: messages, timeout: 120, scenario: "thinkFalse")

        let body = try XCTUnwrap(lastRequestBody(result), "no request body captured")
        XCTAssertEqual(body["think"] as? Bool, false, "think:false was not sent; body=\(body)")

        XCTAssertTrue(result.finalText.contains("4"),
                      "expected an answer containing 4, got: \(result.finalText)")
        let reasoning = result.deliveredReasoning ?? ""
        XCTAssertTrue(reasoning.isEmpty,
                      "think:false should suppress reasoning, but reasoning was delivered: \(reasoning.prefix(200))")
    }

    // think:true must reach the wire AND actually produce reasoning.
    func test_ollama_thinkTrue_setsThinkTrueAndReasons() throws {
        let messages = [LLM.Message(role: .user,
                                    content: "A farmer has 17 sheep; all but 9 run away. How many are left? Think it through.")]
        let result = try runOllama(thinking: true, messages: messages, timeout: 300, scenario: "thinkTrue")

        let body = try XCTUnwrap(lastRequestBody(result), "no request body captured")
        XCTAssertEqual(body["think"] as? Bool, true, "think:true was not sent; body=\(body)")

        XCTAssertFalse(result.finalText.isEmpty, "expected a non-empty answer")
        let reasoning = result.deliveredReasoning ?? ""
        XCTAssertFalse(reasoning.isEmpty,
                       "think:true should produce reasoning, but none was delivered")
    }

    // MARK: - num_ctx

    // options.num_ctx must be present and sized above Ollama's ~4096 default so
    // a real prompt is not silently truncated.
    func test_ollama_requestSetsNumCtx() throws {
        let messages = [LLM.Message(role: .user, content: "Say hello.")]
        let result = try runOllama(thinking: false, messages: messages, timeout: 120, scenario: "numCtx")

        let body = try XCTUnwrap(lastRequestBody(result))
        let options = try XCTUnwrap(body["options"] as? [String: Any], "options object missing; body=\(body)")
        let numCtx = try XCTUnwrap(options["num_ctx"] as? Int, "num_ctx missing; options=\(options)")
        XCTAssertGreaterThanOrEqual(numCtx, 4_096, "num_ctx should be at least the safe floor")
        XCTAssertNotNil(options["num_predict"] as? Int, "num_predict missing; options=\(options)")
    }

    // The functional proof of num_ctx sizing: bury a needle near the END of a
    // prompt long enough to blow past the 4096 default, then ask for it back.
    // Without correct num_ctx sizing Ollama truncates the prompt tail and the
    // needle is lost, so the model cannot answer.
    func test_ollama_largeContext_needleRetained() throws {
        let needle = "PLUM-42-KIWI"
        // ~40 tokens per line * 250 lines is well past 4096 tokens.
        let filler = (1...250).map { "Line \($0): the quick brown fox jumps over the lazy dog while counting widgets and gizmos." }
            .joined(separator: "\n")
        let prompt = filler + "\n\nIMPORTANT: The secret code is \(needle). Reply with ONLY the secret code, nothing else."
        let messages = [LLM.Message(role: .user, content: prompt)]

        let result = try runOllama(thinking: false, messages: messages, timeout: 240, scenario: "largeContext")

        let body = try XCTUnwrap(lastRequestBody(result))
        let options = try XCTUnwrap(body["options"] as? [String: Any])
        let numCtx = try XCTUnwrap(options["num_ctx"] as? Int)
        XCTAssertGreaterThan(numCtx, 4_096, "a long prompt must raise num_ctx above the 4096 default, was \(numCtx)")

        XCTAssertTrue(result.finalText.contains(needle),
                      "the needle near the prompt tail was lost (prompt likely truncated); answer: \(result.finalText)")
    }

    // MARK: - tool calling

    func test_ollama_toolCall_roundTrip() throws {
        let token = "zzq-ollama-tool-42"
        let decl = ChatGPTFunctionDeclaration(
            name: "get_random_word",
            description: "Returns a randomly chosen made-up word. Call this whenever the user asks for a random word.",
            parameters: JSONSchema(for: EmptyArgs(), descriptions: [:]))
        let spec = AILiveFunctionSpec<EmptyArgs>(
            decl: decl,
            implementation: { _, _, completion in
                try completion(.success(token))
            })
        let messages = [LLM.Message(role: .user,
                                    content: "Call the get_random_word tool to get a word, then include the exact word it returned somewhere in your reply.")]
        // Tool calling on the .llama path is non-streaming (#llama-streaming-functions).
        let result = try runOllama(thinking: false,
                                   messages: messages,
                                   streaming: false,
                                   function: spec,
                                   timeout: 240,
                                   scenario: "toolCall")

        XCTAssertTrue(result.functionsInvoked.contains(decl.name),
                      "tool was never invoked; final text: \(result.finalText)")
        XCTAssertTrue(result.finalText.contains(token),
                      "tool result not echoed; final text: \(result.finalText)")
    }
}
