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
import AppKit
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

    // think:true must reach the wire AND actually produce reasoning. Keep the
    // prompt trivial so the model doesn't spend minutes thinking.
    func test_ollama_thinkTrue_setsThinkTrueAndReasons() throws {
        let messages = [LLM.Message(role: .user, content: "What is 5 + 8? Think briefly.")]
        let result = try runOllama(thinking: true, messages: messages, timeout: 300, scenario: "thinkTrue")

        let body = try XCTUnwrap(lastRequestBody(result), "no request body captured")
        XCTAssertEqual(body["think"] as? Bool, true, "think:true was not sent; body=\(body)")

        let reasoning = result.deliveredReasoning ?? ""
        XCTAssertFalse(reasoning.isEmpty,
                       "think:true should produce reasoning, but none was delivered")
        // Answer may land in content or reasoning; require it somewhere.
        XCTAssertTrue((result.finalText + " " + reasoning).contains("13"),
                      "wrong or missing answer; text=\(result.finalText) reasoning=\(String(reasoning.prefix(160)))")
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

    // The same round-trip while STREAMING: Ollama's native /api/chat streams tool
    // calls together with content (since May 2025), and iTerm2 now sends tools on
    // the streaming path. Proves the streamed tool_call is parsed, executed, and its
    // result echoed back on the next (streamed) turn.
    func test_ollama_toolCall_streaming() throws {
        let token = "zzq-ollama-stream-tool-42"
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
        let result = try runOllama(thinking: false,
                                   messages: messages,
                                   streaming: true,
                                   function: spec,
                                   timeout: 240,
                                   scenario: "toolCallStreaming")

        XCTAssertTrue(result.functionsInvoked.contains(decl.name),
                      "streamed tool was never invoked; final text: \(result.finalText)")
        XCTAssertTrue(result.finalText.contains(token),
                      "streamed tool result not echoed; final text: \(result.finalText)")
    }

    // Generic tool runner (the primary runOllama is pinned to EmptyArgs).
    private func runOllamaTool<T: Codable>(messages: [LLM.Message],
                                           function: AILiveFunctionSpec<T>,
                                           thinking: Bool = false,
                                           timeout: TimeInterval = 240,
                                           scenario: String) throws -> AILiveRunResult {
        let apiKey = try ollamaKeyOrSkip()
        let model = try ollamaModel()
        try requireReachableOllama(model: model.name)
        // These tests exercise the non-streaming tool path; the streaming path is
        // covered by test_ollama_toolCall_streaming.
        return try AILiveDriver.run(model: model,
                                    apiKey: apiKey,
                                    messages: messages,
                                    streaming: false,
                                    thinking: thinking,
                                    function: function,
                                    scenarioTag: scenario,
                                    timeout: timeout,
                                    test: self)
    }

    private struct AddArgs: Codable {
        var a = 0
        var b = 0
    }

    private func addTool(callCount: NSMutableArray) -> AILiveFunctionSpec<AddArgs> {
        let decl = ChatGPTFunctionDeclaration(
            name: "add",
            description: "Adds two integers and returns their sum. Use this for any addition.",
            parameters: JSONSchema(for: AddArgs(),
                                   descriptions: ["a": "First addend.", "b": "Second addend."]))
        return AILiveFunctionSpec<AddArgs>(
            decl: decl,
            implementation: { _, args, completion in
                callCount.add(args.a + args.b)
                try completion(.success("\(args.a + args.b)"))
            })
    }

    // A tool with real arguments: the model must pass 4 and 5, and its final
    // answer must reflect the tool's computed result (proves args round-trip
    // into the tool and the result round-trips back in the native shape).
    func test_ollama_toolCall_withArguments() throws {
        let calls = NSMutableArray()
        let tool = addTool(callCount: calls)
        let messages = [LLM.Message(role: .user,
                                    content: "Use the add tool to compute 4 plus 5, then tell me the result as a number.")]
        let result = try runOllamaTool(messages: messages, function: tool, scenario: "toolArgs")

        XCTAssertTrue(result.functionsInvoked.contains("add"),
                      "add tool was never invoked; final text: \(result.finalText)")
        XCTAssertTrue(calls.contains(9),
                      "the tool did not receive a=4,b=5 (sums seen: \(calls)); arguments did not round-trip")
        XCTAssertTrue(result.finalText.contains("9"),
                      "final answer did not reflect the tool result; final text: \(result.finalText)")
    }

    // Agentic loop: two SEQUENTIAL tool calls, where the second depends on the
    // first's result. Exercises the multi-round native tool round-trip, not just
    // a single call.
    func test_ollama_agentic_twoSequentialToolCalls() throws {
        let calls = NSMutableArray()
        let tool = addTool(callCount: calls)
        let messages = [LLM.Message(role: .user,
                                    content: "First use the add tool to compute 2 plus 3. Then use the add tool again to add 10 to that result. Tell me only the final number.")]
        let result = try runOllamaTool(messages: messages, function: tool, timeout: 300, scenario: "agentic")

        XCTAssertGreaterThanOrEqual(result.functionsInvoked.filter { $0 == "add" }.count, 2,
                                    "expected at least two sequential add calls, saw: \(result.functionsInvoked)")
        XCTAssertTrue(result.finalText.contains("15"),
                      "the two-step computation did not reach 15; final text: \(result.finalText)")
    }

    // Regression for the non-streaming thinking bug: with Think ON, tools force
    // the non-streaming path, and parseNonStreamingResponse consumes only .first.
    // If the reasoning message leads, the tool call is never dispatched and the
    // agentic loop silently breaks. Assert the tool still fires and its result is
    // used, WITH thinking enabled.
    func test_ollama_toolCall_withThinking_nonStreaming() throws {
        let calls = NSMutableArray()
        let tool = addTool(callCount: calls)
        let messages = [LLM.Message(role: .user,
                                    content: "Use the add tool to compute 4 plus 5, then tell me the result as a number.")]
        let result = try runOllamaTool(messages: messages, function: tool,
                                       thinking: true, timeout: 300, scenario: "toolThinking")
        XCTAssertTrue(result.functionsInvoked.contains("add"),
                      "tool never dispatched under thinking (answer/tool dropped by .first); text: \(result.finalText)")
        XCTAssertTrue(calls.contains(9), "add did not receive 4,5 (sums: \(calls))")
        XCTAssertTrue(result.finalText.contains("9"),
                      "final answer lost the tool result under thinking; text: \(result.finalText)")
    }

    // MARK: - dynamic provider discovery

    // The cache refreshes from the real /api/tags and surfaces the installed
    // model (with capabilities) via its change notification.
    func test_ollama_cache_discoversInstalledModel() throws {
        _ = try ollamaKeyOrSkip()
        try requireReachableOllama(model: ollamaModelName)
        let cache = OllamaModelCache()
        let endpoint = "\(AILiveHarness.ollamaBaseURL)/api/chat"
        let exp = expectation(forNotification: OllamaModelCache.didChangeNotification, object: nil)
        cache.refresh(endpoint: endpoint)
        wait(for: [exp], timeout: 20)
        let discovered = cache.models(forEndpoint: endpoint)
        XCTAssertTrue(discovered.contains { $0.name == ollamaModelName },
                      "cache did not discover \(ollamaModelName); got \(discovered.map { $0.name })")
        // qwen3.5:4b advertises all capabilities; confirm they came through.
        if let qwen = discovered.first(where: { $0.name == ollamaModelName }) {
            XCTAssertTrue(qwen.features.contains(.vision))
            XCTAssertTrue(qwen.features.contains(.configurableThinking))
            XCTAssertGreaterThan(qwen.contextWindowTokens, 0)
        }
    }

    // /api/tags does NOT carry per-model capabilities or the real context window
    // on a real server (both come from /api/show), so discovery must enrich each
    // model via /api/show. This drives the real discovery fetch path and asserts
    // the discovered model matches /api/show ground truth. Before the enrichment
    // fix it fails (features stay streaming-only, window falls back to the default);
    // after it, discovery reflects the true capabilities and window.
    func test_ollama_discovery_reflectsApiShowCapabilitiesAndContext() throws {
        _ = try ollamaKeyOrSkip()
        try requireReachableOllama(model: ollamaModelName)

        // Ground truth from /api/show.
        let show = try postOllamaJSON(path: "/api/show", body: ["model": ollamaModelName])
        let realCaps = Set((show["capabilities"] as? [String]) ?? [])
        guard realCaps.contains("vision") || realCaps.contains("thinking") else {
            throw XCTSkip("\(ollamaModelName) advertises no vision/thinking in /api/show; use a richer model")
        }
        let realContext: Int? = {
            guard let info = show["model_info"] as? [String: Any] else { return nil }
            // The key is architecture-prefixed, e.g. "qwen3.context_length".
            for (key, value) in info where key.hasSuffix(".context_length") {
                if let n = value as? Int { return n }
            }
            return nil
        }()

        // Drive the real discovery fetch path (which must consult /api/show). The
        // notification wait pumps the runloop so the async enrichment can land.
        let cache = OllamaModelCache()
        let endpoint = "\(AILiveHarness.ollamaBaseURL)/api/chat"
        let exp = expectation(forNotification: OllamaModelCache.didChangeNotification, object: nil)
        cache.refresh(endpoint: endpoint)
        wait(for: [exp], timeout: 60)
        let discovered = try XCTUnwrap(
            cache.models(forEndpoint: endpoint).first { $0.name == ollamaModelName },
            "discovery did not surface \(ollamaModelName)")

        if realCaps.contains("vision") {
            XCTAssertTrue(discovered.features.contains(.vision),
                          "model is vision-capable per /api/show, but discovery missed it (enrich via /api/show)")
        }
        if realCaps.contains("thinking") {
            XCTAssertTrue(discovered.features.contains(.configurableThinking),
                          "model is thinking-capable per /api/show, but discovery missed it")
        }
        if let realContext, realContext > OllamaModelDiscovery.defaultContextWindow {
            XCTAssertEqual(discovered.contextWindowTokens, realContext,
                           "discovery used the fallback window \(discovered.contextWindowTokens); the real /api/show window is \(realContext)")
        }
    }

    // MARK: - live HTTP helpers (synchronous, matching requireReachableOllama)

    private func syncData(_ request: URLRequest) throws -> Data {
        let sem = DispatchSemaphore(value: 0)
        var out: Data?
        var failure: Error?
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            failure = error
            out = data
            sem.signal()
        }
        task.resume()
        if sem.wait(timeout: .now() + 10) == .timedOut {
            throw AIError("timed out fetching \(request.url?.path ?? "?")")
        }
        if let failure { throw failure }
        guard let out else { throw AIError("no data from \(request.url?.path ?? "?")") }
        return out
    }

    private func postOllamaJSON(path: String, body: [String: Any]) throws -> [String: Any] {
        guard let url = URL(string: "\(AILiveHarness.ollamaBaseURL)\(path)") else {
            throw AIError("bad Ollama URL for \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try syncData(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError("\(path) did not return a JSON object")
        }
        return json
    }

    // MARK: - vision

    private func solidColorPNG(_ color: NSColor, size: Int = 96) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    // Native Ollama vision (message.images[]) against a vision-capable model.
    // A solid red image; the model must identify the color, proving the image
    // reached it in the native shape.
    func test_ollama_vision_describesImage() throws {
        let apiKey = try ollamaKeyOrSkip()
        var model = try ollamaModel()
        model.features = [.streaming, .vision]
        try requireReachableOllama(model: model.name)

        let png = solidColorPNG(.red)
        XCTAssertFalse(png.isEmpty, "failed to render test image")
        let attachment = LLM.Message.Attachment(
            inline: true, id: "red",
            type: .file(.init(name: "red.png", content: png, mimeType: "image/png", localPath: nil)))
        let messages = [LLM.Message(responseID: nil, role: .user,
                                    body: .multipart([
                                        .text("What is the single dominant color in this image? Answer with just the color name."),
                                        .attachment(attachment)]))]
        let result = try AILiveDriver.run(model: model, apiKey: apiKey, messages: messages,
                                          streaming: false,
                                          function: Optional<AILiveFunctionSpec<EmptyArgs>>.none,
                                          scenarioTag: "vision", timeout: 240, test: self)
        XCTAssertTrue(result.finalText.lowercased().contains("red"),
                      "vision model did not identify the red image; got: \(result.finalText)")
    }

    // MARK: - smoke (both transports)

    func test_ollama_smoke_nonStreaming() throws {
        let result = try runOllama(thinking: false,
                                   messages: [LLM.Message(role: .user, content: "Reply with exactly: pong")],
                                   streaming: false, timeout: 120, scenario: "smokeNonStreaming")
        XCTAssertTrue(result.finalText.lowercased().contains("pong"),
                      "expected pong, got: \(result.finalText)")
    }

    func test_ollama_smoke_streaming() throws {
        let result = try runOllama(thinking: false,
                                   messages: [LLM.Message(role: .user, content: "Reply with exactly: pong")],
                                   streaming: true, timeout: 120, scenario: "smokeStreaming")
        XCTAssertTrue(result.finalText.lowercased().contains("pong"),
                      "expected pong, got: \(result.finalText)")
    }

    // Streaming must assemble from multiple NDJSON deltas, not arrive as one
    // blob. Asks for enough tokens that the server emits several chunks.
    func test_ollama_streaming_deliversIncrementalChunks() throws {
        let result = try runOllama(thinking: false,
                                   messages: [LLM.Message(role: .user, content: "List the numbers 1 through 20, separated by commas.")],
                                   streaming: true, timeout: 120, scenario: "streamChunks")
        XCTAssertGreaterThan(result.streamedChunks.count, 1,
                             "streaming delivered \(result.streamedChunks.count) chunk(s); expected incremental deltas")
        XCTAssertTrue(result.finalText.contains("20"), "answer truncated: \(result.finalText)")
    }

    // MARK: - multi-turn

    func test_ollama_multiTurn_nonStreaming() throws {
        try assertMultiTurnCarriesContext(streaming: false, scenario: "multiTurnNonStreaming")
    }

    func test_ollama_multiTurn_streaming() throws {
        try assertMultiTurnCarriesContext(streaming: true, scenario: "multiTurnStreaming")
    }

    private func assertMultiTurnCarriesContext(streaming: Bool, scenario: String) throws {
        let messages = [
            LLM.Message(role: .user, content: "My favorite number is 7. Remember it."),
            LLM.Message(role: .assistant, content: "Got it, your favorite number is 7."),
            LLM.Message(role: .user, content: "What is my favorite number multiplied by 6? Reply with just the number."),
        ]
        let result = try runOllama(thinking: false, messages: messages,
                                   streaming: streaming, timeout: 120, scenario: scenario)
        XCTAssertTrue(result.finalText.contains("42"),
                      "prior-turn context was lost (expected 42); got: \(result.finalText)")
    }

    // A system message must steer behavior.
    func test_ollama_systemMessage_respected() throws {
        let messages = [
            LLM.Message(role: .system, content: "You are a calculator. Reply with only the numeric result, no words."),
            LLM.Message(role: .user, content: "6 times 7"),
        ]
        let result = try runOllama(thinking: false, messages: messages,
                                   streaming: false, timeout: 120, scenario: "system")
        XCTAssertTrue(result.finalText.contains("42"),
                      "system instruction not followed; got: \(result.finalText)")
    }

    // Non-ASCII content must survive serialization and round-trip.
    func test_ollama_unicode_roundTrips() throws {
        let messages = [LLM.Message(role: .user,
                                    content: "Repeat this text back exactly, unchanged: café ☕ 日本語 —")]
        let result = try runOllama(thinking: false, messages: messages,
                                   streaming: false, timeout: 120, scenario: "unicode")
        XCTAssertTrue(result.finalText.contains("café"), "lost accented text: \(result.finalText)")
        XCTAssertTrue(result.finalText.contains("日本語"), "lost CJK text: \(result.finalText)")
    }

    // A longer answer must not be cut off, i.e. num_predict is sized sanely.
    func test_ollama_longOutput_notTruncated() throws {
        let messages = [LLM.Message(role: .user,
                                    content: "Write the numbers 1 to 50, one per line, nothing else.")]
        let result = try runOllama(thinking: false, messages: messages,
                                   streaming: true, timeout: 180, scenario: "longOutput")
        XCTAssertTrue(result.finalText.contains("50"),
                      "long output was truncated before reaching 50; got tail: \(result.finalText.suffix(80))")
    }

    // MARK: - think (both transports + coexistence)

    func test_ollama_thinkFalse_nonStreaming() throws {
        let result = try runOllama(thinking: false,
                                   messages: [LLM.Message(role: .user, content: "What is 2+2? Just the number.")],
                                   streaming: false, timeout: 120, scenario: "thinkFalseNonStreaming")
        XCTAssertEqual(lastRequestBody(result)?["think"] as? Bool, false)
        XCTAssertTrue(result.finalText.contains("4"), "got: \(result.finalText)")
        XCTAssertTrue((result.deliveredReasoning ?? "").isEmpty, "reasoning leaked with think:false")
    }

    func test_ollama_thinkTrue_nonStreaming_producesReasoning() throws {
        let result = try runOllama(thinking: true,
                                   messages: [LLM.Message(role: .user, content: "Is 91 prime? Think step by step, then answer yes or no.")],
                                   streaming: false, timeout: 300, scenario: "thinkTrueNonStreaming")
        XCTAssertEqual(lastRequestBody(result)?["think"] as? Bool, true)
        XCTAssertFalse((result.deliveredReasoning ?? "").isEmpty, "think:true produced no reasoning")
        // The answer must survive the non-streaming path (it is 91 = 7*13, not
        // prime -> "no"). Accept it in content or reasoning, but it must appear:
        // the old leading-reasoning-message bug delivered an empty answer here.
        let combined = (result.finalText + " " + (result.deliveredReasoning ?? "")).lowercased()
        XCTAssertTrue(combined.contains("no") || combined.contains("not prime"),
                      "answer lost on the non-streaming thinking path; text=\(result.finalText)")
    }

    // The streaming think path must deliver reasoning AND reach the right answer.
    // Whether the answer lands in the visible content or inside the reasoning is
    // the model's call (a small model often keeps a trivial answer in its
    // reasoning and leaves content empty), so accept it in either place; the
    // point is that streamed thinking works end to end and the computation is
    // correct.
    func test_ollama_thinkTrue_streaming_reasonsAndAnswers() throws {
        let result = try runOllama(thinking: true,
                                   messages: [LLM.Message(role: .user, content: "What is 12 + 30? Think briefly, then give the number.")],
                                   streaming: true, timeout: 300, scenario: "thinkStreaming")
        XCTAssertFalse((result.deliveredReasoning ?? "").isEmpty, "no reasoning delivered on the streaming think path")
        let combined = result.finalText + " " + (result.deliveredReasoning ?? "")
        XCTAssertTrue(combined.contains("42"),
                      "wrong or missing answer; text=\(result.finalText) reasoning=\(String((result.deliveredReasoning ?? "").prefix(200)))")
    }

    // A thinking turn's reasoning must not break the NEXT turn (Ollama, unlike
    // DeepSeek, does not require thinking echoed back; a prior assistant turn
    // must still round-trip cleanly).
    func test_ollama_multiTurn_withThinking() throws {
        let messages = [
            LLM.Message(role: .user, content: "My favorite number is 7."),
            LLM.Message(role: .assistant, content: "Understood."),
            LLM.Message(role: .user, content: "Multiply my favorite number by 6 and give just the number."),
        ]
        let result = try runOllama(thinking: true, messages: messages,
                                   streaming: false, timeout: 300, scenario: "multiTurnThinking")
        // With thinking on, a small model may surface the answer in its reasoning
        // rather than the final content. Either is fine here: the point is that the
        // prior-turn context survived and the reasoning round-trip didn't break the
        // turn (no 400, a real response came back with the right computation).
        let combined = result.finalText + " " + (result.deliveredReasoning ?? "")
        XCTAssertTrue(combined.contains("42"),
                      "thinking multi-turn lost context or broke; text=\(result.finalText) reasoning=\(String((result.deliveredReasoning ?? "").prefix(200)))")
    }
}
