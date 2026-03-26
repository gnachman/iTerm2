//
//  KeeperDataSource.swift
//  iTerm2SharedARC
//
//  Keychain / UserDefaults for Keeper Commander API key and URL, and “Keeper Security Settings” sheet wiring.
//  All HTTP to Commander (v2 queue, ls/get/record commands) lives in pwmplugin: iterm2-keeper-adapter.
//

import Foundation
import AppKit
import Security

/// No default API URL: user must set API URL in Keeper Security Settings.

/// Posted when Keeper connection fails (e.g. no API key, service unreachable). userInfo[@"error"] = error message (String).
public let iTerm2KeeperConnectionDidFailNotification = Notification.Name("iTerm2KeeperConnectionDidFail")
/// Posted when Keeper fetch succeeds after a connection attempt.
public let iTerm2KeeperConnectionDidSucceedNotification = Notification.Name("iTerm2KeeperConnectionDidSucceed")

// MARK: - Test overrides (Keychain/UI)

/// Test overrides: when set, production uses these instead of real Keychain/UI. Cleared in production.
internal enum KeeperTestOverrides {
    static var apiKeyFromKeychain: (() -> String?)?
    static var secureKeychainReturns: (() -> String?)?
    static var standardKeychainReturns: (() -> String?)?
    static var storeAPIKeyInKeychain: ((String) -> Void)?
    static var deleteAPIKeyFromKeychain: (() -> Void)?
    static var showAPIKeyDialogOverride: ((String?, NSWindow?, @escaping (KeeperAPIKeyPromptResult?) -> Void) -> Void)?
    static var showAPIKeyDialogUIOverride: ((String?, NSWindow?, @escaping (KeeperAPIKeyPromptResult?) -> Void) -> Void)?
    static var callDialogUI: ((String?, NSWindow?, @escaping (KeeperAPIKeyPromptResult?) -> Void) -> Void)?
    static var defaultDialogUI: ((String?, NSWindow?, @escaping (KeeperAPIKeyPromptResult?) -> Void) -> Void)?
    static var fallbackDialogUIForCoverage: ((String?, NSWindow?, @escaping (KeeperAPIKeyPromptResult?) -> Void) -> Void)?
    static var apiURLFromStorage: (() -> String?)?
    static var forceAccessControlCreationToFail: Bool = false
    static var forceSecItemAddToFail: Bool = false
}

// MARK: - API key prompt (with optional existing key)

enum KeeperAPIKeyPromptResult {
    case useExisting
    case useNew(String)
    case cancel
}

// MARK: - ObjC bridge (password manager window registers the settings sheet here)

class KeeperDataSource: NSObject {
    private static var _showKeeperSettingsSheetHandler: ((NSWindow?, @escaping (String?) -> Void) -> Void)?

    /// When set by the app (e.g. password manager window), the full “Keeper Security Settings” sheet is shown for API key + URL.
    static var showKeeperSettingsSheetHandler: ((NSWindow?, @escaping (String?) -> Void) -> Void)? {
        get { _showKeeperSettingsSheetHandler }
        set { _showKeeperSettingsSheetHandler = newValue }
    }

    /// Register the handler that shows the full Keeper Security Settings sheet. Call with nil when the sheet is not available.
    @objc static func setShowKeeperSettingsSheetHandler(_ handler: ((NSWindow?, @escaping (String?) -> Void) -> Void)?) {
        _showKeeperSettingsSheetHandler = handler
    }
}

// MARK: - Keychain and API URL storage

internal let keeperLegacyUserDefaultsAPIKeyKey = "NoSyncKeeperCommanderAPIKey"
internal let keeperLegacyUserDefaultsAPIURLKey = "NoSyncKeeperCommanderAPIURL"

private let keeperKeychainService = "com.iterm2.keeper-service-mode"
private let keeperKeychainAccountAPIKey = "api-key"
private let keeperKeychainAccountAPIURL = "api-url"
private let keeperLegacyKeychainService = "iTerm2-Keeper"

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

internal func keeperAPIKeyFromStandardKeychain() -> String? {
    if let fn = KeeperTestOverrides.standardKeychainReturns, let key = fn(), !key.isEmpty { return key }
    return try? SSKeychain.password(forService: keeperKeychainService, account: keeperKeychainAccountAPIKey)
}

internal func keeperStoreAPIKeyInKeychain(_ key: String) {
    if let fn = KeeperTestOverrides.storeAPIKeyInKeychain { fn(key); return }
    let keyData = Data(key.utf8)
    if #available(macOS 10.15, *) {
        var access: SecAccessControl?
        if KeeperTestOverrides.forceAccessControlCreationToFail {
            access = nil
        } else {
            var error: Unmanaged<CFError>?
            access = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                SecAccessControlCreateFlags.userPresence,
                &error
            )
        }
        guard let access = access else {
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
        let status = KeeperTestOverrides.forceSecItemAddToFail ? errSecDuplicateItem : SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            return
        }
        let msg = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
        DLog("Keeper: biometric keychain add failed (\(status)) \(msg), using standard keychain")
        NSLog("[iTerm2 Keeper] Data protection keychain add failed: %@ (use standard keychain)", msg)
    }
    keeperStoreAPIKeyInStandardKeychain(key)
}

internal func keeperStoreAPIKeyInStandardKeychain(_ key: String) {
    _ = SSKeychain.setPassword(key, forService: keeperKeychainService, account: keeperKeychainAccountAPIKey)
}

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
    _ = SSKeychain.deletePassword(forService: keeperKeychainService, account: keeperKeychainAccountAPIKey)
    _ = SSKeychain.deletePassword(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIKey)
    iTermUserDefaults.userDefaults().removeObject(forKey: keeperLegacyUserDefaultsAPIKeyKey)
}

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
        _ = SSKeychain.deletePassword(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIKey)
        if let legacyURL = try? SSKeychain.password(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIURL), !legacyURL.isEmpty {
            keeperStoreAPIURLInKeychain(legacyURL)
            _ = SSKeychain.deletePassword(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIURL)
        }
    }
}

internal func keeperAPIURLFromStorage() -> String? {
    if let fn = KeeperTestOverrides.apiURLFromStorage, let url = fn(), !url.isEmpty { return url }
    if let url = iTermUserDefaults.userDefaults().string(forKey: keeperLegacyUserDefaultsAPIURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
        return url
    }
    if let url = try? SSKeychain.password(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIURL), !url.isEmpty {
        iTermUserDefaults.userDefaults().set(url, forKey: keeperLegacyUserDefaultsAPIURLKey)
        _ = SSKeychain.deletePassword(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIURL)
        return url
    }
    if let url = try? SSKeychain.password(forService: keeperKeychainService, account: keeperKeychainAccountAPIURL), !url.isEmpty {
        iTermUserDefaults.userDefaults().set(url, forKey: keeperLegacyUserDefaultsAPIURLKey)
        _ = SSKeychain.deletePassword(forService: keeperKeychainService, account: keeperKeychainAccountAPIURL)
        return url
    }
    return nil
}

internal func keeperStoreAPIURLInKeychain(_ url: String) {
    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
    iTermUserDefaults.userDefaults().set(trimmed.isEmpty ? nil : trimmed, forKey: keeperLegacyUserDefaultsAPIURLKey)
    _ = SSKeychain.deletePassword(forService: keeperKeychainService, account: keeperKeychainAccountAPIURL)
    _ = SSKeychain.deletePassword(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIURL)
}

internal func keeperClearAPIURLStorage() {
    iTermUserDefaults.userDefaults().removeObject(forKey: keeperLegacyUserDefaultsAPIURLKey)
    _ = SSKeychain.deletePassword(forService: keeperKeychainService, account: keeperKeychainAccountAPIURL)
    _ = SSKeychain.deletePassword(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIURL)
}

// MARK: - API key dialog UI (legacy; deprecated)

func keeperShowAPIKeyDialogUI(existingKey: String?, window: NSWindow?, completion: @escaping (KeeperAPIKeyPromptResult?) -> Void) {
    completion(.cancel)
}

internal func keeperResolvedDialogFunction() -> (String?, NSWindow?, @escaping (KeeperAPIKeyPromptResult?) -> Void) -> Void {
    if let fn = KeeperTestOverrides.callDialogUI { return fn }
    if let fn = KeeperTestOverrides.defaultDialogUI { return fn }
    if let fn = KeeperTestOverrides.fallbackDialogUIForCoverage { return fn }
    return keeperShowAPIKeyDialogUI
}

/// Shows API key flow. When `KeeperDataSource.showKeeperSettingsSheetHandler` is set, that sheet runs instead of legacy UI.
/// Must be called on the main thread.
func keeperShowAPIKeyDialog(existingKey: String?, window: NSWindow?, completion: @escaping (KeeperAPIKeyPromptResult?) -> Void) {
    dispatchPrecondition(condition: .onQueue(.main))
    if let fn = KeeperTestOverrides.showAPIKeyDialogOverride { fn(existingKey, window, completion); return }
    if let fn = KeeperTestOverrides.showAPIKeyDialogUIOverride { fn(existingKey, window, completion); return }
    if let showSheet = KeeperDataSource.showKeeperSettingsSheetHandler {
        showSheet(window) { key in
            if let key = key, !key.isEmpty {
                completion(.useNew(key))
            } else {
                completion(.cancel)
            }
        }
        return
    }
    if KeeperTestOverrides.callDialogUI != nil || KeeperTestOverrides.defaultDialogUI != nil || KeeperTestOverrides.fallbackDialogUIForCoverage != nil {
        keeperResolvedDialogFunction()(existingKey, window, completion)
        return
    }
    completion(.cancel)
}

// MARK: - Keeper credentials request (sheet shown by window controller)

@objc public protocol KeeperCredentialsRequestDelegate: AnyObject {
    func keeperDataSourceRequestCredentials(forWindow window: NSWindow, completion: @escaping (String?) -> Void)
}
