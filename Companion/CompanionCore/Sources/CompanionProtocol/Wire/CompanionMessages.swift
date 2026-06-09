//
//  CompanionMessages.swift
//  CompanionCore
//
//  The application-level protocol spoken over the (Noise-encrypted) channel.
//  It deliberately mirrors the macOS ChatClient <-> ChatBroker surface: the
//  phone is a remote ChatClient and the mac runs a bridge that forwards these
//  to its real ChatBroker.
//
//  ChatBroker recap (mac):
//    create(chatWithTitle:terminalSessionGuid:...) -> chatID
//    delete(chatID:)
//    publish(message:toChatID:partial:)
//    subscribe(chatID:) -> stream of Update { .delivery(Message, chatID),
//                                             .typingStatus(Bool, Participant) }
//
//  The companion protocol adds listing (the phone has no local database) and
//  request/response correlation via a client-assigned requestID.
//

import Foundation

/// How a new chat should be created. Mirrors the two choices on the phone's
/// Create screen.
public enum ChatModeDTO: Codable, Equatable, Hashable {
    /// Orchestrator chat that can see all sessions.
    case orchestrator
    /// Chat bound to a single terminal session.
    case session(guid: String)
}

/// Sent by the phone (client) to the mac (host).
public enum CompanionClientMessage: Codable {
    /// Home screen: ask for the chat list and the session list in one round
    /// trip. Replied to with `.chatsAndSessions`.
    case listChatsAndSessions

    /// Create screen: create a chat. Replied to with `.chatCreated`.
    case createChat(title: String, mode: ChatModeDTO)

    /// Delete a chat. No reply beyond an optional `.error`.
    case deleteChat(chatID: String)

    /// Begin receiving `.delivery` / `.typingStatus` events for a chat and
    /// replay its history. Replied to with `.history`, then a live stream.
    case subscribe(chatID: String)

    /// Stop receiving events for a chat.
    case unsubscribe(chatID: String)

    /// Publish a user message to a chat (the phone only ever sends user-author
    /// messages). `partial` matches ChatBroker.publish(partial:).
    case publish(message: MessageDTO, toChatID: String, partial: Bool)

    /// Liveness check. Replied to with `.pong`.
    case ping
}

/// Sent by the mac (host) to the phone (client). Either a reply correlated to a
/// client requestID (carried by the envelope) or an unsolicited event with no
/// requestID (a subscription delivery).
public enum CompanionHostMessage: Codable {
    /// Reply to `.listChatsAndSessions`.
    case chatsAndSessions(chats: [ChatDTO], sessions: [SessionDTO])

    /// Reply to `.createChat`.
    case chatCreated(chat: ChatDTO)

    /// Reply to `.subscribe`: the existing messages, oldest first.
    case history(chatID: String, messages: [MessageDTO])

    /// Unsolicited: a message was delivered to a subscribed chat. Mirrors
    /// ChatBroker.Update.delivery(Message, chatID). `partial` is true for
    /// streaming deltas (append/commit).
    case delivery(message: MessageDTO, chatID: String, partial: Bool)

    /// Unsolicited: typing-status change. Mirrors
    /// ChatBroker.Update.typingStatus(Bool, Participant).
    case typingStatus(isTyping: Bool, participant: ParticipantDTO, chatID: String)

    /// Reply to `.ping`.
    case pong

    /// An error, optionally correlated to a request via the envelope.
    case error(CompanionError)
}

/// The framed envelope every application message travels in. `requestID`
/// correlates a host reply with the client message that triggered it; it is nil
/// for unsolicited host events (deliveries, typing status).
public struct CompanionEnvelope<Payload: Codable>: Codable {
    public var requestID: UInt64?
    public var payload: Payload

    public init(requestID: UInt64?, payload: Payload) {
        self.requestID = requestID
        self.payload = payload
    }
}

public typealias ClientEnvelope = CompanionEnvelope<CompanionClientMessage>
public typealias HostEnvelope = CompanionEnvelope<CompanionHostMessage>
