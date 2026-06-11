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

    func start(onEvent: @escaping @Sendable (CompanionHostMessage) -> Void,
               onClose: @escaping @Sendable () -> Void) async {
        await session.start(onEvent: onEvent, onClose: onClose)
    }

    /// Liveness check; throws if the mac does not answer.
    func ping() async throws {
        _ = try await session.request(.ping)
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

    /// Delete a chat. No reply; the mac pushes a fresh chat list (or an
    /// error) afterwards.
    func deleteChat(chatID: String) async throws {
        try await session.send(.deleteChat(chatID: chatID))
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

    func sendSelectSessionResponse(chatID: String,
                                   originalMessage: Message,
                                   sessionGuid: String?,
                                   terminal: Bool) async throws {
        try await session.send(.selectSessionResponse(chatID: chatID,
                                                      originalMessage: originalMessage,
                                                      sessionGuid: sessionGuid,
                                                      terminal: terminal))
    }

    func sendRemoteCommandDecision(chatID: String,
                                   messageUniqueID: UUID,
                                   decision: CompanionRemoteCommandDecision) async throws {
        try await session.send(.remoteCommandDecision(chatID: chatID,
                                                      messageUniqueID: messageUniqueID,
                                                      decision: decision))
    }

    func sendLinkSession(chatID: String, sessionGuid: String, terminal: Bool) async throws {
        try await session.send(.linkSession(chatID: chatID, sessionGuid: sessionGuid, terminal: terminal))
    }

    func resolveMentions(_ identifiers: [String]) async throws -> [CompanionMentionResolution] {
        let reply = try await session.request(.resolveMentions(identifiers: identifiers))
        switch reply {
        case .mentionsResolved(let resolutions):
            return resolutions
        case .error(let error):
            throw error
        default:
            throw CompanionError(code: .badRequest, message: "Unexpected reply to mention resolution")
        }
    }

    func sessionScreenInfo(guid: String) async throws -> CompanionSessionScreenInfo {
        let reply = try await session.request(.fetchSessionScreenInfo(sessionGuid: guid))
        switch reply {
        case .sessionScreenInfo(let info):
            return info
        case .error(let error):
            throw error
        default:
            throw CompanionError(code: .badRequest, message: "Unexpected reply to session info request")
        }
    }

    func sessionContent(guid: String, firstLine: Int, lineCount: Int) async throws -> CompanionSessionContent {
        let reply = try await session.request(.fetchSessionContent(sessionGuid: guid,
                                                                   firstLine: firstLine,
                                                                   lineCount: lineCount))
        switch reply {
        case .sessionContent(let content):
            return content
        case .error(let error):
            throw error
        default:
            throw CompanionError(code: .badRequest, message: "Unexpected reply to session content request")
        }
    }

    func workgroupInfo(id: String) async throws -> CompanionWorkgroupInfo {
        let reply = try await session.request(.fetchWorkgroupInfo(workgroupID: id))
        switch reply {
        case .workgroupInfo(let info):
            return info
        case .error(let error):
            throw error
        default:
            throw CompanionError(code: .badRequest, message: "Unexpected reply to workgroup info request")
        }
    }

    func sessionTree() async throws -> CompanionSessionTree {
        let reply = try await session.request(.fetchSessionTree)
        switch reply {
        case .sessionTree(let tree):
            return tree
        case .error(let error):
            throw error
        default:
            throw CompanionError(code: .badRequest, message: "Unexpected reply to session tree request")
        }
    }

    /// Report this device's push capability (and credentials) to the mac.
    func sendPushStatus(authorization: CompanionPushAuthorization,
                        token: Data?,
                        relaySecret: Data?,
                        sandbox: Bool) async throws {
        try await session.send(.pushStatus(authorization: authorization,
                                           token: token,
                                           relaySecret: relaySecret,
                                           sandbox: sandbox))
    }

    /// Answer the mac's notification-permission request.
    func sendNotificationPermissionResponse(requestID: UInt64,
                                            authorization: CompanionPushAuthorization) async throws {
        try await session.send(.notificationPermissionResponse(requestID: requestID,
                                                               authorization: authorization))
    }

    /// Tell the mac this device is unpairing (sent before close()).
    func sendUnpairing() async throws {
        try await session.send(.unpairing)
    }

    func close() async {
        await session.close()
    }
}
