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
