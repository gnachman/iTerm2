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

/// A rendered scrollback tile addressed by absolute (overflow-adjusted) line,
/// plus the current availability window so the phone can size its history canvas
/// and resolve eviction races deterministically.
struct CompanionHistoryTile: Codable, Equatable {
    var streamID: UInt32
    var generationId: UInt32
    /// First absolute line actually rendered (clamped to what is available).
    var firstAbsLine: Int64
    /// Lines actually rendered (0 if the request was entirely evicted).
    var lineCount: Int
    /// Oldest available absolute line right now (== totalScrollbackOverflow).
    var windowFirstAbsLine: Int64
    /// Total available lines right now (scrollback + screen).
    var windowLineCount: Int
    var pngData: Data
}

/// A codec for a live session stream.
enum CompanionStreamCodec: String, Codable, Equatable {
    case hevc
    case h264
}

/// Phone-supplied parameters for a live session stream.
struct CompanionStreamParams: Codable, Equatable {
    /// Codecs the phone can decode, best first; the host picks the first it can
    /// produce.
    var supportedCodecs: [CompanionStreamCodec]
    /// Upper bound on frames per second the phone wants delivered.
    var maxFrameRate: Double
    /// Phone-permitted sustained bandwidth ceiling in bits per second (e.g.
    /// tighter on cellular); the host streams at the min of this and its own
    /// budget. nil means the phone imposes no limit.
    var maxBitrate: Int?
    /// Highest media-frame wire version the phone can decode. nil/absent means the
    /// phone predates versioned frames, so the host must emit version 1. The host
    /// emits min(this, its own current version), so an old phone keeps working
    /// (without per-frame geometry) and a new phone gets generationId/liveTop.
    var maxMediaFrameVersion: Int? = nil

    init(supportedCodecs: [CompanionStreamCodec],
         maxFrameRate: Double,
         maxBitrate: Int?,
         maxMediaFrameVersion: Int? = nil) {
        self.supportedCodecs = supportedCodecs
        self.maxFrameRate = maxFrameRate
        self.maxBitrate = maxBitrate
        self.maxMediaFrameVersion = maxMediaFrameVersion
    }
}

/// Reply to `.startSessionStream`: the stream is live with the negotiated codec.
struct CompanionStreamStarted: Codable, Equatable {
    var streamID: UInt32
    var codec: CompanionStreamCodec
}

/// The fixed (per-generation) screen geometry needed to map a touch on the
/// encoded image to a terminal cell, all in ENCODED PIXELS (the units of
/// pixelWidth/pixelHeight), so the phone works entirely in image space:
///   column = floor((imageX - leftMargin) / cellWidth)
///   row    = floor((imageY - topMargin)  / cellHeight)
/// Margins are 0 today (the stream renders without margins) but are carried so
/// the transform stays correct if that changes. This changes only on a
/// resize/font/scale change, so it rides streamConfig with the generationId; the
/// per-frame top line (liveTop) rides the media-frame header instead.
struct CompanionCellGeometry: Codable, Equatable {
    var cellWidth: Double
    var cellHeight: Double
    var leftMargin: Double
    var topMargin: Double
}

/// A point in absolute terminal coordinates, computed by the phone from a touch
/// using the stream geometry: column is a 0-based cell, absLine is the
/// overflow-adjusted absolute line (so it stays valid as scrollback grows). The
/// host maps it to a VT100GridAbsCoord to drive the real selection.
struct CompanionSelectionPoint: Codable, Equatable {
    var absLine: Int64
    var column: Int
}

/// The current selection's span in absolute terminal coordinates, reported by the
/// host so the phone can draw draggable handles at the endpoints. start is the
/// earlier coordinate, end the later one.
struct CompanionSelectionRange: Codable, Equatable {
    var start: CompanionSelectionPoint
    var end: CompanionSelectionPoint
}

/// Phase of a phone-driven selection drag.
enum CompanionSelectionPhase: String, Codable, Equatable {
    case begin
    case move
    case end
}

/// How a selection snaps. character = exact cells; word/line/smart match the
/// Mac's double/triple/smart selection. Only meaningful on `.begin`.
enum CompanionSelectionMode: String, Codable, Equatable {
    case character
    case word
    case line
    case smart
}

/// Decoder configuration for a live stream: the codec parameter sets plus the
/// pixel geometry of the encoded frames. Re-sent with a fresh generationId
/// whenever the geometry changes.
struct CompanionStreamConfig: Codable, Equatable {
    var streamID: UInt32
    /// Bumped on every geometry change; media frames carry the generation they
    /// were rendered at so the phone applies the matching configuration.
    var generationId: UInt32
    /// Codec parameter sets (hvcC for HEVC, avcC for H.264) for decoder setup.
    var codecExtradata: Data
    var pixelWidth: Int
    var pixelHeight: Int
    /// Render scale (encoded pixels per Mac point).
    var scale: Double
    var columns: Int
    var rows: Int
    /// Cell/margin geometry for touch-to-cell mapping. Optional: a host too old
    /// to send it (pre-geometry build) decodes as nil, and the phone keeps the
    /// video working but cannot offer selection.
    var cellGeometry: CompanionCellGeometry? = nil
    /// Oldest available absolute line (== totalScrollbackOverflow) at config time,
    /// so the phone can lay out the history canvas. Older hosts decode as 0.
    var firstAbsLine: Int64 = 0
    /// Total available lines (scrollback + screen) at config time.
    var totalLines: Int = 0
}

/// Why a live stream ended.
enum CompanionStreamEndReason: String, Codable, Equatable {
    case stoppedByClient
    case sessionClosed
    case superseded
    case error
    /// The host paused the stream to stay within the relay's data budget.
    case dataLimitReached
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

// CompanionSyncItem / CompanionSyncMessageItem / CompanionSyncAlertItem (the
// leaf wire structs of a `.syncSince` reply) live in the CompanionProtocol
// package so the NSE and this production enum share one definition. See
// CompanionSyncItem.swift.

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

    /// Render a scrollback tile by absolute (overflow-adjusted) line for the live
    /// canvas's history. Replied to with `.historyTile`.
    case fetchHistoryTile(streamID: UInt32, firstAbsLine: Int64, lineCount: Int, generationId: UInt32)

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

    /// Live view: begin streaming a session's visible screen as encoded video on
    /// the media channel. Replied to with `.streamStarted`, then a
    /// `.streamConfig`, then a push stream of media frames.
    case startSessionStream(sessionGuid: String, params: CompanionStreamParams)

    /// Stop a live stream started with `.startSessionStream`. No reply beyond an
    /// eventual `.streamEnded`.
    case stopSessionStream(streamID: UInt32)

    /// Ask the host to emit a keyframe now (on (re)subscribe, after a decode
    /// error, or when resuming from background). No direct reply; a keyframe
    /// arrives on the media channel.
    case requestKeyframe(streamID: UInt32)

    /// Update a running stream's parameters (frame-rate cap, bandwidth budget).
    case updateStreamParams(streamID: UInt32, params: CompanionStreamParams)

    /// Periodic flow-control feedback: the newest media PTS the phone has
    /// received/displayed and its current decode-queue depth, so the host can
    /// pace end-to-end (the relay hides TCP-level signals). No reply.
    case streamAck(streamID: UInt32, lastPTSMilliseconds: UInt64, queueDepth: Int)

    /// Live-view text selection driven from the phone. `.begin` starts a live
    /// selection at `point` (snapped per `mode`), `.move` extends its end, `.end`
    /// finalizes it; the resulting highlight is rendered into the streamed frames.
    /// No reply. `mode` is only consulted on `.begin`.
    case selectionGesture(streamID: UInt32, phase: CompanionSelectionPhase,
                          mode: CompanionSelectionMode, point: CompanionSelectionPoint)

    /// Clear any live-view selection on the session. No reply.
    case clearSelection(streamID: UInt32)

    /// Copy the session's current selection to a string. Replied to with
    /// `.selectionText`.
    case copySelection(sessionGuid: String)

    /// Select the entire terminal content (edit-menu Select All). No reply; a
    /// `.selectionRange` follows.
    case selectAllInStream(streamID: UInt32)

    /// Paste text into the session as input (edit-menu Paste of the phone's
    /// clipboard). No reply.
    case pasteText(sessionGuid: String, text: String)

    /// Discriminators this build knows. MUST list every case above (except
    /// `.unsupported` is included so a peer that literally sends it round-trips).
    /// Add a line here whenever a case is added.
    static let knownPayloadKeys: Set<String> = [
        "unsupported", "hello", "listChatsAndSessions", "createChat", "deleteChat",
        "subscribe", "unsubscribe", "publish", "selectSessionResponse",
        "remoteCommandDecision", "linkSession", "resolveMentions",
        "fetchSessionScreenInfo", "fetchSessionContent", "fetchHistoryTile", "fetchWorkgroupInfo",
        "fetchSessionTree", "pushStatus", "notificationPermissionResponse", "ping",
        "relayRoomSecret", "messagesSince", "syncSince", "unpairing",
        "startSessionStream", "stopSessionStream", "requestKeyframe",
        "updateStreamParams", "streamAck",
        "selectionGesture", "clearSelection", "copySelection",
        "selectAllInStream", "pasteText",
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
    /// app upgrade is required. `wantsNotificationPermission` is true when the user
    /// has opted into phone alerts: the phone, knowing its own permission state and
    /// foreground status, asks iOS for notification permission if it hasn't yet.
    /// Sent on every connect so it never depends on timing. Optional for
    /// cross-version compatibility: an older mac omits it (decodes as nil -> false).
    case hello(revision: Int, minimumPeer: Int, wantsNotificationPermission: Bool?)

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

    /// Reply to `.fetchHistoryTile`.
    case historyTile(CompanionHistoryTile)

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

    /// Reply to `.startSessionStream`: the stream is live with a negotiated codec.
    case streamStarted(CompanionStreamStarted)

    /// Stream (re)configuration: codec parameter sets and pixel geometry. Sent
    /// right after `.streamStarted`, and again with a fresh generationId whenever
    /// the geometry changes; the next media frame after a change sets its
    /// configChanged flag.
    case streamConfig(CompanionStreamConfig)

    /// Unsolicited: the stream ended (client stopped it, the session closed, it
    /// was superseded, or an error occurred).
    case streamEnded(streamID: UInt32, reason: CompanionStreamEndReason)

    /// Unsolicited: the history window changed in a way the live top alone cannot
    /// convey -- scrollback trimmed (firstAbsLine advanced) or cleared (totalLines
    /// dropped). Carries the current oldest available absolute line and total line
    /// count so the phone can drop evicted tiles and reanchor its canvas.
    case streamExtent(streamID: UInt32, firstAbsLine: Int64, totalLines: Int)

    /// Reply to `.copySelection`: the selected text (empty if nothing is
    /// selected). The phone places it on the clipboard.
    case selectionText(text: String)

    /// Unsolicited: the session's selection changed (after a phone gesture or any
    /// other cause). Carries the span so the phone can draw/move handles; nil when
    /// there is no selection.
    case selectionRange(streamID: UInt32, range: CompanionSelectionRange?)

    /// Discriminators this build knows. Add a line here whenever a case is added.
    static let knownPayloadKeys: Set<String> = [
        "unsupported", "hello", "chatsAndSessions", "chatCreated", "history",
        "delivery", "typingStatus", "mentionsResolved", "sessionScreenInfo",
        "sessionContent", "workgroupInfo", "sessionTree", "pong",
        "relayRoomSecretStored", "chatListChanged", "requestNotificationPermission",
        "unpaired", "messagesSince", "syncSince", "error",
        "streamStarted", "streamConfig", "streamEnded", "selectionText",
        "selectionRange", "historyTile", "streamExtent",
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
