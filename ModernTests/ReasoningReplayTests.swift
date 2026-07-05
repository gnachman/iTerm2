//
//  ReasoningReplayTests.swift
//  iTerm2 ModernTests
//
//  OpenAI Responses reasoning items must survive the whole loop: captured
//  from responses (streaming and not), persisted with the chat message that
//  carries the function call, and replayed (in order, before their
//  function_call items) when the conversation is re-sent. Requests run
//  stateless (store:false + include reasoning.encrypted_content) so the
//  persisted state is the only state.
//

import XCTest
@testable import iTerm2SharedARC

final class ReasoningReplayTests: XCTestCase {
    private func model(named name: String) throws -> AIMetadata.Model {
        try XCTUnwrap(AIMetadata.instance.models.first { $0.name == name },
                      "model \(name) missing from AIMetadata")
    }

    private let blob = "gAAAAAB-encrypted-reasoning-payload"

    private func reasoningItem(id: String = "rs_1") -> LLM.ReasoningItem {
        LLM.ReasoningItem(id: id, encryptedContent: blob, summary: ["thought about it"])
    }

    private func functionCallMessage(reasoningItems: [LLM.ReasoningItem]?) -> LLM.Message {
        let call = LLM.FunctionCall(name: "lookup", arguments: "{}")
        let id = LLM.Message.FunctionCallID(callID: "call_42", itemID: "fc_1")
        return LLM.Message(responseID: nil,
                           role: .assistant,
                           body: .functionCall(call, id: id),
                           reasoningItems: reasoningItems)
    }

    // MARK: - Codable persistence

    func testLLMMessage_reasoningItems_roundTrip() throws {
        let original = functionCallMessage(reasoningItems: [reasoningItem()])
        let decoded = try JSONDecoder().decode(LLM.Message.self,
                                               from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.reasoningItems, [reasoningItem()])
    }

    func testLLMMessage_legacyPayloadWithoutReasoningItems_decodesNil() throws {
        let legacy = functionCallMessage(reasoningItems: nil)
        let data = try JSONEncoder().encode(legacy)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("reasoningItems"),
                       "nil reasoningItems must be omitted, not encoded as null")
        let decoded = try JSONDecoder().decode(LLM.Message.self, from: data)
        XCTAssertNil(decoded.reasoningItems)
    }

    /// The persistence ride: a chat Message's .remoteCommandRequest carries
    /// the LLM.Message verbatim inside the content JSON, so reasoning items
    /// attached to it must survive the on-disk round trip with no schema
    /// migration.
    func testChatMessage_externalRemoteCommandRequest_persistsReasoningItems() throws {
        let payload = RemoteCommandPayload.external(ExternalRemoteCommand(
            llmMessage: functionCallMessage(reasoningItems: [reasoningItem()]),
            name: "lookup",
            argsJSON: "{}",
            markdownDescription: "Lookup"))
        let message = Message(chatID: "c",
                              author: .agent,
                              content: .remoteCommandRequest(payload, safe: nil),
                              sentDate: Date(),
                              uniqueID: UUID())
        let decoded = try JSONDecoder().decode(Message.self,
                                               from: JSONEncoder().encode(message))
        guard case .remoteCommandRequest(let decodedPayload, _) = decoded.content else {
            XCTFail("content did not round-trip as remoteCommandRequest")
            return
        }
        XCTAssertEqual(decodedPayload.llmMessage.reasoningItems, [reasoningItem()])
    }

    // MARK: - Request building (stateless replay)

    private func inputItems(messages: [LLM.Message],
                            previousResponseID: String? = nil) throws -> (json: [String: Any], items: [[String: Any]]) {
        let body = try ResponsesBodyRequestBuilder(
            messages: messages,
            provider: LLMProvider(model: try model(named: "gpt-5")),
            functions: [],
            stream: false,
            hostedTools: HostedTools(),
            previousResponseID: previousResponseID,
            shouldThink: nil).body()
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let items = try XCTUnwrap(json["input"] as? [[String: Any]])
        return (json, items)
    }

    func testResponsesRequest_alwaysRequestsEncryptedReasoning() throws {
        // Hybrid design (probe-verified: store:true returns the blobs too):
        // server-side state keeps serving live turns, but EVERY request asks
        // for encrypted reasoning so the blobs can be persisted for replay
        // after a reload or expiry. store is left at the server default
        // (true); it must never be sent as false.
        let (json, _) = try inputItems(messages: [LLM.Message(role: .user, content: "hi")])
        let include = json["include"] as? [String] ?? []
        XCTAssertTrue(include.contains("reasoning.encrypted_content"),
                      "encrypted reasoning must be requested so it can be persisted")
        XCTAssertNotEqual(json["store"] as? Bool, false,
                          "store:false would forfeit the previous_response_id fast path")
    }

    func testResponsesRequest_keepsPreviousResponseIDFastPath() throws {
        // With a usable previousResponseID the existing behavior stands:
        // reference the server state and send only the newest item.
        let user = LLM.Message(role: .user, content: "hi")
        let assistant = LLM.Message(responseID: "resp_1", role: .assistant, body: .text("hello"))
        let followUp = LLM.Message(role: .user, content: "again")
        let (json, items) = try inputItems(messages: [user, assistant, followUp],
                                           previousResponseID: "resp_1")
        XCTAssertEqual(json["previous_response_id"] as? String, "resp_1")
        XCTAssertEqual(items.count, 1, "the fast path sends only the newest item")
    }

    func testResponsesRequest_emitsReasoningItemBeforeItsFunctionCall() throws {
        let user = LLM.Message(role: .user, content: "look it up")
        let (_, items) = try inputItems(messages: [user, functionCallMessage(reasoningItems: [reasoningItem()])])
        guard items.count == 3 else {
            XCTFail("expected [user message, reasoning, function_call], got \(items)")
            return
        }
        XCTAssertEqual(items[1]["type"] as? String, "reasoning")
        XCTAssertEqual(items[1]["id"] as? String, "rs_1")
        XCTAssertEqual(items[1]["encrypted_content"] as? String, blob)
        XCTAssertNotNil(items[1]["summary"],
                        "the API 400s a replayed reasoning item with no summary key")
        XCTAssertEqual(items[2]["type"] as? String, "function_call")
        XCTAssertEqual(items[2]["call_id"] as? String, "call_42")
        XCTAssertEqual(items[2]["id"] as? String, "fc_1",
                       "a call replayed WITH its reasoning keeps its item id")
    }

    /// A turn that had both a text preamble and a tool call collapses into
    /// one multipart assistant message with the reasoning items attached.
    /// The replay order [reasoning, text message, function_call] is the
    /// API's own output order for such a turn and is accepted on re-send
    /// (live-verified); pin that the builder emits exactly that order.
    func testResponsesRequest_multipartTurn_replaysReasoningThenTextThenCall() throws {
        let call = LLM.FunctionCall(name: "lookup", arguments: "{}")
        let id = LLM.Message.FunctionCallID(callID: "call_42", itemID: "fc_1")
        let assistant = LLM.Message(responseID: nil,
                                    role: .assistant,
                                    body: .multipart([
                                        .text("I will look that up."),
                                        .functionCall(call, id: id),
                                    ]),
                                    reasoningItems: [reasoningItem()])
        let user = LLM.Message(role: .user, content: "look it up")
        let (_, items) = try inputItems(messages: [user, assistant])
        guard items.count == 4 else {
            XCTFail("expected [user, reasoning, message, function_call], got \(items)")
            return
        }
        XCTAssertEqual(items[1]["type"] as? String, "reasoning")
        XCTAssertEqual(items[2]["role"] as? String, "assistant")
        XCTAssertEqual(items[2]["content"] as? String, "I will look that up.")
        XCTAssertEqual(items[3]["type"] as? String, "function_call")
        XCTAssertEqual(items[3]["id"] as? String, "fc_1",
                       "the call keeps its item id when its reasoning is present")
    }

    /// The .function-role replay path (repair-synthesized calls) must apply
    /// the same id-gating as the .assistant path: one construction site, one
    /// rule.
    func testResponsesRequest_functionRoleCall_appliesSameIDGating() throws {
        let call = LLM.FunctionCall(name: "lookup", arguments: "{}")
        let id = LLM.Message.FunctionCallID(callID: "call_42", itemID: "fc_1")
        let bare = LLM.Message(responseID: nil, role: .function,
                               body: .functionCall(call, id: id))
        let (_, bareItems) = try inputItems(messages: [LLM.Message(role: .user, content: "hi"), bare])
        XCTAssertEqual(bareItems.last?["type"] as? String, "function_call")
        XCTAssertNil(bareItems.last?["id"],
                     "a reasoning-less .function-role call must drop its item id too")

        let withReasoning = LLM.Message(responseID: nil, role: .function,
                                        body: .functionCall(call, id: id),
                                        reasoningItems: [reasoningItem()])
        let (_, items) = try inputItems(messages: [LLM.Message(role: .user, content: "hi"), withReasoning])
        XCTAssertEqual(items.dropFirst().first?["type"] as? String, "reasoning")
        XCTAssertEqual(items.last?["id"] as? String, "fc_1")
    }

    /// A reasoning-only turn (no text, no call) must not silently discard
    /// its captured reasoning items on the non-streaming path; the streaming
    /// parser already surfaces them on a bodiless message.
    func testResponsesParser_reasoningOnlyTurn_keepsReasoningItems() throws {
        let body = """
        {
            "id": "resp_test", "object": "response", "created_at": 0,
            "status": "incomplete", "model": "gpt-5", "metadata": {},
            "parallel_tool_calls": false, "previous_response_id": null,
            "reasoning": null, "service_tier": "default", "temperature": 1.0,
            "text": {"format": {"type": "text"}}, "tool_choice": "auto",
            "tools": [], "top_p": 1.0, "truncation": "disabled",
            "usage": {"input_tokens": 1, "output_tokens": 1, "total_tokens": 2,
                      "input_tokens_details": {"cached_tokens": 0},
                      "output_tokens_details": {"reasoning_tokens": 1}},
            "user": null, "instructions": null, "max_output_tokens": null,
            "background": null, "incomplete_details": null, "output_text": null,
            "output": [
                {"type": "reasoning", "id": "rs_only", "summary": [],
                 "encrypted_content": "\(blob)"}
            ]
        }
        """.data(using: .utf8)!
        var parser = ResponsesResponseParser()
        let response = try XCTUnwrap(try parser.parse(data: body))
        XCTAssertEqual(response.choiceMessages.count, 1)
        XCTAssertEqual(response.choiceMessages[0].reasoningItems?.map(\.id), ["rs_only"])
        XCTAssertNil(response.choiceMessages[0].function_call)
    }

    func testResponsesRequest_legacyCallWithoutReasoning_dropsItemID() throws {
        // Best-effort migration: a call persisted before reasoning items
        // existed must replay WITHOUT its OpenAI item id, so the API treats
        // it as developer-provided context instead of demanding the missing
        // reasoning item. call_id stays (it pairs the output).
        let user = LLM.Message(role: .user, content: "look it up")
        let (_, items) = try inputItems(messages: [user, functionCallMessage(reasoningItems: nil)])
        XCTAssertEqual(items.count, 2, "expected [user message, function_call]")
        XCTAssertEqual(items[1]["type"] as? String, "function_call")
        XCTAssertEqual(items[1]["call_id"] as? String, "call_42")
        XCTAssertNil(items[1]["id"],
                     "a legacy call with no reasoning item must not name an OpenAI item id")
    }

    func testResponsesRequest_nonReasoningModel_omitsInclude() throws {
        // Non-reasoning models 400 the include ("Encrypted content is not
        // supported with this model"), so it is gated on the model actually
        // reasoning.
        let body = try ResponsesBodyRequestBuilder(
            messages: [LLM.Message(role: .user, content: "hi")],
            provider: LLMProvider(model: try model(named: "gpt-4.1")),
            functions: [],
            stream: false,
            hostedTools: HostedTools(),
            previousResponseID: nil,
            shouldThink: nil).body()
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["include"],
                     "non-reasoning models must not request encrypted reasoning")
    }

    // MARK: - Gemini thought-signature fallback

    /// Gemini 3-series rejects a replayed functionCall part with no
    /// thought_signature; older Gemini never emits signatures at all, and
    /// because Gemini has no previous_response_id, live tool round-trips
    /// resend the just-made call too. So the fallback token is injected ONLY
    /// for models that require signatures: a real captured signature replays
    /// verbatim everywhere, a signature-less call gets the documented bypass
    /// token on 3-series, and stays bare on older models (their pre-existing
    /// accepted shape).
    func testGemini_functionCallReplay_gatesFallbackThoughtSignatureByModel() throws {
        func parts(signature: String?, modelName: String?) throws -> [[String: Any]] {
            let call = LLM.FunctionCall(name: "lookup", arguments: "{}",
                                        id: nil, thoughtSignature: signature)
            let messages = [
                LLM.Message(responseID: nil, role: .user, content: "hi"),
                LLM.Message(responseID: nil, role: .assistant,
                            body: .functionCall(call, id: nil)),
                LLM.Message(responseID: nil, role: .function,
                            body: .functionOutput(name: "lookup", output: "{}", id: nil)),
            ]
            let bodyData = try GeminiRequestBuilder(
                messages: messages,
                functions: [],
                hostedTools: HostedTools(),
                modelName: modelName).body()
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
            return contents.flatMap { ($0["parts"] as? [[String: Any]]) ?? [] }
        }

        let real = try parts(signature: "sig-123", modelName: "gemini-2.5-flash")
            .compactMap { $0["thoughtSignature"] as? String }
        XCTAssertEqual(real, ["sig-123"], "a captured signature must replay verbatim on any model")

        let gated = try parts(signature: nil, modelName: "gemini-3-flash-preview")
            .compactMap { $0["thoughtSignature"] as? String }
        XCTAssertEqual(gated, [GeminiRequestBuilder.missingThoughtSignatureFallback],
                       "a signature-less call must carry the bypass token on 3-series")

        let bare = try parts(signature: nil, modelName: "gemini-2.5-flash")
            .compactMap { $0["thoughtSignature"] as? String }
        XCTAssertEqual(bare, [],
                       "older Gemini must not receive a foreign signature it never asked for")

        let unknown = try parts(signature: nil, modelName: nil)
            .compactMap { $0["thoughtSignature"] as? String }
        XCTAssertEqual(unknown, [],
                       "no model knowledge -> no injection (the pre-fallback behavior)")
    }

    func testGemini_requiresThoughtSignature_byModelGeneration() {
        XCTAssertTrue(GeminiRequestBuilder.requiresThoughtSignature(modelName: "gemini-3-flash-preview"))
        XCTAssertTrue(GeminiRequestBuilder.requiresThoughtSignature(modelName: "gemini-3.5-flash"))
        XCTAssertTrue(GeminiRequestBuilder.requiresThoughtSignature(modelName: "gemini-3.1-pro-preview"))
        XCTAssertTrue(GeminiRequestBuilder.requiresThoughtSignature(modelName: "gemini-4-pro"),
                      "future generations presumably keep the requirement")
        XCTAssertFalse(GeminiRequestBuilder.requiresThoughtSignature(modelName: "gemini-2.5-pro"))
        XCTAssertFalse(GeminiRequestBuilder.requiresThoughtSignature(modelName: "gemini-2.0-flash"))
        // Generation-less aliases (gemini-flash-latest) resolve to CURRENT
        // Gemini, which requires signatures; an unparseable name must err
        // toward injecting the bypass token (2.x tolerates it, 3.x 400s
        // without it), so only a positively identified pre-3 generation
        // opts out.
        XCTAssertTrue(GeminiRequestBuilder.requiresThoughtSignature(modelName: "gemini-flash-latest"))
        XCTAssertTrue(GeminiRequestBuilder.requiresThoughtSignature(modelName: "gemini-pro-latest"))
        XCTAssertTrue(GeminiRequestBuilder.requiresThoughtSignature(modelName: "my-custom-gemini-proxy"),
                      "anything served via the Gemini API without a provable pre-3 generation gets the token")
        XCTAssertFalse(GeminiRequestBuilder.requiresThoughtSignature(modelName: nil),
                       "no model knowledge (test-only path) -> no injection")
    }

    /// The follow-up user text after a tool round trip must stay a SEPARATE
    /// user Content: folding it into the functionResponse's Content makes
    /// Gemini return an empty answer.
    func testGemini_userTextAfterFunctionResponse_staysSeparateContent() throws {
        let call = LLM.FunctionCall(name: "lookup", arguments: "{}",
                                    id: nil, thoughtSignature: "sig")
        let messages = [
            LLM.Message(responseID: nil, role: .user, content: "hi"),
            LLM.Message(responseID: nil, role: .assistant,
                        body: .functionCall(call, id: nil)),
            LLM.Message(responseID: nil, role: .function,
                        body: .functionOutput(name: "lookup", output: "{}", id: nil)),
            LLM.Message(responseID: nil, role: .user, content: "what did it say?"),
        ]
        let bodyData = try GeminiRequestBuilder(
            messages: messages,
            functions: [],
            hostedTools: HostedTools()).body()
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.count, 4,
                       "the functionResponse turn and the follow-up user text must not merge")
        let last = try XCTUnwrap(contents.last?["parts"] as? [[String: Any]])
        XCTAssertEqual(last.count, 1)
        XCTAssertEqual(last[0]["text"] as? String, "what did it say?")
    }

    // MARK: - Response parsing (capture)

    func testResponsesParser_capturesReasoningItems() throws {
        let body = """
        {
            "id": "resp_test",
            "object": "response",
            "created_at": 0,
            "status": "completed",
            "model": "gpt-5",
            "metadata": {},
            "parallel_tool_calls": false,
            "previous_response_id": null,
            "reasoning": null,
            "service_tier": "default",
            "temperature": 1.0,
            "text": {"format": {"type": "text"}},
            "tool_choice": "auto",
            "tools": [],
            "top_p": 1.0,
            "truncation": "disabled",
            "usage": {"input_tokens": 1, "output_tokens": 1, "total_tokens": 2,
                      "input_tokens_details": {"cached_tokens": 0},
                      "output_tokens_details": {"reasoning_tokens": 0}},
            "user": null,
            "instructions": null,
            "max_output_tokens": null,
            "background": null,
            "incomplete_details": null,
            "output_text": null,
            "output": [
                {"type": "reasoning", "id": "rs_1", "summary": [],
                 "encrypted_content": "\(blob)"},
                {"type": "function_call", "id": "fc_1", "call_id": "call_42",
                 "name": "lookup", "arguments": "{}", "status": "completed"}
            ]
        }
        """.data(using: .utf8)!
        var parser = ResponsesResponseParser()
        let response = try XCTUnwrap(try parser.parse(data: body))
        XCTAssertEqual(response.choiceMessages.count, 1)
        let message = response.choiceMessages[0]
        XCTAssertEqual(message.reasoningItems?.count, 1)
        XCTAssertEqual(message.reasoningItems?.first?.id, "rs_1")
        XCTAssertEqual(message.reasoningItems?.first?.encryptedContent, blob)
        XCTAssertEqual(message.function_call?.name, "lookup",
                       "capturing reasoning must not displace the function call")
    }

    func testResponsesStreamingParser_capturesReasoningItems() throws {
        let event = """
        {
            "type": "response.output_item.done",
            "sequence_number": 3,
            "output_index": 0,
            "item": {"type": "reasoning", "id": "rs_1", "summary": [],
                     "encrypted_content": "\(blob)"}
        }
        """.data(using: .utf8)!
        var parser = ResponsesResponseStreamingParser()
        let response = try XCTUnwrap(try parser.parse(data: event))
        let withReasoning = response.choiceMessages.compactMap(\.reasoningItems).flatMap { $0 }
        XCTAssertEqual(withReasoning.map(\.id), ["rs_1"])
        XCTAssertEqual(withReasoning.first?.encryptedContent, blob)
    }
}
