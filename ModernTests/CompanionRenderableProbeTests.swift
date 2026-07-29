//
//  CompanionRenderableProbeTests.swift
//  iTerm2 ModernTests
//
//  The single render predicate (Message.isCompanionRenderable) and the stateless
//  ChatDatabase.hasRenderableContentSince probe that the wakeup coordinator uses
//  instead of a drifting high-water mark. Together they are the structural fix for
//  the empty-placeholder class of bug: "should we push" is now defined by the SAME
//  predicate as "what the NSE renders".
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionRenderableProbeTests: XCTestCase {

    // MARK: - isCompanionRenderable predicate (no database)

    private func msg(_ content: Message.Content, author: Participant) -> Message {
        Message(chatID: "c", author: author, content: content, sentDate: Date(), uniqueID: UUID())
    }

    func testIsCompanionRenderable() {
        // A real agent reply renders.
        XCTAssertTrue(msg(.markdown("hello"), author: .agent).isCompanionRenderable)
        // The user's own message must never notify (wrong author).
        XCTAssertFalse(msg(.markdown("hi"), author: .user).isCompanionRenderable)
        // A substance-free agent message (whitespace only) does not render.
        XCTAssertFalse(msg(.markdown("   "), author: .agent).isCompanionRenderable)
        // Hidden bookkeeping (a .commit) does not render.
        XCTAssertFalse(msg(.commit(UUID()), author: .agent).isCompanionRenderable)
        // A .classic remote command blocks on the user (Allow/Deny) and MUST be shown.
        XCTAssertTrue(msg(.remoteCommandRequest(
            .classic(RemoteCommand(llmMessage: LLM.Message(role: .assistant, content: nil),
                                   content: .executeCommand(.init(command: "git push")))),
            safe: nil), author: .agent).isCompanionRenderable)
        // A .external orchestration tool call is auto-executed / informational only.
        XCTAssertFalse(msg(.remoteCommandRequest(
            .external(ExternalRemoteCommand(llmMessage: LLM.Message(role: .assistant, content: nil),
                                            name: "scroll_wheel", argsJSON: "{}",
                                            markdownDescription: "scrolling")),
            safe: nil), author: .agent).isCompanionRenderable)
        // A session pick also blocks on the user, so it is shown.
        XCTAssertTrue(msg(.selectSessionRequest(msg(.markdown("needs a session"), author: .agent),
                                                terminal: true),
                          author: .agent).isCompanionRenderable)
    }

    // MARK: - hasRenderableContentSince (live database)

    private func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("renderprobetest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func insert(_ db: iTermDatabase,
                        _ content: Message.Content,
                        author: Participant,
                        chatID: String = "c",
                        uniqueID: UUID = UUID()) throws {
        let m = Message(chatID: chatID, author: author, content: content,
                        sentDate: Date(), uniqueID: uniqueID)
        let (sql, args) = m.appendQuery()
        try db.executeUpdate(sql, withArguments: args)
    }

    private func classicRequest(_ command: String) -> Message.Content {
        .remoteCommandRequest(
            .classic(RemoteCommand(llmMessage: LLM.Message(role: .assistant, content: nil),
                                   content: .executeCommand(.init(command: command)))),
            safe: nil)
    }

    func testHasRenderableContentSince_messages() throws {
        let dir = try makeTempDir()
        let chatdb = try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
        // seq 1 renderable (agent reply); seq 2 not (user); seq 3 not (empty agent).
        try insert(chatdb.db, .markdown("the review finished"), author: .agent)  // 1
        try insert(chatdb.db, .markdown("thanks"), author: .user)                // 2
        try insert(chatdb.db, .markdown("   "), author: .agent)                  // 3

        // From the bottom: the agent reply at seq 1 is renderable.
        XCTAssertTrue(chatdb.hasRenderableContentSince(messageSeq: 0, alertSeq: 0, mutedChatIDs: []))
        // Past the reply: only a user row and an empty agent row remain -> nothing to
        // show. This is exactly the case that used to push and drain to a placeholder.
        XCTAssertFalse(chatdb.hasRenderableContentSince(messageSeq: 1, alertSeq: 0, mutedChatIDs: []))
        // A muted chat's renderable content is excluded.
        XCTAssertFalse(chatdb.hasRenderableContentSince(messageSeq: 0, alertSeq: 0, mutedChatIDs: ["c"]))
    }

    func testHasRenderableContentSince_alerts() throws {
        let dir = try makeTempDir()
        let chatdb = try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
        let seq = chatdb.insertAlert(CompanionAlertRecord(
            seq: 0, uniqueID: UUID(), threadKey: "t", title: "Alert", body: "Body", createdDate: Date()))
        XCTAssertEqual(seq, 1)
        // Above the alert floor -> renderable; at/above the alert's own seq -> nothing.
        XCTAssertTrue(chatdb.hasRenderableContentSince(messageSeq: 0, alertSeq: 0, mutedChatIDs: []))
        XCTAssertFalse(chatdb.hasRenderableContentSince(messageSeq: 0, alertSeq: 1, mutedChatIDs: []))
    }

    // MARK: - Answered .classic requests are resolved, not live prompts

    func testAnsweredClassicRequestIsResolved() {
        let reqID = UUID()
        let request = Message(chatID: "c", author: .agent, content: classicRequest("ls"),
                              sentDate: Date(), uniqueID: reqID)
        let response = Message(chatID: "c", author: .user,
                               content: .remoteCommandResponse(.success("ok"), reqID, "executeCommand", nil),
                               sentDate: Date(), uniqueID: UUID())
        let answered = Message.answeredRequestIDs(in: [request, response])
        XCTAssertEqual(answered, [reqID])
        XCTAssertTrue(request.isResolvedClassicRequest(answeredRequestIDs: answered),
                      "a .classic request with a matching response is resolved")
        let pending = Message(chatID: "c", author: .agent, content: classicRequest("git push"),
                              sentDate: Date(), uniqueID: UUID())
        XCTAssertFalse(pending.isResolvedClassicRequest(answeredRequestIDs: answered),
                       "an unanswered .classic request is still a live prompt")
        XCTAssertFalse(msg(.markdown("hi"), author: .agent).isResolvedClassicRequest(answeredRequestIDs: answered),
                       "a plain reply is never a resolved request")
    }

    func testHasRenderableContentSince_answeredClassicRequestIsNotShown() throws {
        let dir = try makeTempDir()
        let chatdb = try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
        // An auto-run .classic request is persisted alongside its response -> resolved.
        let reqID = UUID()
        try insert(chatdb.db, classicRequest("ls"), author: .agent, uniqueID: reqID)
        try insert(chatdb.db, .remoteCommandResponse(.success("ok"), reqID, "executeCommand", nil),
                   author: .user)
        XCTAssertFalse(chatdb.hasRenderableContentSince(messageSeq: 0, alertSeq: 0, mutedChatIDs: []),
                       "an answered (auto-run) .classic request must not count as renderable")
        // A later, UNANSWERED request is a live prompt worth showing.
        try insert(chatdb.db, classicRequest("git push"), author: .agent)
        XCTAssertTrue(chatdb.hasRenderableContentSince(messageSeq: 0, alertSeq: 0, mutedChatIDs: []),
                      "an unanswered .classic request is a pending prompt")
    }
}
