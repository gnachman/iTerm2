//
//  LlamaToolArgumentTypeTests.swift
//  iTerm2 ModernTests
//
//  Regression test for the Ollama tool-argument decode failure observed in
//  the field on 3.7.0 (orchestration mode, local Ollama 0.33.0).
//
//  What happened: every `get_screen_contents` call against a claude-code
//  session failed with "Failed to decode API response: DecodingError
//  .valueNotFound: Expected value of type String but found null instead.
//  Path: message.toolCalls[0].function.arguments.lines".
//
//  Root cause: LlamaResponse typed tool_calls[].function.arguments as
//  [String: String]. Ollama echoes tool arguments back with the JSON types
//  the tool's own schema declared, and OrchestratorToolDefinitions declares
//  several non-string parameters -- `lines` as integer|null on
//  get_screen_contents, `lines` as integer on scroll_wheel,
//  `append_newline` / `notify_user` as boolean|null elsewhere. A single
//  non-string value fails the whole response decode, so the tool call never
//  reaches the dispatcher at all.
//
//  get_screen_contents was unusable against every tui/claude-code session,
//  because its own description tells the model to send lines=null there.
//
//  These tests drive the real parser and assert the arguments survive into
//  the orchestrator's own argument structs, whose types (Int?, Bool?)
//  already matched the schema -- only the decoder in between disagreed.
//

import XCTest
@testable import iTerm2SharedARC

final class LlamaToolArgumentTypeTests: XCTestCase {

    // A complete non-streaming Ollama /api/chat reply carrying one tool call.
    private func response(tool: String, arguments: String) -> Data {
        return Data("""
        {"model":"qwen3.6:35b-a3b-mtp-q4_K_M",\
        "message":{"role":"assistant","content":"",\
        "tool_calls":[{"function":{"name":"\(tool)","arguments":\(arguments)}}]},\
        "done":true}
        """.utf8)
    }

    // Parse as the app does, then hand back the JSON argument string the
    // dispatcher would receive.
    private func argumentJSON(tool: String,
                              arguments: String,
                              file: StaticString = #filePath,
                              line: UInt = #line) throws -> Data {
        var parser = LlamaResponseParser()
        let parsed = try parser.parse(data: response(tool: tool, arguments: arguments))
        let body = try XCTUnwrap(parsed?.choiceMessages.first?.body, file: file, line: line)
        guard case .functionCall(let call, _) = body else {
            XCTFail("expected a function call, got \(body)", file: file, line: line)
            return Data()
        }
        XCTAssertEqual(call.name, tool, file: file, line: line)
        return Data(try XCTUnwrap(call.arguments, file: file, line: line).utf8)
    }

    // The exact failing case: the schema tells the model to send null for
    // tui/claude-code sessions, so this is the common path, not an edge.
    func testGetScreenContents_nullLines() throws {
        let json = try argumentJSON(
            tool: "get_screen_contents",
            arguments: #"{"lines":null,"session_guid":"ptys_8DB5V43V3T2GR"}"#)
        let args = try JSONDecoder().decode(GetScreenContentsArgs.self, from: json)
        XCTAssertNil(args.lines)
        XCTAssertEqual(args.sessionGuid, "ptys_8DB5V43V3T2GR")
    }

    // The shell-session path: a real integer line count.
    func testGetScreenContents_integerLines() throws {
        let json = try argumentJSON(
            tool: "get_screen_contents",
            arguments: #"{"session_guid":"ptys_8DB5V43V3T2GR","lines":100}"#)
        let args = try JSONDecoder().decode(GetScreenContentsArgs.self, from: json)
        XCTAssertEqual(args.lines, 100)
        XCTAssertEqual(args.sessionGuid, "ptys_8DB5V43V3T2GR")
    }

    // scroll_wheel declares `lines` as a non-nullable integer.
    func testScrollWheel_integerLines() throws {
        let json = try argumentJSON(
            tool: "scroll_wheel",
            arguments: #"{"session_guid":"ptys_X","lines":3,"direction":"up"}"#)
        let args = try JSONDecoder().decode(ScrollWheelArgs.self, from: json)
        XCTAssertEqual(args.lines, 3)
        XCTAssertEqual(args.direction, .up)
    }

    // send_text declares `append_newline` as boolean|null. This is the tool
    // that actually drives sessions, so the same defect blocked writes too.
    func testSendText_booleanAppendNewline() throws {
        let json = try argumentJSON(
            tool: "send_text",
            arguments: #"{"session_guid":"ptys_X","text":"ls","append_newline":false}"#)
        let args = try JSONDecoder().decode(SendTextArgs.self, from: json)
        XCTAssertEqual(args.appendNewline, false)
        XCTAssertEqual(args.text, "ls")
    }

    // All-string arguments were the only shape the old decoder accepted;
    // widening it must not regress them.
    func testAllStringArgumentsStillDecode() throws {
        let json = try argumentJSON(
            tool: "get_state",
            arguments: #"{"session_guid":"ptys_X"}"#)
        let args = try JSONDecoder().decode([String: String].self, from: json)
        XCTAssertEqual(args["session_guid"], "ptys_X")
    }

    // MARK: - Streaming preamble + tool call (regression for a review finding)

    // Recursively collect all rendered text from a message body.
    private func text(in body: LLM.Message.Body) -> String {
        switch body {
        case .text(let s): return s
        case .multipart(let parts): return parts.map { text(in: $0) }.joined()
        default: return ""
        }
    }

    // Finding: a streamed chunk can carry BOTH assistant preamble text and a tool
    // call in the same delta. The non-streaming path keeps both (a .multipart
    // body, Llama.swift:114-117), but the streaming path (Llama.swift:150-156)
    // appends only the function-call message when a tool call is present, silently
    // dropping the spoken text. The two paths must not diverge: streaming must
    // still surface the preamble the model actually emitted.
    func testStreaming_preambleTextWithToolCall_isNotDropped() throws {
        let data = Data("""
        {"model":"qwen3","message":{"role":"assistant",\
        "content":"Let me check the weather for you.",\
        "tool_calls":[{"function":{"name":"get_weather","arguments":{"city":"SF"}}}]},\
        "done":false}
        """.utf8)
        let response = try JSONDecoder().decode(LlamaResponse<LlamaStreamingValue>.self, from: data)
        let messages = response.choiceMessages

        let hasFunctionCall = messages.contains { message in
            if case .functionCall = message.body { return true }
            return false
        }
        XCTAssertTrue(hasFunctionCall, "the tool call must still be delivered")

        let combined = messages.map { text(in: $0.body) }.joined()
        XCTAssertTrue(combined.contains("Let me check the weather for you."),
                      "streaming must not drop assistant preamble text that co-arrived with the tool call")
    }

    // Finding: the streaming path returns [] for the terminal done:true chunk (to
    // avoid re-emitting accumulated content). If a future Ollama build delivers the
    // tool_call ONLY in the done chunk, it must still be surfaced, not dropped.
    func testStreaming_toolCallInDoneChunk_isNotDropped() throws {
        let data = Data("""
        {"model":"qwen3","message":{"role":"assistant","content":"",\
        "tool_calls":[{"function":{"name":"get_weather","arguments":{"city":"SF"}}}]},\
        "done":true}
        """.utf8)
        let response = try JSONDecoder().decode(LlamaResponse<LlamaStreamingValue>.self, from: data)
        let hasFunctionCall = response.choiceMessages.contains { message in
            if case .functionCall = message.body { return true }
            return false
        }
        XCTAssertTrue(hasFunctionCall,
                      "a tool call arriving only in the done:true streamed chunk must still be dispatched")
    }
}
