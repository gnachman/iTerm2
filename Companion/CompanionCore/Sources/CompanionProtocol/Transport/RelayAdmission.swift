//
//  RelayAdmission.swift
//  CompanionCore
//
//  The JSON admission handshake spoken with the relay Durable Object before it
//  splices two sockets. It is intentionally tiny and uniform so the DO does
//  not leak the room's admission mode: the client sends Hello {v, role}, the
//  DO always replies with a Challenge {nonce}, the client presents a Proof
//  (a pairing ticket OR a join signature over the bound transcript), and the
//  DO answers with a Result. The matching half runs in the JS Worker. See
//  docs/companion-relay-design.md.
//
//  Data fields (nonce, signature) JSON-encode as base64 strings, which the JS
//  Worker reads and writes directly.
//

import Foundation

public enum RelayAdmission {
    public enum Role: String, Codable, Equatable {
        case mac
        case phone
    }

    /// First WS message: declares the protocol version and which slot the
    /// client wants. Carries no credential (the Proof does).
    public struct Hello: Codable, Equatable {
        public var v: Int
        public var role: Role

        public init(v: Int, role: Role) {
            self.v = v
            self.role = role
        }
    }

    /// The DO's uniform reply: a fresh nonce the client must bind into its
    /// proof. Sent regardless of admission mode, so a connector cannot probe
    /// whether a room is pairing/established/absent.
    public struct Challenge: Codable, Equatable {
        public var nonce: Data

        public init(nonce: Data) {
            self.nonce = nonce
        }
    }

    /// The client's credential. Exactly one of `ticket` (pairing admission) or
    /// `signature` (established-room join, or a pre-auth Mac parker sends
    /// neither) is present.
    public struct Proof: Codable, Equatable {
        public var ticket: String?
        public var signature: Data?

        enum CodingKeys: String, CodingKey {
            case ticket
            case signature = "sig"
        }

        public init(ticket: String?, signature: Data?) {
            self.ticket = ticket
            self.signature = signature
        }
    }

    /// The DO's verdict. `accepted` carries the one-time registration token
    /// (present only for a pairing-phone admission that will register a
    /// verifier); `rejected` carries a short reason.
    public struct Result: Codable, Equatable {
        public var ok: Bool
        public var registrationToken: String?
        public var error: String?

        public static func accepted(registrationToken: String? = nil) -> Result {
            Result(ok: true, registrationToken: registrationToken, error: nil)
        }

        public static func rejected(error: String) -> Result {
            Result(ok: false, registrationToken: nil, error: error)
        }
    }
}
