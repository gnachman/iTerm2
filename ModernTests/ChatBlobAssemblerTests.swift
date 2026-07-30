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
    func test_sendPath_anthropic_messagesMatch() throws { try assertSendPathMatches(.anthropic, key: "messages") }
    func test_sendPath_gemini_contentsMatch() throws { try assertSendPathMatches(.gemini, key: "contents") }
    func test_sendPath_responses_inputMatch() throws { try assertSendPathMatches(.responses, key: "input") }

    /// Truncation + reduction compose. When truncation drops the oldest `dropCount`
    /// head blobs (whole rounds) from the frozen bytes, the message reduction still
    /// peels ALL N frozen rounds and keeps only the current round (dropCount selects
    /// which BLOBS splice, not which messages reduce). The result must reproduce the
    /// live builder fed the TRUNCATED history (oldest dropCount rounds removed).
    /// This guards the dropCount <-> frozenRoundCount alignment: an off-by-one would
    /// drop or duplicate a round at the splice boundary.
    func test_sendPath_truncatedReplay_matchesTruncatedLiveHistory() throws {
        var model = try baseModel()
        model.api = .chatCompletions
        let r0 = plainRound, r1 = toolRound, r2 = plainRound  // three frozen rounds
        let priorConvo = r0 + r1 + r2
        let db = try makeTempDB()
        ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: priorConvo, api: .chatCompletions,
                                         modelName: model.name, hostedTools: HostedTools(), database: db)
        let blobs = db.blobs(inChat: "A")
        XCTAssertEqual(blobs.count, 3)

        let system = LLM.Message(role: .system, content: "You are helpful.")
        let newUser = user("what's next?")
        let full = [system] + priorConvo + [newUser]

        let dropCount = 1  // truncation drops the oldest round
        let frozen = try ChatBlobAssembler.stitchInner(Array(blobs[dropCount...]))
        // Reduction peels all N frozen rounds regardless of dropCount.
        let reduced = try XCTUnwrap(ChatBlobAssembler.messagesPastFrozenRounds(full, frozenRoundCount: blobs.count))

        let blobNative = try messagesArray(builder(model, messages: reduced, frozen: frozen), key: "messages")
        let truncatedLive = [system] + r1 + r2 + [newUser]  // oldest round removed
        let live = try messagesArray(builder(model, messages: truncatedLive, frozen: nil), key: "messages")
        XCTAssertEqual(blobNative as NSArray, live as NSArray,
                       "truncated blob replay must equal the live builder fed the truncated history")
    }

    // MARK: - forkBlobPrefix (fork blob inheritance)

    private func blob(_ chatID: String) -> ChatBlob {
        ChatBlob(chatID: chatID, blobProtocol: .anthropic, role: .user, payload: Data("[]".utf8))
    }

    /// A fully-linked retained prefix returns exactly those source blobs, in order.
    func test_forkBlobPrefix_cleanPrefix_returnsIt() {
        let b0 = blob("A"), b1 = blob("A"), b2 = blob("A")
        let source = [b0, b1, b2]
        let retained = [b0.blobID.uuidString, b1.blobID.uuidString]  // fork keeps first two rounds
        let result = ChatBlobAssembler.forkBlobPrefix(sourceBlobs: source, retainedBlobRefs: retained)
        XCTAssertEqual(result?.map { $0.blobID }, [b0.blobID, b1.blobID])
    }

    /// No retained refs (nothing linked, e.g. a migration-era prefix) -> copy nothing.
    func test_forkBlobPrefix_noRefs_returnsNil() {
        XCTAssertNil(ChatBlobAssembler.forkBlobPrefix(sourceBlobs: [blob("A")], retainedBlobRefs: []))
    }

    /// Refs that don't match the source's blob prefix in order (a gap, or a reordered
    /// / migration-unlinked head) must refuse rather than copy a misaligned set.
    func test_forkBlobPrefix_mismatch_returnsNil() {
        let b0 = blob("A"), b1 = blob("A")
        // retained ref points at b1 as the FIRST retained round, but the source prefix
        // starts with b0 -> not a clean prefix.
        XCTAssertNil(ChatBlobAssembler.forkBlobPrefix(sourceBlobs: [b0, b1],
                                                      retainedBlobRefs: [b1.blobID.uuidString]))
    }

    /// More retained refs than source blobs (impossible clean prefix) -> nil.
    func test_forkBlobPrefix_moreRefsThanBlobs_returnsNil() {
        let b0 = blob("A")
        XCTAssertNil(ChatBlobAssembler.forkBlobPrefix(sourceBlobs: [b0],
                                                      retainedBlobRefs: [b0.blobID.uuidString, UUID().uuidString]))
    }

    // MARK: - AIConversation pre-reduce bail (must not drop the current round)

    /// When the chat layer pre-reduces conversation.messages to the current round and
    /// the blob path then DECLINES (protocol switch / oversized round / corrupt blob),
    /// the fallback rebuilds the full history from fullHistoryProvider -- which yields
    /// only the PRIOR rounds (translate(history) excludes the current turn). The
    /// outgoing request must therefore be prior + current, never prior alone, or it
    /// would resend the previous conversation with no new question.
    @MainActor
    func test_outgoingRequest_preReduceBail_includesCurrentRound() {
        var convo = AIConversation(registrationProvider: nil, messages: [])
        let currentUser = user("the NEW question")
        convo.messages = [currentUser]  // pre-reduced: current round only
        let prior = [user("old q"), asst("old a")]
        convo.controller.blobReplayProvider = { _ in nil }   // force the blob path to bail
        convo.controller.fullHistoryProvider = { prior }     // prior rounds only (excludes current)

        let out = convo.outgoingRequestForTesting()
        XCTAssertEqual(out.messages, prior + [currentUser],
                       "bail must send prior rounds AND the current round")
        XCTAssertNil(out.frozen)
    }

    // MARK: - blobReplayPlan (full send decision: gate + reduce + truncate + splice)

    private func capture3Rounds(_ db: ChatDatabase, model: AIMetadata.Model) -> [[LLM.Message]] {
        let rounds = [plainRound, toolRound, plainRound]
        ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: rounds.flatMap { $0 },
                                         api: model.api, modelName: model.name,
                                         hostedTools: HostedTools(), database: db)
        return rounds
    }

    /// Under budget: no truncation. The plan returns [system, newUser] and the whole
    /// frozen history (all blobs), and byte-matches the live full-history builder.
    func test_blobReplayPlan_underBudget_keepsAllBlobs() throws {
        var model = try baseModel(); model.api = .chatCompletions
        let db = try makeTempDB()
        let rounds = capture3Rounds(db, model: model)
        let system = LLM.Message(role: .system, content: "You are helpful.")
        let newUser = user("next?")
        let full = [system] + rounds.flatMap { $0 } + [newUser]

        let plan = try XCTUnwrap(ChatBlobAssembler.blobReplayPlan(
            chatID: "A", fullMessages: full, expectedProtocol: .chatCompletions,
            contextWindow: 1_000_000, outputReserve: 1000, policy: .fitOnly,
            tokenEstimate: { _ in 1 }, envelopeTokens: { 0 }, database: db))
        XCTAssertEqual(plan.messages, [system, newUser])
        XCTAssertEqual(plan.frozen, try ChatBlobAssembler.stitchInner(db.blobs(inChat: "A")))
    }

    /// messagesAreReduced=true: the chat layer already pre-reduced `fullMessages` to
    /// [system, newUser] (skipping the wasted translate of the frozen prefix), so the
    /// plan must NOT drop any round from the list (frozenRoundCount 0). It returns the
    /// pre-reduced list unchanged plus ALL blobs, and its wire is byte-identical to the
    /// non-pre-reduced plan fed the whole conversation -- proving the fast path sends
    /// exactly what the full path would.
    func test_blobReplayPlan_messagesAreReduced_matchesFullPath() throws {
        var model = try baseModel(); model.api = .chatCompletions
        let db = try makeTempDB()
        let rounds = capture3Rounds(db, model: model)
        let system = LLM.Message(role: .system, content: "You are helpful.")
        let newUser = user("next?")

        // The full path: hand the whole conversation, let the plan reduce it.
        let fullPath = try XCTUnwrap(ChatBlobAssembler.blobReplayPlan(
            chatID: "A", fullMessages: [system] + rounds.flatMap { $0 } + [newUser],
            expectedProtocol: .chatCompletions,
            contextWindow: 1_000_000, outputReserve: 1000, policy: .fitOnly,
            tokenEstimate: { _ in 1 }, envelopeTokens: { 0 }, database: db))

        // The fast path: hand the pre-reduced list, tell the plan not to reduce again.
        let reducedPath = try XCTUnwrap(ChatBlobAssembler.blobReplayPlan(
            chatID: "A", fullMessages: [system, newUser], expectedProtocol: .chatCompletions,
            contextWindow: 1_000_000, outputReserve: 1000, policy: .fitOnly,
            messagesAreReduced: true,
            tokenEstimate: { _ in 1 }, envelopeTokens: { 0 }, database: db))

        XCTAssertEqual(reducedPath.messages, [system, newUser])
        XCTAssertEqual(reducedPath.messages, fullPath.messages)
        XCTAssertEqual(reducedPath.frozen, fullPath.frozen)
        let reducedWire = try messagesArray(builder(model, messages: reducedPath.messages, frozen: reducedPath.frozen), key: "messages")
        let fullWire = try messagesArray(builder(model, messages: fullPath.messages, frozen: fullPath.frozen), key: "messages")
        XCTAssertEqual(reducedWire as NSArray, fullWire as NSArray)
    }

    /// Over budget: drops the oldest whole round and the result byte-matches the live
    /// builder fed the TRUNCATED history (composes reduction + truncation + splice).
    func test_blobReplayPlan_overBudget_dropsOldestRound_matchesTruncatedLive() throws {
        var model = try baseModel(); model.api = .chatCompletions
        let db = try makeTempDB()
        let rounds = capture3Rounds(db, model: model)  // r0, r1, r2
        let system = LLM.Message(role: .system, content: "You are helpful.")
        let newUser = user("next?")
        let full = [system] + rounds.flatMap { $0 } + [newUser]

        // fit budget = 1000 - 100 = 900; each blob weighs 300 -> 900 + tail > 900 -> drop 1.
        let plan = try XCTUnwrap(ChatBlobAssembler.blobReplayPlan(
            chatID: "A", fullMessages: full, expectedProtocol: .chatCompletions,
            contextWindow: 1000, outputReserve: 100, policy: .fitOnly,
            tokenEstimate: { _ in 300 }, envelopeTokens: { 0 }, database: db))
        XCTAssertEqual(plan.frozen, try ChatBlobAssembler.stitchInner(Array(db.blobs(inChat: "A")[1...])),
                       "oldest blob dropped from the frozen bytes")
        let blobNative = try messagesArray(builder(model, messages: plan.messages, frozen: plan.frozen), key: "messages")
        let truncatedLive = [system] + rounds[1] + rounds[2] + [newUser]
        let live = try messagesArray(builder(model, messages: truncatedLive, frozen: nil), key: "messages")
        XCTAssertEqual(blobNative as NSArray, live as NSArray)
    }

    /// envelopeTokens (tool schemas + volatile context the builder adds at send
    /// time, not in `reduced`) folds into the budget: the SAME conversation that fits
    /// with a zero envelope must truncate once a large envelope is counted. Guards
    /// the finding that omitting it could send an over-window request with no
    /// fallback (the frozen prefix is bounded ONLY here).
    func test_blobReplayPlan_envelopeTokensCountedInBudget() throws {
        var model = try baseModel(); model.api = .chatCompletions
        let db = try makeTempDB()
        let rounds = capture3Rounds(db, model: model)
        let system = LLM.Message(role: .system, content: "You are helpful.")
        let full = [system] + rounds.flatMap { $0 } + [user("next?")]

        // Weights sum to 600 (3 x 200); fit budget = 1000 - 100 = 900. With no
        // envelope the whole history fits (no drop). With a 400-token envelope,
        // 600 + 400 + tail > 900 -> a head blob must be dropped.
        let noEnvelope = try XCTUnwrap(ChatBlobAssembler.blobReplayPlan(
            chatID: "A", fullMessages: full, expectedProtocol: .chatCompletions,
            contextWindow: 1000, outputReserve: 100, policy: .fitOnly,
            tokenEstimate: { _ in 200 }, envelopeTokens: { 0 }, database: db))
        XCTAssertEqual(noEnvelope.frozen, try ChatBlobAssembler.stitchInner(db.blobs(inChat: "A")),
                       "with no envelope the whole history fits")

        let withEnvelope = try XCTUnwrap(ChatBlobAssembler.blobReplayPlan(
            chatID: "A", fullMessages: full, expectedProtocol: .chatCompletions,
            contextWindow: 1000, outputReserve: 100, policy: .fitOnly,
            tokenEstimate: { _ in 200 }, envelopeTokens: { 400 }, database: db))
        XCTAssertEqual(withEnvelope.frozen, try ChatBlobAssembler.stitchInner(Array(db.blobs(inChat: "A")[1...])),
                       "counting the envelope forces the oldest round to be dropped")
    }

    /// The tail alone exceeds the budget: even dropping every blob can't fit, so the
    /// plan refuses (nil) and the caller falls back to the codec's in-message elision.
    func test_blobReplayPlan_tailOverBudget_returnsNil() throws {
        var model = try baseModel(); model.api = .chatCompletions
        let db = try makeTempDB()
        let rounds = capture3Rounds(db, model: model)
        let system = LLM.Message(role: .system, content: "You are helpful.")
        let full = [system] + rounds.flatMap { $0 } + [user("next?")]
        // contextWindow tiny so fixedCost (the reduced tail) alone exceeds fit budget.
        XCTAssertNil(ChatBlobAssembler.blobReplayPlan(
            chatID: "A", fullMessages: full, expectedProtocol: .chatCompletions,
            contextWindow: 4, outputReserve: 2, policy: .fitOnly,
            tokenEstimate: { _ in 1 }, envelopeTokens: { 0 }, database: db))
    }

    /// A protocol mismatch (blobs frozen under a different protocol) fails the safety
    /// gate, so the plan refuses.
    func test_blobReplayPlan_protocolMismatch_returnsNil() throws {
        var model = try baseModel(); model.api = .chatCompletions
        let db = try makeTempDB()
        _ = capture3Rounds(db, model: model)  // frozen as chatCompletions
        let system = LLM.Message(role: .system, content: "s")
        let full = [system] + [user("next?")]
        XCTAssertNil(ChatBlobAssembler.blobReplayPlan(
            chatID: "A", fullMessages: full, expectedProtocol: .responses,  // mismatch
            contextWindow: 1_000_000, outputReserve: 1000, policy: .fitOnly,
            tokenEstimate: { _ in 1 }, envelopeTokens: { 0 }, database: db))
    }

    // MARK: - messagesPastFrozenRounds (the send-time reduction)

    /// The reduction the controller applies before splicing frozen bytes: from the
    /// full outgoing [system, ...all rounds..., current-round-partial], keep the
    /// leading system message(s) and only the rounds PAST the frozen ones. Its
    /// output, spliced with the frozen bytes, is what the send-path parity tests
    /// prove equals the live full-history request.
    func test_messagesPastFrozenRounds_dropsFrozenKeepsSystemAndTail() throws {
        let system = LLM.Message(role: .system, content: "sys")
        let full = [system] + plainRound + toolRound + [user("now")]  // 2 frozen rounds + current
        let reduced = try XCTUnwrap(ChatBlobAssembler.messagesPastFrozenRounds(full, frozenRoundCount: 2))
        XCTAssertEqual(reduced.first?.role, .system)
        XCTAssertEqual(reduced.dropFirst().map { $0 }, [user("now")],
                       "the two finished rounds are dropped; only system + the current round remain")
    }

    /// A current round mid-tool-loop (user + preamble + tool_use + tool_result) is
    /// kept whole as the tail; the frozen prefix is still dropped.
    func test_messagesPastFrozenRounds_keepsPartialCurrentRound() throws {
        let system = LLM.Message(role: .system, content: "sys")
        let full = [system] + plainRound + toolRound  // 1 frozen round + an in-progress tool round
        let reduced = try XCTUnwrap(ChatBlobAssembler.messagesPastFrozenRounds(full, frozenRoundCount: 1))
        XCTAssertEqual(reduced, [system] + toolRound)
    }

    /// No system message: reduction still drops the frozen rounds.
    func test_messagesPastFrozenRounds_noSystem() throws {
        let full = plainRound + plainRound + [user("q3")]
        let reduced = try XCTUnwrap(ChatBlobAssembler.messagesPastFrozenRounds(full, frozenRoundCount: 2))
        XCTAssertEqual(reduced, [user("q3")])
    }

    /// Multiple leading system messages are all peeled and preserved ahead of the
    /// tail (a chat can carry more than one system message).
    func test_messagesPastFrozenRounds_peelsMultipleSystem() throws {
        let s1 = LLM.Message(role: .system, content: "a")
        let s2 = LLM.Message(role: .system, content: "b")
        let full = [s1, s2] + plainRound + [user("now")]
        let reduced = try XCTUnwrap(ChatBlobAssembler.messagesPastFrozenRounds(full, frozenRoundCount: 1))
        XCTAssertEqual(reduced, [s1, s2, user("now")])
    }

    /// Only system messages, no rounds: with a positive frozen count the guard
    /// (rounds.count > frozenRoundCount) fails, so reduction refuses (nil).
    func test_messagesPastFrozenRounds_allSystemNoRounds_returnsNil() throws {
        let full = [LLM.Message(role: .system, content: "a"), LLM.Message(role: .system, content: "b")]
        XCTAssertNil(ChatBlobAssembler.messagesPastFrozenRounds(full, frozenRoundCount: 1))
    }

    /// Frozen count zero is a no-op (everything is the tail).
    func test_messagesPastFrozenRounds_zeroIsIdentity() throws {
        let system = LLM.Message(role: .system, content: "sys")
        let full = [system] + plainRound + [user("q2")]
        XCTAssertEqual(try XCTUnwrap(ChatBlobAssembler.messagesPastFrozenRounds(full, frozenRoundCount: 0)), full)
    }

    /// Misalignment guard: if fewer rounds are present than are frozen (or exactly
    /// as many, leaving no current round), the reduction refuses (nil) so the caller
    /// falls back to the full, un-spliced request rather than send a history-less one.
    func test_messagesPastFrozenRounds_misalignment_returnsNil() throws {
        let system = LLM.Message(role: .system, content: "sys")
        let full = [system] + plainRound  // 1 round present
        XCTAssertNil(ChatBlobAssembler.messagesPastFrozenRounds(full, frozenRoundCount: 1),
                     "equal counts leave no current round -> refuse")
        XCTAssertNil(ChatBlobAssembler.messagesPastFrozenRounds(full, frozenRoundCount: 2),
                     "more frozen than present -> refuse")
    }

    /// The value bytes of the JSON array at `key` (from `[` to its matching `]`),
    /// depth- and string-aware. For byte-exact comparison of the cache-relevant
    /// prefix without the surrounding envelope fields (e.g. max_tokens).
    private func arrayBytes(forKey key: String, in body: Data) -> Data? {
        let s = String(decoding: body, as: UTF8.self)
        guard let keyRange = s.range(of: "\"\(key)\":") else { return nil }
        let after = s[keyRange.upperBound...]
        guard after.first == "[" else { return nil }
        var depth = 0, inString = false, escaped = false
        var idx = after.startIndex
        while idx < after.endIndex {
            let c = after[idx]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" { inString = true }
            else if c == "[" || c == "{" { depth += 1 }
            else if c == "}" { depth -= 1 }
            else if c == "]" { depth -= 1; if depth == 0 { return Data(after[after.startIndex...idx].utf8) } }
            idx = after.index(after: idx)
        }
        return nil
    }

    /// Anthropic's cache is a byte-prefix match over tools -> system -> messages, so
    /// the blob-native "messages" array must be BYTE-identical (not just parse-equal)
    /// to the live full-history one. This is what the .sortedKeys blob encoding
    /// guarantees; max_tokens (a top-level sibling, not in the cached prefix) is
    /// allowed to differ.
    func test_sendPath_anthropic_messagesAreByteIdentical() throws {
        var model = try baseModel()
        model.api = .anthropic
        let priorConvo = plainRound + toolRound
        let db = try makeTempDB()
        ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: priorConvo, api: .anthropic,
                                         modelName: model.name, hostedTools: HostedTools(), database: db)
        let inner = try ChatBlobAssembler.stitchInner(db.blobs(inChat: "A"))
        let system = LLM.Message(role: .system, content: "You are helpful.")
        let newUser = user("what's next?")
        let blobNative = try builder(model, messages: [system, newUser], frozen: inner).body()
        let live = try builder(model, messages: [system] + priorConvo + [newUser], frozen: nil).body()
        XCTAssertEqual(arrayBytes(forKey: "messages", in: blobNative),
                       arrayBytes(forKey: "messages", in: live),
                       "blob-native Anthropic messages array must be byte-identical to the live one")
    }

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
