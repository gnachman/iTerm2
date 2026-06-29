//
//  CompanionEnvelopeForwardCompatTests.swift
//  iTerm2 ModernTests
//
//  Forward compatibility: a message type a build does not recognize (sent by a
//  newer peer) must NOT fail the whole envelope decode. Swift's synthesized enum
//  Codable throws on an unknown case, so CompanionEnvelope decodes an unknown
//  payload into `.unsupported` while preserving the requestID, letting the
//  receiver reply with a correlated error instead of dropping the frame.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionEnvelopeForwardCompatTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d
    }
    private func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e
    }

    func testUnknownClientMessageDecodesToUnsupportedKeepingRequestID() throws {
        // A payload case this build doesn't have (a future phone's message type).
        let json = #"{"requestID":42,"payload":{"someFutureMessage":{"x":1}}}"#.data(using: .utf8)!
        let env = try decoder().decode(ClientEnvelope.self, from: json)
        XCTAssertEqual(env.requestID, 42, "requestID must survive so the host can reply with an error")
        guard case .unsupported = env.payload else {
            return XCTFail("an unknown message type must decode to .unsupported")
        }
    }

    func testUnknownHostMessageDecodesToUnsupported() throws {
        let json = #"{"payload":{"brandNewEvent":{}}}"#.data(using: .utf8)!
        let env = try decoder().decode(HostEnvelope.self, from: json)
        XCTAssertNil(env.requestID)
        guard case .unsupported = env.payload else {
            return XCTFail("an unknown host message must decode to .unsupported")
        }
    }

    func testKnownMessageStillRoundTrips() throws {
        // The lenient decode must not weaken decoding of recognized messages.
        let original = ClientEnvelope(requestID: 7,
                                      payload: .hello(revision: 3, minimumPeer: 2))
        let data = try encoder().encode(original)
        let decoded = try decoder().decode(ClientEnvelope.self, from: data)
        XCTAssertEqual(decoded.requestID, 7)
        guard case let .hello(revision, minimumPeer) = decoded.payload else {
            return XCTFail("expected .hello, got \(decoded.payload)")
        }
        XCTAssertEqual(revision, 3)
        XCTAssertEqual(minimumPeer, 2)
    }

    func testMalformedBodyOfKnownCaseThrowsRatherThanUnsupported() throws {
        // The regression this guards: an older build receiving a KNOWN case whose
        // body it can't decode (here .history with a bad Message in the array, as
        // from a newer Mac with a new content variant) must THROW so the read loop
        // drops-and-logs the frame and the request times out - NOT collapse the
        // whole reply to .unsupported, which would fail the entire chat open.
        let json = #"{"requestID":3,"payload":{"history":{"chatID":"c","messages":[{"not":"a real message"}],"maxSeq":5}}}"#
            .data(using: .utf8)!
        XCTAssertThrowsError(try decoder().decode(HostEnvelope.self, from: json)) { error in
            XCTAssertTrue(error is DecodingError, "a known case with a bad body must surface a DecodingError, got \(error)")
        }
    }

    func testKnownNoArgumentCaseDecodes() throws {
        // A no-associated-value case (encoded as {"pong":{}}) must decode to the
        // real case, not .unsupported - guards against a forgotten knownPayloadKeys
        // entry for argument-free cases.
        let json = #"{"requestID":1,"payload":{"pong":{}}}"#.data(using: .utf8)!
        let env = try decoder().decode(HostEnvelope.self, from: json)
        guard case .pong = env.payload else {
            return XCTFail("expected .pong, got \(env.payload)")
        }
    }

    func testExplicitUnsupportedRoundTrips() throws {
        // A peer that literally sends .unsupported must decode back to it (the
        // discriminator "unsupported" is a known key).
        let data = try encoder().encode(HostEnvelope(requestID: 9, payload: .unsupported))
        let decoded = try decoder().decode(HostEnvelope.self, from: data)
        XCTAssertEqual(decoded.requestID, 9)
        guard case .unsupported = decoded.payload else {
            return XCTFail("expected .unsupported, got \(decoded.payload)")
        }
    }

    // MARK: knownPayloadKeys exhaustiveness
    //
    // The envelope decoder maps any discriminator NOT in knownPayloadKeys to
    // .unsupported. If a case were added but its key omitted from the set, this
    // same build would drop the real (legit) payload as "unsupported". These
    // tests are the only mechanism that fails when a case is added without
    // updating the set: clientKey/hostKey are EXHAUSTIVE switches (a new case
    // breaks the build there), the representative arrays drive them, and the set
    // of representative keys is asserted EQUAL to knownPayloadKeys.

    private static let sampleMessage = Message(
        chatID: "c", author: .agent, content: .markdown("x"),
        sentDate: Date(timeIntervalSince1970: 0),
        uniqueID: UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!)

    // CompanionError lives in CompanionProtocol, which this target can't link, so
    // build the .error representative by decoding rather than naming the type.
    private static let sampleErrorMessage: CompanionHostMessage = {
        // A single unlabeled associated value encodes under "_0".
        let json = #"{"payload":{"error":{"_0":{"code":"internalError","message":"x"}}}}"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        // swiftlint:disable:next force_try
        return (try! decoder.decode(HostEnvelope.self, from: json)).payload
    }()

    private func discriminator<T: Encodable>(_ value: T) throws -> String {
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder().encode(value)) as? [String: Any])
        XCTAssertEqual(obj.count, 1, "a synthesized enum value encodes under exactly one key")
        return try XCTUnwrap(obj.keys.first)
    }

    /// One representative value per CompanionClientMessage case.
    private static let clientReps: [CompanionClientMessage] = [
        .unsupported,
        .hello(revision: 1, minimumPeer: 1),
        .listChatsAndSessions,
        .createChat(title: "t", mode: .orchestrator),
        .deleteChat(chatID: "c"),
        .subscribe(chatID: "c"),
        .unsubscribe(chatID: "c"),
        .publish(message: sampleMessage, toChatID: "c", partial: false),
        .selectSessionResponse(chatID: "c", originalMessage: sampleMessage, sessionGuid: nil, terminal: false),
        .remoteCommandDecision(chatID: "c", messageUniqueID: UUID(), decision: .allowOnce),
        .linkSession(chatID: "c", sessionGuid: "s", terminal: false),
        .resolveMentions(identifiers: []),
        .fetchSessionScreenInfo(sessionGuid: "s"),
        .fetchSessionContent(sessionGuid: "s", firstLine: 0, lineCount: 1),
        .fetchWorkgroupInfo(workgroupID: "w"),
        .fetchSessionTree,
        .pushStatus(authorization: .authorized, token: nil, relaySecret: nil, sandbox: false),
        .notificationPermissionResponse(requestID: 1, authorization: .authorized),
        .ping,
        .relayRoomSecret(Data()),
        .messagesSince(collapseToken: "t", seq: 0, limit: 1, nonce: nil),
        .unpairing,
    ]

    /// EXHAUSTIVE: a new case breaks the build here. When it does, add a branch,
    /// a `clientReps` entry, and a `knownPayloadKeys` entry (the tests enforce the
    /// last two match).
    private func clientKey(_ m: CompanionClientMessage) -> String {
        switch m {
        case .unsupported: return "unsupported"
        case .hello: return "hello"
        case .listChatsAndSessions: return "listChatsAndSessions"
        case .createChat: return "createChat"
        case .deleteChat: return "deleteChat"
        case .subscribe: return "subscribe"
        case .unsubscribe: return "unsubscribe"
        case .publish: return "publish"
        case .selectSessionResponse: return "selectSessionResponse"
        case .remoteCommandDecision: return "remoteCommandDecision"
        case .linkSession: return "linkSession"
        case .resolveMentions: return "resolveMentions"
        case .fetchSessionScreenInfo: return "fetchSessionScreenInfo"
        case .fetchSessionContent: return "fetchSessionContent"
        case .fetchWorkgroupInfo: return "fetchWorkgroupInfo"
        case .fetchSessionTree: return "fetchSessionTree"
        case .pushStatus: return "pushStatus"
        case .notificationPermissionResponse: return "notificationPermissionResponse"
        case .ping: return "ping"
        case .relayRoomSecret: return "relayRoomSecret"
        case .messagesSince: return "messagesSince"
        case .unpairing: return "unpairing"
        }
    }

    private static let hostReps: [CompanionHostMessage] = [
        .unsupported,
        .hello(revision: 1, minimumPeer: 1),
        .chatsAndSessions(chats: [], sessions: []),
        .chatCreated(entry: CompanionChatListEntry(chat: Chat(title: "t", permissions: ""), snippet: nil)),
        .history(chatID: "c", messages: [], maxSeq: 0),
        .delivery(message: sampleMessage, chatID: "c", partial: false),
        .typingStatus(isTyping: true, participant: .agent, chatID: "c"),
        .mentionsResolved([]),
        .sessionScreenInfo(CompanionSessionScreenInfo(guid: "s", name: "n", lineCount: 0, columns: 0,
                                                      width: 0, lineHeight: 0, scale: 1)),
        .sessionContent(CompanionSessionContent(guid: "s", firstLine: 0, lineCount: 0, pngData: Data())),
        .workgroupInfo(CompanionWorkgroupInfo(workgroupID: "w", name: "n", members: [])),
        .sessionTree(CompanionSessionTree(windows: [])),
        .pong,
        .relayRoomSecretStored,
        .chatListChanged(chats: []),
        .requestNotificationPermission(requestID: 1),
        .unpaired,
        .messagesSince(chatName: "", previews: [], maxSeq: 0, truncated: false, reset: false),
        sampleErrorMessage,
    ]

    /// EXHAUSTIVE: see clientKey.
    private func hostKey(_ m: CompanionHostMessage) -> String {
        switch m {
        case .unsupported: return "unsupported"
        case .hello: return "hello"
        case .chatsAndSessions: return "chatsAndSessions"
        case .chatCreated: return "chatCreated"
        case .history: return "history"
        case .delivery: return "delivery"
        case .typingStatus: return "typingStatus"
        case .mentionsResolved: return "mentionsResolved"
        case .sessionScreenInfo: return "sessionScreenInfo"
        case .sessionContent: return "sessionContent"
        case .workgroupInfo: return "workgroupInfo"
        case .sessionTree: return "sessionTree"
        case .pong: return "pong"
        case .relayRoomSecretStored: return "relayRoomSecretStored"
        case .chatListChanged: return "chatListChanged"
        case .requestNotificationPermission: return "requestNotificationPermission"
        case .unpaired: return "unpaired"
        case .messagesSince: return "messagesSince"
        case .error: return "error"
        }
    }

    func testClientKnownPayloadKeysMatchEveryCase() throws {
        for rep in Self.clientReps {
            // The encoded wire key must equal the declared (switch) key...
            XCTAssertEqual(try discriminator(rep), clientKey(rep))
            // ...and every case must be in knownPayloadKeys (else it would decode
            // to .unsupported on this same build).
            XCTAssertTrue(CompanionClientMessage.knownPayloadKeys.contains(clientKey(rep)),
                          "\(clientKey(rep)) missing from CompanionClientMessage.knownPayloadKeys")
        }
        XCTAssertEqual(Set(Self.clientReps.map { clientKey($0) }),
                       CompanionClientMessage.knownPayloadKeys,
                       "representatives and knownPayloadKeys must match exactly")
    }

    func testHostKnownPayloadKeysMatchEveryCase() throws {
        for rep in Self.hostReps {
            XCTAssertEqual(try discriminator(rep), hostKey(rep))
            XCTAssertTrue(CompanionHostMessage.knownPayloadKeys.contains(hostKey(rep)),
                          "\(hostKey(rep)) missing from CompanionHostMessage.knownPayloadKeys")
        }
        XCTAssertEqual(Set(Self.hostReps.map { hostKey($0) }),
                       CompanionHostMessage.knownPayloadKeys,
                       "representatives and knownPayloadKeys must match exactly")
    }
}
