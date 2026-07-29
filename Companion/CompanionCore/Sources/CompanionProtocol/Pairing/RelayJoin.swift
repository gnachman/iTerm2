//
//  RelayJoin.swift
//  CompanionCore
//
//  The asymmetric relay-join credential. Both devices derive the same Ed25519
//  signing key from the phone-minted roomSecret (couriered to the Mac over the
//  Noise channel); they authenticate a room join by signing a transcript bound
//  to (version, role, the DO's challenge nonce, room name, relay origin). The
//  relay stores only the public verifier, so a relay compromise or storage
//  dump authorizes nothing. See docs/companion-relay-design.md.
//

import Foundation
import CryptoKit

public enum RelayJoin {
    public enum Role: UInt8 {
        case mac = 1
        case phone = 2
    }

    /// Protocol version, bound as the first field of every signed transcript so
    /// a signature is valid only for the version that produced it (a future
    /// version reinterpreting the same fields cannot reuse it). Must match the
    /// relay's PROTOCOL_VERSION.
    public static let protocolVersion: UInt8 = 1

    /// HKDF label that domain-separates the join signing key from any other
    /// use of roomSecret.
    private static let keyLabel = "relay-auth-ed25519"

    /// Derive the per-pairing Ed25519 signing key from the room secret.
    /// Deterministic, so both devices arrive at the same key independently.
    public static func signingKey(roomSecret: Data) -> Curve25519.Signing.PrivateKey {
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: roomSecret),
            info: Data(keyLabel.utf8),
            outputByteCount: 32)
        let seed = derived.withUnsafeBytes { Data($0) }
        // 32 random bytes is a valid Ed25519 seed; derivation can't fail.
        return try! Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    }

    /// The public verifier the relay stores. 32 bytes.
    public static func verifier(roomSecret: Data) -> Data {
        signingKey(roomSecret: roomSecret).publicKey.rawRepresentation
    }

    /// The bytes a join signs. Binding room name and origin makes the key
    /// useless outside this room and relay. Length-prefixed and domain-separated,
    /// so no field boundary is ambiguous and a join signature can never be
    /// confused with a delete (a distinct domain) or any other signed message.
    public static func transcript(role: Role,
                                  nonce: Data,
                                  roomName: String,
                                  origin: String) -> Data {
        CanonicalEncoding.encode(domain: "iterm2-relay-join",
                                 [Data([protocolVersion]), Data([role.rawValue]), nonce,
                                  Data(roomName.utf8), Data(origin.utf8)])
    }

    /// The bytes a room-deletion request signs. A DISTINCT domain
    /// ("iterm2-relay-delete" vs the join's "iterm2-relay-join") means a captured
    /// join signature can never be replayed to authorize a deletion. Bound to a
    /// fresh single-use challenge (anti-replay), the room name, and the origin.
    /// `challenge` is the raw nonce bytes (the relay's base64 challenge decoded).
    public static func deleteTranscript(challenge: Data,
                                        roomName: String,
                                        origin: String) -> Data {
        CanonicalEncoding.encode(domain: "iterm2-relay-delete",
                                 [Data([protocolVersion]), challenge,
                                  Data(roomName.utf8), Data(origin.utf8)])
    }

    /// Verify a join signature against the stored verifier.
    public static func verify(signature: Data, transcript: Data, verifier: Data) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: verifier) else {
            return false
        }
        return key.isValidSignature(signature, for: transcript)
    }
}
