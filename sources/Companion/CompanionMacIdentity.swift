//
//  CompanionMacIdentity.swift
//  iTerm2
//
//  The Mac's long-term Noise static identity for companion pairing. The public
//  key is what the phone pins (it travels in the QR code's rs field); the
//  private key is generated once and kept in the login keychain so the
//  advertised public key stays stable across launches.
//

import Foundation
import CompanionNoise

@objc(iTermCompanionMacIdentity)
final class CompanionMacIdentity: NSObject {
    private static let service = "com.googlecode.iterm2.companion"
    private static let account = "mac-noise-static-private-key"

    /// The persisted keypair, generating and storing one on first use.
    static func keyPair() throws -> NoiseKeyPair {
        if let privateKey = loadPrivateKey() {
            return try NoiseKeyPair.from(privateKey: privateKey)
        }
        let generated = try NoiseKeyPair.generate()
        try storePrivateKey(generated.privateKey)
        return generated
    }

    /// Destroy the stored identity (used when unpairing); the next pairing
    /// generates a fresh keypair.
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
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CompanionMacError.keychain(status)
        }
    }
}

enum CompanionMacError: Error, CustomStringConvertible {
    case keychain(OSStatus)
    case chatSystemUnavailable
    case unknownChat(String)

    var description: String {
        switch self {
        case .keychain(let status):
            return "Keychain error \(status)"
        case .chatSystemUnavailable:
            return "The chat system is not available"
        case .unknownChat(let id):
            return "Unknown chat \(id)"
        }
    }
}
