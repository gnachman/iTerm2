//
//  AITermControllerCancelTests.swift
//  iTerm2 ModernTests
//
//  A cancelled AITermController request must stay dead. Cancelling does not
//  always stop the transfer, and the controller is reused for the next turn,
//  so a cancelled request's deferred send, late streamed words, and final
//  response must not reach the state machine. Before this was enforced,
//  deleting an AI chat message mid-turn and then sending another message made
//  the new message "answer" with the rest of the deleted message's reply
//  (QA finding F-086). Driven hermetically through iTermAIClient's replay hook.
//

import XCTest
@testable import iTerm2SharedARC

final class AITermControllerCancelTests: XCTestCase {
    override func tearDown() {
        iTermAIClient.requestInterceptor = nil
        iTermAIClient.liveObserver = nil
        super.tearDown()
    }

    private final class RecordingDelegate: AITermControllerDelegate {
        var streamed = ""
        var errors: [Error] = []
        var uploadedIDs: [String] = []
        var uploadFailures: [Error] = []
        var onStreamEnd: (() -> Void)?
        func aitermControllerWillSendRequest(_ sender: AITermController) {}
        func aitermController(_ sender: AITermController, offerChoice: String) {}
        func aitermController(_ sender: AITermController, didStreamUpdate update: String?) {
            if let update {
                streamed += update
            } else {
                onStreamEnd?()
            }
        }
        func aitermController(_ sender: AITermController, didStreamAttachment: LLM.Message.Attachment) {}
        func aitermController(_ sender: AITermController, didFailWithError error: Error) { errors.append(error) }
        func aitermControllerRequestRegistration(_ sender: AITermController,
                                                 completion: @escaping (AITermController.Registration) -> ()) {}
        func aitermController(_ sender: AITermController, didCreateVectorStore id: String, withName name: String) {}
        func aitermController(_ sender: AITermController, didFailToCreateVectorStoreWithError: Error) {}
        func aitermController(_ sender: AITermController, didUploadFileWithID id: String) { uploadedIDs.append(id) }
        func aitermController(_ sender: AITermController, didFailToUploadFileWithError error: Error) {
            uploadFailures.append(error)
        }
        func aitermControllerDidAddFilesToVectorStore(_ sender: AITermController) {}
        func aitermControllerDidFailToAddFilesToVectorStore(_ sender: AITermController, error: Error) {}
        func aitermController(_ sender: AITermController, willInvokeFunction function: LLM.AnyFunction) {}
        func aitermControllerDidCancelOutstandingRequest(_ sender: AITermController) {}
    }

    private func makeController(model: AIMetadata.Model) throws -> (AITermController, RecordingDelegate) {
        let controller = AITermController(
            registration: try XCTUnwrap(AITermController.Registration(apiKey: "test-key")))
        let delegate = RecordingDelegate()
        controller.delegate = delegate
        controller.providerOverride = LLMProvider(model: model)
        return (controller, delegate)
    }

    private func sse(_ event: String, _ data: String) -> String {
        return "event: \(event)\ndata: \(data)\n\n"
    }

    // A complete Anthropic streamed answer carrying `text`.
    private func anthropicEvents(_ text: String) -> [String] {
        let quoted = String(String(data: try! JSONSerialization.data(withJSONObject: [text]),
                                   encoding: .utf8)!.dropFirst().dropLast())
        return [
            sse("message_start", #"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"claude-opus-4-8","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":1}}}"#),
            sse("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#),
            sse("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":\#(quoted)}}"#),
            sse("content_block_stop", #"{"type":"content_block_stop","index":0}"#),
            sse("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":1,"output_tokens":10}}"#),
            sse("message_stop", #"{"type":"message_stop"}"#),
        ]
    }

    private func delivery(_ text: String) -> iTermAIClient.ReplayDelivery {
        let events = anthropicEvents(text)
        return iTermAIClient.ReplayDelivery(streamChunks: events,
                                            response: WebResponse(data: events.joined(), error: nil),
                                            errorReason: nil)
    }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
    }

    // handle(.begin) defers the send to the next main-queue turn. A cancel in
    // that window must keep the request from going out at all; otherwise it is
    // sent anyway and its reply fires the delegate a second time.
    func testCancelBeforeDeferredSendKeepsRequestFromGoingOut() throws {
        var sends = 0
        iTermAIClient.requestInterceptor = { [unowned self] _, _ in
            sends += 1
            return self.delivery("should never be sent")
        }
        let (controller, delegate) = try makeController(model: AIMetadata.recommendedAnthropicModel)

        controller.request(messages: [LLM.Message(role: .user, content: "A")], stream: true)
        controller.cancelOutstandingOperation()
        drainMainQueue()

        XCTAssertEqual(sends, 0, "a request cancelled before its deferred send must not be sent")
        XCTAssertEqual(delegate.streamed, "")
    }

    // The deleted message's request (A) is cancelled and the next message's
    // request (B) goes out on the same controller while A's words and response
    // are still on their way. B's reply must be B's alone.
    func testLateEventsOfCancelledRequestDoNotLeakIntoNextRequest() throws {
        let (controller, delegate) = try makeController(model: AIMetadata.recommendedAnthropicModel)
        var sends = 0
        iTermAIClient.requestInterceptor = { [unowned self] _, _ in
            sends += 1
            if sends == 1 {
                // A is being sent. (Its state is still .initializedMessages
                // here, so this exercises the generation guards on A's words
                // and response rather than the .querySent cancel arm.) Cancel it and start B before A's events,
                // which the replay delivers after this returns, reach the main
                // queue: B's deferred send is queued ahead of them, so A's
                // events land while B is outstanding.
                controller.cancelOutstandingOperation()
                controller.request(messages: [LLM.Message(role: .user, content: "B")], stream: true)
                return self.delivery("ANSWER_TO_DELETED_A")
            }
            return self.delivery("ANSWER_TO_B")
        }
        let finished = expectation(description: "B's stream ended")
        finished.assertForOverFulfill = false
        delegate.onStreamEnd = { finished.fulfill() }

        controller.request(messages: [LLM.Message(role: .user, content: "A")], stream: true)
        wait(for: [finished], timeout: 5)
        drainMainQueue()

        XCTAssertEqual(sends, 2)
        XCTAssertFalse(delegate.streamed.contains("ANSWER_TO_DELETED_A"),
                       "the cancelled request's reply leaked into the next one: \(delegate.streamed)")
        XCTAssertEqual(delegate.streamed, "ANSWER_TO_B")
        XCTAssertTrue(delegate.errors.isEmpty, "unexpected errors: \(delegate.errors)")
    }

    // Stop or Delete while an attachment uploads cancels the controller in
    // .uploadingFile. That used to be it_fatalError. It must instead fail the
    // upload exactly once and ignore the upload's late response.
    func testCancelDuringFileUploadFailsUploadOnceAndIgnoresLateResponse() throws {
        var model = AIMetadata.recommendedOpenAIModel
        model.api = .responses
        model.vectorStoreConfig = .openAI
        let (controller, delegate) = try makeController(model: model)
        iTermAIClient.requestInterceptor = { _, _ in
            // The controller is now in .uploadingFile. Cancel it the way
            // ChatAgent.stop() does.
            controller.cancelOutstandingOperation()
            return iTermAIClient.ReplayDelivery(streamChunks: [],
                                                response: WebResponse(data: #"{"id":"file-late"}"#, error: nil),
                                                errorReason: nil)
        }
        let delivered = expectation(description: "the upload's late response was delivered")
        iTermAIClient.liveObserver = { _ in delivered.fulfill() }

        controller.request(uploadFileNamed: "a.txt", content: Data("x".utf8))
        // The observer runs in the same main-queue block as the request's
        // completion, so once it fires the late response has been handled.
        wait(for: [delivered], timeout: 5)

        XCTAssertEqual(delegate.uploadFailures.count, 1, "the cancel must fail the upload once")
        XCTAssertTrue(delegate.uploadFailures.first is PendingCommandCanceled)
        XCTAssertEqual(delegate.uploadedIDs, [], "a cancelled upload's late response must be ignored")
    }
    // The upload twin of the deferred-send case: a cancel before the upload is
    // sent must still fail the upload, or the attachment pipeline waits forever.
    func testCancelBeforeDeferredUploadFailsUploadOnce() throws {
        var model = AIMetadata.recommendedOpenAIModel
        model.api = .responses
        model.vectorStoreConfig = .openAI
        let (controller, delegate) = try makeController(model: model)
        var sends = 0
        iTermAIClient.requestInterceptor = { _, _ in
            sends += 1
            return iTermAIClient.ReplayDelivery(streamChunks: [],
                                                response: WebResponse(data: #"{"id":"file-x"}"#, error: nil),
                                                errorReason: nil)
        }
        controller.request(uploadFileNamed: "a.txt", content: Data("x".utf8))
        controller.cancelOutstandingOperation()
        drainMainQueue()

        XCTAssertEqual(sends, 0, "a cancelled upload must not be sent")
        XCTAssertEqual(delegate.uploadFailures.count, 1, "the cancel must fail the upload once")
        XCTAssertTrue(delegate.uploadFailures.first is PendingCommandCanceled)
        XCTAssertEqual(delegate.uploadedIDs, [])
    }
}
