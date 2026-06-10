//
//  CompanionClient.swift
//  iTerm2 Companion
//
//  A typed facade over CompanionSession: it turns the companion request/reply
//  enums into async methods the UI can call, and forwards unsolicited host
//  events (deliveries, typing status) to a handler. The wire carries the real
//  model types (Chat, Message) shared with the Mac app.
//

import Foundation
import CompanionProtocol

actor CompanionClient {
    private let session: CompanionSession

    init(session: CompanionSession) {
        self.session = session
    }

    func start(onEvent: @escaping @Sendable (CompanionHostMessage) -> Void) async {
        await session.start(onEvent: onEvent)
    }

    func listChatsAndSessions() async throws -> (chats: [CompanionChatListEntry],
                                                 sessions: [CompanionSessionSummary]) {
        let reply = try await session.request(.listChatsAndSessions)
        switch reply {
        case .chatsAndSessions(let chats, let sessions):
            return (chats, sessions)
        case .error(let error):
            throw error
        default:
            throw CompanionError(code: .badRequest, message: "Unexpected reply to list request")
        }
    }

    func createChat(title: String, mode: CompanionNewChatMode) async throws -> CompanionChatListEntry {
        let reply = try await session.request(.createChat(title: title, mode: mode))
        switch reply {
        case .chatCreated(let entry):
            return entry
        case .error(let error):
            throw error
        default:
            throw CompanionError(code: .badRequest, message: "Unexpected reply to create request")
        }
    }

    /// Subscribe to a chat and return its existing history.
    func subscribe(chatID: String) async throws -> [Message] {
        let reply = try await session.request(.subscribe(chatID: chatID))
        switch reply {
        case .history(_, let messages):
            return messages
        case .error(let error):
            throw error
        default:
            throw CompanionError(code: .badRequest, message: "Unexpected reply to subscribe request")
        }
    }

    func unsubscribe(chatID: String) async throws {
        try await session.send(.unsubscribe(chatID: chatID))
    }

    func publish(_ message: Message, toChatID chatID: String) async throws {
        try await session.send(.publish(message: message, toChatID: chatID, partial: false))
    }

    func close() async {
        await session.close()
    }
}
