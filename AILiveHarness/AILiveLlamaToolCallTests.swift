//
//  AILiveLlamaToolCallTests.swift
//  iTerm2 AI live harness
//
//  Live regression coverage for the Ollama tool-argument decode defect
//  (issue 13017 / PR #748). LlamaResponse typed
//  tool_calls[].function.arguments as [String: String]. Ollama echoes tool
//  arguments back with the JSON types the tool's own schema declared, so any
//  non-string parameter -- integer, integer|null, boolean|null -- failed the
//  decode of the WHOLE response before the tool call ever reached the
//  dispatcher. The production orchestration tools declare exactly these
//  shapes: get_screen_contents (lines: integer|null), scroll_wheel
//  (lines: integer), send_text (append_newline: boolean|null),
//  register_watch / register_timer (notify_user: boolean|null).
//
//  The offline LlamaToolArgumentTypeTests (ModernTests) feeds hand-written
//  wire bytes to the parser. These live tests close the other half: they
//  exercise a real local Ollama round-trip, so Ollama's own
//  grammar-constrained output -- the very thing that makes null/number
//  unavoidable and unfixable from the chat side -- hits the real parser.
//
//  Why this was invisible before: the smoke/multiTurn/toolCall matrix in
//  AILiveHarness covers only OpenAI, Anthropic, Gemini and DeepSeek; there
//  was no Llama/Ollama lane in the tool-call path at all, and the standard
//  runToolCall uses a parameterless tool (EmptyArgs), so even a Llama lane
//  there would not have carried a non-string argument.
//
//  Gated on LLAMA_API_KEY, like the attachment matrix's llama lane. Ollama
//  needs no real key; any non-empty value enables the lane. Run with a small
//  model against a local Ollama, e.g.:
//
//    LLAMA_API_KEY=ollama LLAMA_MODELS=qwen3.5:4b \
//      tools/run_ai_live.sh llama_toolCall
//
//  LLAMA_MODELS names the local Ollama model to drive (comma-separated; the
//  first non-empty entry wins). It defaults to llama3.3:latest to match the
//  attachment matrix, but that is a 42GB model -- set LLAMA_MODELS to
//  something small.
//

import XCTest
@testable import iTerm2SharedARC

extension AILiveHarness {

    // MARK: - Test methods

    // get_screen_contents shape: lines is integer|null. The tool's own
    // description tells the model to send null for tui/claude-code sessions,
    // so null is the common path, not an edge -- this is the exact field in
    // the field report. Whether the model emits null or a number, the
    // [String:String] decoder chokes and the fixed decoder does not.
    func test_llama_toolCall_nullableInteger() throws {
        try runLlamaTypedToolCall(
            toolName: "get_screen_contents",
            paramName: "lines",
            paramSchema: ["type": ["integer", "null"],
                          "description": "Number of trailing lines to return. Pass null for the default."],
            prompt: "Call the get_screen_contents tool to read the current screen. "
                  + "There is no specific line count to request, so pass lines as null.",
            decode: NullableLinesArgs.self)
    }

    // scroll_wheel shape: lines is a non-nullable integer.
    func test_llama_toolCall_integer() throws {
        try runLlamaTypedToolCall(
            toolName: "scroll_wheel",
            paramName: "lines",
            paramSchema: ["type": "integer",
                          "description": "Number of scroll-wheel notches to send."],
            prompt: "Call the scroll_wheel tool to scroll up by three notches. Pass lines as 3.",
            decode: LinesArgs.self)
    }

    // send_text shape: append_newline is boolean|null. This is the tool that
    // actually drives sessions, so the same defect blocked writes, not only
    // reads: its own description tells the model to pass append_newline=false
    // when sending a standalone control key.
    func test_llama_toolCall_nullableBoolean() throws {
        try runLlamaTypedToolCall(
            toolName: "send_text",
            paramName: "append_newline",
            paramSchema: ["type": ["boolean", "null"],
                          "description": "Whether to append a newline. Pass false for a standalone control key."],
            prompt: "Call the send_text tool to send the single character q as a standalone "
                  + "control key, so pass append_newline as false.",
            decode: AppendNewlineArgs.self)
    }

    // MARK: - Runner

    /// Drive one live Ollama tool call whose schema declares a single
    /// non-string parameter, and assert the response round-trips.
    ///
    /// The regression signal is simply that the tool call decoded and
    /// dispatched at all. Against the [String:String] decoder the whole
    /// LlamaResponse fails to parse the moment a non-string argument arrives,
    /// so `AILiveDriver.run` rethrows and the catch below fires. We do NOT
    /// assert a specific argument value: whether the model emits null or a
    /// number for a nullable field is model-dependent, and both shapes are
    /// exactly what the bug choked on.
    private func runLlamaTypedToolCall<T: Codable>(
        toolName: String,
        paramName: String,
        paramSchema: [String: Any],
        prompt: String,
        decode: T.Type,
        file: StaticString = #file,
        line: UInt = #line) throws {

        let apiKey = try llamaKeyOrSkip()
        let model = try llamaModel()

        let decl = ChatGPTFunctionDeclaration(
            name: toolName,
            description: "Test tool mirroring a production orchestration tool's argument shape.",
            parameters: JSONSchema(rawJSON: [
                "type": "object",
                "properties": [paramName: paramSchema],
                "required": [paramName],
            ]))
        let spec = AILiveFunctionSpec<T>(
            decl: decl,
            implementation: { _, _, completion in
                try completion(.success("done"))
            })
        let messages = [LLM.Message(role: .user, content: prompt)]

        throttle(forVendor: "llama")
        do {
            // Llama sends tools only on the non-streaming path (the streaming
            // request builder drops tools; see AIMetadata #llama-streaming-functions),
            // so tool calls must be exercised with streaming: false.
            let result = try AILiveDriver.run(
                model: model,
                apiKey: apiKey,
                messages: messages,
                streaming: false,
                function: spec,
                scenarioTag: "llamaToolCall.\(toolName)",
                test: self)
            XCTAssertTrue(
                result.functionsInvoked.contains(toolName),
                "[llama/\(model.name)] \(toolName) was never invoked; the typed "
                + "argument \(paramName) failed to decode. final text: \(result.finalText)",
                file: file, line: line)
        } catch {
            XCTFail(
                "[llama/\(model.name)/\(toolName)] tool-argument round-trip failed to "
                + "decode (the [String:String] decoder rejects a non-string \(paramName)): \(error)",
                file: file, line: line)
        }
    }

    // MARK: - Llama model / key resolution

    /// Read the live-harness config file directly. AILiveHarness.loadConfig is
    /// private to its own file, so this extension re-reads it the same way
    /// keyOrSkipForLane does.
    private func llamaLiveConfig() throws -> [String: String] {
        let path = AILiveHarness.configFilePath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw XCTSkip("Live AI harness config missing.")
        }
        return json
    }

    private func llamaKeyOrSkip() throws -> String {
        let key = (try llamaLiveConfig())["LLAMA_API_KEY"] ?? ""
        if key.isEmpty {
            throw XCTSkip("No LLAMA_API_KEY set; skipping llama tool-call tests. "
                          + "Run with LLAMA_API_KEY=ollama LLAMA_MODELS=<small-model> and Ollama running.")
        }
        return key
    }

    /// Synthesize the AIMetadata.Model to drive. Bases it on the catalog's
    /// llama3.3:latest entry (vendor .llama, api .llama, localhost:11434/api/chat,
    /// functionCalling) and overrides the name to the configured local model so
    /// a small model can stand in for the 42GB default.
    private func llamaModel() throws -> AIMetadata.Model {
        guard var template = AIMetadata.instance.models.first(where: { $0.name == "llama3.3:latest" }) else {
            throw XCTSkip("llama3.3:latest template not in AIMetadata; cannot synthesize a llama model.")
        }
        let configured = (try llamaLiveConfig())["LLAMA_MODELS"]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        if let configured {
            template.name = configured
        }
        return template
    }
}

// MARK: - Argument decode types
//
// One per production argument shape. These match the orchestrator's own arg
// structs (Int?, Int, Bool?), which is the whole point: only the decoder in
// between disagreed.

private struct NullableLinesArgs: Codable {
    var lines: Int?
}

private struct LinesArgs: Codable {
    var lines: Int
}

private struct AppendNewlineArgs: Codable {
    var append_newline: Bool?
}
