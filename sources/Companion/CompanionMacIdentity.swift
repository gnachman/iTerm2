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
    // The paired phone's static PUBLIC key, the reconnect authentication anchor.
    // Public, so not secret, but it lives in the keychain (not UserDefaults)
    // because its INTEGRITY is what matters: a tampered value would let an
    // impostor's static be accepted on reconnect. Kept beside the private key it
    // is matched against.
    private static let pairedPhoneAccount = "paired-phone-noise-static-public-key"
    // The room secret the phone couriered over the Noise channel. Secret (it
    // derives the relay join signing key), so the keychain is the right home.
    private static let roomSecretAccount = "paired-relay-room-secret"

    /// The persisted keypair, generating and storing one on first use. Reads the
    /// in-memory cache (primed at launch) so a reconnect never touches the
    /// keychain; only first-use generation writes.
    static func keyPair() throws -> NoiseKeyPair {
        if let privateKey = load(account: account) {
            return try NoiseKeyPair.from(privateKey: privateKey)
        }
        let generated = try NoiseKeyPair.generate()
        try store(generated.privateKey, account: account)
        return generated
    }

    /// Destroy the stored identity (used when unpairing); the next pairing
    /// generates a fresh keypair.
    static func deleteKeyPair() {
        delete(account: account)
    }

    /// The paired phone's pinned static public key, or nil if none is pinned.
    static func pairedPhoneStaticPublicKey() -> Data? {
        load(account: pairedPhoneAccount)
    }

    static func storePairedPhoneStaticPublicKey(_ key: Data) throws {
        try store(key, account: pairedPhoneAccount)
    }

    static func deletePairedPhoneStaticPublicKey() {
        delete(account: pairedPhoneAccount)
    }

    /// The room secret couriered from the phone (nil if none stored yet).
    static func pairedRoomSecret() -> Data? {
        load(account: roomSecretAccount)
    }

    static func storePairedRoomSecret(_ secret: Data) throws {
        try store(secret, account: roomSecretAccount)
    }

    static func deletePairedRoomSecret() {
        delete(account: roomSecretAccount)
    }

    // The phone-minted push relay secret (32 bytes). It authorizes pushing to
    // the paired phone, so the keychain is the right home (not UserDefaults).
    private static let pushSecretAccount = "paired-push-relay-secret"

    static func pairedPushSecret() -> Data? {
        load(account: pushSecretAccount)
    }

    static func storePairedPushSecret(_ secret: Data) throws {
        try store(secret, account: pushSecretAccount)
    }

    static func deletePairedPushSecret() {
        delete(account: pushSecretAccount)
    }

    // In-memory mirror of the keychain items, populated at launch and on every
    // write, so the connection and push hot paths never read the keychain. The
    // login keychain gates each item by the code signature of the binary that
    // wrote it; a build signed differently from the writer (e.g. a notarized
    // Nightly reading an item a local debug build created) pops a confirmation
    // prompt. Reading at launch, while the user is present, keeps that prompt off
    // the mid-connection path where nobody is at the keyboard. An inner nil
    // records “loaded and absent”, so a missing item is not re-read every call.
    private static let cacheLock = NSLock()
    private static var cache = [String: Data?]()

    /// Read every keychain-backed item into the cache. Call once at launch, while
    /// the user is at the keyboard, so any keychain confirmation prompt is
    /// answered then rather than mid-connection while the user is away. Idempotent
    /// (cached items are not re-read), and side-effect-free: it does not generate
    /// a Noise keypair, so an unpaired user gets no new key material.
    static func primeCacheAtLaunch() {
        _ = load(account: account)
        _ = load(account: pairedPhoneAccount)
        _ = load(account: roomSecretAccount)
        _ = load(account: pushSecretAccount)
    }

    private static func load(account: String) -> Data? {
        cacheLock.lock()
        if let cached = cache[account] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        // The keychain read runs unlocked so a confirmation prompt can't block
        // other accounts behind the lock. A concurrent store/delete may therefore
        // populate the cache while this read is in flight; that value is fresher,
        // so on writeback only fill a still-absent entry rather than clobbering it.
        let value = keychainLoad(account: account)
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[account] {
            return cached
        }
        cache.updateValue(value, forKey: account)
        return value
    }

    private static func store(_ key: Data, account: String) throws {
        try keychainStore(key, account: account)
        cacheLock.lock()
        cache.updateValue(key, forKey: account)
        cacheLock.unlock()
    }

    private static func delete(account: String) {
        keychainDelete(account: account)
        cacheLock.lock()
        cache.updateValue(nil, forKey: account)
        cacheLock.unlock()
    }

    private static func keychainLoad(account: String) -> Data? {
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

    private static func keychainStore(_ key: Data, account: String) throws {
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

    private static func keychainDelete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
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
