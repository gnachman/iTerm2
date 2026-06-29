//
//  CompanionPushNonceCrypto.swift
//  CompanionCore
//
//  Seals/opens the push nonce under the shared room secret. The nonce proves a
//  relay connection is the mac's own solicited NSE fetch (so the mac skips the
//  intrusion warning), so it is a secret capability. It travels in the APNs push
//  payload, which the relay and Apple carry but must not be able to read - they
//  hold only derivatives of the room secret (the hashed room name, the HMAC
//  collapse token), never the secret itself. So the mac seals the nonce and only
//  the phone (which holds the room secret in its App Group keychain) opens it.
//  The relay/Apple see ciphertext; a credential thief who has the room secret
//  never receives the push, so this changes nothing for them.
//

import Foundation
import CryptoKit

public enum CompanionPushNonceCrypto {
    /// Domain-separated key so the room secret's other uses (room name, collapse
    /// token HMAC, join signatures) never share key material with this.
    private static func key(roomSecret: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: roomSecret),
            info: Data("companion-push-nonce".utf8),
            outputByteCount: 32)
    }

    /// Seal a nonce -> base64 of the ChaChaPoly combined box (nonce|ct|tag).
    public static func seal(nonce: String, roomSecret: Data) throws -> String {
        let box = try ChaChaPoly.seal(Data(nonce.utf8), using: key(roomSecret: roomSecret))
        return box.combined.base64EncodedString()
    }

    /// Open a sealed nonce, or nil if it is malformed or authentication fails
    /// (e.g. the room secret was rotated by a re-pair between push and fetch).
    public static func open(_ sealedBase64: String, roomSecret: Data) -> String? {
        guard let data = Data(base64Encoded: sealedBase64),
              let box = try? ChaChaPoly.SealedBox(combined: data),
              let opened = try? ChaChaPoly.open(box, using: key(roomSecret: roomSecret)) else {
            return nil
        }
        return String(data: opened, encoding: .utf8)
    }
}
