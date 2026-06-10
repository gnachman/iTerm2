//
//  CompanionMessages.swift
//  iTerm2
//
//  NOTE: This file is also compiled into the iTerm2 Companion iOS app. Keep it
//  platform-neutral (Foundation only); Mac-only code goes in sibling files.
//
//  The application-level protocol spoken over the (Noise-encrypted) channel.
//  It deliberately mirrors the macOS ChatClient <-> ChatBroker surface, and it
//  carries the real model types (Chat, Message) rather than parallel DTOs so
//  the phone renders exactly what the Mac renders. Types the Mac model embeds
//  that cannot cross (today: iTermCodableLocatedString) have same-named,
//  wire-compatible stand-ins on the phone.
//

import Foundation
import CompanionProtocol

/// What a terminal session looks like on the wire. PTYSession itself cannot
/// cross, so this is the protocol's projection of one (used by the phone's
/// session picker).
public struct CompanionSessionSummary: Codable, Equatable, Hashable {
    public var guid: String
    public var name: String
    public var subtitle: String

    public init(guid: String, name: String, subtitle: String) {
        self.guid = guid
        self.name = name
        self.subtitle = subtitle
    }
}

/// A chat-list row: the chat plus its snippet (which the Mac computes from the
/// last visible message; the phone has no messages until it subscribes).
struct CompanionChatListEntry: Codable {
    var chat: Chat
    var snippet: String?
}

/// How a new chat should be created (the phone's Create screen).
enum CompanionNewChatMode: Codable, Equatable {
    /// Orchestrator chat that can see all sessions.
    case orchestrator
    /// Chat bound to a single terminal session.
    case session(guid: String)
}

/// Sent by the phone (client) to the mac (host).
enum CompanionClientMessage: Codable {
    /// Home screen: ask for the chat list and the session list in one round
    /// trip. Replied to with `.chatsAndSessions`.
    case listChatsAndSessions

    /// Create screen: create a chat. Replied to with `.chatCreated`.
    case createChat(title: String, mode: CompanionNewChatMode)

    /// Delete a chat. No reply beyond an optional `.error`.
    case deleteChat(chatID: String)

    /// Begin receiving `.delivery` / `.typingStatus` events for a chat and
    /// replay its history. Replied to with `.history`, then a live stream.
    case subscribe(chatID: String)

    /// Stop receiving events for a chat.
    case unsubscribe(chatID: String)

    /// Publish a user message to a chat (the phone only ever sends user-author
    /// messages). `partial` matches ChatBroker.publish(partial:).
    case publish(message: Message, toChatID: String, partial: Bool)

    /// Liveness check. Replied to with `.pong`.
    case ping

    /// The phone is unpairing: the mac should forget the pairing and destroy
    /// its key material. No reply; the phone closes after sending.
    case unpairing
}

/// Sent by the mac (host) to the phone (client). Either a reply correlated to a
/// client requestID (carried by the envelope) or an unsolicited event with no
/// requestID (a subscription delivery).
enum CompanionHostMessage: Codable {
    /// Reply to `.listChatsAndSessions`.
    case chatsAndSessions(chats: [CompanionChatListEntry], sessions: [CompanionSessionSummary])

    /// Reply to `.createChat`.
    case chatCreated(entry: CompanionChatListEntry)

    /// Reply to `.subscribe`: the existing visible messages, oldest first.
    case history(chatID: String, messages: [Message])

    /// Unsolicited: a message was delivered to a subscribed chat. Mirrors
    /// ChatBroker.Update.delivery(Message, chatID). `partial` is true for
    /// streaming deltas (append/appendAttachment/commit).
    case delivery(message: Message, chatID: String, partial: Bool)

    /// Unsolicited: typing-status change. Mirrors
    /// ChatBroker.Update.typingStatus(Bool, Participant).
    case typingStatus(isTyping: Bool, participant: Participant, chatID: String)

    /// Reply to `.ping`.
    case pong

    /// Unsolicited farewell: the mac unpaired this device. The phone should
    /// forget its stored pairing and return to the scan screen. Sent (and
    /// flushed) just before the mac closes the connection.
    case unpaired

    /// An error, optionally correlated to a request via the envelope.
    case error(CompanionError)
}

/// The framed envelope every application message travels in. `requestID`
/// correlates a host reply with the client message that triggered it; it is nil
/// for unsolicited host events (deliveries, typing status).
struct CompanionEnvelope<Payload: Codable>: Codable {
    var requestID: UInt64?
    var payload: Payload

    init(requestID: UInt64?, payload: Payload) {
        self.requestID = requestID
        self.payload = payload
    }
}

typealias ClientEnvelope = CompanionEnvelope<CompanionClientMessage>
typealias HostEnvelope = CompanionEnvelope<CompanionHostMessage>
