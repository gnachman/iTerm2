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
import CryptoKit

/// The opaque, per-chat APNs collapse id for the relay-push feature:
/// HMAC-SHA256(roomSecret, chatID), hex, truncated to 128 bits. Computed
/// identically on the Mac (push sender + host token resolver) and the phone
/// (per-chat watermark key + NSE), so the chatID never leaves the device in the
/// clear while same-chat pushes still coalesce and different chats stay
/// distinct. 32 hex chars, well under the APNs 64-byte collapse-id limit.
public enum CompanionCollapseToken {
    public static func make(roomSecret: Data, chatID: String) -> String {
        let code = HMAC<SHA256>.authenticationCode(for: Data(chatID.utf8),
                                                   using: SymmetricKey(data: roomSecret))
        return Data(Data(code).prefix(16)).hexEncodedString()
    }
}

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

/// One display-ready message in a `.messagesSince` reply: a short body (built
/// Mac-side via Content.snippetText, so attachments are byte-free placeholders
/// and long turns are truncated) plus the bits the NSE needs to render and
/// de-duplicate one notification. Carries no attachment bytes and no full
/// Message, by design (docs/push.txt section 2).
struct CompanionMessagePreview: Codable, Equatable {
    var uniqueID: UUID
    var author: Participant
    var body: String

    init(uniqueID: UUID, author: Participant, body: String) {
        self.uniqueID = uniqueID
        self.author = author
        self.body = body
    }
}

/// One display-ready chat message in a `.syncSince` reply. Unlike
/// CompanionMessagePreview it carries the `chatID` and `seq`, because a unified
/// sync returns items from MANY chats: the NSE computes each notification's
/// threadIdentifier on-device as HMAC(roomSecret, chatID) (so no per-chat id
/// crosses the APNs payload) and uses `seq` to advance the per-chat watermark and
/// the global message floor. Carries no attachment bytes and no full Message.
struct CompanionSyncMessageItem: Codable, Equatable {
    var chatID: String
    var chatName: String
    var uniqueID: UUID
    var author: Participant
    var body: String
    var seq: Int64
}

/// One terminal alert (e.g. "Mark Set", a fired notification trigger) in a
/// `.syncSince` reply. `threadKey` is the source session's guid; the NSE groups a
/// session's alerts by computing HMAC(roomSecret, "alert:" + threadKey)
/// on-device. `seq` advances the global alert floor. Alerts have no in-app
/// read-state, so the floor is both the query bound and the suppression cursor.
struct CompanionSyncAlertItem: Codable, Equatable {
    var alertID: UUID
    var threadKey: String
    var title: String
    var body: String
    var seq: Int64
}

/// One item in a `.syncSince` reply: a chat message or a terminal alert. Custom
/// Codable so it encodes as {"message": {…}} / {"alert": {…}} (the synthesized
/// enum Codable would nest the value under "_0"); the slim NSESyncSince mirror
/// reproduces this flat single-key shape.
enum CompanionSyncItem: Equatable {
    case message(CompanionSyncMessageItem)
    case alert(CompanionSyncAlertItem)
}

extension CompanionSyncItem: Codable {
    private enum CodingKeys: String, CodingKey { case message, alert }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .message(let item): try container.encode(item, forKey: .message)
        case .alert(let item): try container.encode(item, forKey: .alert)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let item = try container.decodeIfPresent(CompanionSyncMessageItem.self, forKey: .message) {
            self = .message(item)
        } else if let item = try container.decodeIfPresent(CompanionSyncAlertItem.self, forKey: .alert) {
            self = .alert(item)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "CompanionSyncItem: neither message nor alert present"))
        }
    }
}

/// Sent by the phone (client) to the mac (host).
enum CompanionClientMessage: Codable, CompanionMessagePayload {
    /// A message type this build does not recognize (a newer phone sent it). The
    /// envelope decodes an unknown payload into this so the frame is not dropped;
    /// the host replies with a correlated error.
    case unsupported

    /// Version handshake, sent by the phone as its FIRST message after the Noise
    /// channel is up (before any other request). Carries this build's
    /// companion-protocol revision and the oldest peer revision it accepts. The
    /// mac replies with its own `.hello`; each side then decides whether an app
    /// upgrade is required. See CompanionProtocolVersion.
    case hello(revision: Int, minimumPeer: Int)

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

    /// Couriers the phone-minted relay room secret to the mac (re-sent every
    /// connect, idempotent). The mac persists it, derives the same relay-join
    /// signing key, and replies `.relayRoomSecretStored` (correlated by
    /// requestID). The phone waits for that ack before registering its verifier
    /// with the relay, so the room is never established while the mac lacks the
    /// key to park. See docs/companion-relay-design.md.
    case relayRoomSecret(Data)

    /// Relay-push: the NSE asks for new messages in the chat identified by the
    /// opaque per-chat collapse token (HMAC(roomSecret, chatID)), with seq
    /// greater than the phone's per-chat watermark. Replied to with
    /// `.messagesSince`. The token (not a chatID) is sent so the chatID never
    /// appears in the APNs payload; the mac resolves it back to a chat.
    ///
    /// `nonce` is the one-time value the mac placed in the triggering push and
    /// the NSE echoes back, so the mac can recognize its OWN solicited fetch and
    /// skip the presence warning. Optional for cross-version compatibility: an
    /// older NSE (or a push that carried none) omits it, decoding as nil.
    case messagesSince(collapseToken: String, seq: Int64, limit: Int, nonce: String?)

    /// Relay push (revision >= 2): woken by a contentless wakeup (the fixed
    /// `CompanionPushWakeup.collapseSentinel` collapse id), the NSE asks for
    /// everything new across ALL chats and alerts in one round trip. `messageSeq`
    /// is the phone's global message floor, `alertSeq` its global alert floor;
    /// the mac returns chat messages with seq > messageSeq and alerts with
    /// seq > alertSeq. Replied to with `.syncSince`. `nonce` works exactly as in
    /// `.messagesSince` (echoed back so the mac recognizes its own solicited
    /// fetch). Supersedes the per-chat `.messagesSince` push for new peers.
    case syncSince(messageSeq: Int64, alertSeq: Int64, limit: Int, nonce: String?)

    /// The phone is unpairing: the mac should forget the pairing and destroy
    /// its key material. No reply; the phone closes after sending.
    case unpairing

    /// Discriminators this build knows. MUST list every case above (except
    /// `.unsupported` is included so a peer that literally sends it round-trips).
    /// Add a line here whenever a case is added.
    static let knownPayloadKeys: Set<String> = [
        "unsupported", "hello", "listChatsAndSessions", "createChat", "deleteChat",
        "subscribe", "unsubscribe", "publish", "selectSessionResponse",
        "remoteCommandDecision", "linkSession", "resolveMentions",
        "fetchSessionScreenInfo", "fetchSessionContent", "fetchWorkgroupInfo",
        "fetchSessionTree", "pushStatus", "notificationPermissionResponse", "ping",
        "relayRoomSecret", "messagesSince", "syncSince", "unpairing",
    ]
}

/// Sent by the mac (host) to the phone (client). Either a reply correlated to a
/// client requestID (carried by the envelope) or an unsolicited event with no
/// requestID (a subscription delivery).
enum CompanionHostMessage: Codable, CompanionMessagePayload {
    /// A message type this build does not recognize (a newer mac sent it). The
    /// envelope decodes an unknown payload into this so the frame is not dropped;
    /// the phone ignores it (an unsolicited event) or treats it as an unexpected
    /// reply.
    case unsupported

    /// Reply to the phone's `.hello`: the mac's companion-protocol revision and
    /// the oldest peer revision it accepts, so the phone can decide whether an
    /// app upgrade is required.
    case hello(revision: Int, minimumPeer: Int)

    /// Reply to `.listChatsAndSessions`.
    case chatsAndSessions(chats: [CompanionChatListEntry], sessions: [CompanionSessionSummary])

    /// Reply to `.createChat`.
    case chatCreated(entry: CompanionChatListEntry)

    /// Reply to `.subscribe`: the existing visible messages, oldest first, plus
    /// the chat's current max seq so the phone can advance its per-chat push
    /// watermark (subscribing == viewing the chat == read up to maxSeq), keeping
    /// the NSE from re-notifying already-read turns. See docs/push.txt section 8.
    case history(chatID: String, messages: [Message], maxSeq: Int64)

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

    /// Ack of `.relayRoomSecret` (correlated by requestID): the mac persisted
    /// the room secret and can now sign its relay parks. The phone proceeds to
    /// register its verifier only after this.
    case relayRoomSecretStored

    /// Unsolicited: the Mac's chat list changed (a chat was renamed, its
    /// icon was generated, or a chat was created/deleted/reordered).
    /// Carries the fresh list; the phone replaces its copy. Session-list
    /// changes will get a sibling message when the need arises.
    case chatListChanged(chats: [CompanionChatListEntry])

    /// Unsolicited: ask the phone to prompt the user for notification
    /// permission (driven by the orchestrator's request_notification_
    /// permission tool). The phone replies with
    /// `.notificationPermissionResponse` carrying the same requestID.
    case requestNotificationPermission(requestID: UInt64)

    /// Unsolicited farewell: the mac unpaired this device. The phone should
    /// forget its stored pairing and return to the scan screen. Sent (and
    /// flushed) just before the mac closes the connection.
    case unpaired

    /// Reply to `.messagesSince`: short, display-ready previews (one
    /// notification each on the phone) in CHRONOLOGICAL order (oldest first - the
    /// previews carry no seq, so the NSE delivers them in this order verbatim),
    /// the chat's display title, the chat's current max seq (the per-chat
    /// watermark advances to this), and whether more visible messages existed than
    /// the limit. Empty previews mean nothing new, or the token matched no chat;
    /// either way the NSE shows the generic fallback.
    case messagesSince(chatName: String, previews: [CompanionMessagePreview], maxSeq: Int64, truncated: Bool, reset: Bool)

    /// Reply to `.syncSince`: every new chat message and alert, oldest first
    /// (items carry their own `seq` so the NSE both orders and filters them).
    /// `maxMessageSeq` / `maxAlertSeq` are the global tips the phone advances its
    /// floors to. `messageReset` / `alertReset` mean the corresponding floor was
    /// beyond the host's tip (the store rewound) and must be set DOWN rather than
    /// max-merged. `truncated` means more items existed than the limit. Empty
    /// items mean nothing new; the NSE shows the generic fallback.
    case syncSince(items: [CompanionSyncItem], maxMessageSeq: Int64, maxAlertSeq: Int64, messageReset: Bool, alertReset: Bool, truncated: Bool)

    /// An error, optionally correlated to a request via the envelope.
    case error(CompanionError)

    /// Discriminators this build knows. Add a line here whenever a case is added.
    static let knownPayloadKeys: Set<String> = [
        "unsupported", "hello", "chatsAndSessions", "chatCreated", "history",
        "delivery", "typingStatus", "mentionsResolved", "sessionScreenInfo",
        "sessionContent", "workgroupInfo", "sessionTree", "pong",
        "relayRoomSecretStored", "chatListChanged", "requestNotificationPermission",
        "unpaired", "messagesSince", "syncSince", "error",
    ]
}

/// The framed envelope every application message travels in. `requestID`
/// correlates a host reply with the client message that triggered it; it is nil
/// for unsolicited host events (deliveries, typing status).
/// A companion message that can represent "a message type this build does not
/// recognize." Lets CompanionEnvelope decode a newer peer's unknown message type
/// into a sentinel (preserving requestID) instead of failing the whole decode -
/// Swift's synthesized enum Codable throws on an unknown case, which would
/// otherwise make one new message type break an older peer entirely.
protocol CompanionMessagePayload: Codable {
    static var unsupported: Self { get }
    /// The discriminator keys (case names) this build recognizes. Synthesized
    /// enum Codable encodes a case as {"<caseName>": ...}; the envelope decoder
    /// maps an UNKNOWN discriminator to `.unsupported` (forward compatibility) but
    /// lets a decode failure of a KNOWN case propagate (a corrupt or newer-content
    /// body must not be masked as "unsupported"). Keep in sync with the cases.
    static var knownPayloadKeys: Set<String> { get }
}

struct CompanionEnvelope<Payload: CompanionMessagePayload>: Codable {
    var requestID: UInt64?
    var payload: Payload

    init(requestID: UInt64?, payload: Payload) {
        self.requestID = requestID
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey { case requestID, payload }

    // Custom decode for forward compatibility - but ONLY for a genuinely unknown
    // message TYPE. decodeForwardCompatible peeks the payload's discriminator: an
    // unknown case (a newer peer's new message type) throws
    // ForwardCompatibilityError.unknownCase, which we turn into `.unsupported`
    // with the requestID intact instead of failing the frame. A KNOWN case whose
    // body fails to decode (malformed, or a newer-content body) throws a
    // DecodingError that propagates to the read loop's drop-and-log path - a
    // blanket `try?` here would instead mask it as "unsupported", turning one bad
    // message into a failed reply (or a spurious "upgrade required"). Encoding
    // stays synthesized. (Shared with Message/ClientLocal; see
    // KeyedDecodingContainer.decodeForwardCompatible.)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decodeIfPresent(UInt64.self, forKey: .requestID)
        do {
            payload = try container.decodeForwardCompatible(Payload.self, forKey: .payload,
                                                            knownDiscriminators: Payload.knownPayloadKeys)
        } catch ForwardCompatibilityError.unknownCase {
            payload = .unsupported
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(requestID, forKey: .requestID)
        try container.encode(payload, forKey: .payload)
    }
}

typealias ClientEnvelope = CompanionEnvelope<CompanionClientMessage>
typealias HostEnvelope = CompanionEnvelope<CompanionHostMessage>
