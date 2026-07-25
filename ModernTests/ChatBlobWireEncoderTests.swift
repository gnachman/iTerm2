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

    /// The messages array the LIVE per-vendor builder puts on the wire for
    /// `round` (envelope like model/tools/system lives at the top level, not in
    /// this array). Ground truth for "the bytes the vendor already accepted".
    private func liveMessagesArray(_ round: [LLM.Message], api: iTermAIAPI) throws -> [Any] {
        var model = try baseModel()
        model.api = api
        let builder = LLMRequestBuilder(
            provider: LLMProvider(model: model), apiKey: "test-key", messages: round,
            functions: [], stream: false, hostedTools: HostedTools(), previousResponseID: nil,
            shouldThink: nil, reasoningEffort: nil, serviceTier: nil, trailingVolatileText: nil)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: builder.body()) as? [String: Any])
        return try XCTUnwrap(body["messages"] as? [Any], "no messages array in \(api.rawValue) body")
    }

    private func encoderElements(_ round: [LLM.Message], api: iTermAIAPI) throws -> [Any] {
        let data = try ChatBlobWireEncoder.encodeRound(round, api: api)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])
    }

    /// The frozen blob bytes must equal the live builder's message array. Compared
    /// as parsed JSON so key order is irrelevant; only content divergence fails.
    private func assertByteFaithful(_ api: iTermAIAPI, _ round: [LLM.Message],
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try encoderElements(round, api: api) as NSArray,
                       try liveMessagesArray(round, api: api) as NSArray,
                       "frozen blob bytes must equal the live \(api.rawValue) builder's message array",
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
        // Non-Anthropic encoders are not built yet; they must fail loudly, not
        // silently produce an empty or wrong-format payload.
        XCTAssertThrowsError(try ChatBlobWireEncoder.encodeRound(plainRound, api: .gemini)) { error in
            guard case ChatBlobWireEncoderError.unsupportedProtocol(.gemini) = error else {
                return XCTFail("expected unsupportedProtocol(.gemini); got \(error)")
            }
        }
    }
}
