//
//  ChatBlobWireEncoderTests.swift
//  iTerm2 ModernTests
//
//  Phase 2 of the blob redesign: freezing a completed conversational round into
//  its protocol's request-shape wire form. The headline test is COMPOSITIONALITY
//  — convert(r1 + r2) == convert(r1) + convert(r2) — which is the invariant that
//  makes "stitch the stored rounds" byte-equivalent to "serialize the whole
//  conversation at once." If it ever fails, blob-native replay would diverge from
//  a live request. Also pins that the encoder freezes the cross-message passes
//  once (an assistant preamble + tool call coalesce into ONE wire message, the
//  fix for mutator B) and that a round round-trips through JSON unchanged.
//

import XCTest
@testable import iTerm2SharedARC

final class ChatBlobWireEncoderTests: XCTestCase {

    // MARK: - Round builders (a round = user turn + novel agent/tool items)

    private func userText(_ s: String) -> LLM.Message {
        LLM.Message(role: .user, content: s)
    }
    private func assistantText(_ s: String) -> LLM.Message {
        LLM.Message(role: .assistant, content: s)
    }
    private func assistantToolCall(name: String, args: String, callID: String) -> LLM.Message {
        LLM.Message(role: .assistant,
                    function_call: LLM.FunctionCall(name: name, arguments: args,
                                                    id: callID, thoughtSignature: nil))
    }
    private func toolResult(name: String, output: String, callID: String) -> LLM.Message {
        LLM.Message(role: .function, content: output, name: name,
                    functionCallID: LLM.Message.FunctionCallID(callID: callID, itemID: ""))
    }

    /// A plain round: user asks, agent answers with text only.
    private var plainRound: [LLM.Message] {
        [userText("hi"), assistantText("hello there")]
    }

    /// A tool round: user asks, agent emits a text preamble THEN a tool call (two
    /// separate assistant messages, as the live app commits them), the tool result
    /// comes back, then the agent's final text. This is the shape that exercises
    /// both coalescing (preamble+call) and tool-pair adjacency.
    private var toolRound: [LLM.Message] {
        [userText("weather in Paris?"),
         assistantText("Let me check."),
         assistantToolCall(name: "get_weather", args: "{\"location\":\"Paris\"}", callID: "call_1"),
         toolResult(name: "get_weather", output: "Sunny, 20C", callID: "call_1"),
         assistantText("It's sunny and 20C in Paris.")]
    }

    // MARK: - Compositionality (the load-bearing invariant)

    func test_anthropic_convertMessages_isCompositionalOverRounds() {
        let r1 = plainRound
        let r2 = toolRound
        let perRound = AnthropicRequestBuilder.convertMessages(r1)
                     + AnthropicRequestBuilder.convertMessages(r2)
        let whole = AnthropicRequestBuilder.convertMessages(r1 + r2)
        XCTAssertEqual(perRound, whole,
                       "convert(r1)+convert(r2) must equal convert(r1+r2); otherwise stitching stored rounds would diverge from a live request")
    }

    /// Three rounds, including one that ends on a tool round, to guard the round
    /// boundary (assistant→user) against cross-round coalescing.
    func test_anthropic_compositional_acrossManyRounds() {
        let rounds = [plainRound, toolRound, plainRound, toolRound]
        let perRound = rounds.flatMap { AnthropicRequestBuilder.convertMessages($0) }
        let whole = AnthropicRequestBuilder.convertMessages(rounds.flatMap { $0 })
        XCTAssertEqual(perRound, whole)
    }

    // MARK: - Generic wire-level compositionality (the STORED payloads concatenate)

    /// The invariant stated on the stored bytes, protocol-agnostically: decoding
    /// each round's payload elements and concatenating them equals decoding the
    /// whole conversation's payload. Compared at the JSON level so no per-type
    /// Equatable is needed; apply to every protocol as its encoder lands.
    private func assertWireCompositional(_ api: iTermAIAPI, _ rounds: [[LLM.Message]],
                                         file: StaticString = #filePath, line: UInt = #line) throws {
        func elems(_ round: [LLM.Message]) throws -> [Any] {
            let data = try ChatBlobWireEncoder.encodeRound(round, api: api)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])
        }
        let perRound = try rounds.flatMap { try elems($0) }
        let whole = try elems(rounds.flatMap { $0 })
        XCTAssertEqual(perRound as NSArray, whole as NSArray,
                       "stored round payloads must concatenate to the whole-conversation payload for api \(api.rawValue)",
                       file: file, line: line)
    }

    func test_anthropic_wireLevelCompositional() throws {
        try assertWireCompositional(.anthropic, [plainRound, toolRound, plainRound, toolRound])
    }

    func test_chatCompletions_wireLevelCompositional() throws {
        try assertWireCompositional(.chatCompletions, [plainRound, toolRound, plainRound, toolRound])
    }

    func test_llama_wireLevelCompositional() throws {
        try assertWireCompositional(.llama, [plainRound, toolRound, plainRound, toolRound])
    }

    func test_earlyO1_wireLevelCompositional() throws {
        try assertWireCompositional(.earlyO1, [plainRound, toolRound, plainRound, toolRound])
    }

    // MARK: - Byte-faithfulness to the live builder (the actual requirement)

    private func baseModel() throws -> AIMetadata.Model {
        guard let m = AIMetadata.instance.models.first else {
            throw XCTSkip("empty AIMetadata catalog")
        }
        return m
    }

    /// The top-level key holding the per-message wire array in each protocol's
    /// request body (Gemini uses "contents", the Responses API uses "input").
    private func wireKey(_ api: iTermAIAPI) -> String {
        switch api {
        case .gemini: return "contents"
        case .responses: return "input"
        default: return "messages"
        }
    }

    /// The frozen blob bytes must equal the LIVE builder's per-message array for
    /// the same round (envelope like model/tools/system lives at the top level,
    /// not in this array). The model name is passed to BOTH sides so a
    /// model-dependent conversion (Gemini's thought-signature fallback) matches.
    /// Compared as parsed JSON so key order is irrelevant; only content divergence
    /// fails.
    private func assertByteFaithful(_ api: iTermAIAPI, _ round: [LLM.Message],
                                    hostedTools: HostedTools = HostedTools(),
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        var model = try baseModel()
        model.api = api
        let encData = try ChatBlobWireEncoder.encodeRound(round, api: api, modelName: model.name,
                                                          hostedTools: hostedTools)
        let encElems = try XCTUnwrap(JSONSerialization.jsonObject(with: encData) as? [Any])
        let builder = LLMRequestBuilder(
            provider: LLMProvider(model: model), apiKey: "test-key", messages: round,
            functions: [], stream: false, hostedTools: hostedTools, previousResponseID: nil,
            shouldThink: nil, reasoningEffort: nil, serviceTier: nil, trailingVolatileText: nil)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: builder.body()) as? [String: Any])
        let liveElems = try XCTUnwrap(body[wireKey(api)] as? [Any],
                                      "no \(wireKey(api)) array in \(api.rawValue) body")
        XCTAssertEqual(encElems as NSArray, liveElems as NSArray,
                       "frozen blob bytes must equal the live \(api.rawValue) builder's \(wireKey(api)) array",
                       file: file, line: line)
    }

    /// A round whose user turn carries multi-text-part array content: a text
    /// preamble plus a .code attachment map to two ADJACENT text parts
    /// (CompletionsMessage.init multipart path). This is the shape llama's
    /// joinText collapses; a .string-only fixture never exercises it.
    private var multiTextRound: [LLM.Message] {
        [LLM.Message(role: .user, body: .multipart([
            .text("Please review this:"),
            .attachment(LLM.Message.Attachment(inline: false, id: "a1", type: .code("let x = 1")))])),
         assistantText("Looks fine.")]
    }

    func test_llama_byteFaithful_multiTextPart() throws {
        try assertByteFaithful(.llama, multiTextRound)
    }

    func test_chatCompletions_byteFaithful_multiTextPart() throws {
        try assertByteFaithful(.chatCompletions, multiTextRound)
    }

    func test_earlyO1_byteFaithful_multiTextPart() throws {
        try assertByteFaithful(.earlyO1, multiTextRound)
    }

    // A round whose agent turn carries DeepSeek-style reasoning content, which
    // DeepSeek requires echoed back on assistant turns (reasoning_content).
    private var reasoningRound: [LLM.Message] {
        [userText("weather in Paris?"),
         LLM.Message(role: .assistant, content: "It's sunny and 20C.",
                     reasoningContent: "The user asked for current weather; I'll answer directly.")]
    }

    func test_deepSeek_wireLevelCompositional() throws {
        try assertWireCompositional(.deepSeek, [plainRound, toolRound, reasoningRound, toolRound])
    }

    func test_deepSeek_byteFaithful_multiTextPart() throws {
        try assertByteFaithful(.deepSeek, multiTextRound)
    }

    func test_deepSeek_byteFaithful_reasoningRound() throws {
        try assertByteFaithful(.deepSeek, reasoningRound)
    }

    // MARK: - Gemini (coalescing + model-dependent thoughtSignature)

    /// A round whose agent turn emits a tool call carrying a real thoughtSignature
    /// (Gemini 3 requires it echoed back), so byte-faithfulness must preserve it.
    private var geminiSignedToolRound: [LLM.Message] {
        [userText("weather in Paris?"),
         LLM.Message(role: .assistant,
                     function_call: LLM.FunctionCall(name: "get_weather", arguments: "{\"location\":\"Paris\"}",
                                                     id: "call_1", thoughtSignature: "SIG_ABC123")),
         toolResult(name: "get_weather", output: "Sunny, 20C", callID: "call_1"),
         assistantText("It's sunny in Paris.")]
    }

    func test_gemini_wireLevelCompositional() throws {
        try assertWireCompositional(.gemini, [plainRound, geminiSignedToolRound, plainRound])
    }

    func test_gemini_byteFaithful_multiTextPart() throws {
        try assertByteFaithful(.gemini, multiTextRound)
    }

    /// Exercises the coalescing seam (model text + model tool_call merge into one
    /// Content) and thoughtSignature preservation, against the live builder.
    func test_gemini_byteFaithful_signedToolRound() throws {
        try assertByteFaithful(.gemini, geminiSignedToolRound)
    }

    /// The model-dependent bit: on a generation-3 model a signature-less tool call
    /// must have the documented fallback token injected, frozen into the blob
    /// exactly as the live request sent it.
    func test_gemini_injectsThoughtSignatureFallback_onGen3Model() throws {
        let round = [userText("weather?"),
                     assistantToolCall(name: "get_weather", args: "{}", callID: "c1")]
        let data = try ChatBlobWireEncoder.encodeRound(round, api: .gemini, modelName: "gemini-3-flash")
        let contents = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let signatures = contents
            .flatMap { ($0["parts"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["thoughtSignature"] as? String }
        XCTAssertTrue(signatures.contains(GeminiRequestBuilder.missingThoughtSignatureFallback),
                      "a gen-3 model must inject the fallback thoughtSignature on a signature-less call; got \(signatures)")
    }

    /// And on a pre-3 model, no fallback is injected (the call stays signature-less).
    // MARK: - Responses (one message -> many items; reasoning before call)

    /// A round whose tool call carries OpenAI encrypted reasoning items (the
    /// Responses API requires them replayed, ahead of the function call). Exercises
    /// reasoningEntries + the keepItemIDs gate + reasoning-before-call ordering.
    private var responsesReasoningToolRound: [LLM.Message] {
        [userText("weather in Paris?"),
         LLM.Message(role: .assistant,
                     body: .functionCall(LLM.FunctionCall(name: "get_weather",
                                                          arguments: "{\"location\":\"Paris\"}", id: "call_1"),
                                         id: LLM.Message.FunctionCallID(callID: "call_1", itemID: "fc_item_1")),
                     reasoningItems: [LLM.ReasoningItem(id: "rs_1", encryptedContent: "ENC_ABC", summary: nil)]),
         toolResult(name: "get_weather", output: "Sunny, 20C", callID: "call_1"),
         assistantText("It's sunny in Paris.")]
    }

    func test_responses_wireLevelCompositional() throws {
        try assertWireCompositional(.responses, [plainRound, responsesReasoningToolRound, plainRound])
    }

    func test_responses_byteFaithful_multiTextPart() throws {
        try assertByteFaithful(.responses, multiTextRound)
    }

    func test_responses_byteFaithful_reasoningToolRound() throws {
        try assertByteFaithful(.responses, responsesReasoningToolRound)
    }

    /// A round whose user turn attaches an uploaded file by id. The Responses
    /// builder encodes a .fileID subpart DIFFERENTLY depending on code interpreter:
    /// dropped from content when on (it rides the tools envelope), emitted as an
    /// input_file when off. The encoder must be given the live hostedTools so the
    /// frozen content matches; freezing an input_file for a code-interpreter chat
    /// would resurrect content the live request never sent (and can 400).
    private var fileIDRound: [LLM.Message] {
        [LLM.Message(role: .user, body: .multipart([
            .text("Analyze this file:"),
            .attachment(LLM.Message.Attachment(inline: false, id: "att-1",
                                               type: .fileID(id: "file_abc123", name: "data.pdf")))])),
         assistantText("Done.")]
    }

    func test_responses_byteFaithful_fileID_noCodeInterpreter() throws {
        try assertByteFaithful(.responses, fileIDRound, hostedTools: HostedTools())
    }

    func test_responses_byteFaithful_fileID_withCodeInterpreter() throws {
        try assertByteFaithful(.responses, fileIDRound,
                               hostedTools: HostedTools(codeInterpreter: true))
    }

    // MARK: - Attachment matrix (per-vendor MIME handling must be frozen faithfully)

    private func attachmentFileRound(mime: String, bytes: Data) -> [LLM.Message] {
        [LLM.Message(role: .user, body: .multipart([
            .text("Here is a file:"),
            .attachment(LLM.Message.Attachment(
                inline: false, id: "att-1",
                type: .file(.init(name: "f", content: bytes, mimeType: mime, localPath: nil))))])),
         assistantText("Got it.")]
    }

    // A representative spread of MIME classes that hit distinct per-vendor
    // branches: raster images (base64 image block / inline_data / image_url),
    // textual-but-image (svg -> text, not a binary image), documents (pdf),
    // plain/markdown/json text, non-image binary (audio), and unknown binary.
    private static let attachmentMimes: [(String, Data)] = [
        ("image/png", Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0xFF, 0x10])),
        ("image/webp", Data([0x52, 0x49, 0x46, 0x46, 0x00, 0xFF, 0x57, 0x45])),
        ("image/svg+xml", Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><rect/></svg>".utf8)),
        ("application/pdf", Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x00, 0xFF])),
        ("text/plain", Data("hello world".utf8)),
        ("text/markdown", Data("# Title\n\nbody".utf8)),
        ("application/json", Data("{\"k\":1}".utf8)),
        ("application/xml", Data("<r/>".utf8)),
        ("audio/mpeg", Data([0xFF, 0xFB, 0x90, 0x00, 0x11])),
        ("application/octet-stream", Data([0x00, 0x01, 0x02, 0xFF, 0xC3, 0x28])),
    ]

    /// One matrix cell: the frozen blob's per-message array must equal the live
    /// builder's for this vendor + MIME. Non-fatal (records and continues) so one
    /// run surfaces EVERY divergent cell, and each failure names its cell.
    private func checkAttachmentCell(_ api: iTermAIAPI, mime: String, bytes: Data) {
        let round = attachmentFileRound(mime: mime, bytes: bytes)
        do {
            var model = try baseModel()
            model.api = api
            let encData = try ChatBlobWireEncoder.encodeRound(round, api: api, modelName: model.name)
            let enc = try XCTUnwrap(JSONSerialization.jsonObject(with: encData) as? [Any])
            let builder = LLMRequestBuilder(
                provider: LLMProvider(model: model), apiKey: "test-key", messages: round,
                functions: [], stream: false, hostedTools: HostedTools(), previousResponseID: nil,
                shouldThink: nil, reasoningEffort: nil, serviceTier: nil, trailingVolatileText: nil)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: builder.body()) as? [String: Any])
            let live = try XCTUnwrap(body[wireKey(api)] as? [Any], "no \(wireKey(api)) in \(api.rawValue) body")
            XCTAssertEqual(enc as NSArray, live as NSArray,
                           "attachment byte divergence for \(api.rawValue)/\(mime)")
        } catch {
            XCTFail("attachment cell \(api.rawValue)/\(mime) threw: \(error)")
        }
    }

    /// Anthropic is excluded on purpose: its encoder freezes convertMessages
    /// verbatim (the live body's rolling cache marker on the last message is
    /// assembly-time envelope), so a live-body comparison would spuriously differ
    /// and a convertMessages comparison is tautological. Its attachment handling is
    /// the builder's, exercised by the live attachment matrix.
    func test_attachments_byteFaithfulMatrix() {
        let apis: [iTermAIAPI] = [.chatCompletions, .llama, .earlyO1, .deepSeek, .gemini, .responses]
        for api in apis {
            for (mime, bytes) in Self.attachmentMimes {
                checkAttachmentCell(api, mime: mime, bytes: bytes)
            }
        }
    }

    /// The reasoning item must be frozen ahead of the function_tool_call it
    /// produced (the API rejects the reverse), and the call must keep its item id
    /// when replayed with its reasoning.
    func test_responses_reasoningItemPrecedesCall_andKeepsItemID() throws {
        let data = try ChatBlobWireEncoder.encodeRound(responsesReasoningToolRound, api: .responses)
        let items = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let types = items.map { $0["type"] as? String }
        guard let reasoningIdx = types.firstIndex(of: "reasoning"),
              let callIdx = types.firstIndex(of: "function_call") else {
            return XCTFail("expected both a reasoning and a function_call item; got \(types)")
        }
        XCTAssertLessThan(reasoningIdx, callIdx, "reasoning item must precede its function_call")
        // Its item id is kept (paired with the reasoning); call_id is always kept.
        let call = items[callIdx]
        XCTAssertEqual(call["id"] as? String, "fc_item_1")
        XCTAssertEqual(call["call_id"] as? String, "call_1")
    }

    func test_gemini_noFallback_onGen2Model() throws {
        let round = [userText("weather?"),
                     assistantToolCall(name: "get_weather", args: "{}", callID: "c1")]
        let data = try ChatBlobWireEncoder.encodeRound(round, api: .gemini, modelName: "gemini-2.5-flash")
        let contents = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let signatures = contents
            .flatMap { ($0["parts"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["thoughtSignature"] as? String }
        XCTAssertFalse(signatures.contains(GeminiRequestBuilder.missingThoughtSignatureFallback),
                       "a pre-gen-3 model must not inject the fallback token; got \(signatures)")
    }

    /// CompletionsMessage is ENCODE-ONLY (it emits role "tool" for a function
    /// output but its Role can't decode "tool"), so the stored payload is asserted
    /// at the JSON level — which is also how the assembler must stitch it (merge
    /// the JSON arrays; never decode into the typed wire struct).
    func test_chatCompletions_encodeRound_hasExpectedWireShape() throws {
        let payload = try ChatBlobWireEncoder.encodeRound(toolRound, api: .chatCompletions)
        let arr = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [[String: Any]])
        // Pure map, no coalescing: user, assistant(text), assistant(tool_calls),
        // tool(result), assistant(final) -> 5 elements.
        XCTAssertEqual(arr.count, 5)
        XCTAssertEqual(arr.map { $0["role"] as? String },
                       ["user", "assistant", "assistant", "tool", "assistant"])
    }

    // MARK: - The cross-message passes are frozen once, at capture

    /// Mutator B: a text preamble immediately followed by a tool call must become
    /// ONE assistant wire message carrying [text, tool_use], not two consecutive
    /// assistant messages (which Anthropic rejects). Freezing this at capture is
    /// what lets reconstruction skip coalescing entirely.
    func test_anthropic_preambleAndToolCall_coalesceIntoOneAssistantMessage() {
        let wire = AnthropicRequestBuilder.convertMessages(toolRound)
        // Expect: [user, assistant(text+tool_use), user(tool_result), assistant(final)]
        XCTAssertEqual(wire.count, 4, "got roles \(wire.map { $0.role })")
        XCTAssertEqual(wire[0].role, .user)
        XCTAssertEqual(wire[1].role, .assistant)
        XCTAssertEqual(wire[2].role, .user)
        XCTAssertEqual(wire[3].role, .assistant)

        guard case .array(let blocks) = wire[1].content else {
            return XCTFail("coalesced assistant turn must be a content-block array; got \(wire[1].content)")
        }
        // First block is the preamble text, a later block is the tool_use.
        var sawText = false, sawToolUse = false
        for b in blocks {
            if case .text = b { sawText = true }
            if case .toolUse = b { sawToolUse = true }
        }
        XCTAssertTrue(sawText && sawToolUse,
                      "the merged assistant message must contain BOTH the preamble text and the tool_use (mutator B); blocks=\(blocks)")

        // The tool_result must be paired to the tool_use by id (no positional guesswork).
        guard case .array(let resultBlocks) = wire[2].content,
              case .toolResult(let tr) = resultBlocks.first else {
            return XCTFail("third message must be a tool_result block")
        }
        XCTAssertEqual(tr.tool_use_id, "call_1")
    }

    // MARK: - Round-trips through the stored payload

    func test_anthropic_encodeRound_roundTripsToWireMessages() throws {
        let payload = try ChatBlobWireEncoder.encodeRound(toolRound, api: .anthropic)
        let decoded = try JSONDecoder().decode([AnthropicMessage].self, from: payload)
        XCTAssertEqual(decoded, AnthropicRequestBuilder.convertMessages(toolRound),
                       "the stored blob payload must decode to exactly the round's wire messages")
    }

    func test_encodeRound_unsupportedProtocol_throws() {
        // Legacy single-prompt completions has no per-message wire array, so it is
        // (so far) unsupported and must fail loudly, not silently produce an empty
        // or wrong-format payload.
        XCTAssertThrowsError(try ChatBlobWireEncoder.encodeRound(plainRound, api: .completions)) { error in
            guard case ChatBlobWireEncoderError.unsupportedProtocol(.completions) = error else {
                return XCTFail("expected unsupportedProtocol(.completions); got \(error)")
            }
        }
    }
}
