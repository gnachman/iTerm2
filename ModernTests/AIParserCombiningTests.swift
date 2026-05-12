//
//  AIParserCombiningTests.swift
//  iTerm2 ModernTests
//
//  Offline unit tests for the parser-level combining work that turns a
//  multi-piece vendor response (Anthropic [text, tool_use], Gemini [text,
//  functionCall], OpenAI Responses [message, function_tool_call], and
//  modern chat-completions text + tool_calls in one message) into a single
//  LLM.Message with a multipart body. Also covers the matching round-trip
//  through ResponsesAPIRequest.transform, which is the only request builder
//  whose .assistant branch I had to extend for this refactor.
//
//  These tests fill the offline coverage gaps the live harness covers but
//  the existing offline tests do not. The refusal fixtures don't include
//  tool calls, so the .functionCall branches in each parser were
//  un-exercised; the multipart-aware LLM.Message.function_call getter and
//  ResponsesAPIRequest.assistantEntries had no offline coverage at all.
//

import XCTest
@testable import iTerm2SharedARC

final class AIParserCombiningTests: XCTestCase {

    private func model(named name: String) throws -> AIMetadata.Model {
        guard let m = AIMetadata.instance.models.first(where: { $0.name == name }) else {
            throw XCTSkip("Model \(name) not in AIMetadata; test skipped")
        }
        return m
    }

    // MARK: - LLM.Message.function_call multipart-aware getter

    /// A multipart body containing a function-call part must surface that
    /// call via the .function_call getter, otherwise AITerm's dispatch
    /// path can't find function calls in collapsed turns.
    func testMessage_functionCall_findsCallInsideMultipart() {
        let call = LLM.FunctionCall(name: "get_weather", arguments: "{}", id: "call_42")
        let body: LLM.Message.Body = .multipart([
            .text("Let me look that up."),
            .functionCall(call, id: nil),
        ])
        let m = LLM.Message(responseID: nil, role: .assistant, body: body)
        XCTAssertEqual(m.function_call?.name, "get_weather")
        XCTAssertEqual(m.function_call?.arguments, "{}")
    }

    /// A multipart body that holds only text must report no function call.
    func testMessage_functionCall_returnsNilForTextOnlyMultipart() {
        let body: LLM.Message.Body = .multipart([.text("hello"), .text("world")])
        let m = LLM.Message(responseID: nil, role: .assistant, body: body)
        XCTAssertNil(m.function_call)
    }

    // MARK: - Anthropic [text, tool_use] combining

    /// Anthropic returns one assistant turn whose content array can hold
    /// both a text preamble and a tool_use block. The parser must collapse
    /// them into a single multipart-bodied .assistant message and the
    /// embedded function call must be findable via .function_call.
    func testAnthropicParser_combinesTextPlusToolUseIntoMultipart() throws {
        let body = """
        {
            "id": "msg_test_1",
            "type": "message",
            "role": "assistant",
            "model": "claude-haiku-4-5",
            "content": [
                {"type": "text", "text": "I'll look that up for you."},
                {"type": "tool_use", "id": "toolu_abc", "name": "get_weather", "input": {"city": "Tokyo"}}
            ],
            "stop_reason": "tool_use",
            "stop_sequence": null,
            "usage": {"input_tokens": 5, "output_tokens": 5}
        }
        """.data(using: .utf8)!
        var parser = AnthropicResponseParser()
        let response = try XCTUnwrap(try parser.parse(data: body))
        XCTAssertEqual(response.choiceMessages.count, 1, "parser must collapse to one Message")
        let message = response.choiceMessages[0]
        guard case let .multipart(parts) = message.body else {
            XCTFail("expected multipart body, got \(message.body)")
            return
        }
        XCTAssertEqual(parts.count, 2)
        if case let .text(t) = parts[0] {
            XCTAssertEqual(t, "I'll look that up for you.")
        } else {
            XCTFail("first part should be .text, got \(parts[0])")
        }
        if case let .functionCall(call, _) = parts[1] {
            XCTAssertEqual(call.name, "get_weather")
            XCTAssertEqual(call.id, "toolu_abc")
        } else {
            XCTFail("second part should be .functionCall, got \(parts[1])")
        }
        XCTAssertEqual(message.function_call?.name, "get_weather",
                       "AITerm relies on function_call to find the embedded call in the multipart")
    }

    /// Anthropic returns one tool_use block with no text preamble. Parser
    /// should produce a single Message with a flat .functionCall body, not
    /// a multipart wrapping one part.
    func testAnthropicParser_singleToolUse_flatFunctionCallBody() throws {
        let body = """
        {
            "id": "msg_test_2",
            "type": "message",
            "role": "assistant",
            "model": "claude-haiku-4-5",
            "content": [
                {"type": "tool_use", "id": "toolu_x", "name": "f", "input": {}}
            ],
            "stop_reason": "tool_use",
            "stop_sequence": null,
            "usage": {"input_tokens": 1, "output_tokens": 1}
        }
        """.data(using: .utf8)!
        var parser = AnthropicResponseParser()
        let response = try XCTUnwrap(try parser.parse(data: body))
        XCTAssertEqual(response.choiceMessages.count, 1)
        if case let .functionCall(call, _) = response.choiceMessages[0].body {
            XCTAssertEqual(call.name, "f")
        } else {
            XCTFail("single tool_use should produce a flat .functionCall body, got \(response.choiceMessages[0].body)")
        }
    }

    // MARK: - Gemini [text, functionCall] combining

    /// Gemini 3 returns one candidate with two parts: a text preamble and
    /// a functionCall part carrying a thoughtSignature. The parser must
    /// produce a single .assistant message with a multipart body, and the
    /// thoughtSignature must survive on the embedded FunctionCall.
    func testGeminiParser_combinesPartsAndPreservesThoughtSignature() throws {
        let body = """
        {
            "candidates": [
                {
                    "content": {
                        "role": "model",
                        "parts": [
                            {"text": "Looking that up..."},
                            {"functionCall": {"name": "lookup", "args": {"q": "x"}}, "thoughtSignature": "sig_xyz"}
                        ]
                    },
                    "finishReason": "STOP"
                }
            ]
        }
        """.data(using: .utf8)!
        var parser = LLMGeminiResponseParser()
        let response = try XCTUnwrap(try parser.parse(data: body))
        XCTAssertEqual(response.choiceMessages.count, 1)
        let message = response.choiceMessages[0]
        guard case let .multipart(parts) = message.body else {
            XCTFail("expected multipart body, got \(message.body)")
            return
        }
        XCTAssertEqual(parts.count, 2)
        if case let .functionCall(call, _) = parts[1] {
            XCTAssertEqual(call.name, "lookup")
            XCTAssertEqual(call.thoughtSignature, "sig_xyz",
                           "thoughtSignature must survive parser combining")
        } else {
            XCTFail("second part should be .functionCall, got \(parts[1])")
        }
        XCTAssertEqual(message.function_call?.name, "lookup")
    }

    /// Gemini returns a single candidate with only one functionCall part.
    /// Parser should produce a flat .functionCall body, not a multipart of
    /// one element.
    func testGeminiParser_singleFunctionCallPart_flatBody() throws {
        let body = """
        {
            "candidates": [
                {
                    "content": {
                        "role": "model",
                        "parts": [
                            {"functionCall": {"name": "f", "args": {}}}
                        ]
                    },
                    "finishReason": "STOP"
                }
            ]
        }
        """.data(using: .utf8)!
        var parser = LLMGeminiResponseParser()
        let response = try XCTUnwrap(try parser.parse(data: body))
        XCTAssertEqual(response.choiceMessages.count, 1)
        if case let .functionCall(call, _) = response.choiceMessages[0].body {
            XCTAssertEqual(call.name, "f")
        } else {
            XCTFail("single functionCall part should produce a flat body, got \(response.choiceMessages[0].body)")
        }
    }

    // MARK: - OpenAI ChatCompletions text + tool_calls combining

    /// Modern chat-completions can deliver an assistant turn that carries
    /// both content and tool_calls in the same message. CompletionsMessage.
    /// llmMessage must surface both as a multipart body, not drop the text
    /// or the call.
    func testModernChatCompletions_combinesContentAndToolCalls() throws {
        let body = """
        {
            "id": "chatcmpl_test",
            "object": "chat.completion",
            "created": 0,
            "model": "gpt-4o-mini",
            "choices": [
                {
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": "Let me check that.",
                        "tool_calls": [
                            {
                                "id": "call_42",
                                "type": "function",
                                "function": {"name": "lookup", "arguments": "{}"}
                            }
                        ]
                    },
                    "finish_reason": "tool_calls"
                }
            ]
        }
        """.data(using: .utf8)!
        var parser = LLMModernResponseParser()
        let response = try XCTUnwrap(try parser.parse(data: body))
        XCTAssertEqual(response.choiceMessages.count, 1)
        let message = response.choiceMessages[0]
        guard case let .multipart(parts) = message.body else {
            XCTFail("expected multipart body when both content and tool_calls are present, got \(message.body)")
            return
        }
        XCTAssertEqual(parts.count, 2)
        if case let .text(t) = parts[0] {
            XCTAssertEqual(t, "Let me check that.")
        } else {
            XCTFail("first part should be .text, got \(parts[0])")
        }
        if case let .functionCall(call, id) = parts[1] {
            XCTAssertEqual(call.name, "lookup")
            XCTAssertEqual(id?.callID, "call_42")
        } else {
            XCTFail("second part should be .functionCall, got \(parts[1])")
        }
        XCTAssertEqual(message.function_call?.name, "lookup")
    }

    /// When chat-completions returns multiple n-sampling choices (which
    /// iTerm2 never asks for) the parser must surface only the first; the
    /// combine logic in AITerm is gone, so leaking extra choices would
    /// silently change behavior.
    func testModernChatCompletions_clampsToFirstChoice() throws {
        let body = """
        {
            "id": "chatcmpl_test",
            "object": "chat.completion",
            "created": 0,
            "model": "gpt-4o-mini",
            "choices": [
                {"index": 0, "message": {"role": "assistant", "content": "first"}, "finish_reason": "stop"},
                {"index": 1, "message": {"role": "assistant", "content": "second"}, "finish_reason": "stop"}
            ]
        }
        """.data(using: .utf8)!
        var parser = LLMModernResponseParser()
        let response = try XCTUnwrap(try parser.parse(data: body))
        XCTAssertEqual(response.choiceMessages.count, 1, "iTerm2 never sets n>1; parser must clamp")
        XCTAssertEqual(response.choiceMessages[0].body.maybeContent, "first")
    }

    // MARK: - OpenAI Responses combining + assistant round-trip

    /// OpenAI Responses can return an assistant turn whose output array
    /// contains both a message (text) and a function_tool_call. The parser
    /// must collapse them into one .assistant multipart Message, and the
    /// embedded function call must carry both its call_id and item id.
    func testResponsesParser_combinesMessageAndFunctionToolCall() throws {
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
                {"type": "message", "id": "msg1", "role": "assistant",
                 "status": "completed",
                 "content": [
                     {"type": "output_text", "text": "Calling tool now.", "annotations": []}
                 ]},
                {"type": "function_call", "id": "fc1", "call_id": "call_42",
                 "name": "lookup", "arguments": "{}", "status": "completed"}
            ]
        }
        """.data(using: .utf8)!
        var parser = ResponsesResponseParser()
        let response = try XCTUnwrap(try parser.parse(data: body))
        XCTAssertEqual(response.choiceMessages.count, 1,
                       "Responses parser must collapse output items to one Message")
        let message = response.choiceMessages[0]
        XCTAssertEqual(message.role, .assistant,
                       "function call is now embedded in an assistant turn, not a .function-role message")
        guard case let .multipart(parts) = message.body else {
            XCTFail("expected multipart, got \(message.body)")
            return
        }
        XCTAssertEqual(parts.count, 2)
        if case let .functionCall(call, id) = parts[1] {
            XCTAssertEqual(call.name, "lookup")
            XCTAssertEqual(id?.callID, "call_42")
            XCTAssertEqual(id?.itemID, "fc1")
        } else {
            XCTFail("second part should be .functionCall, got \(parts[1])")
        }
        XCTAssertEqual(message.function_call?.name, "lookup")
    }

    /// Round-trip: an .assistant multipart message produced by the
    /// Responses parser must serialize back through ResponsesAPIRequest's
    /// .assistant branch as a paired (message item, function_tool_call
    /// item) so a full conversation resend (previousResponseID == nil)
    /// reconstructs the wire shape. This exercises the new
    /// assistantEntries helper, which has no offline coverage otherwise.
    func testResponsesRequest_assistantMultipart_roundTripsToMessagePlusFunctionToolCall() throws {
        let model = try model(named: "gpt-5")
        let call = LLM.FunctionCall(name: "lookup", arguments: "{}")
        let id = LLM.Message.FunctionCallID(callID: "call_42", itemID: "fc1")
        let assistant = LLM.Message(responseID: nil, role: .assistant,
                                    body: .multipart([
                                        .text("Calling tool now."),
                                        .functionCall(call, id: id),
                                    ]))
        let user = LLM.Message(responseID: nil, role: .user, body: .text("Hi"))
        let body = try ResponsesBodyRequestBuilder(
            messages: [user, assistant],
            provider: LLMProvider(model: model),
            functions: [],
            stream: false,
            hostedTools: HostedTools(),
            previousResponseID: nil,
            shouldThink: nil).body()
        guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            XCTFail("Body is not a JSON object")
            return
        }
        guard let inputItems = json["input"] as? [[String: Any]] else {
            XCTFail("Body has no input array, got \(json)")
            return
        }
        // Expect: [user message, assistant message, function_tool_call].
        // assistantEntries fans out the multipart into TWO wire entries.
        XCTAssertEqual(inputItems.count, 3,
                       "assistant multipart should split into message + function_tool_call")
        XCTAssertEqual(inputItems[0]["role"] as? String, "user")
        XCTAssertEqual(inputItems[1]["role"] as? String, "assistant")
        XCTAssertEqual(inputItems[1]["content"] as? String, "Calling tool now.")
        XCTAssertEqual(inputItems[2]["type"] as? String, "function_call")
        XCTAssertEqual(inputItems[2]["call_id"] as? String, "call_42")
        XCTAssertEqual(inputItems[2]["name"] as? String, "lookup")
    }

    /// Round-trip: a flat .assistant text message must still produce one
    /// message item (not split into anything else). Guards against the
    /// new assistantEntries helper accidentally fanning out non-multipart
    /// bodies.
    func testResponsesRequest_assistantText_remainsSingleMessageItem() throws {
        let model = try model(named: "gpt-5")
        let assistant = LLM.Message(responseID: nil, role: .assistant,
                                    body: .text("Done."))
        let body = try ResponsesBodyRequestBuilder(
            messages: [assistant],
            provider: LLMProvider(model: model),
            functions: [],
            stream: false,
            hostedTools: HostedTools(),
            previousResponseID: nil,
            shouldThink: nil).body()
        guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let inputItems = json["input"] as? [[String: Any]] else {
            XCTFail("Body decode failed")
            return
        }
        XCTAssertEqual(inputItems.count, 1)
        XCTAssertEqual(inputItems[0]["role"] as? String, "assistant")
        XCTAssertEqual(inputItems[0]["content"] as? String, "Done.")
    }

    // MARK: - Streaming clamping and combining

    /// Modern chat-completions streaming: a delta carrying both content
    /// and a tool_call must surface as a multipart body (not drop either
    /// side). The streaming parser's choiceMessages is called on every
    /// chunk; this single-delta-with-both test pins the "combine in the
    /// delta" path the refactor preserved.
    func testModernChatCompletionsStreaming_combinesTextAndToolCallInOneDelta() throws {
        let chunk = """
        {
            "id": "chatcmpl_test",
            "object": "chat.completion.chunk",
            "created": 0,
            "model": "gpt-4o-mini",
            "choices": [
                {
                    "index": 0,
                    "delta": {
                        "role": "assistant",
                        "content": "Calling tool",
                        "tool_calls": [
                            {"index": 0, "id": "call_42", "type": "function",
                             "function": {"name": "f", "arguments": "{}"}}
                        ]
                    },
                    "finish_reason": null
                }
            ]
        }
        """.data(using: .utf8)!
        var parser = LLMModernStreamingResponseParser()
        let response = try XCTUnwrap(try parser.parse(data: chunk))
        XCTAssertEqual(response.choiceMessages.count, 1, "streaming parser must clamp to first choice")
        let message = response.choiceMessages[0]
        guard case let .multipart(parts) = message.body else {
            XCTFail("expected multipart for mixed delta, got \(message.body)")
            return
        }
        XCTAssertEqual(parts.count, 2)
        if case let .text(t) = parts[0] { XCTAssertEqual(t, "Calling tool") }
        if case let .functionCall(call, id) = parts[1] {
            XCTAssertEqual(call.name, "f")
            XCTAssertEqual(id?.callID, "call_42")
        } else {
            XCTFail("second part should be .functionCall, got \(parts[1])")
        }
    }

    /// Modern chat-completions streaming: multiple choices in a chunk
    /// (n>1, which iTerm2 never asks for) must clamp to the first.
    func testModernChatCompletionsStreaming_clampsToFirstChoice() throws {
        let chunk = """
        {
            "id": "chatcmpl_test",
            "object": "chat.completion.chunk",
            "created": 0,
            "model": "gpt-4o-mini",
            "choices": [
                {"index": 0, "delta": {"role": "assistant", "content": "first"}, "finish_reason": null},
                {"index": 1, "delta": {"role": "assistant", "content": "second"}, "finish_reason": null}
            ]
        }
        """.data(using: .utf8)!
        var parser = LLMModernStreamingResponseParser()
        let response = try XCTUnwrap(try parser.parse(data: chunk))
        XCTAssertEqual(response.choiceMessages.count, 1)
        XCTAssertEqual(response.choiceMessages[0].body.maybeContent, "first")
    }

    /// DeepSeek streaming chunk delivering a tool_call must surface a
    /// .functionCall body (not silently drop it) and clamp to the first
    /// choice.
    func testDeepSeekStreaming_toolCallSurfaces() throws {
        let chunk = """
        {
            "id": "chatcmpl_test",
            "object": "chat.completion.chunk",
            "created": 0,
            "model": "deepseek-chat",
            "choices": [
                {
                    "index": 0,
                    "delta": {
                        "role": "assistant",
                        "content": null,
                        "tool_calls": [
                            {"index": 0, "id": "call_7", "type": "function",
                             "function": {"name": "f", "arguments": "{}"}}
                        ]
                    },
                    "finish_reason": null
                }
            ]
        }
        """.data(using: .utf8)!
        var parser = DeepSeekStreamingResponseParser()
        let response = try XCTUnwrap(try parser.parse(data: chunk))
        XCTAssertEqual(response.choiceMessages.count, 1)
        XCTAssertEqual(response.choiceMessages[0].function_call?.name, "f")
        XCTAssertEqual(response.choiceMessages[0].functionCallID?.callID, "call_7")
    }

    /// DeepSeek streaming end-of-tool-call sentinel (finish_reason=tool_calls
    /// with an otherwise empty delta) must produce no message rather than
    /// a phantom empty one.
    func testDeepSeekStreaming_finishReasonToolCalls_producesNoMessage() throws {
        let chunk = """
        {
            "id": "chatcmpl_test",
            "object": "chat.completion.chunk",
            "created": 0,
            "model": "deepseek-chat",
            "choices": [
                {"index": 0, "delta": {}, "finish_reason": "tool_calls"}
            ]
        }
        """.data(using: .utf8)!
        var parser = DeepSeekStreamingResponseParser()
        let response = try XCTUnwrap(try parser.parse(data: chunk))
        XCTAssertTrue(response.choiceMessages.isEmpty,
                      "tool_calls sentinel must not surface a message")
    }

    // MARK: - Responses request builder backward-compat fallback

    /// Pre-refactor persisted history can hold an .assistant message
    /// whose body is `.attachment(.code(...))`. The new assistantEntries
    /// helper must surface its inner text via maybeContent rather than
    /// silently drop the entry on serialization, so chat-history
    /// databases written before the consolidation still round-trip.
    func testResponsesRequest_assistantAttachmentCode_fallsBackToText() throws {
        let model = try model(named: "gpt-5")
        let attachment = LLM.Message.Attachment(inline: true,
                                                id: "att-1",
                                                type: .code("print('hi')"))
        let assistant = LLM.Message(responseID: nil, role: .assistant,
                                    body: .attachment(attachment))
        let body = try ResponsesBodyRequestBuilder(
            messages: [assistant],
            provider: LLMProvider(model: model),
            functions: [],
            stream: false,
            hostedTools: HostedTools(),
            previousResponseID: nil,
            shouldThink: nil).body()
        guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let inputItems = json["input"] as? [[String: Any]] else {
            XCTFail("Body decode failed")
            return
        }
        XCTAssertEqual(inputItems.count, 1)
        XCTAssertEqual(inputItems[0]["role"] as? String, "assistant")
        XCTAssertEqual(inputItems[0]["content"] as? String, "print('hi')")
    }

    /// Persisted assistant turns carrying .attachment(.file) (which
    /// body.maybeContent returns nil for) must NOT silently disappear on
    /// a full resend. The Responses assistant role can't accept
    /// input_file on the wire, so the round-trip emits a text
    /// placeholder describing the file. Guards against the silent-drop
    /// bug the reviewer caught after the initial refactor.
    func testResponsesRequest_assistantAttachmentFile_emitsPlaceholder() throws {
        let model = try model(named: "gpt-5")
        let file = LLM.Message.Attachment.AttachmentType.File(name: "report.pdf",
                                                              content: Data([0x25, 0x50, 0x44, 0x46]),
                                                              mimeType: "application/pdf")
        let attachment = LLM.Message.Attachment(inline: true,
                                                id: "att-1",
                                                type: .file(file))
        let assistant = LLM.Message(responseID: nil, role: .assistant,
                                    body: .attachment(attachment))
        let body = try ResponsesBodyRequestBuilder(
            messages: [assistant],
            provider: LLMProvider(model: model),
            functions: [],
            stream: false,
            hostedTools: HostedTools(),
            previousResponseID: nil,
            shouldThink: nil).body()
        guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let inputItems = json["input"] as? [[String: Any]] else {
            XCTFail("Body decode failed")
            return
        }
        XCTAssertEqual(inputItems.count, 1, "assistant turn must not be dropped")
        XCTAssertEqual(inputItems[0]["role"] as? String, "assistant")
        let content = inputItems[0]["content"] as? String ?? ""
        XCTAssertTrue(content.contains("report.pdf"),
                      "placeholder should preserve the file name; got \(content)")
        XCTAssertTrue(content.contains("application/pdf"),
                      "placeholder should include the mime type; got \(content)")
    }

    /// Same as above for .attachment(.fileID). A previously persisted
    /// assistant turn with an opaque vector-store/file id must survive
    /// resend as a name-bearing placeholder rather than vanishing.
    func testResponsesRequest_assistantAttachmentFileID_emitsPlaceholder() throws {
        let model = try model(named: "gpt-5")
        let attachment = LLM.Message.Attachment(inline: false,
                                                id: "att-1",
                                                type: .fileID(id: "file_abc123", name: "diagram.png"))
        let assistant = LLM.Message(responseID: nil, role: .assistant,
                                    body: .attachment(attachment))
        let body = try ResponsesBodyRequestBuilder(
            messages: [assistant],
            provider: LLMProvider(model: model),
            functions: [],
            stream: false,
            hostedTools: HostedTools(),
            previousResponseID: nil,
            shouldThink: nil).body()
        guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let inputItems = json["input"] as? [[String: Any]] else {
            XCTFail("Body decode failed")
            return
        }
        XCTAssertEqual(inputItems.count, 1, "assistant turn must not be dropped")
        let content = inputItems[0]["content"] as? String ?? ""
        XCTAssertTrue(content.contains("diagram.png"),
                      "placeholder should preserve the file name; got \(content)")
    }

    /// .attachment(.statusUpdate) is ephemeral (web-search started,
    /// reasoning summary, etc.) and never meant to round-trip. The
    /// assistantEntries fallback should drop it without emitting a
    /// placeholder.
    func testResponsesRequest_assistantStatusUpdate_dropped() throws {
        let model = try model(named: "gpt-5")
        let attachment = LLM.Message.Attachment(inline: true,
                                                id: "att-1",
                                                type: .statusUpdate(.webSearchStarted))
        let assistantAttach = LLM.Message(responseID: nil, role: .assistant,
                                          body: .attachment(attachment))
        let user = LLM.Message(responseID: nil, role: .user, body: .text("hi"))
        let body = try ResponsesBodyRequestBuilder(
            messages: [user, assistantAttach],
            provider: LLMProvider(model: model),
            functions: [],
            stream: false,
            hostedTools: HostedTools(),
            previousResponseID: nil,
            shouldThink: nil).body()
        guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let inputItems = json["input"] as? [[String: Any]] else {
            XCTFail("Body decode failed")
            return
        }
        // Only the user message survives; the status update is ephemeral.
        XCTAssertEqual(inputItems.count, 1)
        XCTAssertEqual(inputItems[0]["role"] as? String, "user")
    }

    // MARK: - LegacyOpenAI clamp

    /// Legacy text-completions: n>1 alternatives must collapse to the
    /// first. iTerm2 never asks for n>1, so this is a guard against a
    /// future regression that bumps n and silently leaks multiple
    /// completions through choiceMessages.
    func testLegacyOpenAI_clampsToFirstChoice() throws {
        let body = """
        {
            "id": "cmpl_test",
            "object": "text_completion",
            "created": 0,
            "model": "gpt-3.5-turbo-instruct",
            "choices": [
                {"text": "first", "index": 0, "logprobs": null, "finish_reason": "stop"},
                {"text": "second", "index": 1, "logprobs": null, "finish_reason": "stop"}
            ]
        }
        """.data(using: .utf8)!
        var parser = LLMLegacyResponseParser()
        let response = try XCTUnwrap(try parser.parse(data: body))
        XCTAssertEqual(response.choiceMessages.count, 1)
        XCTAssertEqual(response.choiceMessages[0].body.maybeContent, "first")
    }

    // MARK: - Anthropic tool_use id wrapper population
    //
    // The Anthropic serializer's .functionOutput branch reads the tool_use_id
    // from the outer LLM.Message.Body.functionCall wrapper FunctionCallID. If
    // the parser leaves the wrapper nil and stashes the id only on the inner
    // LLM.FunctionCall.id, persisted tool calls round-trip back to Anthropic
    // as plain text and the API rejects the request for a missing tool_result.
    // These tests pin the wrapper id on all three Anthropic parse paths.

    /// Non-streaming AnthropicResponseParser: the wrapper FunctionCallID's
    /// callID must equal the inner FunctionCall.id.
    func testAnthropicParser_choiceMessage_setsWrapperFunctionCallID() throws {
        let body = """
        {
            "id": "msg_test_wrap_1",
            "type": "message",
            "role": "assistant",
            "model": "claude-haiku-4-5",
            "content": [
                {"type": "tool_use", "id": "toolu_wrap_1", "name": "f", "input": {}}
            ],
            "stop_reason": "tool_use",
            "stop_sequence": null,
            "usage": {"input_tokens": 1, "output_tokens": 1}
        }
        """.data(using: .utf8)!
        var parser = AnthropicResponseParser()
        let response = try XCTUnwrap(try parser.parse(data: body))
        let message = try XCTUnwrap(response.choiceMessages.first)
        guard case let .functionCall(call, wrapper) = message.body else {
            XCTFail("expected .functionCall body, got \(message.body)")
            return
        }
        XCTAssertEqual(call.id, "toolu_wrap_1")
        XCTAssertEqual(wrapper?.callID, "toolu_wrap_1",
                       "wrapper FunctionCallID.callID must equal tool_use id so .functionOutput round-trips back to Anthropic as a tool_result block")
    }

    /// Streaming AnthropicStreamingResponseParser: a content_block_start
    /// event for a tool_use must produce a .functionCall whose wrapper
    /// FunctionCallID.callID equals the tool_use id. itemID must also be
    /// the tool_use id (not "") so two distinct parallel tool_use blocks
    /// don't merge in LLM.Message.Body.tryAppend on matching empty itemIDs.
    func testAnthropicStreamingParser_toolUse_setsWrapperFunctionCallID() throws {
        let event = """
        {
            "type": "content_block_start",
            "index": 0,
            "content_block": {
                "type": "tool_use",
                "id": "toolu_stream_1",
                "name": "f",
                "input": {}
            }
        }
        """.data(using: .utf8)!
        var parser = AnthropicStreamingResponseParser()
        let response = try XCTUnwrap(try parser.parse(data: event))
        let message = try XCTUnwrap(response.choiceMessages.first)
        guard case let .functionCall(call, wrapper) = message.body else {
            XCTFail("expected .functionCall body, got \(message.body)")
            return
        }
        XCTAssertEqual(call.id, "toolu_stream_1")
        XCTAssertEqual(wrapper?.callID, "toolu_stream_1")
        XCTAssertEqual(wrapper?.itemID, "toolu_stream_1",
                       "itemID must equal tool_use id so tryAppend doesn't merge distinct parallel tool calls")
    }

    /// Two streaming content_block_start events for different parallel
    /// tool_use blocks must NOT merge into one .functionCall via
    /// LLM.Message.Body.tryAppend. The merge predicate compares wrapper
    /// itemIDs, so populating itemID with the tool_use id (rather than "")
    /// is what keeps the second tool call from being concatenated into the
    /// first. Anthropic disables parallel tool use today, so this is a
    /// guard for future enablement.
    func testAnthropicStreamingParser_distinctToolUseBlocks_doNotMerge() throws {
        let event1 = """
        {
            "type": "content_block_start",
            "index": 0,
            "content_block": {"type": "tool_use", "id": "toolu_a", "name": "alpha", "input": {}}
        }
        """.data(using: .utf8)!
        let event2 = """
        {
            "type": "content_block_start",
            "index": 1,
            "content_block": {"type": "tool_use", "id": "toolu_b", "name": "beta", "input": {}}
        }
        """.data(using: .utf8)!
        var parser = AnthropicStreamingResponseParser()
        let first = try XCTUnwrap(try parser.parse(data: event1)?.choiceMessages.first?.body)
        let second = try XCTUnwrap(try parser.parse(data: event2)?.choiceMessages.first?.body)
        var accumulator = first
        let merged = accumulator.tryAppend(second)
        XCTAssertFalse(merged,
                       "distinct parallel tool_use blocks must keep distinct itemIDs so tryAppend rejects the merge")
    }

    /// AnthropicMessage.llmMessage (the round-trip deserialization path):
    /// a multipart content array containing a toolUse block must produce a
    /// .functionCall whose wrapper FunctionCallID.callID equals the tool_use
    /// id.
    func testAnthropicMessage_llmMessage_toolUse_setsWrapperFunctionCallID() throws {
        let raw = """
        {
            "role": "assistant",
            "content": [
                {"type": "text", "text": "thinking"},
                {"type": "tool_use", "id": "toolu_round_1", "name": "f", "input": {}}
            ]
        }
        """.data(using: .utf8)!
        let anthropicMessage = try JSONDecoder().decode(AnthropicMessage.self, from: raw)
        let llmMessage = anthropicMessage.llmMessage
        guard case let .multipart(parts) = llmMessage.body else {
            XCTFail("expected multipart body, got \(llmMessage.body)")
            return
        }
        let callPart = parts.first { part in
            if case .functionCall = part { return true }
            return false
        }
        guard case let .functionCall(call, wrapper) = try XCTUnwrap(callPart) else {
            XCTFail("expected .functionCall part")
            return
        }
        XCTAssertEqual(call.id, "toolu_round_1")
        XCTAssertEqual(wrapper?.callID, "toolu_round_1")
    }
}
