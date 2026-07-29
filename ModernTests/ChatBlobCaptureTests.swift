//
//  ChatBlobCaptureTests.swift
//  iTerm2 ModernTests
//
//  Phase 2 capture orchestration: splitting a chat's reconstructed history into
//  rounds and freezing any round not already stored. Covers the round-split rule
//  (a round begins at each user message), and the incremental/idempotent capture
//  that serves both normal per-turn capture and one-shot migration through one
//  path.
//

import XCTest
@testable import iTerm2SharedARC

final class ChatBlobCaptureTests: XCTestCase {

    private func user(_ s: String) -> LLM.Message { LLM.Message(role: .user, content: s) }
    private func asst(_ s: String) -> LLM.Message { LLM.Message(role: .assistant, content: s) }
    private func toolCall(_ callID: String) -> LLM.Message {
        LLM.Message(role: .assistant,
                    function_call: LLM.FunctionCall(name: "f", arguments: "{}", id: callID, thoughtSignature: nil))
    }
    private func toolResult(_ callID: String) -> LLM.Message {
        LLM.Message(role: .function, content: "out", name: "f",
                    functionCallID: LLM.Message.FunctionCallID(callID: callID, itemID: ""))
    }

    // MARK: - roundTokenWeight (turn-over-turn usage delta)

    func test_roundTokenWeight_delta() {
        XCTAssertEqual(ChatBlobCapture.roundTokenWeight(thisTurnPromptTokens: 8600,
                                                        previousTurnPromptTokens: 8000), 600)
    }

    func test_roundTokenWeight_firstTurn_nilPrevious_isNil() {
        XCTAssertNil(ChatBlobCapture.roundTokenWeight(thisTurnPromptTokens: 8000,
                                                      previousTurnPromptTokens: nil))
    }

    func test_roundTokenWeight_noUsageThisTurn_isNil() {
        XCTAssertNil(ChatBlobCapture.roundTokenWeight(thisTurnPromptTokens: nil,
                                                      previousTurnPromptTokens: 8000))
    }

    /// A shrinking prompt (an edit/truncation dropped history between turns) must not
    /// yield a negative weight.
    func test_roundTokenWeight_shrunkPrompt_clampsToZero() {
        XCTAssertEqual(ChatBlobCapture.roundTokenWeight(thisTurnPromptTokens: 5000,
                                                        previousTurnPromptTokens: 8000), 0)
    }

    // MARK: - rounds(from:)

    func testRounds_empty() {
        XCTAssertTrue(ChatBlobCapture.rounds(from: []).isEmpty)
    }

    func testRounds_singleUser() {
        XCTAssertEqual(ChatBlobCapture.rounds(from: [user("hi")]).count, 1)
    }

    func testRounds_userThenAgent_isOneRound() {
        let r = ChatBlobCapture.rounds(from: [user("hi"), asst("hello")])
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].count, 2)
    }

    func testRounds_splitsAtEachUserMessage() {
        let msgs = [user("q1"), asst("a1"), user("q2"), asst("a2"), user("q3"), asst("a3")]
        let r = ChatBlobCapture.rounds(from: msgs)
        XCTAssertEqual(r.map { $0.count }, [2, 2, 2])
        XCTAssertEqual(r.map { $0[0].role }, [.user, .user, .user])
    }

    /// A tool round (user + preamble + tool_use + tool_result + final agent text)
    /// is ONE round: everything between two user messages belongs together, so
    /// truncation by whole rounds can never split a tool_use/tool_result pair.
    func testRounds_toolRound_staysOneRound() {
        let msgs = [user("weather?"), asst("let me check"), toolCall("c1"),
                    toolResult("c1"), asst("it's sunny"),
                    user("thanks"), asst("welcome")]
        let r = ChatBlobCapture.rounds(from: msgs)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].count, 5)
        XCTAssertEqual(r[1].count, 2)
    }

    // MARK: - captureNewRounds (incremental + idempotent, live DB)

    private func makeTempDB() throws -> ChatDatabase {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("chatblobcapture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
    }

    private func capture(_ db: ChatDatabase, chatID: String, _ msgs: [LLM.Message]) -> Int {
        ChatBlobCapture.captureNewRounds(chatID: chatID, allMessages: msgs, api: .chatCompletions,
                                         modelName: nil, hostedTools: HostedTools(), database: db)
    }

    func testCapture_freezesAllRoundsFirstTime() throws {
        let db = try makeTempDB()
        let msgs = [user("q1"), asst("a1"), user("q2"), asst("a2")]
        XCTAssertEqual(capture(db, chatID: "A", msgs), 2, "first capture freezes both rounds")
        let blobs = db.blobs(inChat: "A")
        XCTAssertEqual(blobs.count, 2)
        XCTAssertEqual(blobs.map { $0.blobProtocol }, [.chatCompletions, .chatCompletions])
        // Each payload is that round's wire-message array (2 messages per round here).
        for blob in blobs {
            let arr = try XCTUnwrap(JSONSerialization.jsonObject(with: blob.payload) as? [Any])
            XCTAssertEqual(arr.count, 2)
        }
    }

    func testCapture_isIncremental_onlyNewRounds() throws {
        let db = try makeTempDB()
        let first = [user("q1"), asst("a1")]
        XCTAssertEqual(capture(db, chatID: "A", first), 1)
        // A second turn appends one more round to the history.
        let second = first + [user("q2"), asst("a2")]
        XCTAssertEqual(capture(db, chatID: "A", second), 1, "only the new round is frozen")
        XCTAssertEqual(db.blobs(inChat: "A").count, 2)
    }

    func testCapture_isIdempotent() throws {
        let db = try makeTempDB()
        let msgs = [user("q1"), asst("a1"), user("q2"), asst("a2")]
        XCTAssertEqual(capture(db, chatID: "A", msgs), 2)
        XCTAssertEqual(capture(db, chatID: "A", msgs), 0, "re-capturing the same history freezes nothing new")
        XCTAssertEqual(db.blobs(inChat: "A").count, 2)
    }

    func testCapture_migratesWholeLegacyHistoryInOnePath() throws {
        let db = try makeTempDB()
        // A "legacy" chat with several rounds and zero blobs: the first capture
        // freezes them all (the migration), then subsequent turns are incremental.
        let legacy = [user("q1"), asst("a1"), user("q2"), asst("a2"), user("q3"), asst("a3")]
        XCTAssertEqual(capture(db, chatID: "A", legacy), 3)
        XCTAssertEqual(capture(db, chatID: "A", legacy + [user("q4"), asst("a4")]), 1)
        XCTAssertEqual(db.blobs(inChat: "A").count, 4)
    }

    /// The capture-side fast path: appending only the NEW rounds each turn
    /// (appendNewRounds, fed the translated tail) must persist byte-identical blobs
    /// to the original path that re-translates the whole history and re-slices it
    /// (captureNewRounds). This is what lets capture translate only the tail without
    /// changing what gets stored.
    func test_appendNewRounds_matchesCaptureNewRounds() throws {
        let r0 = [user("q0"), asst("a0")]
        let r1 = [user("q1"), asst("pre"), toolCall("c1"), toolResult("c1"), asst("post")]
        let r2 = [user("q2"), asst("a2")]

        // Baseline: whole-history incremental capture, one turn at a time.
        let full = try makeTempDB()
        XCTAssertEqual(ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: r0, api: .chatCompletions,
                                                        modelName: "m", hostedTools: HostedTools(), database: full), 1)
        XCTAssertEqual(ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: r0 + r1, api: .chatCompletions,
                                                        modelName: "m", hostedTools: HostedTools(), database: full), 1)
        XCTAssertEqual(ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: r0 + r1 + r2, api: .chatCompletions,
                                                        modelName: "m", hostedTools: HostedTools(), database: full), 1)

        // Fast path: bootstrap the first round, then append only each new round.
        let fast = try makeTempDB()
        XCTAssertEqual(ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: r0, api: .chatCompletions,
                                                        modelName: "m", hostedTools: HostedTools(), database: fast), 1)
        XCTAssertEqual(ChatBlobCapture.appendNewRounds(chatID: "A", newRounds: [r1], api: .chatCompletions,
                                                       modelName: "m", hostedTools: HostedTools(), database: fast), 1)
        XCTAssertEqual(ChatBlobCapture.appendNewRounds(chatID: "A", newRounds: [r2], api: .chatCompletions,
                                                       modelName: "m", hostedTools: HostedTools(), database: fast), 1)

        // Compare parsed JSON (order-independent): chatCompletions blobs use a
        // non-sorted encoder, so two independent encodings of the same round can
        // differ only in key order. Production never re-encodes a stored blob (it
        // splices the bytes verbatim), so semantic equality is the right invariant:
        // the fast path must freeze the SAME rounds, message-for-message.
        let fullBlobs = full.blobs(inChat: "A")
        let fastBlobs = fast.blobs(inChat: "A")
        let fullJSON = fullBlobs.map { try? JSONSerialization.jsonObject(with: $0.payload) as? [Any] }
        let fastJSON = fastBlobs.map { try? JSONSerialization.jsonObject(with: $0.payload) as? [Any] }
        XCTAssertEqual(fullJSON.count, 3)
        XCTAssertEqual(fastJSON.count, 3)
        for (a, b) in zip(fullJSON, fastJSON) {
            XCTAssertEqual((a ?? []) as NSArray, (b ?? []) as NSArray,
                           "fast-path blob must be semantically identical to the full-history path")
        }
        XCTAssertEqual(fullBlobs.map { $0.blobProtocol }, fastBlobs.map { $0.blobProtocol })
    }

    /// For a sorted-keys protocol (Anthropic, whose prompt cache is a byte-prefix
    /// match), the fast path must freeze BYTE-identical blobs to the full path, so the
    /// capture optimization can never perturb the cached prefix.
    func test_appendNewRounds_anthropicBytesIdentical() throws {
        let r0 = [user("q0"), asst("a0")]
        let r1 = [user("q1"), asst("pre"), toolCall("c1"), toolResult("c1"), asst("post")]

        let full = try makeTempDB()
        ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: r0, api: .anthropic,
                                         modelName: "m", hostedTools: HostedTools(), database: full)
        ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: r0 + r1, api: .anthropic,
                                         modelName: "m", hostedTools: HostedTools(), database: full)

        let fast = try makeTempDB()
        ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: r0, api: .anthropic,
                                         modelName: "m", hostedTools: HostedTools(), database: fast)
        ChatBlobCapture.appendNewRounds(chatID: "A", newRounds: [r1], api: .anthropic,
                                        modelName: "m", hostedTools: HostedTools(), database: fast)

        XCTAssertEqual(full.blobs(inChat: "A").map { $0.payload },
                       fast.blobs(inChat: "A").map { $0.payload },
                       "Anthropic (sorted-keys) fast-path blobs must be byte-identical")
    }

    /// appendNewRounds honors the same protocol guard as captureNewRounds: it must
    /// not stack new-protocol rounds on old-protocol blobs.
    func test_appendNewRounds_protocolMismatch_refuses() throws {
        let db = try makeTempDB()
        XCTAssertEqual(ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: [user("q"), asst("a")],
                                                        api: .chatCompletions, modelName: nil,
                                                        hostedTools: HostedTools(), database: db), 1)
        XCTAssertEqual(ChatBlobCapture.appendNewRounds(chatID: "A", newRounds: [[user("q2"), asst("a2")]],
                                                       api: .responses, modelName: nil,
                                                       hostedTools: HostedTools(), database: db), 0)
        XCTAssertEqual(db.blobs(inChat: "A").count, 1)
    }

    /// An encode failure (here: an unsupported protocol) must stop without
    /// appending a gapped/partial sequence.
    func testCapture_encodeFailure_appendsNothing() throws {
        let db = try makeTempDB()
        let n = ChatBlobCapture.captureNewRounds(chatID: "A",
                                                 allMessages: [user("q1"), asst("a1")],
                                                 api: .completions,  // unsupported -> encodeRound throws
                                                 modelName: nil, hostedTools: HostedTools(), database: db)
        XCTAssertEqual(n, 0)
        XCTAssertTrue(db.blobs(inChat: "A").isEmpty)
    }

    /// A protocol switch mid-chat must NOT append new-protocol rounds on top of
    /// old-protocol blobs (that yields a mixed, unreplayable sequence). The caller
    /// must re-freeze via replaceBlobs first; until then, capture refuses.
    func testCapture_protocolMismatch_refusesToAppend() throws {
        let db = try makeTempDB()
        let r1 = [user("q1"), asst("a1")]
        XCTAssertEqual(ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: r1,
                                                        api: .chatCompletions, modelName: nil,
                                                        hostedTools: HostedTools(), database: db), 1)
        // Next turn arrives under a DIFFERENT protocol without a re-freeze.
        let r2 = r1 + [user("q2"), asst("a2")]
        let n = ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: r2,
                                                 api: .responses, modelName: nil,
                                                 hostedTools: HostedTools(), database: db)
        XCTAssertEqual(n, 0, "must refuse to append under a different protocol")
        let blobs = db.blobs(inChat: "A")
        XCTAssertEqual(blobs.count, 1, "sequence must be unchanged (no mixed-protocol corruption)")
        XCTAssertEqual(blobs.first?.blobProtocol, .chatCompletions)
    }

    /// Same protocol continues to append (the guard only refuses a real mismatch).
    func testCapture_sameProtocol_stillAppends() throws {
        let db = try makeTempDB()
        let r1 = [user("q1"), asst("a1")]
        XCTAssertEqual(capture(db, chatID: "A", r1), 1)
        XCTAssertEqual(capture(db, chatID: "A", r1 + [user("q2"), asst("a2")]), 1)
        XCTAssertEqual(db.blobCount(inChat: "A"), 2)
    }

    func testBlobCount_countsRowsWithoutDecoding() throws {
        let db = try makeTempDB()
        XCTAssertEqual(db.blobCount(inChat: "A"), 0)
        for i in 0..<3 {
            db.appendBlob(ChatBlob(chatID: "A", blobProtocol: .anthropic, role: .user,
                                   payload: Data("r\(i)".utf8)))
        }
        XCTAssertEqual(db.blobCount(inChat: "A"), 3)
        XCTAssertEqual(db.storedBlobProtocol(inChat: "A"), Int(iTermAIAPI.anthropic.rawValue))
        XCTAssertNil(db.storedBlobProtocol(inChat: "empty"))
    }

    // MARK: - captureTurn (protocol-switch handling)

    func testCaptureTurn_sameProtocol_isIncremental() throws {
        let db = try makeTempDB()
        let r1 = [user("q1"), asst("a1")]
        XCTAssertEqual(ChatBlobCapture.captureTurn(chatID: "A", allMessages: r1, api: .chatCompletions,
                                                   modelName: nil, hostedTools: HostedTools(), database: db), 1)
        XCTAssertEqual(ChatBlobCapture.captureTurn(chatID: "A", allMessages: r1 + [user("q2"), asst("a2")],
                                                   api: .chatCompletions, modelName: nil,
                                                   hostedTools: HostedTools(), database: db), 1)
        XCTAssertEqual(db.blobCount(inChat: "A"), 2)
        XCTAssertEqual(db.storedBlobProtocol(inChat: "A"), Int(iTermAIAPI.chatCompletions.rawValue))
    }

    /// A protocol switch clears the old-protocol blobs and re-freezes the WHOLE
    /// history under the new protocol (so the sequence is never mixed).
    func testCaptureTurn_protocolSwitch_reFreezesWholeHistory() throws {
        let db = try makeTempDB()
        let convo = [user("q1"), asst("a1"), user("q2"), asst("a2")]
        XCTAssertEqual(ChatBlobCapture.captureTurn(chatID: "A", allMessages: convo, api: .chatCompletions,
                                                   modelName: nil, hostedTools: HostedTools(), database: db), 2)
        // Next turn arrives under a different protocol (user switched providers).
        let after = convo + [user("q3"), asst("a3")]
        let appended = ChatBlobCapture.captureTurn(chatID: "A", allMessages: after, api: .anthropic,
                                                   modelName: nil, hostedTools: HostedTools(), database: db)
        XCTAssertEqual(appended, 3, "the whole history (3 rounds) re-freezes under the new protocol")
        let blobs = db.blobs(inChat: "A")
        XCTAssertEqual(blobs.count, 3)
        XCTAssertTrue(blobs.allSatisfy { $0.blobProtocol == .anthropic },
                      "every blob is now the new protocol; none of the old chatCompletions blobs remain")
    }

    /// The real per-round token count is credited ONLY when exactly one new round is
    /// frozen (the incremental case it describes). A multi-round migration capture
    /// can't split one turn's usage across rounds, so those store nil (byte estimate).
    func testCapture_creditsTokenCount_onlyOnSingleRound() throws {
        let db = try makeTempDB()
        // Incremental: one new round -> the count is stored on it.
        ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: [user("q1"), asst("a1")],
                                         api: .chatCompletions, modelName: nil, hostedTools: HostedTools(),
                                         newRoundTokenCount: 600, database: db)
        XCTAssertEqual(db.blobs(inChat: "A").last?.tokenCount, 600)

        // Migration: multiple new rounds at once -> none is credited (all nil).
        let db2 = try makeTempDB()
        ChatBlobCapture.captureNewRounds(chatID: "B",
                                         allMessages: [user("q1"), asst("a1"), user("q2"), asst("a2")],
                                         api: .chatCompletions, modelName: nil, hostedTools: HostedTools(),
                                         newRoundTokenCount: 600, database: db2)
        XCTAssertEqual(db2.blobs(inChat: "B").count, 2)
        XCTAssertTrue(db2.blobs(inChat: "B").allSatisfy { $0.tokenCount == nil },
                      "a multi-round migration capture must not credit one turn's usage to a round")
    }

    /// Finding 3 (interrupted/cancelled tool round): an orphaned tool_use (no
    /// tool_result, e.g. a tool cancelled mid-turn) must NOT be frozen into a blob as
    /// a broken pairing that a vendor 400s on replay. Capture reconstructs via the
    /// same repair pass ChatAgent runs (repairingOrphanedToolPairs), which heals the
    /// orphan BEFORE freezing, so the captured blob carries a well-formed
    /// tool_use/tool_result pair. This pins that chain deterministically (the live
    /// path is covered indirectly by the queue tests' orphan scenarios).
    func testCapture_healsOrphanedToolUse_intoWellFormedBlob() throws {
        let db = try makeTempDB()
        // A round whose assistant tool_use never got a tool_result (interrupted).
        let orphaned: [LLM.Message] = [
            user("run a command"),
            LLM.Message(role: .assistant,
                        function_call: LLM.FunctionCall(name: "execute_command", arguments: "{}",
                                                        id: "call_orphan", thoughtSignature: nil)),
        ]
        // Capture heals via the repair pass, exactly as ChatAgent's translate() does.
        let healed = AIChatToolCallRepair.repairingOrphanedToolPairs(orphaned)
        ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: healed, api: .anthropic,
                                         modelName: nil, hostedTools: HostedTools(), database: db)
        let blobs = db.blobs(inChat: "A")
        XCTAssertFalse(blobs.isEmpty, "the healed round must be frozen")
        for blob in blobs {
            let payload = String(decoding: blob.payload, as: UTF8.self)
            if payload.contains("tool_use") {
                XCTAssertTrue(payload.contains("tool_result"),
                              "a captured round with a tool_use must be healed to carry its tool_result")
            }
        }
    }

    func testCapture_recordsResponseID_fromRoundTail() throws {
        let db = try makeTempDB()
        // Responses-style: the round's final assistant message carries a responseID.
        var finalMsg = asst("done")
        finalMsg.responseID = "resp_123"
        let msgs = [user("q1"), finalMsg]
        _ = ChatBlobCapture.captureNewRounds(chatID: "A", allMessages: msgs, api: .chatCompletions,
                                             modelName: nil, hostedTools: HostedTools(), database: db)
        XCTAssertEqual(try XCTUnwrap(db.blobs(inChat: "A").first).responseID, "resp_123")
    }
}
