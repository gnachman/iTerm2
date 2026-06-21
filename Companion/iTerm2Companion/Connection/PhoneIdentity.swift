//
//  PhoneIdentity.swift
//  iTerm2 Companion
//
//  The phone's long-term Noise static identity and relay room secret. Stored in
//  the Keychain so the phone presents a stable identity across pairings and app
//  launches. The Noise key and the room secret live in a shared App Group
//  keychain access group so the Notification Service Extension can read them to
//  reconnect; the push-relay secret stays app-only (the NSE never needs it).
//  Existing installs are migrated from the app's default access group into the
//  shared group, crash-safely, at launch (see migrateSharedItemsToAppGroup).
//

import Foundation
import Security
import CompanionNoise
import CompanionProtocol

enum PhoneIdentity {
    // Shared identifiers (single source of truth in CompanionProtocol) so the
    // NSE reads exactly the same items. pushSecretAccount is app-only.
    private static let service = CompanionSharedIdentifiers.keychainService
    private static let account = CompanionSharedIdentifiers.noiseStaticPrivateKeyAccount
    private static let pushSecretAccount = "push-relay-secret"
    private static let roomSecretAccount = CompanionSharedIdentifiers.roomSecretAccount
    static let appGroup = CompanionSharedIdentifiers.appGroup

    /// Accounts shared with the NSE (stored in the App Group keychain group).
    private static let sharedAccounts = [account, roomSecretAccount]

    /// Move the NSE-shared items from the default access group into the App Group
    /// keychain group. Idempotent + crash-safe; call once at launch.
    static func migrateSharedItemsToAppGroup() {
        do {
            try KeychainAccessGroupMigration.migrate(accounts: sharedAccounts,
                                                     toGroup: appGroup,
                                                     store: SecItemStore(service: service))
        } catch {
            NSLog("PhoneIdentity: keychain access-group migration failed: \(error)")
        }
    }

    /// Return the persisted keypair, generating and storing one on first use.
    static func keyPair() throws -> NoiseKeyPair {
        if let privateKey = loadShared(account: account) {
            return try NoiseKeyPair.from(privateKey: privateKey)
        }
        let generated = try NoiseKeyPair.generate()
        try store(generated.privateKey, account: account, accessGroup: appGroup)
        return generated
    }

    /// Destroy the stored identity (used when disconnecting); the next pairing
    /// generates a fresh keypair.
    static func deleteKeyPair() {
        // Wipe everywhere on unpair/rotation: the nil-accessGroup SecItemDelete
        // omits kSecAttrAccessGroup, so it spans ALL of the app's access groups
        // (the App Group copy AND any leftover pre-migration default-group copy).
        // (Here that span is wanted - unlike the migration, which must not delete
        // with nil; see KeychainAccessGroupMigration.)
        delete(account: account, accessGroup: appGroup)
        delete(account: account, accessGroup: nil)
    }

    /// The random secret that authorizes pushes to this phone. App-only (the NSE
    /// never sends pushes), so it is not in the shared group.
    static func pushRelaySecret() throws -> Data {
        if let secret = load(account: pushSecretAccount, accessGroup: nil) {
            return secret
        }
        let secret = try randomSecret()
        try store(secret, account: pushSecretAccount, accessGroup: nil)
        return secret
    }

    static func deletePushRelaySecret() {
        delete(account: pushSecretAccount, accessGroup: nil)
    }

    /// The 32-byte room secret the phone mints to lock the relay room. Shared
    /// with the NSE so it can sign its reconnect join. Generated on first use.
    static func roomSecret() throws -> Data {
        if let secret = loadShared(account: roomSecretAccount) {
            return secret
        }
        let secret = try randomSecret()
        try store(secret, account: roomSecretAccount, accessGroup: appGroup)
        return secret
    }

    /// The stored room secret if one has been minted, without minting one.
    static func existingRoomSecret() -> Data? {
        loadShared(account: roomSecretAccount)
    }

    static func deleteRoomSecret() {
        delete(account: roomSecretAccount, accessGroup: appGroup)
        delete(account: roomSecretAccount, accessGroup: nil)
    }

    // MARK: Pairing code (App Group keychain, so it survives an app reinstall
    // that wipes UserDefaults, and the NSE can read it).

    private static let pairingCodeAccount = CompanionSharedIdentifiers.pairingCodeAccount

    /// The stored pairing code, or nil if none. Decoded from a JSON blob in the
    /// App Group keychain group.
    static func pairingCode() -> PairingCode? {
        guard let data = loadSharedData(account: pairingCodeAccount) else { return nil }
        return try? JSONDecoder().decode(PairingCode.self, from: data)
    }

    /// Persist the pairing code (replaces any existing one).
    static func storePairingCode(_ code: PairingCode) throws {
        let data = try JSONEncoder().encode(code)
        try store(data, account: pairingCodeAccount, accessGroup: appGroup)
    }

    static func deletePairingCode() {
        delete(account: pairingCodeAccount, accessGroup: appGroup)
        delete(account: pairingCodeAccount, accessGroup: nil)
    }

    // MARK: Keychain plumbing

    private static func randomSecret() throws -> Data {
        var secret = Data(count: 32)
        let status = secret.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: "PhoneIdentity", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not generate secret (\(status))"])
        }
        return secret
    }

    /// Read a shared item from the App Group group, falling back to the default
    /// group (a pre-migration install, or a crash mid-migration). The launch
    /// migration moves it into the shared group so the NSE can read it.
    private static func loadShared(account: String) -> Data? {
        load(account: account, accessGroup: appGroup) ?? load(account: account, accessGroup: nil)
    }

    /// Like loadShared, but for variable-length blobs (the pairing code), so it
    /// does not apply the 32-byte key check `load` enforces.
    private static func loadSharedData(account: String) -> Data? {
        loadData(account: account, accessGroup: appGroup) ?? loadData(account: account, accessGroup: nil)
    }

    private static func loadData(account: String, accessGroup: String?) -> Data? {
        var query = baseQuery(account: account, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return data
    }

    private static func baseQuery(account: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private static func delete(account: String, accessGroup: String?) {
        SecItemDelete(baseQuery(account: account, accessGroup: accessGroup) as CFDictionary)
    }

    private static func load(account: String, accessGroup: String?) -> Data? {
        var query = baseQuery(account: account, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, data.count == 32 else {
            return nil
        }
        return data
    }

    private static func store(_ key: Data, account: String, accessGroup: String?) throws {
        var query = baseQuery(account: account, accessGroup: accessGroup)
        query[kSecValueData as String] = key
        // Available after first unlock; this device only, never synced.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "PhoneIdentity", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not store keychain item (\(status))"])
        }
    }
}

/// SecItem-backed KeychainItemStore for the access-group migration.
private struct SecItemStore: KeychainItemStore {
    let service: String

    private func baseQuery(account: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    func read(account: String, accessGroup: String?) throws -> Data? {
        var query = baseQuery(account: account, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw error(status)
        }
        return data
    }

    func add(account: String, accessGroup: String?, data: Data) throws {
        var query = baseQuery(account: account, accessGroup: accessGroup)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem { return }   // already present == success
        guard status == errSecSuccess else { throw error(status) }
    }

    func delete(account: String, accessGroup: String?) throws {
        let status = SecItemDelete(baseQuery(account: account, accessGroup: accessGroup) as CFDictionary)
        if status == errSecItemNotFound { return }
        guard status == errSecSuccess else { throw error(status) }
    }

    private func error(_ status: OSStatus) -> NSError {
        NSError(domain: "SecItemStore", code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "keychain status \(status)"])
    }
}
