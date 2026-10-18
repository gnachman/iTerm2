//
//  ChatListSelectionFollowsChatTests.swift
//  iTerm2 ModernTests
//
//  Sending a message in a chat moves it to the top of the AI Chats list. The
//  selection must follow the chat to its new row rather than stay on the old
//  row index, which now shows a different chat (QA finding F-383).
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
private final class FakeChatListDataSource: ChatListDataSource {
    var chats: [Chat]

    init(chats: [Chat]) {
        self.chats = chats
    }

    func numberOfChats(in chatListViewController: ChatListViewController) -> Int {
        chats.count
    }

    func chatListViewController(_ chatListViewController: ChatListViewController, chatAt index: Int) -> Chat {
        chats[index]
    }

    func chatListViewController(_ viewController: ChatListViewController, indexOfChatID chatID: String) -> Int? {
        chats.firstIndex { $0.id == chatID }
    }

    func snippet(forChatID: String) -> String? {
        nil
    }

    func firstIndex(forGuid guid: String) -> Int? {
        nil
    }

    func chatSearchResultsIterator(query: String) -> AnySequence<ChatSearchResult> {
        AnySequence([])
    }
}

@MainActor
final class ChatListSelectionFollowsChatTests: XCTestCase {
    func testSelectionFollowsAChatThatMovesToTheTop() throws {
        let chats = (0..<5).map { Chat(title: "Chat \($0)", permissions: "") }
        let dataSource = FakeChatListDataSource(chats: chats)
        let viewController = ChatListViewController()
        viewController.dataSource = dataSource
        _ = viewController.view
        viewController.reloadData()

        let moved = chats[3]
        viewController.select(chatID: moved.id)
        XCTAssertEqual(viewController.selectedChatIDs(), [moved.id])

        // Bump the selected chat to the top, as ChatListModel does when a
        // message is added, and post the list-wide change notification.
        dataSource.chats.remove(at: 3)
        dataSource.chats.insert(moved, at: 0)
        NotificationCenter.default.post(name: ChatListModel.metadataDidChange, object: nil)

        XCTAssertEqual(viewController.selectedChatIDs(), [moved.id],
                       "the highlight should follow the chat to row 0")
        XCTAssertEqual(viewController.selectedChatID, moved.id)
    }

    // Moving a different chat above the selected one shifts the selected
    // chat's row down by one; the selection must follow it.
    func testSelectionFollowsAChatWhoseRowShifts() throws {
        let chats = (0..<5).map { Chat(title: "Chat \($0)", permissions: "") }
        let dataSource = FakeChatListDataSource(chats: chats)
        let viewController = ChatListViewController()
        viewController.dataSource = dataSource
        _ = viewController.view
        viewController.reloadData()

        let selected = chats[1]
        viewController.select(chatID: selected.id)

        let bumped = chats[4]
        dataSource.chats.remove(at: 4)
        dataSource.chats.insert(bumped, at: 0)
        NotificationCenter.default.post(name: ChatListModel.metadataDidChange, object: nil)

        XCTAssertEqual(viewController.selectedChatIDs(), [selected.id])
    }
}
