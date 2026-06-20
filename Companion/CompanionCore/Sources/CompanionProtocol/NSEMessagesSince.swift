//
//  NSEMessagesSince.swift
//  CompanionCore
//
//  A minimal, dependency-free mirror of the messagesSince request/reply wire
//  format, so the Notification Service Extension can talk to the host WITHOUT
//  compiling the full chat model. CompanionClientMessage / CompanionHostMessage
//  are single Codable enums whose OTHER cases reference Message / Chat / LLM, so
//  decoding them would drag that whole layer into the tiny NSE. The NSE instead
//  encodes just the one request and decodes just the one reply with these slim
//  structs over the raw Noise channel.
//
//  These MUST stay byte-compatible with CompanionClientMessage.messagesSince and
//  CompanionHostMessage.messagesSince. Swift's default enum Codable encodes a
//  case with associated values as a single key (the case name) whose value is a
//  keyed container of the labeled values - which is exactly the shape mirrored
//  here. A cross-check test against the production enums guards against drift
//  (the App Attest "synthetic test built the wrong way" lesson).
//

import Foundation

public enum NSEMessagesSince {
    /// Mirror of CompanionMessagePreview. `author` is the Participant raw value
    /// (a string); the NSE only displays it, so it needs no Participant enum.
    public struct Preview: Codable, Equatable {
        public let uniqueID: UUID
        public let author: String
        public let body: String
    }

    /// Mirror of CompanionHostMessage.messagesSince's payload.
    public struct Reply: Codable, Equatable {
        public let chatName: String
        public let previews: [Preview]
        public let maxSeq: Int64
        public let truncated: Bool
    }

    // MARK: Request

    private struct RequestEnvelope: Encodable {
        let requestID: UInt64
        let payload: Payload
        struct Payload: Encodable {
            let messagesSince: Args
            struct Args: Encodable {
                let collapseToken: String
                let seq: Int64
                let limit: Int
            }
        }
    }

    /// The request frame the host expects:
    /// {"requestID":N,"payload":{"messagesSince":{"collapseToken":…,"seq":…,"limit":…}}}
    public static func encodeRequest(requestID: UInt64,
                                     collapseToken: String,
                                     seq: Int64,
                                     limit: Int) throws -> Data {
        try WireCoding.encode(RequestEnvelope(
            requestID: requestID,
            payload: .init(messagesSince: .init(collapseToken: collapseToken,
                                                seq: seq,
                                                limit: limit))))
    }

    // MARK: Reply

    /// The kind of host reply frame, so the NSE can fail FAST on a correlated
    /// error instead of waiting out its deadline.
    public enum ReplyOutcome: Equatable {
        case messages(requestID: UInt64?, reply: Reply)
        /// The host replied with an error (e.g. a transient startup-race case).
        case error(requestID: UInt64?)
        /// Some other / unsolicited frame (delivery, typing) - keep waiting.
        case other
    }

    private struct ReplyEnvelope: Decodable {
        let requestID: UInt64?
        let payload: Payload
        struct Payload: Decodable {
            // Present only for a messagesSince reply.
            let messagesSince: Reply?
            // Presence (not contents) marks an error reply.
            let error: ErrorProbe?
            struct ErrorProbe: Decodable {}
        }
    }

    /// Classify a host reply frame. A messagesSince reply carries its data; an
    /// error reply is recognized so the caller fails fast; anything else is an
    /// unrelated frame to skip.
    public static func decodeReply(_ data: Data) throws -> ReplyOutcome {
        let envelope = try WireCoding.decode(ReplyEnvelope.self, from: data)
        if let reply = envelope.payload.messagesSince {
            return .messages(requestID: envelope.requestID, reply: reply)
        }
        if envelope.payload.error != nil {
            return .error(requestID: envelope.requestID)
        }
        return .other
    }
}
