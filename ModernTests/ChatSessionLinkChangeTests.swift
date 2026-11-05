//
//  ChatSessionLinkChangeTests.swift
//  iTerm2
//
//  Created by George Nachman on 11/4/26.
//

import XCTest
@testable import iTerm2SharedARC

/// A chat's session link is written from several places (the chat window, the companion app,
/// link repair). The chat's view model tells its delegate about every change, so the view
/// controller keeps its command-output registration on the linked session however the link was
/// written.
final class ChatSessionLinkChangeTests: XCTestCase {
    private final class DelegateSpy: ChatViewControllerModelDelegate {
        var linkChanges = 0
        func chatViewControllerModel(didInsertItemAtIndex: Int) {}
        func chatViewControllerModel(didRemoveItemsInRange range: Range<Int>) {}
        func chatViewControllerModel(didModifyItemsAtIndexes indexSet: IndexSet) {}
        func chatViewControllerModelSessionLinkDidChange() {
            linkChanges += 1
        }
    }

    private func makeDatabase() throws -> ChatDatabase {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("chatlinktest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return try XCTUnwrap(ChatDatabase(url: dir.appendingPathComponent("chatdb.sqlite")))
    }

    private func makeListModel() throws -> ChatListModel {
        try XCTUnwrap(ChatListModel(database: try makeDatabase()))
    }

    func testLinkChangesReachTheDelegateWhicheverWriterMadeThem() throws {
        let listModel = try makeListModel()
        let chat = Chat(title: "Linked", permissions: "")
        try listModel.add(chat: chat)
        let other = Chat(title: "Other", permissions: "")
        try listModel.add(chat: other)
        let model = ChatViewControllerModel(chatID: chat.id, listModel: listModel)
        let spy = DelegateSpy()
        model.delegate = spy

        // Written through the list model directly, as the companion app does.
        try listModel.setTerminalGuid(for: chat.id, to: "session-a")
        XCTAssertEqual(spy.linkChanges, 1)
        XCTAssertEqual(model.terminalSessionGuid, "session-a")

        try listModel.setTerminalGuid(for: chat.id, to: "session-a")
        XCTAssertEqual(spy.linkChanges, 1, "Writing the same link is not a change")

        try listModel.setTerminalGuid(for: other.id, to: "session-b")
        XCTAssertEqual(spy.linkChanges, 1, "Another chat's link is not this chat's")

        try model.setTerminalSessionGuid(nil)
        XCTAssertEqual(spy.linkChanges, 2, "Unlinking is a change")
    }

    /// Turning on orchestration clears the links, which is a change.
    func testEnablingOrchestrationIsALinkChange() throws {
        let listModel = try makeListModel()
        let chat = Chat(title: "Linked", permissions: "")
        try listModel.add(chat: chat)
        try listModel.setTerminalGuid(for: chat.id, to: "session-a")
        let model = ChatViewControllerModel(chatID: chat.id, listModel: listModel)
        let spy = DelegateSpy()
        model.delegate = spy

        try listModel.setOrchestrationEnabled(true, forChatID: chat.id)
        XCTAssertEqual(spy.linkChanges, 1)
        XCTAssertNil(model.terminalSessionGuid)

        try listModel.setOrchestrationEnabled(false, forChatID: chat.id)
        try listModel.setOrchestrationEnabled(true, forChatID: chat.id)
        XCTAssertEqual(spy.linkChanges, 1, "A chat with no links has none to change")
    }

    /// Unlinking a session that went away clears the links of the chats linked to it.
    @MainActor
    func testUnlinkingASessionIsALinkChange() throws {
        let db = try makeDatabase()
        let listModel = try XCTUnwrap(ChatListModel(database: db))
        let chat = Chat(title: "Linked", permissions: "")
        try listModel.add(chat: chat)
        let other = Chat(title: "Other", permissions: "")
        try listModel.add(chat: other)
        try listModel.setTerminalGuid(for: chat.id, to: "session-a")
        try listModel.setTerminalGuid(for: other.id, to: "session-b")
        let model = ChatViewControllerModel(chatID: chat.id, listModel: listModel)
        let spy = DelegateSpy()
        model.delegate = spy
        let otherModel = ChatViewControllerModel(chatID: other.id, listModel: listModel)
        let otherSpy = DelegateSpy()
        otherModel.delegate = otherSpy

        db.unlink(sessionGuid: "session-a")
        XCTAssertEqual(spy.linkChanges, 1)
        XCTAssertEqual(otherSpy.linkChanges, 0, "Only the chats linked to the session change")
    }
}
