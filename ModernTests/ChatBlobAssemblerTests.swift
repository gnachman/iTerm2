//
//  ChatBlobAssemblerTests.swift
//  iTerm2 ModernTests
//
//  The end-to-end round-trip proof for the blob redesign: capture a multi-round
//  conversation into stored blobs, stitch them back, and assert the result equals
//  what the LIVE per-vendor builder produces for the whole conversation at once.
//  This ties capture (ChatBlobCapture) + storage (ChatDatabase) + the JSON-level
//  merge (ChatBlobAssembler) together and confirms replay is byte-faithful across
//  the DB, not just at the encoder level.
//

import XCTest
@testable import iTerm2SharedARC

final class ChatBlobAssemblerTests: XCTestCase {

    // MARK: - Fixtures

    private func user(_ s: String) -> LLM.Message { LLM.Message(role: .user, content: s) }
    private func asst(_ s: String) -> LLM.Message { LLM.Message(role: .assistant, content: s) }
    private func toolCall(name: String, args: String, callID: String) -> LLM.Message {
        LLM.Message(role: .assistant,
                    function_call: LLM.FunctionCall(name: name, arguments: args, id: callID, thoughtSignature: nil))
    }
    private func toolResult(name: String, output: String, callID: String) -> LLM.Message {
        LLM.Message(role: .function, content: output, name: name,
                    functionCallID: LLM.Message.FunctionCallID(callID: callID, itemID: ""))
    }

    private var plainRound: [LLM.Message] { [user("hi"), asst("hello there")] }
    private var toolRound: [LLM.Message] {
        [user("weather in Paris?"), asst("Let me check."),
         toolCall(name: "get_weather", args: "{\"location\":\"Paris\"}", callID: "call_1"),
         toolResult(name: "get_weather", output: "Sunny, 20C", callID: "call_1"),
         asst("It's sunny and 20C in Paris.")]
    }

    // MARK: - Live-builder ground truth (shared with the encoder tests)

    private func baseModel() throws -> AIMetadata.Model {
        guard let m = AIMetadata.instance.models.first else { throw XCTSkip("empty AIMetadata catalog") }
        return m
    }
    private func wireKey(_ api: iTermAIAPI) -> String {
        switch api {
        case .gemini: return "contents"
        case .responses: return "input"
        default: return "messages"
        }
    }
    private func makeTempDB() throws -> ChatDatabase {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("chatblobasm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
    }

    /// Capture the rounds into a temp DB, stitch them back, and compare to the live
    /// builder's whole-conversation message array. For Anthropic the live body adds
    /// a cache marker to the last message (assembly-time envelope), so the ground
    /// truth is convertMessages (the unmarked array the encoder freezes); for the
    /// others the stitched array equals the live body's message array directly.
    private func assertRoundTrip(_ api: iTermAIAPI, _ rounds: [[LLM.Message]],
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        var model = try baseModel()
        model.api = api
        let convo = rounds.flatMap { $0 }
        let db = try makeTempDB()
        ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: convo, api: api,
                                         modelName: model.name, hostedTools: HostedTools(), database: db)
        // One blob per round was stored.
        XCTAssertEqual(db.blobCount(inChat: "A"), rounds.count, file: file, line: line)

        let stitched = try ChatBlobAssembler.stitch(db.blobs(inChat: "A"))

        let expected: [Any]
        if api == .anthropic {
            let data = try JSONEncoder().encode(AnthropicRequestBuilder.convertMessages(convo))
            expected = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])
        } else {
            let builder = LLMRequestBuilder(
                provider: LLMProvider(model: model), apiKey: "test-key", messages: convo,
                functions: [], stream: false, hostedTools: HostedTools(), previousResponseID: nil,
                shouldThink: nil, reasoningEffort: nil, serviceTier: nil, trailingVolatileText: nil)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: builder.body()) as? [String: Any])
            expected = try XCTUnwrap(body[wireKey(api)] as? [Any])
        }
        XCTAssertEqual(stitched as NSArray, expected as NSArray,
                       "stitch(captured blobs) must equal the live \(api.rawValue) builder's whole-conversation array",
                       file: file, line: line)
    }

    // MARK: - Round-trip across every protocol

    func test_roundTrip_anthropic() throws { try assertRoundTrip(.anthropic, [plainRound, toolRound, plainRound]) }
    func test_roundTrip_chatCompletions() throws { try assertRoundTrip(.chatCompletions, [plainRound, toolRound, plainRound]) }
    func test_roundTrip_llama() throws { try assertRoundTrip(.llama, [plainRound, toolRound, plainRound]) }
    func test_roundTrip_earlyO1() throws { try assertRoundTrip(.earlyO1, [plainRound, toolRound, plainRound]) }
    func test_roundTrip_deepSeek() throws { try assertRoundTrip(.deepSeek, [plainRound, toolRound, plainRound]) }
    func test_roundTrip_gemini() throws { try assertRoundTrip(.gemini, [plainRound, toolRound, plainRound]) }
    func test_roundTrip_responses() throws { try assertRoundTrip(.responses, [plainRound, toolRound, plainRound]) }

    // MARK: - Integrity

    func test_stitch_corruptPayload_throws() throws {
        let db = try makeTempDB()
        db.appendBlob(ChatBlob(chatID: "A", blobProtocol: .chatCompletions, role: .user,
                               payload: Data("not a json array".utf8)))
        XCTAssertThrowsError(try ChatBlobAssembler.stitch(db.blobs(inChat: "A"))) { error in
            guard case ChatBlobAssemblerError.corruptPayload = error else {
                return XCTFail("expected corruptPayload; got \(error)")
            }
        }
    }

    func test_stitch_empty_isEmpty() throws {
        XCTAssertTrue(try ChatBlobAssembler.stitch([]).isEmpty)
    }
}
