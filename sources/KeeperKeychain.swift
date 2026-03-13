//
//  KeeperKeychain.swift
//  iTerm2SharedARC
//
//  API key and API URL storage (Keychain, UserDefaults, migration). Extracted so KeeperDataSource can achieve full unit test coverage by mocking at the call site.
//

import Foundation
import Security

// MARK: - Constants (internal for use by KeeperDataSource migration)

internal let keeperLegacyUserDefaultsAPIKeyKey = "NoSyncKeeperCommanderAPIKey"
internal let keeperLegacyUserDefaultsAPIURLKey = "NoSyncKeeperCommanderAPIURL"

private let keeperKeychainService = "com.iterm2.keeper-service-mode"
private let keeperKeychainAccountAPIKey = "api-key"
private let keeperKeychainAccountAPIURL = "api-url"
private let keeperLegacyKeychainService = "iTerm2-Keeper"

// MARK: - API key read/write

/// Reads API key from data-protection Keychain (triggers Touch ID/passcode once per read). Returns nil if not found or user cancels.
internal func keeperAPIKeyFromSecureKeychain() -> String? {
    if let fn = KeeperTestOverrides.secureKeychainReturns, let key = fn(), !key.isEmpty { return key }
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keeperKeychainService,
        kSecAttrAccount as String: keeperKeychainAccountAPIKey,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    if #available(macOS 10.15, *) {
        query[kSecUseDataProtectionKeychain as String] = true
    }
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
        return nil
    }
    return token
}

/// Reads API key from standard Keychain (fallback when device has no biometric / user presence).
internal func keeperAPIKeyFromStandardKeychain() -> String? {
    if let fn = KeeperTestOverrides.standardKeychainReturns, let key = fn(), !key.isEmpty { return key }
    return try? SSKeychain.password(forService: keeperKeychainService, account: keeperKeychainAccountAPIKey)
}

/// Stores API key in Keychain. Prefers data-protection Keychain; falls back to standard Keychain if unavailable.
internal func keeperStoreAPIKeyInKeychain(_ key: String) {
    if let fn = KeeperTestOverrides.storeAPIKeyInKeychain { fn(key); return }
    let keyData = Data(key.utf8)
    if #available(macOS 10.15, *) {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            SecAccessControlCreateFlags.userPresence,
            &error
        ) else {
            keeperStoreAPIKeyInStandardKeychain(key)
            return
        }
        keeperDeleteAPIKeyFromKeychain()
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keeperKeychainService,
            kSecAttrAccount as String: keeperKeychainAccountAPIKey,
            kSecValueData as String: keyData,
            kSecAttrAccessControl as String: access,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            return
        }
        let msg = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
        DLog("Keeper: biometric keychain add failed (\(status)) \(msg), using standard keychain")
        NSLog("[iTerm2 Keeper] Data protection keychain add failed: %@ (use standard keychain)", msg)
    }
    keeperStoreAPIKeyInStandardKeychain(key)
}

private func keeperStoreAPIKeyInStandardKeychain(_ key: String) {
    _ = try? SSKeychain.setPassword(key, forService: keeperKeychainService, account: keeperKeychainAccountAPIKey)
}

/// Returns API key from secure or standard Keychain. When found only in standard, migrates to data-protection Keychain.
internal func keeperAPIKeyFromKeychain() -> String? {
    if let fn = KeeperTestOverrides.apiKeyFromKeychain, let key = fn(), !key.isEmpty { return key }
    if let key = keeperAPIKeyFromSecureKeychain() {
        return key
    }
    if let key = keeperAPIKeyFromStandardKeychain(), !key.isEmpty {
        keeperStoreAPIKeyInKeychain(key)
        return key
    }
    return nil
}

internal func keeperDeleteAPIKeyFromKeychain() {
    if let fn = KeeperTestOverrides.deleteAPIKeyFromKeychain { fn(); return }
    if #available(macOS 10.15, *) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keeperKeychainService,
            kSecAttrAccount as String: keeperKeychainAccountAPIKey,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(query as CFDictionary)
    }
    try? SSKeychain.deletePassword(forService: keeperKeychainService, account: keeperKeychainAccountAPIKey)
    try? SSKeychain.deletePassword(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIKey)
    iTermUserDefaults.userDefaults().removeObject(forKey: keeperLegacyUserDefaultsAPIKeyKey)
}

// MARK: - Migration

/// Call once per launch before reading the API key. Migrates token from UserDefaults or legacy Keychain into the new secure Keychain.
internal func keeperMigrateLegacyKeeperTokenIfNeeded() {
    if let legacyKey = iTermUserDefaults.userDefaults().string(forKey: keeperLegacyUserDefaultsAPIKeyKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !legacyKey.isEmpty {
        keeperStoreAPIKeyInKeychain(legacyKey)
        iTermUserDefaults.userDefaults().removeObject(forKey: keeperLegacyUserDefaultsAPIKeyKey)
        if let legacyURL = iTermUserDefaults.userDefaults().string(forKey: keeperLegacyUserDefaultsAPIURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !legacyURL.isEmpty {
            keeperStoreAPIURLInKeychain(legacyURL)
        }
        return
    }
    if let legacyKey = try? SSKeychain.password(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIKey), !legacyKey.isEmpty {
        keeperStoreAPIKeyInKeychain(legacyKey)
        try? SSKeychain.deletePassword(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIKey)
        if let legacyURL = try? SSKeychain.password(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIURL), !legacyURL.isEmpty {
            keeperStoreAPIURLInKeychain(legacyURL)
            try? SSKeychain.deletePassword(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIURL)
        }
    }
}

// MARK: - API URL storage

internal func keeperAPIURLFromStorage() -> String? {
    if let fn = KeeperTestOverrides.apiURLFromStorage, let url = fn(), !url.isEmpty { return url }
    if let url = iTermUserDefaults.userDefaults().string(forKey: keeperLegacyUserDefaultsAPIURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
        return url
    }
    if let url = try? SSKeychain.password(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIURL), !url.isEmpty {
        iTermUserDefaults.userDefaults().set(url, forKey: keeperLegacyUserDefaultsAPIURLKey)
        try? SSKeychain.deletePassword(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIURL)
        return url
    }
    if let url = try? SSKeychain.password(forService: keeperKeychainService, account: keeperKeychainAccountAPIURL), !url.isEmpty {
        iTermUserDefaults.userDefaults().set(url, forKey: keeperLegacyUserDefaultsAPIURLKey)
        try? SSKeychain.deletePassword(forService: keeperKeychainService, account: keeperKeychainAccountAPIURL)
        return url
    }
    return nil
}

internal func keeperStoreAPIURLInKeychain(_ url: String) {
    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
    iTermUserDefaults.userDefaults().set(trimmed.isEmpty ? nil : trimmed, forKey: keeperLegacyUserDefaultsAPIURLKey)
    try? SSKeychain.deletePassword(forService: keeperKeychainService, account: keeperKeychainAccountAPIURL)
    try? SSKeychain.deletePassword(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIURL)
}

/// Removes API URL from UserDefaults and Keychain. Used when user clears the URL in settings.
internal func keeperClearAPIURLStorage() {
    iTermUserDefaults.userDefaults().removeObject(forKey: keeperLegacyUserDefaultsAPIURLKey)
    try? SSKeychain.deletePassword(forService: keeperKeychainService, account: keeperKeychainAccountAPIURL)
    try? SSKeychain.deletePassword(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIURL)
}
