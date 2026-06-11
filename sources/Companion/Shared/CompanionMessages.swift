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

/// How one @-mention identifier resolved on the Mac. The phone renders the
/// display name as a tappable link that opens the session view (or, for a
/// workgroup, the member-list view).
struct CompanionMentionResolution: Codable, Equatable {
    /// The identifier as written after the "@": a bare session guid,
    /// "session:<uuid>", or "wg-<uuid>".
    var identifier: String
    /// The entity's live name, or nil when the identifier no longer resolves
    /// (the phone then shows the same "[defunct session]" text the Mac does).
    var displayName: String?
    /// The session to open when the mention is tapped. For a workgroup this is
    /// its leader session, mirroring the Mac's click behavior.
    var sessionGuid: String?
    /// Set when the mention names a real workgroup; tapping it opens the
    /// member list instead of a single session.
    var workgroupID: String?
}

/// The Mac's sessions organized the way the user sees them: window, tab,
/// pane, with one more level under panes that host a peer group.
struct CompanionSessionTree: Codable, Equatable {
    struct Window: Codable, Equatable {
        var title: String
        var tabs: [Tab]
    }
    struct Tab: Codable, Equatable {
        var title: String
        var panes: [Pane]
    }
    struct Pane: Codable, Equatable {
        /// The session currently occupying the pane.
        var session: CompanionSessionSummary
        /// All members of the pane's peer group when it hosts more than one
        /// session (e.g. a workgroup's Code Review peer); empty otherwise.
        var peers: [Peer]
    }
    struct Peer: Codable, Equatable {
        /// The peer's role name, e.g. “Code Review”.
        var roleName: String
        var session: CompanionSessionSummary
    }
    var windows: [Window]
}

/// One member of a workgroup, as shown in the phone's workgroup view.
struct CompanionWorkgroupMember: Codable, Equatable {
    var roleName: String
    /// nil when the member's session has not launched yet (or has exited).
    var sessionGuid: String?
    var sessionName: String?
    /// The session's machine-readable status (OSC 21337 / cc-status), when it
    /// reports one.
    var statusText: String?
    /// The status detail line, when present.
    var detailText: String?
    var state: SessionState
}

/// Reply payload describing a workgroup and its members.
struct CompanionWorkgroupInfo: Codable, Equatable {
    var workgroupID: String
    var name: String
    var members: [CompanionWorkgroupMember]
}

/// Geometry of a session's content, fetched before any pixels so the phone can
/// size its scrollable canvas and decide how many lines to request per tile.
struct CompanionSessionScreenInfo: Codable, Equatable {
    var guid: String
    var name: String
    /// Total renderable lines (scrollback plus screen).
    var lineCount: Int
    var columns: Int
    /// Width in Mac points of a rendered line image (includes side margins).
    var width: Double
    /// Height in Mac points of one line (the cell height).
    var lineHeight: Double
    /// The backing scale content is rendered at (Mac pixels per Mac point),
    /// so the phone can stop zooming at the bitmaps' native resolution.
    var scale: Double
}

/// One rendered slice of a session's content, as a bitmap.
struct CompanionSessionContent: Codable {
    var guid: String
    /// First line actually rendered (requests are clamped to valid lines).
    var firstLine: Int
    /// Number of lines actually rendered.
    var lineCount: Int
    var pngData: Data
}

/// The phone's notification-permission state, as iOS reports it.
enum CompanionPushAuthorization: String, Codable {
    /// The user has never been asked; the prompt can be shown.
    case notDetermined
    /// The user declined (or revoked in Settings); the prompt cannot be
    /// shown again, only Settings can change it.
    case denied
    case authorized
}

/// The user's verdict on a classic remoteCommandRequest bubble (the four
/// buttons the Mac shows: Allow Once / Always Allow / Deny this Time /
/// Always Deny).
enum CompanionRemoteCommandDecision: String, Codable {
    case allowOnce
    case allowAlways
    case denyOnce
    case denyAlways
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

    /// Resolve a selectSessionRequest: link the chosen session and republish
    /// the carried original message (sessionGuid != nil), or decline
    /// (sessionGuid == nil). Mirrors the Mac UI's Select a Session / Cancel.
    case selectSessionResponse(chatID: String, originalMessage: Message, sessionGuid: String?, terminal: Bool)

    /// The user's verdict on a remoteCommandRequest. The mac looks the message
    /// up by id and performs or declines it exactly as its own buttons would.
    case remoteCommandDecision(chatID: String, messageUniqueID: UUID, decision: CompanionRemoteCommandDecision)

    /// Link a session to the chat (the offerLink bubble's Link button).
    case linkSession(chatID: String, sessionGuid: String, terminal: Bool)

    /// Resolve @-mention identifiers (text after the "@") to live names and
    /// reveal targets. Replied to with `.mentionsResolved`.
    case resolveMentions(identifiers: [String])

    /// Session view: ask for a session's content geometry. Replied to with
    /// `.sessionScreenInfo`.
    case fetchSessionScreenInfo(sessionGuid: String)

    /// Session view: render a range of lines as a bitmap. Replied to with
    /// `.sessionContent`.
    case fetchSessionContent(sessionGuid: String, firstLine: Int, lineCount: Int)

    /// Workgroup view: list a workgroup's members with their status. Replied
    /// to with `.workgroupInfo`.
    case fetchWorkgroupInfo(workgroupID: String)

    /// Sessions tab: the window/tab/pane/peer hierarchy. Replied to with
    /// `.sessionTree`.
    case fetchSessionTree

    /// The phone's push capability, sent after each connection and again
    /// whenever it changes (permission granted, APNs token refreshed). When
    /// authorized and registered, carries the APNs token plus the
    /// phone-minted secret the Mac must present to the push relay; the Mac
    /// replaces any previously stored values. `sandbox` is true for
    /// development builds, whose tokens only work against APNs' sandbox
    /// environment.
    case pushStatus(authorization: CompanionPushAuthorization, token: Data?, relaySecret: Data?, sandbox: Bool)

    /// Reply to the host's `.requestNotificationPermission`, correlated by
    /// its requestID. A grant is followed by a `.pushStatus` carrying the
    /// token once APNs issues it.
    case notificationPermissionResponse(requestID: UInt64, authorization: CompanionPushAuthorization)

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

    /// Reply to `.resolveMentions`, one entry per requested identifier.
    case mentionsResolved([CompanionMentionResolution])

    /// Reply to `.fetchSessionScreenInfo`.
    case sessionScreenInfo(CompanionSessionScreenInfo)

    /// Reply to `.fetchSessionContent`.
    case sessionContent(CompanionSessionContent)

    /// Reply to `.fetchWorkgroupInfo`.
    case workgroupInfo(CompanionWorkgroupInfo)

    /// Reply to `.fetchSessionTree`.
    case sessionTree(CompanionSessionTree)

    /// Reply to `.ping`.
    case pong

    /// Unsolicited: ask the phone to prompt the user for notification
    /// permission (driven by the orchestrator's request_notification_
    /// permission tool). The phone replies with
    /// `.notificationPermissionResponse` carrying the same requestID.
    case requestNotificationPermission(requestID: UInt64)

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
