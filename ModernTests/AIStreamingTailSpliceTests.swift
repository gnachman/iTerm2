//
//  AIStreamingTailSpliceTests.swift
//  iTerm2 ModernTests
//
//  Confirms the streamed-vs-authoritative "tail recovery" duplication bug
//  suspected behind duplicate/garbled chat messages (analysis item 4,
//  symptom A/B at sub-message granularity).
//
//  When a streamed answer finalizes, AITermController reconciles the live
//  streamed text against the reparsed authoritative response body. The
//  recovery step (AITerm.swift, in parseStreamingResponse(final:)) is:
//
//      if let fullText = authoritative?.body.maybeContent,
//         fullText.count > streamedText.count {
//          let tail = String(fullText.dropFirst(streamedText.count))
//          ... streamedText += tail; didStreamUpdate(tail)
//      }
//
//  dropFirst(streamedText.count) assumes the live streamed text is a
//  character-count PREFIX of the authoritative body. That holds for the
//  common race (the completion beat the last deltas, so the streamed text is
//  a true prefix and the missing suffix is appended). But when the two
//  diverge in ordering, whitespace, or across text content-blocks, dropping
//  N leading characters splices an overlapping fragment onto the end of the
//  one streamed bubble, so the finalized message duplicates/garbles text.
//
//  These tests pin the current behavior deterministically via the replay
//  harness. test_divergentBody_ pins the BUGGY output; when the finalization
//  is fixed to reconcile against the authoritative body, flip its expected
//  value to the authoritative string. test_alignedBody_ documents the
//  correct behavior on the common (prefix) race so a fix must preserve it.
//

import XCTest
@testable import iTerm2SharedARC

final class AIStreamingTailSpliceTests: XCTestCase {

    override func tearDown() {
        iTermAIClient.requestInterceptor = nil
        super.tearDown()
    }

    private func sse(_ event: String, _ data: String) -> String {
        return "event: \(event)\ndata: \(data)\n\n"
    }

    // Accumulates every non-nil didStreamUpdate so the test can reconstruct
    // the exact text of the single finalized bubble, and signals when the
    // turn ends (didStreamUpdate(nil)).
    private final class AccumulatingDelegate: AITermControllerDelegate {
        var streamed = ""
        var onStreamEnd: (() -> Void)?
        var onError: ((Error) -> Void)?
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

    // A text answer whose incremental stream is truncated (no terminating
    // message_stop), so finalization reconciles against the authoritative
    // body, which is the path that runs the tail-recovery splice. `streamedText` is
    // what the deltas carry; `bodyText` is the authoritative text the
    // reparsed complete body carries.
    private func runFinalization(streamedText: String, bodyText: String) throws -> String {
        func textEvents(_ text: String, terminated: Bool) -> [String] {
            var events = [
                sse("message_start", #"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"claude-opus-4-8","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":1}}}"#),
                sse("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#),
                sse("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":\#(jsonString(text))}}"#),
                sse("content_block_stop", #"{"type":"content_block_stop","index":0}"#),
            ]
            if terminated {
                events.append(sse("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"input_tokens":1,"output_tokens":10}}"#))
                events.append(sse("message_stop", #"{"type":"message_stop"}"#))
            }
            return events
        }

        // Incremental channel: streamed text, truncated before message_stop.
        let streamChunks = textEvents(streamedText, terminated: false)
        // Authoritative body: a complete, terminated response carrying the
        // (possibly divergent) authoritative text.
        let fullBody = textEvents(bodyText, terminated: true).joined()

        iTermAIClient.requestInterceptor = { _, _ in
            iTermAIClient.ReplayDelivery(
                streamChunks: streamChunks,
                response: WebResponse(data: fullBody, error: nil),
                errorReason: nil)
        }

        let controller = AITermController(
            registration: try XCTUnwrap(AITermController.Registration(apiKey: "test-key")))
        let delegate = AccumulatingDelegate()
        controller.delegate = delegate
        controller.providerOverride = LLMProvider(model: AIMetadata.recommendedAnthropicModel)

        let finished = expectation(description: "turn finalized")
        finished.assertForOverFulfill = false
        delegate.onStreamEnd = { finished.fulfill() }
        delegate.onError = { error in XCTFail("controller reported an error: \(error)") }

        controller.request(
            messages: [LLM.Message(role: .user, content: "say something")],
            stream: true)

        wait(for: [finished], timeout: 5.0)
        return delegate.streamed
    }

    // Minimal JSON string encoder for embedding a value in the SSE fixtures.
    private func jsonString(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s], options: [])
        let array = String(data: data, encoding: .utf8)!  // ["..."]
        return String(array.dropFirst().dropLast())        // "..."
    }

    // The common race: the streamed text is a true prefix of the
    // authoritative body, so the recovery appends exactly the missing
    // suffix. This is correct today and a fix must keep it working.
    func test_alignedBody_appendsCleanTail() throws {
        let final = try runFinalization(streamedText: "Hello", bodyText: "Hello world")
        XCTAssertEqual(final, "Hello world")
    }

    // The bug: the streamed text is NOT a prefix of the authoritative body
    // (here they diverge from the second character on). dropFirst(count)
    // drops 11 leading characters of "Hi world, hello" and appends the
    // overlapping remainder "ello" to the already-streamed "Hello world",
    // yielding a garbled, partially-duplicated bubble.
    //
    // This pins the CURRENT (buggy) output. The correct finalized text is
    // the authoritative body, "Hi world, hello"; when the finalization is
    // fixed to reconcile against the body rather than blindly appending a
    // count-based tail, change the expected value below.
    func test_divergentBody_producesGarbledDuplication() throws {
        let streamed = "Hello world"       // 11 chars
        let body = "Hi world, hello"       // 15 chars, not prefixed by `streamed`
        let final = try runFinalization(streamedText: streamed, bodyText: body)

        // Demonstrates the defect: the finalized bubble is neither the
        // streamed text nor the authoritative body, but a garbled splice.
        XCTAssertEqual(final, "Hello worldello",
                       "Tail-recovery spliced an overlapping fragment instead of "
                       + "reconciling against the authoritative body.")
        XCTAssertNotEqual(final, body,
                          "BUG: the finalized bubble does not match the authoritative "
                          + "response body when the streamed text diverges from it.")
    }
}
