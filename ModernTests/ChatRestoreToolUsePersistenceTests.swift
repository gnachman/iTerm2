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

    // MARK: - Orphan request (tool_call with no response) keeps adjacency

    /// A persisted tool call whose response never arrived (an abandoned
    /// `.ask`, or a parked request cleared on the next user message),
    /// followed by later messages, must reconstruct with its synthesized
    /// "interrupted" output IMMEDIATELY after the call. The pre-fix code
    /// appended that filler at the END of the transcript, leaving the
    /// trailing user/agent messages between the tool_call and its output;
    /// DeepSeek (and the legacy OpenAI chat-completions path) reject that
    /// with HTTP 400 "insufficient tool messages following tool_calls
    /// message" (GitLab #12883).
    func testRestore_orphanRequestBeforeLaterMessages_outputIsAdjacent() throws {
        let req = UUID()
        let messages = [
            userText("run a command"),
            requestMessage(callID: "call_orphan", requestUUID: req),  // no response
            userText("actually never mind, let's just chat"),
            agentText("Sure, happy to chat."),
        ]
        let rebuilt = try restoreAndReconstruct(messages)
        assertValidPairing(rebuilt)

        guard let callIdx = rebuilt.firstIndex(where: { toolUseID($0) == "call_orphan" }) else {
            XCTFail("orphan tool_call is missing from the rebuilt prompt")
            return
        }
        XCTAssertLessThan(callIdx + 1, rebuilt.count,
                          "orphan tool_call has nothing after it; its output was dropped")
        XCTAssertEqual(toolResultID(rebuilt[callIdx + 1]), "call_orphan",
                       "the orphan tool_call's output must immediately follow the call, not be deferred past the trailing messages to the end")
    }

    /// Two orphan calls interleaved with text: each call's synthesized
    /// output lands right after that call, not all bunched at the end.
    func testRestore_multipleOrphanRequests_eachOutputIsAdjacent() throws {
        let r1 = UUID(), r2 = UUID()
        let messages = [
            userText("do the first thing"),
            requestMessage(callID: "call_a", requestUUID: r1, command: "echo a"),  // orphan
            agentText("working on it"),
            requestMessage(callID: "call_b", requestUUID: r2, command: "echo b"),  // orphan
            userText("and that's all"),
        ]
        let rebuilt = try restoreAndReconstruct(messages)
        assertValidPairing(rebuilt)

        for callID in ["call_a", "call_b"] {
            guard let callIdx = rebuilt.firstIndex(where: { toolUseID($0) == callID }) else {
                XCTFail("orphan tool_call \(callID) is missing from the rebuilt prompt")
                return
            }
            XCTAssertEqual(toolResultID(rebuilt[callIdx + 1]), callID,
                           "\(callID)'s output must immediately follow its call")
        }
    }

    // MARK: - View-model hiding of resolved requests

    /// A persisted request whose response is present is "resolved" and must be
    /// hidden from the chat UI (no stray Allow/Deny prompt).
    /// Reasoning items persisted with the request's llmMessage must ride the
    /// restore round-trip onto the rebuilt prompt's functionCall message, so
    /// the request builder can replay them before the call.
    func testRestore_persistedReasoningItems_rideRebuiltFunctionCall() throws {
        let requestUUID = UUID()
        var request = requestMessage(callID: "call_r", requestUUID: requestUUID)
        guard case .remoteCommandRequest(.classic(var rc), let safe) = request.content else {
            XCTFail("fixture changed shape")
            return
        }
        rc.llmMessage.reasoningItems = [LLM.ReasoningItem(id: "rs_9",
                                                          encryptedContent: "blob-9")]
        request.content = .remoteCommandRequest(.classic(rc), safe: safe)
        let rebuilt = try restoreAndReconstruct([
            userText("run it"),
            request,
            responseMessage(callID: "call_r", requestUUID: requestUUID),
        ])
        guard let callMessage = rebuilt.first(where: { toolUseID($0) == "call_r" }) else {
            XCTFail("rebuilt prompt lost the tool call")
            return
        }
        XCTAssertEqual(callMessage.reasoningItems?.map(\.id), ["rs_9"])
        XCTAssertEqual(callMessage.reasoningItems?.first?.encryptedContent, "blob-9")
    }

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

    // MARK: - reconstructedRoundCount pin (blob-native fast path)

    /// The blob-native fast path in load() decides "do the chat's blobs cover its
    /// whole history?" by comparing the stored blob count to
    /// ChatAgent.reconstructedRoundCount(displayMessages) -- a cheap counter that
    /// builds NO message body. If it ever UNDERCOUNTS the real round count, the fast
    /// path would skip translating (and so drop) un-frozen history. This pins it to
    /// the production round count: rounds(from: translate(messages)).count, across a
    /// spread of transcripts (plain turns, tool pairs, orphan request, orphan
    /// response, leading agent turn, filtered-out content).
    private func assertRoundCountMatchesTranslate(_ messages: [Message],
                                                  _ label: String,
                                                  file: StaticString = #file,
                                                  line: UInt = #line) {
        let viaTranslate = ChatBlobCapture.rounds(
            from: ChatAgent.translateForTesting(messages, resolve: { _ in nil })).count
        let cheap = ChatAgent.reconstructedRoundCount(messages)
        XCTAssertEqual(cheap, viaTranslate,
                       "reconstructedRoundCount drifted from translate+rounds for: \(label)",
                       file: file, line: line)
    }

    func testReconstructedRoundCount_matchesTranslateAcrossTranscripts() {
        let r1 = UUID(), r2 = UUID(), r3 = UUID()
        assertRoundCountMatchesTranslate([], "empty")
        assertRoundCountMatchesTranslate([userText("hi")], "single user")
        assertRoundCountMatchesTranslate(
            [userText("hi"), agentText("hello")], "one full round")
        assertRoundCountMatchesTranslate(
            [userText("a"), agentText("b"), userText("c"), agentText("d")],
            "two plain rounds")
        assertRoundCountMatchesTranslate(
            [userText("run"),
             requestMessage(callID: "c1", requestUUID: r1),
             responseMessage(callID: "c1", requestUUID: r1),
             agentText("done"),
             userText("again"),
             requestMessage(callID: "c2", requestUUID: r2),
             responseMessage(callID: "c2", requestUUID: r2),
             agentText("done2")],
            "two rounds each with a tool pair")
        // A tool RESPONSE is user-authored but role .function -- it must NOT open a
        // round. If the counter treated it as a user turn it would overcount here.
        assertRoundCountMatchesTranslate(
            [userText("run"),
             agentText("ok"),
             responseMessage(callID: "orphan", requestUUID: r3),
             agentText("recovered")],
            "orphan tool response (user-authored, not a round start)")
        // A request with no matching response (orphan request): still one round.
        assertRoundCountMatchesTranslate(
            [userText("go"), requestMessage(callID: "cx", requestUUID: UUID())],
            "orphan tool request")
        // History that opens with an agent turn: the first message still opens a round.
        assertRoundCountMatchesTranslate(
            [agentText("greeting"), userText("hi"), agentText("bye")],
            "leading agent turn")
    }

    // MARK: - displayTailForNewRounds pin (capture-side translate-only-tail)

    /// The capture fast path translates ONLY displayTailForNewRounds(display, existing)
    /// and freezes its rounds. For that to persist the SAME bytes as the original path
    /// (translate the whole history, then slice rounds[existing...]), the translated
    /// tail must equal the tail of the full translate for every prefix length. This
    /// pins that equality (and that the tail begins with a user turn); a drift would
    /// freeze wrong or duplicated bytes on the write path.
    func testDisplayTailForNewRounds_translatesToFullHistoryTail() throws {
        let req = UUID()
        let display = [
            userText("first"), agentText("reply one"),                    // round 0
            userText("run a tool"),
            { var m = requestMessage(callID: "c1", requestUUID: req); m.responseID = "r1"; return m }(),
            responseMessage(callID: "c1", requestUUID: req),
            agentText("tool done"),                                       // round 1
            userText("third"), agentText("reply three"),                 // round 2
        ]
        let full = ChatAgent.translateForTesting(display, resolve: { _ in nil })
        let fullRounds = ChatBlobCapture.rounds(from: full)
        XCTAssertEqual(fullRounds.count, 3)

        for existing in 0...(fullRounds.count + 1) {
            let tail = ChatAgent.displayTailForNewRounds(display, existing: existing)
            if existing >= fullRounds.count {
                XCTAssertNil(tail, "no rounds beyond \(existing); tail must be nil")
                continue
            }
            let tailMessages = ChatAgent.translateForTesting(try XCTUnwrap(tail), resolve: { _ in nil })
            let expected = Array(fullRounds[existing...]).flatMap { $0 }
            XCTAssertEqual(tailMessages, expected,
                           "translated tail (existing=\(existing)) must equal the full translate's tail")
            XCTAssertEqual(tailMessages.first?.role, .user,
                           "the tail must begin at a round boundary (a user turn)")
        }
    }

    // MARK: - carriedPreviousResponseID (blob-native pre-reduce delta mode)

    private func agentTextWithID(_ s: String, _ responseID: String?) -> Message {
        var m = agentText(s)
        m.responseID = responseID
        return m
    }

    /// The id load() carries forward for a pre-reduced Responses chat must equal what
    /// AIConversation would pick from the non-reduced conversation --
    /// translate(messages).last { .assistant }?.responseID -- INCLUDING when that id
    /// is nil. The `nil` case is the whole point: a terminal assistant turn with no
    /// id must yield nil (full resend), never an earlier turn's stale id.
    private func assertCarriedIDMatchesTranslate(_ messages: [Message],
                                                 _ label: String,
                                                 file: StaticString = #file,
                                                 line: UInt = #line) {
        let viaTranslate = ChatAgent.translateForTesting(messages, resolve: { _ in nil })
            .last { $0.role == .assistant }?.responseID
        let carried = ChatAgent.carriedPreviousResponseID(messages)
        XCTAssertEqual(carried, viaTranslate,
                       "carriedPreviousResponseID diverged from translate for: \(label)",
                       file: file, line: line)
    }

    func testCarriedPreviousResponseID_mirrorsTranslateSelection() {
        // Normal Responses chat: the last assistant's id is carried.
        assertCarriedIDMatchesTranslate(
            [userText("a"), agentTextWithID("b", "resp_1"),
             userText("c"), agentTextWithID("d", "resp_2")],
            "carries the last assistant id")
        XCTAssertEqual(
            ChatAgent.carriedPreviousResponseID(
                [userText("a"), agentTextWithID("b", "resp_1"),
                 userText("c"), agentTextWithID("d", "resp_2")]),
            "resp_2")

        // The reviewer's case: terminal assistant turn has NO id but an earlier one
        // does. Must yield nil (full resend), NOT the stale earlier id.
        let staleTrap = [userText("a"), agentTextWithID("b", "resp_1"),
                         userText("c"), agentTextWithID("d", nil)]
        assertCarriedIDMatchesTranslate(staleTrap, "nil terminal id does not revive earlier id")
        XCTAssertNil(ChatAgent.carriedPreviousResponseID(staleTrap),
                     "a nil-id terminal assistant turn must not carry an earlier turn's id")

        // Trailing tool_result (role .function) after an assistant with an id: the id
        // is still carried (the function turn is skipped), matching translate.
        let req = UUID()
        assertCarriedIDMatchesTranslate(
            [userText("run"),
             { var m = requestMessage(callID: "c1", requestUUID: req); m.responseID = "resp_9"; return m }(),
             responseMessage(callID: "c1", requestUUID: req)],
            "trailing tool_result skipped; assistant id carried")

        // No assistant turn at all: nil.
        assertCarriedIDMatchesTranslate([userText("hi")], "no assistant -> nil")
        XCTAssertNil(ChatAgent.carriedPreviousResponseID([userText("hi")]))
    }
}
