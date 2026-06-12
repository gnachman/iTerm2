//
//  ChatRestoreToolUsePersistenceTests.swift
//  iTerm2 ModernTests
//
//  Backward-compatibility guards for the tool-use persistence change.
//
//  Historically, auto-approved (.always) and auto-denied (.never) tool calls
//  squelched the .remoteCommandRequest from the chat DB and kept only the
//  .remoteCommandResponse, leaving an orphan that the next turn had to repair.
//  The fix persists the request going forward. These tests pin that a chat DB
//  restored from disk reconstructs a VALID LLM prompt (every tool_result
//  preceded by a matching tool_use, no duplicate tool_uses) across three eras
//  of on-disk data:
//
//    1. Old DB (pre-fix): tool exchanges are response-only orphans.
//    2. Mixed DB: some exchanges are old-style orphans, some are new-style
//       persisted request+response pairs (a chat that spanned the upgrade).
//    3. Future DB: every exchange is a persisted request+response pair.
//
//  Restore is modeled by a Codable round-trip, which is exactly how
//  ChatListModel persists a Message (JSON in SQLite); see
//  AIChatMessagePersistenceTests for the same approach.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class ChatRestoreToolUsePersistenceTests: XCTestCase {
    private let chatID = "restore-test-chat"

    // MARK: - Fixtures

    private func fcid(_ s: String) -> LLM.Message.FunctionCallID {
        LLM.Message.FunctionCallID(callID: s, itemID: s)
    }

    /// A persisted assistant tool-call request (new-style: what the fix keeps
    /// on disk). Its llmMessage is a functionCall whose id is `callID`, so the
    /// reload state machine emits a matching tool_use.
    private func requestMessage(callID: String,
                                requestUUID: UUID,
                                command: String = "echo hi") -> Message {
        let llm = LLM.Message(
            role: .assistant,
            body: .functionCall(LLM.FunctionCall(name: "execute_command",
                                                 arguments: "{\"command\":\"\(command)\"}",
                                                 id: callID,
                                                 thoughtSignature: nil),
                                id: fcid(callID)))
        let rc = RemoteCommand(llmMessage: llm,
                               content: .executeCommand(.init(command: command)))
        return Message(chatID: chatID,
                       author: .agent,
                       content: .remoteCommandRequest(.classic(rc), safe: nil),
                       sentDate: Date(timeIntervalSince1970: 1_000),
                       uniqueID: requestUUID)
    }

    /// A persisted tool-call response (present in every era). References the
    /// request by `requestUUID` and carries the function call id for id-based
    /// vendors.
    private func responseMessage(callID: String,
                                 requestUUID: UUID,
                                 output: String = "hi") -> Message {
        Message(chatID: chatID,
                author: .user,
                content: .remoteCommandResponse(.success(output),
                                                requestUUID,
                                                "execute_command",
                                                fcid(callID)),
                sentDate: Date(timeIntervalSince1970: 1_001),
                uniqueID: UUID())
    }

    private func userText(_ s: String) -> Message {
        Message(chatID: chatID, author: .user, content: .markdown(s),
                sentDate: Date(timeIntervalSince1970: 1_002), uniqueID: UUID())
    }

    private func agentText(_ s: String) -> Message {
        Message(chatID: chatID, author: .agent, content: .markdown(s),
                sentDate: Date(timeIntervalSince1970: 1_003), uniqueID: UUID())
    }

    // MARK: - Restore + reconstruct

    /// Persist each message to JSON and read it back, the actual on-disk
    /// round-trip ChatListModel performs, then rebuild the LLM prompt the way
    /// a restored chat does.
    private func restoreAndReconstruct(_ messages: [Message]) throws -> [LLM.Message] {
        let restored = try messages.map { original -> Message in
            let data = try JSONEncoder().encode(original)
            return try JSONDecoder().decode(Message.self, from: data)
        }
        return ChatAgent.aiMessagesForReloadingTranscript(restored)
    }

    // MARK: - Assertions

    private func toolUseID(_ m: LLM.Message) -> String? {
        if case .functionCall(let call, let wrapper) = m.body {
            return call.id ?? wrapper?.callID
        }
        return nil
    }

    private func toolResultID(_ m: LLM.Message) -> String? {
        if case .functionOutput(_, _, let id) = m.body {
            return id?.callID
        }
        return nil
    }

    /// Every tool_result must have an earlier tool_use of the same id, and no
    /// id may carry more than one tool_use (no duplicate synthesis).
    private func assertValidPairing(_ messages: [LLM.Message],
                                    file: StaticString = #file,
                                    line: UInt = #line) {
        var seen = Set<String>()
        var useCountByID = [String: Int]()
        for m in messages {
            if let useID = toolUseID(m) {
                seen.insert(useID)
                useCountByID[useID, default: 0] += 1
            }
            if let resultID = toolResultID(m) {
                XCTAssertTrue(seen.contains(resultID),
                              "tool_result \(resultID) has no preceding tool_use",
                              file: file, line: line)
            }
        }
        for (id, count) in useCountByID {
            XCTAssertEqual(count, 1,
                           "tool_use \(id) appears \(count) times; reconstruction duplicated it",
                           file: file, line: line)
        }
    }

    // MARK: - 1. Old DB (entirely pre-fix): response-only orphans

    func testRestore_oldDatabase_orphanResponsesOnly_reconstructsValid() throws {
        let messages = [
            userText("run something"),
            agentText("Sure, running it."),
            responseMessage(callID: "call_old_1", requestUUID: UUID()),
            agentText("Done."),
            userText("and another"),
            responseMessage(callID: "call_old_2", requestUUID: UUID()),
        ]
        let rebuilt = try restoreAndReconstruct(messages)
        assertValidPairing(rebuilt)
        // Both orphan results must have gained a synthesized tool_use.
        XCTAssertTrue(rebuilt.contains { toolUseID($0) == "call_old_1" })
        XCTAssertTrue(rebuilt.contains { toolUseID($0) == "call_old_2" })
    }

    // MARK: - 2. Mixed DB: old orphans + new persisted pairs in one chat

    func testRestore_mixedDatabase_oldAndNewToolUses_reconstructsValid() throws {
        let req = UUID()
        let messages = [
            userText("first, old style"),
            responseMessage(callID: "call_old", requestUUID: UUID()),   // orphan
            agentText("now a new-style call"),
            requestMessage(callID: "call_new", requestUUID: req),       // persisted request
            responseMessage(callID: "call_new", requestUUID: req),      // its response
            agentText("all set"),
        ]
        let rebuilt = try restoreAndReconstruct(messages)
        assertValidPairing(rebuilt)
        // Old orphan got synthesized; new pair is intact and NOT duplicated.
        XCTAssertTrue(rebuilt.contains { toolUseID($0) == "call_old" })
        XCTAssertEqual(rebuilt.filter { toolUseID($0) == "call_new" }.count, 1,
                       "a persisted request must not be duplicated by repair")
    }

    // MARK: - 3. Future DB: only new-style persisted request+response pairs

    func testRestore_futureDatabase_persistedRequests_reconstructsValidNoDuplicates() throws {
        let r1 = UUID(), r2 = UUID()
        let messages = [
            userText("do two things"),
            requestMessage(callID: "call_a", requestUUID: r1, command: "echo a"),
            responseMessage(callID: "call_a", requestUUID: r1, output: "a"),
            requestMessage(callID: "call_b", requestUUID: r2, command: "echo b"),
            responseMessage(callID: "call_b", requestUUID: r2, output: "b"),
            agentText("finished"),
        ]
        let rebuilt = try restoreAndReconstruct(messages)
        assertValidPairing(rebuilt)
        // No synthesis at all: exactly one tool_use per persisted request.
        XCTAssertEqual(rebuilt.filter { toolUseID($0) == "call_a" }.count, 1)
        XCTAssertEqual(rebuilt.filter { toolUseID($0) == "call_b" }.count, 1)
        XCTAssertEqual(rebuilt.compactMap { toolResultID($0) }.sorted(), ["call_a", "call_b"])
    }

    // MARK: - View-model hiding of resolved requests

    /// A persisted request whose response is present is "resolved" and must be
    /// hidden from the chat UI (no stray Allow/Deny prompt).
    func testViewModel_resolvedRequest_isHidden() {
        let req = UUID()
        let messages = [
            userText("go"),
            requestMessage(callID: "call_x", requestUUID: req),
            responseMessage(callID: "call_x", requestUUID: req),
        ]
        XCTAssertTrue(ChatViewControllerModel.resolvedRequestIDs(in: messages).contains(req),
                      "a request with a matching response must be marked resolved (hidden)")
    }

    /// A pending request (no response yet, e.g. a live .ask awaiting approval)
    /// must remain visible.
    func testViewModel_pendingRequest_isNotHidden() {
        let req = UUID()
        let messages = [
            userText("go"),
            requestMessage(callID: "call_y", requestUUID: req),
        ]
        XCTAssertFalse(ChatViewControllerModel.resolvedRequestIDs(in: messages).contains(req),
                       "a pending request with no response must remain visible")
    }
}
