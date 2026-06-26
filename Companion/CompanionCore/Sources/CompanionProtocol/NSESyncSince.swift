//
//  NSESyncSince.swift
//  CompanionCore
//
//  A minimal, dependency-free mirror of the syncSince request/reply wire format,
//  the sibling of NSEMessagesSince for the contentless-wakeup push (protocol
//  revision >= 2). On a wakeup the Notification Service Extension asks for
//  everything new across ALL chats and alerts in one round trip, WITHOUT
//  compiling the full chat model (CompanionClientMessage / CompanionHostMessage
//  reference Message / Chat / LLM). The NSE encodes just the one request and
//  decodes just the one reply with these slim structs over the raw Noise channel.
//
//  These MUST stay byte-compatible with CompanionClientMessage.syncSince and
//  CompanionHostMessage.syncSince. Swift's default enum Codable encodes a case
//  with associated values as a single key (the case name) whose value is a keyed
//  container of the labeled values; CompanionSyncItem therefore encodes as
//  {"message": {…}} / {"alert": {…}}, mirrored here by an optional-field struct.
//  A cross-check test against the production enums guards against drift.
//

import Foundation

public enum NSESyncSince {
    /// Mirror of CompanionSyncMessageItem. `author` is the Participant raw value
    /// (a string); the NSE only displays it.
    public struct MessageItem: Codable, Equatable {
        public let chatID: String
        public let chatName: String
        public let uniqueID: UUID
        public let author: String
        public let body: String
        public let seq: Int64
    }

    /// Mirror of CompanionSyncAlertItem.
    public struct AlertItem: Codable, Equatable {
        public let alertID: UUID
        public let threadKey: String
        public let title: String
        public let body: String
        public let seq: Int64
    }

    /// Mirror of CompanionSyncItem. The production enum encodes a case as a
    /// single-key object, so exactly one of these is non-nil per item.
    public struct Item: Decodable, Equatable {
        public let message: MessageItem?
        public let alert: AlertItem?
    }

    /// Mirror of CompanionHostMessage.syncSince's payload.
    public struct Reply: Decodable, Equatable {
        public let items: [Item]
        public let maxMessageSeq: Int64
        public let maxAlertSeq: Int64
        public let messageReset: Bool
        public let alertReset: Bool
        public let truncated: Bool
    }

    // MARK: Request

    private struct RequestEnvelope: Encodable {
        let requestID: UInt64
        let payload: Payload
        struct Payload: Encodable {
            let syncSince: Args
            struct Args: Encodable {
                let messageSeq: Int64
                let alertSeq: Int64
                let limit: Int
                // One-time nonce from the push so the mac recognizes its own
                // solicited fetch. Omitted when nil (encodeIfPresent).
                let nonce: String?
            }
        }
    }

    /// The request frame the host expects:
    /// {"requestID":N,"payload":{"syncSince":{"messageSeq":…,"alertSeq":…,"limit":…[,"nonce":…]}}}
    public static func encodeRequest(requestID: UInt64,
                                     messageSeq: Int64,
                                     alertSeq: Int64,
                                     limit: Int,
                                     nonce: String? = nil) throws -> Data {
        try WireCoding.encode(RequestEnvelope(
            requestID: requestID,
            payload: .init(syncSince: .init(messageSeq: messageSeq,
                                            alertSeq: alertSeq,
                                            limit: limit,
                                            nonce: nonce))))
    }

    // MARK: Reply

    /// The kind of host reply frame, so the NSE can fail FAST on a correlated
    /// error instead of waiting out its deadline.
    public enum ReplyOutcome: Equatable {
        case sync(requestID: UInt64?, reply: Reply)
        /// The host replied with an error (e.g. a transient startup-race case).
        case error(requestID: UInt64?)
        /// Some other / unsolicited frame (delivery, typing) - keep waiting.
        case other
    }

    private struct ReplyEnvelope: Decodable {
        let requestID: UInt64?
        let payload: Payload
        struct Payload: Decodable {
            // Present only for a syncSince reply.
            let syncSince: Reply?
            // Presence (not contents) marks an error reply.
            let error: ErrorProbe?
            struct ErrorProbe: Decodable {}
        }
    }

    /// Classify a host reply frame. A syncSince reply carries its data; an error
    /// reply is recognized so the caller fails fast; anything else is an
    /// unrelated frame to skip.
    public static func decodeReply(_ data: Data) throws -> ReplyOutcome {
        let envelope = try WireCoding.decode(ReplyEnvelope.self, from: data)
        if let reply = envelope.payload.syncSince {
            return .sync(requestID: envelope.requestID, reply: reply)
        }
        if envelope.payload.error != nil {
            return .error(requestID: envelope.requestID)
        }
        return .other
    }
}
