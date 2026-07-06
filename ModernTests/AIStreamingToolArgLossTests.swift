//
//  AIStreamingToolArgLossTests.swift
//  iTerm2 ModernTests
//
//  Regression test for the streaming tool-call argument-loss bug observed
//  in the field on 3.7.0beta6 (orchestration mode).
//
//  What happened: the model streamed a `get_screen_contents` call whose
//  `session_guid` argument arrived as Anthropic `input_json_delta`
//  fragments. The AI plugin delivered the final completion BEFORE those
//  argument-bearing stream chunks were consumed (the wire log shows the
//  response recorded ~0.7s before the tail chunks). AITermController
//  finalized the assistant turn from the incomplete incremental
//  accumulator, so the tool call carried empty arguments.
//  LLM.Function.invoke then substitutes "{}" for the empty argument string
//  (see LLM+Mac.swift, "// Anthropic does this"), and the orchestrator
//  dispatcher rejected it as "malformed_args: The data couldn't be read
//  because it is missing" (DecodingError.keyNotFound for session_guid). The
//  model, which believed it HAD supplied session_guid, then retried the
//  identical call ~48 times.
//
//  Root cause: AITermController.parseStreamingResponse(final:) dispatches
//  the tool call from the streamed accumulator and discards the
//  authoritative full response body (WebResponse.data), which DID contain
//  the complete arguments.
//
//  This test models that end-state deterministically: an incremental stream
//  truncated right after the tool_use block opens, paired with a complete
//  final body. The dispatched call must carry the full arguments. It fails
//  today (session_guid is dropped, args arrive as {}) and passes once the
//  finalization reconciles against the authoritative response body.
//

import XCTest
@testable import iTerm2SharedARC

final class AIStreamingToolArgLossTests: XCTestCase {

    override func tearDown() {
        iTermAIClient.requestInterceptor = nil
        super.tearDown()
    }

    // One Anthropic SSE event: an `event:` line, a `data:` line, and the
    // blank-line terminator, exactly as the wire delivers them.
    private func sse(_ event: String, _ data: String) -> String {
        return "event: \(event)\ndata: \(data)\n\n"
    }

    // Minimal delegate that surfaces errors, so a request-build failure fails
    // the test loudly instead of silently timing out.
    private final class Delegate: AITermControllerDelegate {
        var onError: ((Error) -> Void)?
        // Fires when a streamed turn finalizes as a plain text answer
        // (didStreamUpdate(nil)). Tests wait on this so the whole tool-call
        // round-trip (including the terminating follow-up request) completes
        // before the test returns; otherwise in-flight async work leaks past
        // tearDown and clobbers the next test's shared requestInterceptor.
        var onStreamEnd: (() -> Void)?
        func aitermControllerWillSendRequest(_ sender: AITermController) {}
        func aitermController(_ sender: AITermController, offerChoice: String) {}
        func aitermController(_ sender: AITermController, didStreamUpdate update: String?) {
            if update == nil { onStreamEnd?() }
        }
        func aitermController(_ sender: AITermController, didStreamAttachment: LLM.Message.Attachment) {}
        func aitermController(_ sender: AITermController, didFailWithError error: Error) { onError?(error) }
        func aitermControllerRequestRegistration(_ sender: AITermController,
                                                 completion: @escaping (AITermController.Registration) -> ()) {}
        func aitermController(_ sender: AITermController, didCreateVectorStore id: String, withName name: String) {}
        func aitermController(_ sender: AITermController, didFailToCreateVectorStoreWithError: Error) {}
        func aitermController(_ sender: AITermController, didUploadFileWithID id: String) {}
        func aitermController(_ sender: AITermController, didFailToUploadFileWithError: Error) {}
        func aitermControllerDidAddFilesToVectorStore(_ sender: AITermController) {}
        func aitermControllerDidFailToAddFilesToVectorStore(_ sender: AITermController, error: Error) {}
        func aitermController(_ sender: AITermController, willInvokeFunction function: LLM.AnyFunction) {}
        func aitermControllerDidCancelOutstandingRequest(_ sender: AITermController) {}
    }

    func test_streamingToolCall_finalizesWithCompleteArgs_evenWhenIncrementalStreamTruncated() throws {
        // A get_screen_contents call whose only argument is session_guid=ABC.
        let messageStart = sse("message_start", #"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"claude-opus-4-8","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":1}}}"#)
        let textStart = sse("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#)
        let textDelta = sse("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Reading the review screen."}}"#)
        let textStop = sse("content_block_stop", #"{"type":"content_block_stop","index":0}"#)
        let toolStart = sse("content_block_start", #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"get_screen_contents","input":{}}}"#)
        let argEmpty = sse("content_block_delta", #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":""}}"#)
        // The argument-bearing fragments that, in the field, arrived only AFTER
        // the completion had already been finalized.
        let argFrag1 = sse("content_block_delta", #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"session_guid\": \""}}"#)
        let argFrag2 = sse("content_block_delta", #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"ABC\"}"}}"#)
        let toolStop = sse("content_block_stop", #"{"type":"content_block_stop","index":1}"#)
        let messageDelta = sse("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"input_tokens":1,"output_tokens":10}}"#)
        let messageStop = sse("message_stop", #"{"type":"message_stop"}"#)

        // Incremental channel: truncated right after the tool_use block opens,
        // with no argument fragments. This is the accumulator state iTerm2
        // finalized from in the field.
        let truncatedChunks = [messageStart, textStart, textDelta, textStop, toolStart, argEmpty]
        // Authoritative full body: the complete response, arguments included.
        let fullBody = (truncatedChunks + [argFrag1, argFrag2, toolStop, messageDelta, messageStop]).joined()

        var callCount = 0
        iTermAIClient.requestInterceptor = { _, _ in
            callCount += 1
            if callCount == 1 {
                return iTermAIClient.ReplayDelivery(
                    streamChunks: truncatedChunks,
                    response: WebResponse(data: fullBody, error: nil),
                    errorReason: nil)
            }
            // Follow-up round after the tool result: a plain text turn so the
            // conversation terminates instead of looping.
            let done = self.sse("message_start", #"{"type":"message_start","message":{"id":"msg_2","type":"message","role":"assistant","content":[],"model":"claude-opus-4-8","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":1}}}"#)
                + self.sse("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#)
                + self.sse("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"done"}}"#)
                + self.sse("content_block_stop", #"{"type":"content_block_stop","index":0}"#)
                + self.sse("message_stop", #"{"type":"message_stop"}"#)
            return iTermAIClient.ReplayDelivery(
                streamChunks: [done],
                response: WebResponse(data: done, error: nil),
                errorReason: nil)
        }

        let controller = AITermController(
            registration: try XCTUnwrap(AITermController.Registration(apiKey: "test-key")))
        let delegate = Delegate()
        controller.delegate = delegate

        // Anthropic model: streaming + function calling, no thinking config.
        controller.providerOverride = LLMProvider(model: AIMetadata.recommendedAnthropicModel)

        let invoked = expectation(description: "get_screen_contents invoked")
        invoked.assertForOverFulfill = false
        let finished = expectation(description: "conversation finished")
        finished.assertForOverFulfill = false
        delegate.onStreamEnd = { finished.fulfill() }
        // A request-build failure surfaces here; fail loudly rather than
        // letting the invoked expectation time out with no explanation.
        delegate.onError = { error in
            XCTFail("controller reported an error: \(error)")
        }

        var capturedArgs: [String: Any]?
        let decl = ChatGPTFunctionDeclaration(
            name: "get_screen_contents",
            description: "Read the on-screen contents of the target session.",
            parameters: JSONSchema(rawJSON: [
                "type": "object",
                "properties": ["session_guid": ["type": "string"]],
                "required": ["session_guid"],
            ]))
        controller.define(function: decl, arguments: AnyCodable.self) { _, args, completion in
            capturedArgs = args.value as? [String: Any]
            invoked.fulfill()
            try completion(.success(#"{"screen_contents":"ok"}"#))
        }

        controller.request(
            messages: [LLM.Message(role: .user, content: "read the review screen")],
            stream: true)

        wait(for: [invoked, finished], timeout: 5.0)

        XCTAssertEqual(
            capturedArgs?["session_guid"] as? String, "ABC",
            "iTerm2 dispatched the tool call from the truncated incremental stream and dropped session_guid. "
            + "The complete arguments were present in the final response body but were discarded, so the "
            + "orchestrator received {} and rejected it as malformed_args.")
    }

    // The worst-case race, taken from the final call in the field log: the
    // completion beat the tool_use block ENTIRELY, so the incremental
    // accumulator held only a partial text preamble and no function call at
    // all. The old finalization treated that as a plain text answer, fired
    // didStreamUpdate(nil), and ended the conversation with an empty/truncated
    // bubble — the tool was never invoked and the orchestration loop halted.
    // The tool must still be dispatched (with full args) from the authoritative
    // body so the loop continues.
    func test_streamingToolCall_dispatchesFromBody_whenIncrementalStreamHasNoCallAtAll() throws {
        let messageStart = sse("message_start", #"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"claude-opus-4-8","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":1}}}"#)
        let textStart = sse("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#)
        let textDelta = sse("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Reading the review screen."}}"#)
        let textStop = sse("content_block_stop", #"{"type":"content_block_stop","index":0}"#)
        let toolStart = sse("content_block_start", #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"get_screen_contents","input":{}}}"#)
        let argEmpty = sse("content_block_delta", #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":""}}"#)
        let argFrag1 = sse("content_block_delta", #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"session_guid\": \""}}"#)
        let argFrag2 = sse("content_block_delta", #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"ABC\"}"}}"#)
        let toolStop = sse("content_block_stop", #"{"type":"content_block_stop","index":1}"#)
        let messageDelta = sse("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"input_tokens":1,"output_tokens":10}}"#)
        let messageStop = sse("message_stop", #"{"type":"message_stop"}"#)

        // Incremental channel truncated BEFORE the tool_use block opens: only
        // the text preamble arrived. This is the accumulator state that ended
        // the conversation in the field.
        let truncatedChunks = [messageStart, textStart, textDelta, textStop]
        let fullBody = (truncatedChunks + [toolStart, argEmpty, argFrag1, argFrag2, toolStop, messageDelta, messageStop]).joined()

        var callCount = 0
        iTermAIClient.requestInterceptor = { _, _ in
            callCount += 1
            if callCount == 1 {
                return iTermAIClient.ReplayDelivery(
                    streamChunks: truncatedChunks,
                    response: WebResponse(data: fullBody, error: nil),
                    errorReason: nil)
            }
            let done = self.sse("message_start", #"{"type":"message_start","message":{"id":"msg_2","type":"message","role":"assistant","content":[],"model":"claude-opus-4-8","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":1}}}"#)
                + self.sse("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#)
                + self.sse("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"done"}}"#)
                + self.sse("content_block_stop", #"{"type":"content_block_stop","index":0}"#)
                + self.sse("message_stop", #"{"type":"message_stop"}"#)
            return iTermAIClient.ReplayDelivery(
                streamChunks: [done],
                response: WebResponse(data: done, error: nil),
                errorReason: nil)
        }

        let controller = AITermController(
            registration: try XCTUnwrap(AITermController.Registration(apiKey: "test-key")))
        let delegate = Delegate()
        controller.delegate = delegate
        controller.providerOverride = LLMProvider(model: AIMetadata.recommendedAnthropicModel)

        let invoked = expectation(description: "get_screen_contents invoked")
        invoked.assertForOverFulfill = false
        let finished = expectation(description: "conversation finished")
        finished.assertForOverFulfill = false
        delegate.onStreamEnd = { finished.fulfill() }
        delegate.onError = { error in XCTFail("controller reported an error: \(error)") }

        var capturedArgs: [String: Any]?
        let decl = ChatGPTFunctionDeclaration(
            name: "get_screen_contents",
            description: "Read the on-screen contents of the target session.",
            parameters: JSONSchema(rawJSON: [
                "type": "object",
                "properties": ["session_guid": ["type": "string"]],
                "required": ["session_guid"],
            ]))
        controller.define(function: decl, arguments: AnyCodable.self) { _, args, completion in
            capturedArgs = args.value as? [String: Any]
            invoked.fulfill()
            try completion(.success(#"{"screen_contents":"ok"}"#))
        }

        controller.request(
            messages: [LLM.Message(role: .user, content: "read the review screen")],
            stream: true)

        wait(for: [invoked, finished], timeout: 5.0)

        XCTAssertEqual(
            capturedArgs?["session_guid"] as? String, "ABC",
            "The completion raced ahead of the tool_use block, so iTerm2 finalized a text-only turn and never "
            + "dispatched the call. The tool must be dispatched from the authoritative response body instead.")
    }
}
