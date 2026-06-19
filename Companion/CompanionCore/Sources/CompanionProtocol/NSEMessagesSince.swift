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

    private struct ReplyEnvelope: Decodable {
        let requestID: UInt64?
        let payload: Payload
        struct Payload: Decodable {
            // Present only when the host's reply is a messagesSince; an error or
            // any other case decodes this as nil (key absent).
            let messagesSince: Reply?
        }
    }

    /// Decode a host reply frame, returning the messagesSince reply and its
    /// correlating requestID iff that is what the host sent. Returns nil for an
    /// error reply or any other host message (the NSE treats that as fallback).
    public static func decodeReply(_ data: Data) throws -> (requestID: UInt64?, reply: Reply)? {
        let envelope = try WireCoding.decode(ReplyEnvelope.self, from: data)
        guard let reply = envelope.payload.messagesSince else { return nil }
        return (envelope.requestID, reply)
    }
}
