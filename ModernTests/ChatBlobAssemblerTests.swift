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

    // MARK: - Send path (frozen history spliced into the real builder)

    private func builder(_ model: AIMetadata.Model, messages: [LLM.Message], frozen: Data?) -> LLMRequestBuilder {
        LLMRequestBuilder(provider: LLMProvider(model: model), apiKey: "test-key", messages: messages,
                          functions: [], stream: false, hostedTools: HostedTools(), previousResponseID: nil,
                          shouldThink: nil, reasoningEffort: nil, serviceTier: nil, trailingVolatileText: nil,
                          frozenHistoryElements: frozen)
    }
    private func messagesArray(_ builder: LLMRequestBuilder, key: String) throws -> [Any] {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: builder.body()) as? [String: Any])
        return try XCTUnwrap(body[key] as? [Any])
    }

    /// The whole point of the send path: a blob-native request (envelope + new turn,
    /// history spliced from stored blobs) must produce the SAME messages array as a
    /// live request built from the full [LLM.Message] history.
    func test_sendPath_chatCompletions_messagesMatchLiveFullHistory() throws {
        var model = try baseModel()
        model.api = .chatCompletions
        let priorConvo = plainRound + toolRound   // two finished rounds, frozen as blobs
        let db = try makeTempDB()
        ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: priorConvo, api: .chatCompletions,
                                         modelName: model.name, hostedTools: HostedTools(), database: db)
        let inner = try ChatBlobAssembler.stitchInner(db.blobs(inChat: "A"))

        let system = LLM.Message(role: .system, content: "You are helpful.")
        let newUser = user("what's next?")

        let blobNative = try messagesArray(builder(model, messages: [system, newUser], frozen: inner),
                                           key: "messages")
        let live = try messagesArray(builder(model, messages: [system] + priorConvo + [newUser], frozen: nil),
                                     key: "messages")
        XCTAssertEqual(blobNative as NSArray, live as NSArray,
                       "blob-native spliced messages must equal the live full-history messages array")
    }

    /// With no system message, the history splices at the very start of the array.
    func test_sendPath_chatCompletions_noSystem_messagesMatchLive() throws {
        var model = try baseModel()
        model.api = .chatCompletions
        let priorConvo = plainRound + plainRound
        let db = try makeTempDB()
        ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: priorConvo, api: .chatCompletions,
                                         modelName: model.name, hostedTools: HostedTools(), database: db)
        let inner = try ChatBlobAssembler.stitchInner(db.blobs(inChat: "A"))
        let newUser = user("more?")
        let blobNative = try messagesArray(builder(model, messages: [newUser], frozen: inner), key: "messages")
        let live = try messagesArray(builder(model, messages: priorConvo + [newUser], frozen: nil), key: "messages")
        XCTAssertEqual(blobNative as NSArray, live as NSArray)
    }

    /// Blob-native spliced body's message array == the live full-history body's,
    /// for a protocol whose message array is at `key`.
    private func assertSendPathMatches(_ api: iTermAIAPI, key: String,
                                       file: StaticString = #filePath, line: UInt = #line) throws {
        var model = try baseModel()
        model.api = api
        let priorConvo = plainRound + toolRound
        let db = try makeTempDB()
        ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: priorConvo, api: api,
                                         modelName: model.name, hostedTools: HostedTools(), database: db)
        let inner = try ChatBlobAssembler.stitchInner(db.blobs(inChat: "A"))
        let system = LLM.Message(role: .system, content: "You are helpful.")
        let newUser = user("what's next?")
        let blobNative = try messagesArray(builder(model, messages: [system, newUser], frozen: inner), key: key)
        let live = try messagesArray(builder(model, messages: [system] + priorConvo + [newUser], frozen: nil), key: key)
        XCTAssertEqual(blobNative as NSArray, live as NSArray,
                       "blob-native spliced \(key) must equal the live full-history \(key) for \(api.rawValue)",
                       file: file, line: line)
    }

    func test_sendPath_llama_messagesMatch() throws { try assertSendPathMatches(.llama, key: "messages") }
    func test_sendPath_earlyO1_messagesMatch() throws { try assertSendPathMatches(.earlyO1, key: "messages") }
    func test_sendPath_deepSeek_messagesMatch() throws { try assertSendPathMatches(.deepSeek, key: "messages") }

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

    // MARK: - Byte-level stitch (verbatim, for cache byte-stability)

    func test_stitchBytes_singleBlob_isVerbatim() throws {
        let db = try makeTempDB()
        ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: plainRound, api: .chatCompletions,
                                         modelName: nil, hostedTools: HostedTools(), database: db)
        let blob = try XCTUnwrap(db.blobs(inChat: "A").first)
        XCTAssertEqual(try ChatBlobAssembler.stitchBytes([blob]), blob.payload,
                       "one blob's bytes must be reproduced verbatim")
    }

    func test_stitchBytes_parsesToSameAsObjectStitch() throws {
        let db = try makeTempDB()
        let convo = plainRound + toolRound + plainRound
        ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: convo, api: .anthropic,
                                         modelName: nil, hostedTools: HostedTools(), database: db)
        let blobs = db.blobs(inChat: "A")
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: try ChatBlobAssembler.stitchBytes(blobs)) as? [Any])
        XCTAssertEqual(parsed as NSArray, try ChatBlobAssembler.stitch(blobs) as NSArray)
    }

    /// Each blob's inner bytes must appear UNCHANGED in the concatenation (that is
    /// the byte-prefix stability Anthropic's cache needs; a JSON round-trip could
    /// reorder keys and break it).
    func test_stitchBytes_preservesEachBlobsBytesVerbatim() throws {
        let db = try makeTempDB()
        ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: plainRound + toolRound, api: .anthropic,
                                         modelName: nil, hostedTools: HostedTools(), database: db)
        let blobs = db.blobs(inChat: "A")
        let bytes = try ChatBlobAssembler.stitchBytes(blobs)
        for blob in blobs {
            let inner = blob.payload.subdata(in: (blob.payload.startIndex + 1)..<(blob.payload.endIndex - 1))
            XCTAssertNotNil(bytes.range(of: inner),
                            "each blob's inner bytes must appear verbatim in the stitched output")
        }
    }

    func test_stitchBytes_empty_isEmptyArray() throws {
        XCTAssertEqual(try ChatBlobAssembler.stitchBytes([]), Data("[]".utf8))
    }

    func test_stitchBytes_corrupt_throws() throws {
        let db = try makeTempDB()
        db.appendBlob(ChatBlob(chatID: "A", blobProtocol: .anthropic, role: .user,
                               payload: Data("garbage".utf8)))
        XCTAssertThrowsError(try ChatBlobAssembler.stitchBytes(db.blobs(inChat: "A")))
    }

    // MARK: - The safety gate (stitchedHistoryIfSafe)

    func test_safe_noBlobs_returnsNil() throws {
        let db = try makeTempDB()
        XCTAssertNil(ChatBlobAssembler.stitchedHistoryIfSafe(chatID: "A", expectedProtocol: .anthropic, database: db),
                     "a blobless (legacy) chat must fall back to the codec")
    }

    func test_safe_healthy_returnsStitchedHistory() throws {
        let db = try makeTempDB()
        let convo = plainRound + toolRound
        ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: convo, api: .chatCompletions,
                                         modelName: nil, hostedTools: HostedTools(), database: db)
        let safe = try XCTUnwrap(ChatBlobAssembler.stitchedHistoryIfSafe(
            chatID: "A", expectedProtocol: .chatCompletions, database: db))
        let direct = try ChatBlobAssembler.stitch(db.blobs(inChat: "A"))
        XCTAssertEqual(safe as NSArray, direct as NSArray)
    }

    /// A structurally corrupt row (here: a non-UUID blobID) fails to decode, so
    /// blobs(inChat:) is SHORTER than the stored row count. Splicing the survivors
    /// would send a holed conversation, so the count-mismatch guard must refuse.
    func test_safe_structurallyCorruptRow_refuses() throws {
        let db = try makeTempDB()
        db.appendBlob(ChatBlob(chatID: "A", blobProtocol: .chatCompletions, role: .user,
                               payload: Data("[]".utf8)))
        try db.db.executeUpdate(
            "insert into ChatBlob (blobID, chatID, blobProtocol, role, payload) values (?, ?, ?, ?, ?)",
            withArguments: ["not-a-uuid", "A", 1, "user", Data("[]".utf8)])
        XCTAssertEqual(db.blobCount(inChat: "A"), 2)
        XCTAssertEqual(db.blobs(inChat: "A").count, 1, "the corrupt-blobID row is dropped on decode")
        XCTAssertNil(ChatBlobAssembler.stitchedHistoryIfSafe(chatID: "A", expectedProtocol: .chatCompletions, database: db),
                     "must refuse rather than splice a holed history")
    }

    /// An unknown-protocol row (raw 99) DECODES (NS_ENUM accepts any raw), but its
    /// protocol can't equal the turn's protocol, so the protocol check refuses it
    /// (a future-iTerm2 blob opened by this build).
    func test_safe_unknownProtocolRow_refuses() throws {
        let db = try makeTempDB()
        db.appendBlob(ChatBlob(chatID: "A", blobProtocol: .chatCompletions, role: .user,
                               payload: Data("[]".utf8)))
        try db.db.executeUpdate(
            "insert into ChatBlob (blobID, chatID, blobProtocol, role, payload) values (?, ?, ?, ?, ?)",
            withArguments: [UUID().uuidString, "A", 99, "user", Data("[]".utf8)])
        XCTAssertNil(ChatBlobAssembler.stitchedHistoryIfSafe(chatID: "A", expectedProtocol: .chatCompletions, database: db),
                     "a blob under an unknown protocol is not spliceable for this turn")
    }

    func test_safe_protocolMismatch_refuses() throws {
        let db = try makeTempDB()
        ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: plainRound, api: .chatCompletions,
                                         modelName: nil, hostedTools: HostedTools(), database: db)
        XCTAssertNil(ChatBlobAssembler.stitchedHistoryIfSafe(chatID: "A", expectedProtocol: .responses, database: db),
                     "blobs frozen under a different protocol are not spliceable for this turn")
    }

    func test_safe_corruptPayload_refuses() throws {
        let db = try makeTempDB()
        db.appendBlob(ChatBlob(chatID: "A", blobProtocol: .anthropic, role: .user,
                               payload: Data("garbage".utf8)))
        XCTAssertNil(ChatBlobAssembler.stitchedHistoryIfSafe(chatID: "A", expectedProtocol: .anthropic, database: db))
    }
}
