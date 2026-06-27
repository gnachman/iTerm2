//
//  CompanionSyncItem.swift
//  CompanionCore
//
//  The leaf wire structs of a `.syncSince` reply, defined ONCE in the package so
//  both the production CompanionHostMessage.syncSince (Mac/phone app) AND the
//  Notification Service Extension (which links only CompanionCore) use the same
//  types - no re-declared mirror, so the item shape cannot drift and there is
//  nothing to cross-check. The NSE still needs a thin envelope shim (NSESyncSince)
//  because the full CompanionHostMessage enum carries Message/Chat in its other
//  cases and cannot be linked into the NSE; that shim now decodes into these
//  shared types.
//
//  `author` is the Participant raw value (a string), not the Participant enum:
//  the only consumer of a sync item is the NSE, which displays text and ignores
//  author, so keeping it a String avoids dragging the chat-model Participant into
//  the package.
//

import Foundation

/// One display-ready chat message in a `.syncSince` reply. Carries `chatID` and
/// `seq` (a unified sync spans many chats): the NSE computes each notification's
/// threadIdentifier on-device as HMAC(roomSecret, chatID) and uses `seq` to
/// advance the per-chat watermark and the global message floor. No attachment
/// bytes, no full Message.
public struct CompanionSyncMessageItem: Codable, Equatable {
    public var chatID: String
    public var chatName: String
    public var uniqueID: UUID
    public var author: String
    public var body: String
    public var seq: Int64

    public init(chatID: String, chatName: String, uniqueID: UUID, author: String, body: String, seq: Int64) {
        self.chatID = chatID
        self.chatName = chatName
        self.uniqueID = uniqueID
        self.author = author
        self.body = body
        self.seq = seq
    }
}

/// One terminal alert (e.g. "Mark Set", a fired notification trigger) in a
/// `.syncSince` reply. `threadKey` is the source session's guid; the NSE groups a
/// session's alerts by computing HMAC(roomSecret, "alert:" + threadKey)
/// on-device. `seq` advances the global alert floor.
public struct CompanionSyncAlertItem: Codable, Equatable {
    public var alertID: UUID
    public var threadKey: String
    public var title: String
    public var body: String
    public var seq: Int64

    public init(alertID: UUID, threadKey: String, title: String, body: String, seq: Int64) {
        self.alertID = alertID
        self.threadKey = threadKey
        self.title = title
        self.body = body
        self.seq = seq
    }
}

/// One item in a `.syncSince` reply: a chat message or a terminal alert. Custom
/// Codable so it encodes as {"message": {…}} / {"alert": {…}} (synthesized enum
/// Codable would nest the value under "_0"). One definition, so the flat shape can
/// never drift between the production enum and the NSE.
public enum CompanionSyncItem: Equatable {
    case message(CompanionSyncMessageItem)
    case alert(CompanionSyncAlertItem)
}

extension CompanionSyncItem: Codable {
    private enum CodingKeys: String, CodingKey { case message, alert }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .message(let item): try container.encode(item, forKey: .message)
        case .alert(let item): try container.encode(item, forKey: .alert)
        }
    }

    public init(from decoder: Decoder) throws {
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
