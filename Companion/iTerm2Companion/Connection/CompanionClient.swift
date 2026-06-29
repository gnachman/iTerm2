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
               onClose: @escaping @Sendable () -> Void,
               onMedia: (@Sendable (CompanionMediaFrame) -> Void)? = nil) async {
        await session.start(onEvent: onEvent, onClose: onClose, onMedia: onMedia)
    }

    /// Liveness check; throws if the mac does not answer.
    func ping() async throws {
        _ = try await session.request(.ping)
    }

    /// Courier the relay room secret to the mac and wait for its ack (so the
    /// mac holds the key to sign its parks before the phone registers V).
    func registerRoomSecret(_ secret: Data) async throws {
        let reply = try await session.request(.relayRoomSecret(secret))
        switch reply {
        case .relayRoomSecretStored:
            return
        case .error(let error):
            throw error
        default:
            throw CompanionError(code: .badRequest, message: "Unexpected reply to room-secret courier")
        }
    }

    /// Version handshake: send this build's revision/minimumPeer and evaluate the
    /// mac's reply from the phone's side. Call FIRST, before any other request.
    /// .selfMustUpgrade -> upgrade the phone app; .peerMustUpgrade -> upgrade the
    /// Mac app.
    struct HandshakeResult {
        var compatibility: CompanionProtocolVersion.Compatibility
        /// The mac says the user has opted into phone alerts; if this phone hasn't
        /// been asked for notification permission yet, it should ask.
        var wantsNotificationPermission: Bool
        /// The mac's advertised protocol revision, for feature detection (e.g.
        /// live streaming requires >= CompanionProtocolVersion.streamingRevision).
        var peerRevision: Int

        /// Whether the mac supports live session streaming.
        var supportsStreaming: Bool { peerRevision >= CompanionProtocolVersion.streamingRevision }
    }

    func handshakeVersion() async throws -> HandshakeResult {
        let reply = try await session.request(.hello(revision: CompanionProtocolVersion.current,
                                                     minimumPeer: CompanionProtocolVersion.minimumPeer))
        switch reply {
        case .hello(let revision, let minimumPeer, let wantsNotificationPermission):
            return HandshakeResult(
                compatibility: CompanionProtocolVersion.evaluate(peerRevision: revision,
                                                                 peerMinimumPeer: minimumPeer),
                wantsNotificationPermission: wantsNotificationPermission ?? false,
                peerRevision: revision)
        case .error(let error):
            throw error
        default:
            throw CompanionError(code: .badRequest, message: "Unexpected reply to hello")
        }
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
        case .history(let chatID, let messages, let maxSeq):
            // Viewing a chat == reading it: advance the per-chat push watermark
            // to the chat's tip so the NSE won't re-notify these messages.
            Self.advancePushWatermark(chatID: chatID, toMaxSeq: maxSeq)
            return messages
        case .error(let error):
            throw error
        default:
            throw CompanionError(code: .badRequest, message: "Unexpected reply to subscribe request")
        }
    }

    /// Max-merge the per-chat push watermark in the App Group (shared with the
    /// NSE). The token is HMAC(roomSecret, chatID), computed the same way the
    /// mac collapses pushes, so the chatID never has to cross to the NSE.
    private static func advancePushWatermark(chatID: String, toMaxSeq maxSeq: Int64) {
        guard let roomSecret = PhoneIdentity.existingRoomSecret(),
              let backing = UserDefaultsWatermarkBacking(appGroup: PhoneIdentity.appGroup) else {
            return
        }
        let token = CompanionCollapseToken.make(roomSecret: roomSecret, chatID: chatID)
        WatermarkStore(backing: backing).advance(token: token, to: maxSeq)
    }

    // (The NSE talks messagesSince over the slim NSEMessagesSince mirror, not
    // this typed client, so there is no CompanionClient.messagesSince.)

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

    /// Begin a live video stream of a session. The mac replies with the started
    /// stream, then sends a stream config and a push stream of media frames
    /// (delivered via the onMedia handler passed to start). Streaming requires a
    /// mac at CompanionProtocolVersion.streamingRevision or newer.
    func startSessionStream(guid: String,
                            params: CompanionStreamParams) async throws -> CompanionStreamStarted {
        let reply = try await session.request(.startSessionStream(sessionGuid: guid, params: params))
        switch reply {
        case .streamStarted(let started):
            return started
        case .error(let error):
            throw error
        default:
            throw CompanionError(code: .badRequest, message: "Unexpected reply to start-stream request")
        }
    }

    /// Stop a live stream. The mac confirms with an unsolicited streamEnded.
    func stopSessionStream(streamID: UInt32) async throws {
        try await session.send(.stopSessionStream(streamID: streamID))
    }

    /// Ask the mac to emit a keyframe now (on resume, or after a decode error).
    func requestStreamKeyframe(streamID: UInt32) async throws {
        try await session.send(.requestKeyframe(streamID: streamID))
    }

    /// Flow-control feedback: the newest media PTS displayed and the decode-queue
    /// depth, so the mac can pace end-to-end.
    func sendStreamAck(streamID: UInt32, lastPTSMilliseconds: UInt64, queueDepth: Int) async throws {
        try await session.send(.streamAck(streamID: streamID,
                                          lastPTSMilliseconds: lastPTSMilliseconds,
                                          queueDepth: queueDepth))
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
