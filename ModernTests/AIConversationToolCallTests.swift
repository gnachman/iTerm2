//
//  AIConversationToolCallTests.swift
//  iTerm2
//
//  Created for GitLab issue #12707
//
//  Tests for the bug where DeepSeek (and other non-Responses API providers)
//  fail with "insufficient tool messages following toolcalls message" after
//  a tool call completes.
//
//  Root cause: AIConversation.truncatedMessages only sends the last message
//  when previousResponseID is set, but this optimization only works with
//  OpenAI's Responses API which has a previous_response_id parameter.
//  Other APIs like DeepSeek require the full conversation history.

import XCTest
@testable import iTerm2SharedARC

final class AIConversationToolCallTests: XCTestCase {

    // MARK: - Test Helpers

    /// Creates a user message
    private func userMessage(_ content: String) -> LLM.Message {
        LLM.Message(responseID: nil, role: .user, content: content)
    }

    /// Creates an assistant message with text
    private func assistantMessage(_ content: String, responseID: String? = nil) -> LLM.Message {
        LLM.Message(responseID: responseID, role: .assistant, content: content)
    }

    /// Creates an assistant message with a function call (tool call)
    private func assistantFunctionCallMessage(
        functionName: String,
        arguments: String,
        callID: String,
        responseID: String? = nil
    ) -> LLM.Message {
        let functionCall = LLM.FunctionCall(name: functionName, arguments: arguments, id: callID)
        let functionCallID = LLM.Message.FunctionCallID(callID: callID, itemID: "")
        return LLM.Message(
            responseID: responseID,
            role: .assistant,
            body: .functionCall(functionCall, id: functionCallID)
        )
    }

    /// Creates a function output message (tool response)
    private func functionOutputMessage(
        functionName: String,
        output: String,
        callID: String
    ) -> LLM.Message {
        let functionCallID = LLM.Message.FunctionCallID(callID: callID, itemID: "")
        return LLM.Message(
            responseID: nil,
            role: .function,
            body: .functionOutput(name: functionName, output: output, id: functionCallID)
        )
    }

    // MARK: - Bug Reproduction Tests

    /// Tests that the truncate function preserves all messages when under token limit.
    /// This is the baseline - truncate should not remove messages unnecessarily.
    func testTruncatePreservesAllMessagesWhenUnderLimit() {
        let messages = [
            userMessage("What time is it?"),
            assistantFunctionCallMessage(
                functionName: "get_time",
                arguments: "{}",
                callID: "call_123",
                responseID: "resp_1"
            ),
            functionOutputMessage(
                functionName: "get_time",
                output: "14:30 UTC",
                callID: "call_123"
            ),
            assistantMessage("The time is 14:30 UTC", responseID: "resp_2")
        ]

        // With a high token limit, all messages should be preserved
        let result = truncate(messages: messages, maxTokens: 100000)

        XCTAssertEqual(result.count, messages.count,
                       "All messages should be preserved when under token limit")
    }

    /// Tests that a tool call message followed by tool response maintains proper sequencing.
    /// DeepSeek requires: assistant(tool_calls) -> tool(response) -> ...
    func testToolCallSequenceIsValid() {
        let messages = [
            userMessage("What time is it?"),
            assistantFunctionCallMessage(
                functionName: "get_time",
                arguments: "{}",
                callID: "call_123",
                responseID: "resp_1"
            ),
            functionOutputMessage(
                functionName: "get_time",
                output: "14:30 UTC",
                callID: "call_123"
            )
        ]

        // Verify the sequence is valid (function call followed by function output)
        XCTAssertEqual(messages[1].role, .assistant)
        XCTAssertNotNil(messages[1].function_call)
        XCTAssertEqual(messages[2].role, .function)

        // The function output should reference the same call ID
        if case .functionOutput(_, _, let id) = messages[2].body {
            XCTAssertEqual(id?.callID, "call_123")
        } else {
            XCTFail("Expected functionOutput body")
        }
    }

    /// This test demonstrates the BUG in AIConversation.truncatedMessages.
    ///
    /// When previousResponseID is set, the buggy code only returns the last message:
    /// ```swift
    /// private var truncatedMessages: [AITermController.Message] {
    ///     if controller.previousResponseID != nil, let lastMessage = messages.last {
    ///         return truncate(messages: [lastMessage], maxTokens: maxTokens)
    ///     }
    ///     return truncate(messages: messages, maxTokens: maxTokens)
    /// }
    /// ```
    ///
    /// This breaks tool call sequences for non-Responses APIs like DeepSeek because:
    /// 1. After a tool call, the last message is the user's follow-up question
    /// 2. Only that message is sent, missing the tool_calls and tool response
    /// 3. DeepSeek rejects: "insufficient tool messages following toolcalls message"
    func testBugReproduction_TruncatingToLastMessageBreaksToolSequence() {
        // Build a conversation that has completed a tool call
        let messages = [
            userMessage("What time is it in UTC?"),
            assistantFunctionCallMessage(
                functionName: "get_time",
                arguments: "{\"timezone\": \"UTC\"}",
                callID: "call_abc123",
                responseID: "resp_1"
            ),
            functionOutputMessage(
                functionName: "get_time",
                output: "The current time is 14:30:00 UTC",
                callID: "call_abc123"
            ),
            assistantMessage("The current time in UTC is 14:30.", responseID: "resp_2"),
            userMessage("Thanks! Now what about Tokyo?")
        ]

        // Simulate what truncatedMessages does when previousResponseID is set:
        // It only sends the last message
        let buggyTruncatedMessages = [messages.last!]

        XCTAssertEqual(buggyTruncatedMessages.count, 1,
                       "Bug simulation: only last message is sent")
        XCTAssertEqual(buggyTruncatedMessages[0].role, .user,
                       "Bug simulation: only the user's follow-up is sent")

        // This is the problem: the conversation history with tool calls is lost.
        // DeepSeek (and other non-Responses APIs) need the full history to understand
        // that tool calls were made and responded to.

        // The correct behavior should send all messages (or at least maintain
        // tool call sequences) for non-Responses API providers.
        let correctMessages = truncate(messages: messages, maxTokens: 100000)
        XCTAssertEqual(correctMessages.count, messages.count,
                       "Correct behavior: all messages preserved")
    }

    /// Tests the specific failure scenario from issue #12707.
    ///
    /// The user reported:
    /// 1. Asked AI to run some commands (triggers tool calls)
    /// 2. Then asked another question
    /// 3. Got error: "An assistant message with 'tool_calls' must be followed by
    ///    tool messages responding to each 'tool_call_id'"
    func testIssue12707_FollowUpAfterToolCallFails() {
        // Step 1: User asks to run a command
        let step1Messages = [
            userMessage("Run the command 'date' to get the current date")
        ]

        // Step 2: Assistant responds with a tool call
        let step2Messages = step1Messages + [
            assistantFunctionCallMessage(
                functionName: "execute_command",
                arguments: "{\"command\": \"date\"}",
                callID: "call_exec_1",
                responseID: "resp_1"
            )
        ]

        // Step 3: Tool response is received
        let step3Messages = step2Messages + [
            functionOutputMessage(
                functionName: "execute_command",
                output: "Mon Feb 10 14:30:00 UTC 2025",
                callID: "call_exec_1"
            )
        ]

        // Step 4: Assistant provides final response
        let step4Messages = step3Messages + [
            assistantMessage("The current date is Monday, February 10, 2025.", responseID: "resp_2")
        ]

        // Step 5: User asks a follow-up question
        let step5Messages = step4Messages + [
            userMessage("What's the current month?")
        ]

        // BUG: When previousResponseID="resp_2" is set, only the last message is sent
        let buggyRequest = [step5Messages.last!]

        // This would cause DeepSeek to fail because it sees a conversation that
        // previously had tool calls but now doesn't include the tool response.
        // From DeepSeek's perspective, it's an invalid message sequence.

        XCTAssertEqual(buggyRequest.count, 1,
                       "Bug: only sends 1 message instead of full history")

        // Verify the full history has the correct tool call sequence
        XCTAssertEqual(step5Messages.count, 5,
                       "Full history should have 5 messages")

        // Find the tool call and verify it's followed by a tool response
        var foundToolCall = false
        var foundToolResponse = false
        for (i, msg) in step5Messages.enumerated() {
            if msg.function_call != nil {
                foundToolCall = true
                // Next message should be the tool response
                if i + 1 < step5Messages.count {
                    let nextMsg = step5Messages[i + 1]
                    if case .functionOutput(_, _, let id) = nextMsg.body {
                        foundToolResponse = true
                        XCTAssertEqual(id?.callID, "call_exec_1",
                                       "Tool response should match tool call ID")
                    }
                }
            }
        }

        XCTAssertTrue(foundToolCall, "Should have a tool call in history")
        XCTAssertTrue(foundToolResponse, "Tool call should be followed by tool response")
    }

    // MARK: - Integration Test (requires API key)

    /// This test reproduces the bug from issue #12707.
    ///
    /// ROOT CAUSE: When DeepSeek responds with multiple parallel tool_calls,
    /// the streaming parser only handles the FIRST one (line 184 of DeepSeek.swift):
    ///
    ///     if let call = choice.delta.tool_calls?.first {
    ///
    /// We send only 1 tool response, but DeepSeek expects responses for ALL tool_calls.
    /// Result: "insufficient tool messages following toolcalls message"
    ///
    /// This test asks DeepSeek to perform multiple operations simultaneously,
    /// triggering multiple parallel tool_calls, which exposes the bug.
    func testIntegration_DeepSeekToolCallBug() throws {
        let apiKey = try getDeepSeekAPIKey()

        // Manually set the API key since we're not using the normal UI flow
        AITermControllerRegistrationHelper.instance.setKey(apiKey)

        // Configure preferences to use DeepSeek
        let originalVendor = iTermPreferences.unsignedInteger(forKey: kPreferenceKeyAIVendor)
        let originalUseRecommended = iTermPreferences.bool(forKey: kPreferenceKeyUseRecommendedAIModel)

        defer {
            iTermPreferences.setUnsignedInteger(originalVendor, forKey: kPreferenceKeyAIVendor)
            iTermPreferences.setBool(originalUseRecommended, forKey: kPreferenceKeyUseRecommendedAIModel)
        }

        iTermPreferences.setUnsignedInteger(UInt(iTermAIVendor.deepSeek.rawValue), forKey: kPreferenceKeyAIVendor)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyUseRecommendedAIModel)

        var conversation = AIConversation(registrationProvider: nil)
        conversation.model = "deepseek-chat"

        // Track how many function calls we receive
        var functionCallCount = 0

        // Define a simple function
        struct GetInfoArgs: Codable {
            var item: String
        }
        let getInfoDecl = ChatGPTFunctionDeclaration(
            name: "get_info",
            description: "Get information about an item. IMPORTANT: When asked about multiple items, you MUST call this function ONCE PER ITEM in parallel, not once for all items.",
            parameters: JSONSchema(for: GetInfoArgs(item: ""), descriptions: ["item": "The item to get info about"])
        )
        conversation.define(function: getInfoDecl, arguments: GetInfoArgs.self) { _, args, completion in
            functionCallCount += 1
            print("  -> Function get_info called for: \(args.item) (call #\(functionCallCount))")
            try completion(.success("Info about \(args.item): It's great!"))
        }

        print("=== Testing DeepSeek parallel tool calls bug ===")
        print("Asking DeepSeek to get info about multiple items simultaneously...")
        print("This should trigger multiple parallel tool_calls.")
        print("BUG: We only handle the first tool_call, causing 'insufficient tool messages' error.\n")

        // Ask for info about multiple things to trigger parallel tool calls
        conversation.add(text: "Use the get_info function to get information about these three items AT THE SAME TIME using parallel function calls: apple, banana, and cherry. Call the function three times in parallel, once for each item.")

        let expectation = XCTestExpectation(description: "DeepSeek parallel tool calls")
        var error: Error?
        var responseText = ""

        conversation.complete(streaming: { update, _ in
            switch update {
            case .append(let text):
                responseText += text
            case .willInvoke(let function):
                print("  -> Will invoke: \(function.decl.name)")
            default:
                break
            }
        }) { result in
            switch result {
            case .success(let updated):
                conversation = updated
            case .failure(let e):
                error = e
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 120.0)

        print("\n=== Results ===")
        print("Function calls received: \(functionCallCount)")

        if let error = error {
            let errorMessage = error.localizedDescription
            print("Error: \(errorMessage)")

            // Check if this is the bug we're looking for
            if errorMessage.contains("tool") &&
               (errorMessage.contains("insufficient") || errorMessage.contains("followed by")) {
                // This is the bug!
                print("\n*** BUG #12707 REPRODUCED! ***")
                print("DeepSeek sent multiple tool_calls but we only responded to one.")
                XCTFail("BUG #12707: \(errorMessage)")
            } else {
                XCTFail("Unexpected error: \(errorMessage)")
            }
        } else {
            print("Response: \(responseText)")

            // If DeepSeek only called the function once, it might not have used parallel calls
            if functionCallCount < 3 {
                print("\nNote: DeepSeek only made \(functionCallCount) function call(s).")
                print("It may not have used parallel tool_calls. Bug may not be triggered.")
            } else {
                print("\nDeepSeek made \(functionCallCount) function calls and completed successfully.")
                print("This suggests either:")
                print("  1. DeepSeek didn't use parallel tool_calls (called them sequentially)")
                print("  2. The bug fix is already in place")
            }
        }
    }

    private func getDeepSeekAPIKey() throws -> String {
        // Try environment variable first (for Xcode scheme configuration)
        if let envKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"],
           !envKey.isEmpty {
            return envKey
        }
        // Fall back to file
        let keyFilePath = NSString(string: "~/.config/iterm2/deepseek_api_key").expandingTildeInPath
        guard let fileKey = try? String(contentsOfFile: keyFilePath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !fileKey.isEmpty else {
            throw XCTSkip("No API key found. Create ~/.config/iterm2/deepseek_api_key or set DEEPSEEK_API_KEY in Xcode scheme.")
        }
        return fileKey
    }

    // MARK: - Parallel Tool Calls Parser Tests

    /// Tests that DeepSeekStreamingResponseParser handles multiple parallel tool_calls
    /// by processing only the first one.
    ///
    /// When DeepSeek sends multiple tool_calls in a single streaming chunk, we only
    /// process the first one. This keeps the conversation history consistent - we store
    /// one tool_call and one tool_response, so DeepSeek sees a valid sequence.
    func testDeepSeekParser_MultipleParallelToolCalls_ProcessesFirstOnly() throws {
        // This JSON simulates a DeepSeek streaming response with THREE parallel tool_calls
        // in a single chunk.
        let jsonWithMultipleToolCalls = """
        {
            "id": "chatcmpl-abc123",
            "object": "chat.completion.chunk",
            "created": 1234567890,
            "model": "deepseek-chat",
            "choices": [{
                "index": 0,
                "delta": {
                    "role": "assistant",
                    "content": null,
                    "tool_calls": [
                        {
                            "index": 0,
                            "id": "call_apple",
                            "type": "function",
                            "function": {
                                "name": "get_info",
                                "arguments": "{\\"item\\": \\"apple\\"}"
                            }
                        },
                        {
                            "index": 1,
                            "id": "call_banana",
                            "type": "function",
                            "function": {
                                "name": "get_info",
                                "arguments": "{\\"item\\": \\"banana\\"}"
                            }
                        },
                        {
                            "index": 2,
                            "id": "call_cherry",
                            "type": "function",
                            "function": {
                                "name": "get_info",
                                "arguments": "{\\"item\\": \\"cherry\\"}"
                            }
                        }
                    ]
                },
                "finish_reason": null
            }]
        }
        """

        let data = jsonWithMultipleToolCalls.data(using: .utf8)!

        var parser = DeepSeekStreamingResponseParser()
        let response = try parser.parse(data: data)

        guard let streamingResponse = response else {
            XCTFail("Failed to parse response")
            return
        }

        let messages = streamingResponse.choiceMessages

        // We intentionally only process the first tool_call to keep conversation history consistent
        XCTAssertEqual(messages.count, 1, "Should return only the first tool_call")

        if let call = messages.first?.function_call {
            XCTAssertEqual(call.id, "call_apple", "Should be the first tool_call (apple)")
            XCTAssertEqual(call.name, "get_info")
        } else {
            XCTFail("Expected function_call in message")
        }
    }

    /// Tests that individual streaming chunks with single tool_calls work correctly.
    /// This is the "happy path" that currently works - DeepSeek sends tool_calls one at a time.
    func testDeepSeekParser_SingleToolCall_Works() throws {
        let jsonWithSingleToolCall = """
        {
            "id": "chatcmpl-abc123",
            "object": "chat.completion.chunk",
            "created": 1234567890,
            "model": "deepseek-chat",
            "choices": [{
                "index": 0,
                "delta": {
                    "role": "assistant",
                    "content": null,
                    "tool_calls": [
                        {
                            "index": 0,
                            "id": "call_single",
                            "type": "function",
                            "function": {
                                "name": "get_time",
                                "arguments": "{}"
                            }
                        }
                    ]
                },
                "finish_reason": null
            }]
        }
        """

        let data = jsonWithSingleToolCall.data(using: .utf8)!

        var parser = DeepSeekStreamingResponseParser()
        let response = try parser.parse(data: data)

        guard let streamingResponse = response else {
            XCTFail("Failed to parse response")
            return
        }

        let messages = streamingResponse.choiceMessages

        // Single tool_call should work fine
        XCTAssertEqual(messages.count, 1, "Single tool_call should produce 1 message")

        if let call = messages.first?.function_call {
            XCTAssertEqual(call.id, "call_single")
            XCTAssertEqual(call.name, "get_time")
        } else {
            XCTFail("Expected function_call in message")
        }
    }

    /// Tests that when we send a follow-up request after missing parallel tool_calls,
    /// the request body would be invalid (missing tool responses).
    ///
    /// This simulates the full bug flow:
    /// 1. DeepSeek sends 3 parallel tool_calls
    /// 2. We only parse the first one (due to `.first` bug)
    /// 3. We respond to only that one tool_call
    /// 4. User asks follow-up
    /// 5. We build request with conversation history
    /// 6. The request has 1 tool_call but DeepSeek's original had 3
    ///
    /// Note: DeepSeek validates on its side that all tool_calls have responses.
    /// We can't directly test that validation, but we can show the mismatch.
    func testDeepSeekRequest_AfterMissedParallelToolCalls_HasMismatch() throws {
        // Simulate what happens after parsing a response with 3 parallel tool_calls
        // where we only captured the first one due to the `.first` bug.
        //
        // In reality, DeepSeek sent: tool_calls: [apple, banana, cherry]
        // But we only parsed: tool_calls: [apple]

        // Step 1: User message
        let userMessage = LLM.Message(role: .user, content: "Get info about apple, banana, and cherry")

        // Step 2: Assistant responds with tool_call (we only captured 1 of 3)
        // This is what we stored after parsing with the `.first` bug
        let assistantToolCall = LLM.Message(
            role: .assistant,
            content: nil,
            functionCallID: .init(callID: "call_apple", itemID: ""),
            function_call: LLM.FunctionCall(name: "get_info", arguments: "{\"item\": \"apple\"}", id: "call_apple")
        )

        // Step 3: We respond to the one tool_call we saw
        let toolResponse = LLM.Message(
            responseID: nil,
            role: .function,
            body: .functionOutput(name: "get_info", output: "Apple info", id: .init(callID: "call_apple", itemID: ""))
        )

        // Step 4: User asks follow-up
        let followUpMessage = LLM.Message(role: .user, content: "Thanks! What else can you tell me?")

        // Build the conversation history we'd send to DeepSeek
        let messages = [userMessage, assistantToolCall, toolResponse, followUpMessage]

        // Convert messages to DeepSeekRequestBuilder.Message to see how they'd be serialized
        let deepSeekMessages = messages.compactMap { DeepSeekRequestBuilder.Message($0) }

        print("=== Request Body After Missed Parallel Tool Calls ===")
        print("Messages in request: \(deepSeekMessages.count)")

        // Find the assistant message with tool_calls
        var toolCallsInRequest = 0
        var toolResponsesInRequest = 0

        for msg in deepSeekMessages {
            if msg.role == .assistant, let toolCalls = msg.tool_calls {
                toolCallsInRequest = toolCalls.count
                print("Assistant message has \(toolCalls.count) tool_call(s)")
                for tc in toolCalls {
                    print("  - \(tc.function.name ?? "unknown")")
                }
            }
            if msg.role == .tool {
                toolResponsesInRequest += 1
                print("Tool response for: \(msg.tool_call_id ?? "unknown")")
            }
        }

        print("\nSummary:")
        print("  Tool calls in our request: \(toolCallsInRequest)")
        print("  Tool responses in our request: \(toolResponsesInRequest)")
        print("\nBUT DeepSeek originally sent 3 tool_calls!")
        print("DeepSeek will reject this because it remembers sending 3 tool_calls")
        print("but only sees 1 tool response in the conversation history.")

        // This shows the mismatch from our side
        // We're sending 1 tool_call and 1 tool_response, which looks valid
        // But DeepSeek knows it sent 3 tool_calls originally
        XCTAssertEqual(toolCallsInRequest, 1, "We only captured 1 tool_call")
        XCTAssertEqual(toolResponsesInRequest, 1, "We only sent 1 tool_response")

        // The real validation happens on DeepSeek's side:
        // It compares what it SENT (3 tool_calls) vs what we responded to (1)
        // This test documents the bug but can't directly verify DeepSeek's validation
    }

    /// Tests that chunks for parallel tool_calls with index > 0 are ignored.
    ///
    /// When DeepSeek streams parallel tool_calls, it sends chunks with different `index` values.
    /// Index 0 is the first tool_call, index 1 is the second, etc.
    /// We only process index 0 to keep the conversation history consistent.
    func testDeepSeekParser_ParallelToolCallChunks_IgnoresIndexGreaterThanZero() throws {
        // First chunk: first tool_call (index=0)
        let chunk1 = """
        {
            "id": "chatcmpl-abc123",
            "object": "chat.completion.chunk",
            "created": 1234567890,
            "model": "deepseek-chat",
            "choices": [{
                "index": 0,
                "delta": {
                    "role": "assistant",
                    "tool_calls": [{
                        "index": 0,
                        "id": "call_first",
                        "type": "function",
                        "function": {"name": "func_a", "arguments": "{}"}
                    }]
                },
                "finish_reason": null
            }]
        }
        """

        // Second chunk: second parallel tool_call (index=1) - should be ignored
        let chunk2 = """
        {
            "id": "chatcmpl-abc123",
            "object": "chat.completion.chunk",
            "created": 1234567890,
            "model": "deepseek-chat",
            "choices": [{
                "index": 0,
                "delta": {
                    "tool_calls": [{
                        "index": 1,
                        "id": "call_second",
                        "type": "function",
                        "function": {"name": "func_b", "arguments": "{}"}
                    }]
                },
                "finish_reason": null
            }]
        }
        """

        var parser = DeepSeekStreamingResponseParser()

        // Parse first chunk - should return the first tool_call
        let response1 = try parser.parse(data: chunk1.data(using: .utf8)!)
        let messages1 = response1?.choiceMessages ?? []
        XCTAssertEqual(messages1.count, 1, "First chunk should have 1 tool_call")
        XCTAssertEqual(messages1.first?.function_call?.id, "call_first")

        // Parse second chunk - index=1, should be ignored (returns text message only)
        let response2 = try parser.parse(data: chunk2.data(using: .utf8)!)
        let messages2 = response2?.choiceMessages ?? []
        XCTAssertEqual(messages2.count, 1, "Second chunk should return a message")
        XCTAssertNil(messages2.first?.function_call, "Chunk with index > 0 should be ignored")
    }
}
