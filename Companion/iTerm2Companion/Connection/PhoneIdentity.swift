//
//  PhoneIdentity.swift
//  iTerm2 Companion
//
//  The phone's long-term Noise static identity. The private key is generated
//  once and stored in the Keychain so the phone presents a stable identity
//  across pairings and app launches.
//

import Foundation
import Security
import CompanionNoise

enum PhoneIdentity {
    private static let service = "com.googlecode.iterm2.companion"
    private static let account = "noise-static-private-key"
    private static let pushSecretAccount = "push-relay-secret"
    private static let roomSecretAccount = "relay-room-secret"

    /// Return the persisted keypair, generating and storing one on first use.
    static func keyPair() throws -> NoiseKeyPair {
        if let privateKey = load(account: account) {
            return try NoiseKeyPair.from(privateKey: privateKey)
        }
        let generated = try NoiseKeyPair.generate()
        try store(generated.privateKey, account: account)
        return generated
    }

    /// Destroy the stored identity (used when disconnecting); the next
    /// pairing generates a fresh keypair.
    static func deleteKeyPair() {
        delete(account: account)
    }

    /// The random secret that authorizes pushes to this phone: its hash is
    /// registered with the push relay, and the secret itself goes to the
    /// paired Mac over the encrypted channel. Generated on first use.
    static func pushRelaySecret() throws -> Data {
        if let secret = load(account: pushSecretAccount) {
            return secret
        }
        var secret = Data(count: 32)
        let status = secret.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: "PhoneIdentity", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not generate push secret (\(status))"])
        }
        try store(secret, account: pushSecretAccount)
        return secret
    }

    static func deletePushRelaySecret() {
        delete(account: pushSecretAccount)
    }

    /// The 32-byte room secret the phone mints to lock the relay room: it
    /// derives the join signing key (RelayJoin) and is couriered to the Mac
    /// over the Noise channel so the Mac can sign its parks too. Generated on
    /// first use; rotated by deleting it on unpair.
    static func roomSecret() throws -> Data {
        if let secret = load(account: roomSecretAccount) {
            return secret
        }
        var secret = Data(count: 32)
        let status = secret.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: "PhoneIdentity", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not generate room secret (\(status))"])
        }
        try store(secret, account: roomSecretAccount)
        return secret
    }

    /// The stored room secret if one has been minted, without minting one.
    static func existingRoomSecret() -> Data? {
        load(account: roomSecretAccount)
    }

    static func deleteRoomSecret() {
        delete(account: roomSecretAccount)
    }

    // MARK: Keychain plumbing

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, data.count == 32 else {
            return nil
        }
        return data
    }

    private static func store(_ key: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key,
            // Available after first unlock; this device only, never synced.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "PhoneIdentity", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not store pairing key (\(status))"])
        }
    }
}
