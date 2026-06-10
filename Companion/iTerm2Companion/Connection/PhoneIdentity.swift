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

    /// Return the persisted keypair, generating and storing one on first use.
    static func keyPair() throws -> NoiseKeyPair {
        if let privateKey = loadPrivateKey() {
            return try NoiseKeyPair.from(privateKey: privateKey)
        }
        let generated = try NoiseKeyPair.generate()
        try storePrivateKey(generated.privateKey)
        return generated
    }

    /// Destroy the stored identity (used when disconnecting); the next
    /// pairing generates a fresh keypair.
    static func deleteKeyPair() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func loadPrivateKey() -> Data? {
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

    private static func storePrivateKey(_ key: Data) throws {
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
