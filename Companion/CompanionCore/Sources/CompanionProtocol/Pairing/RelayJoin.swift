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
    /// Wire protocol version of the join exchange. Bumping it lets future
    /// admission changes be distinguished from v1.
    public static let version: UInt8 = 1

    public enum Role: UInt8 {
        case mac = 1
        case phone = 2
    }

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

    /// The bytes a join (or rotate/delete) signs. Binding room name and origin
    /// makes the key useless outside this room and relay. Layout is
    /// unambiguous: every field before the trailing variable-length origin is
    /// fixed (version 1, role 1, nonce, 64-char hex room name).
    public static func transcript(role: Role,
                                  nonce: Data,
                                  roomName: String,
                                  origin: String) -> Data {
        var data = Data([version, role.rawValue])
        data.append(nonce)
        data.append(Data(roomName.utf8))
        data.append(Data(origin.utf8))
        return data
    }

    /// Verify a join signature against the stored verifier.
    public static func verify(signature: Data, transcript: Data, verifier: Data) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: verifier) else {
            return false
        }
        return key.isValidSignature(signature, for: transcript)
    }
}
