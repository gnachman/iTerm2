//
//  ChatMessageDeletionTests.swift
//  iTerm2 ModernTests
//
//  Edit/Delete in an AI chat truncate the log from a chosen message onward.
//  The UI (and the companion phone) can only name the rows it displays, so the
//  truncation must also drop rows that are never displayed (hidden tool
//  results, resolved tool requests); otherwise they stay in the store and the
//  next turn's history ships orphaned tool rows to the LLM. A deleted message
//  that is still queued for a future turn must also leave the agent's queue so
//  it is never sent.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class ChatMessageDeletionTests: XCTestCase {
    private func makeBroker() throws -> (ChatBroker, ChatListModel, String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
        let listModel = try XCTUnwrap(ChatListModel(database: db))
        let chat = Chat(title: "t", permissions: "")
        try listModel.add(chat: chat)
        return (ChatBroker(listModel: listModel), listModel, chat.id)
    }

    private func userText(_ text: String, chatID: String) -> Message {
        Message(chatID: chatID,
                author: .user,
                content: .plainText(text, context: nil),
                sentDate: Date(),
                uniqueID: UUID())
    }

    private func agentText(_ text: String, chatID: String) -> Message {
        Message(chatID: chatID,
                author: .agent,
                content: .markdown(text),
                sentDate: Date(),
                uniqueID: UUID())
    }

    // A tool result: hiddenFromClient, so the chat view never shows it and can
    // never name it in a deletion.
    private func hiddenToolResult(chatID: String) -> Message {
        Message(chatID: chatID,
                author: .user,
                content: .remoteCommandResponse(.success("ok"), UUID(), "executeCommand", nil),
                sentDate: Date(),
                uniqueID: UUID())
    }

    private func storedIDs(_ listModel: ChatListModel, _ chatID: String) -> [UUID] {
        guard let messages = listModel.messages(forChat: chatID, createIfNeeded: false) else {
            return []
        }
        return messages.map(\.uniqueID)
    }

    // The view asks to delete only the displayed rows from a message onward.
    // Hidden rows interleaved with and trailing them must go too, or the next
    // turn's history carries orphaned tool rows.
    func testDeleteRemovesHiddenRowsAfterEarliestDeletedMessage() throws {
        let (broker, listModel, chatID) = try makeBroker()
        let a = userText("a", chatID: chatID)
        let aReply = agentText("reply a", chatID: chatID)
        let b = userText("b", chatID: chatID)
        let hidden1 = hiddenToolResult(chatID: chatID)
        let bReply = agentText("reply b", chatID: chatID)
        let hidden2 = hiddenToolResult(chatID: chatID)
        for m in [a, aReply, b, hidden1, bReply, hidden2] {
            try listModel.append(message: m, toChatID: chatID)
        }
        XCTAssertTrue(hidden1.hiddenFromClient)

        var removed: [UUID]?
        let sub = broker.subscribe(chatID: chatID, registrationProvider: nil) { update in
            if case let .messagesRemoved(ids, _) = update { removed = ids }
        }
        defer { sub.unsubscribe() }

        // Exactly what the view's messageIDs(fromIndex:) would produce for "b".
        broker.deleteMessages([b.uniqueID, bReply.uniqueID], fromChatID: chatID)

        XCTAssertEqual(storedIDs(listModel, chatID), [a.uniqueID, aReply.uniqueID],
                       "every stored row from the earliest deleted message onward must be removed, hidden ones included")
        XCTAssertEqual(Set(removed ?? []),
                       Set([b.uniqueID, hidden1.uniqueID, bReply.uniqueID, hidden2.uniqueID]),
                       "subscribers (the agent queue, the phone) must learn of every removed row")
    }

    // Order of the requested IDs must not matter: truncation starts at the
    // earliest stored match.
    func testDeleteTruncatesFromEarliestStoredMatchRegardlessOfArgumentOrder() throws {
        let (broker, listModel, chatID) = try makeBroker()
        let a = userText("a", chatID: chatID)
        let b = userText("b", chatID: chatID)
        let hidden = hiddenToolResult(chatID: chatID)
        let c = userText("c", chatID: chatID)
        for m in [a, b, hidden, c] {
            try listModel.append(message: m, toChatID: chatID)
        }
        broker.deleteMessages([c.uniqueID, b.uniqueID], fromChatID: chatID)
        XCTAssertEqual(storedIDs(listModel, chatID), [a.uniqueID])
    }

    // IDs the store doesn't know (already gone) still fan out so displays
    // converge, and leave the store alone.
    func testDeleteOfUnknownIDsLeavesStoreAndStillFansOut() throws {
        let (broker, listModel, chatID) = try makeBroker()
        let a = userText("a", chatID: chatID)
        try listModel.append(message: a, toChatID: chatID)
        var removed: [UUID]?
        let sub = broker.subscribe(chatID: chatID, registrationProvider: nil) { update in
            if case let .messagesRemoved(ids, _) = update { removed = ids }
        }
        defer { sub.unsubscribe() }
        let ghost = UUID()
        broker.deleteMessages([ghost], fromChatID: chatID)
        XCTAssertEqual(storedIDs(listModel, chatID), [a.uniqueID])
        XCTAssertEqual(removed, [ghost])
    }

    // Chat-state rows (permissions, vector store) are hidden too, but they are
    // agent state, not conversation: ChatAgent.load takes permissions from the
    // latest stored .setPermissions, so truncating it would silently roll the
    // agent back to an older, possibly broader, permission set.
    func testDeleteKeepsChatStateRows() throws {
        let (broker, listModel, chatID) = try makeBroker()
        func row(_ content: Message.Content) -> Message {
            Message(chatID: chatID, author: .user, content: content,
                    sentDate: Date(), uniqueID: UUID())
        }
        let a = userText("a", chatID: chatID)
        let broad = row(.setPermissions([.runCommands, .viewContents]))
        let b = userText("b", chatID: chatID)
        let narrow = row(.setPermissions([.viewContents]))
        let hidden = hiddenToolResult(chatID: chatID)
        let bReply = agentText("reply b", chatID: chatID)
        for m in [a, broad, b, narrow, hidden, bReply] {
            try listModel.append(message: m, toChatID: chatID)
        }
        var removed: [UUID]?
        let sub = broker.subscribe(chatID: chatID, registrationProvider: nil) { update in
            if case let .messagesRemoved(ids, _) = update { removed = ids }
        }
        defer { sub.unsubscribe() }

        broker.deleteMessages([b.uniqueID, bReply.uniqueID], fromChatID: chatID)

        XCTAssertEqual(storedIDs(listModel, chatID), [a.uniqueID, broad.uniqueID, narrow.uniqueID],
                       "the newest permissions row must survive; conversation rows after b must not")
        XCTAssertEqual(Set(removed ?? []), Set([b.uniqueID, hidden.uniqueID, bReply.uniqueID]),
                       "a kept state row must not be reported as removed")
    }

    // MARK: - Pending queue

    // A deleted message queued behind the in-flight turn must be dequeued so it
    // is never sent to the LLM.
    func testRemovedQueuedMessageIsDequeued() {
        let head = userText("head", chatID: "c")
        let queuedB = userText("b", chatID: "c")
        let queuedC = userText("c", chatID: "c")
        let result = ChatService.pendingQueue([head, queuedB, queuedC],
                                              removingMessageIDs: [queuedB.uniqueID])
        XCTAssertEqual(result.map(\.uniqueID), [head.uniqueID, queuedC.uniqueID])
    }

    // The in-flight head is owned by the running turn, whose finishTurn pops
    // index 0. Removing it here would make finishTurn pop the wrong message.
    func testInFlightHeadIsNeverDequeued() {
        let head = userText("head", chatID: "c")
        let queued = userText("b", chatID: "c")
        let result = ChatService.pendingQueue([head, queued],
                                              removingMessageIDs: [head.uniqueID, queued.uniqueID])
        XCTAssertEqual(result.map(\.uniqueID), [head.uniqueID])
    }
    // MARK: - In-flight turn (F-086)

    // Deleting the message whose turn is running abandons that turn: its reply
    // answers a message that is gone, so it must be discarded, not appended
    // after the cut.
    func testDeletingInFlightHeadAbandonsTurnAndDiscardsItsReply() {
        let head = userText("head", chatID: "c")
        var abandoned = ChatService.AbandonedTurns()
        XCTAssertTrue(abandoned.abandonHead(of: [head], ifRemoved: [head.uniqueID]),
                      "removing the in-flight head must cancel its turn")
        XCTAssertTrue(abandoned.contains(head.uniqueID),
                      "the abandoned turn's streaming chunks and reply must be discarded")
    }

    // Removing only queued messages leaves the running turn alone: its message
    // still exists, so its reply is still wanted.
    func testDeletingOnlyQueuedMessagesKeepsInFlightTurn() {
        let head = userText("head", chatID: "c")
        let queued = userText("b", chatID: "c")
        var abandoned = ChatService.AbandonedTurns()
        XCTAssertFalse(abandoned.abandonHead(of: [head, queued], ifRemoved: [queued.uniqueID]))
        XCTAssertFalse(abandoned.contains(head.uniqueID),
                       "a turn whose message survives must publish its reply")
    }

    // An idle chat has no turn to cancel.
    func testDeletingWithEmptyQueueAbandonsNothing() {
        var abandoned = ChatService.AbandonedTurns()
        XCTAssertFalse(abandoned.abandonHead(of: [], ifRemoved: [UUID()]))
    }

    // Abandonment is per turn: the message the user sends next is a new turn
    // whose reply is published normally, while a straggling chunk or completion
    // of the abandoned turn is still recognized after the next turn starts.
    func testAbandonmentIsPerTurn() {
        let deleted = userText("deleted", chatID: "c")
        let next = userText("next", chatID: "c")
        var abandoned = ChatService.AbandonedTurns()
        XCTAssertTrue(abandoned.abandonHead(of: [deleted], ifRemoved: [deleted.uniqueID]))
        XCTAssertFalse(abandoned.abandonHead(of: [next], ifRemoved: [deleted.uniqueID]))
        XCTAssertFalse(abandoned.contains(next.uniqueID))
        XCTAssertTrue(abandoned.contains(deleted.uniqueID))
    }
}
