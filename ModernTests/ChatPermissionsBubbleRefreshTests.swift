//
//  ChatPermissionsBubbleRefreshTests.swift
//  iTerm2
//
//  Changing a permission from the chat's info menu must refresh the
//  permission buttons in the transcript, not only a change made with one of
//  those buttons. QA finding F-109.
//

import XCTest
@testable import iTerm2SharedARC

final class ChatPermissionsBubbleRefreshTests: XCTestCase {
    private func item(_ content: Message.Content) -> ChatViewControllerModel.Item {
        return .message(.init(Message(chatID: "c",
                                      author: .agent,
                                      content: content,
                                      sentDate: Date(),
                                      uniqueID: UUID())))
    }

    func testFindsEveryPermissionsBubble() {
        let items: [ChatViewControllerModel.Item] = [
            .date(DateComponents(year: 2026, month: 1, day: 1)),
            item(.clientLocal(ClientLocal(action: .permissions(terminal: true, guid: "g")))),
            item(.markdown("hello")),
            item(.clientLocal(ClientLocal(action: .notice("n")))),
            item(.clientLocal(ClientLocal(action: .permissions(terminal: false, guid: "b")))),
            .agentTyping,
        ]
        XCTAssertEqual(ChatViewController.permissionsRowIndexes(in: items), IndexSet([1, 4]))
    }
}
