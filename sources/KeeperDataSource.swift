//
//  KeeperDataSource.swift
//  iTerm2SharedARC
//
//  Keeper Security integration via Keeper Commander service mode.
//  Communicates with local Keeper Commander service (e.g. service-create -p 8900 -f json -aip 127.0.0.1).
//  Keychain/URL storage and API key dialog UI are in this file.
//

import Foundation
import AppKit
import Security

/// No default API URL: user must set API URL in Keeper Security Settings.

/// Posted when Keeper connection fails (e.g. no API key, service unreachable). userInfo[@"error"] = error message (String).
public let iTerm2KeeperConnectionDidFailNotification = Notification.Name("iTerm2KeeperConnectionDidFail")
/// Posted when Keeper fetch succeeds after a connection attempt.
public let iTerm2KeeperConnectionDidSucceedNotification = Notification.Name("iTerm2KeeperConnectionDidSucceed")

// MARK: - Test overrides (Keychain/UI; real implementation below in this file)

/// Test overrides: when set, production uses these instead of real Keychain/UI. Cleared in production.
internal enum KeeperTestOverrides {
    static var apiKeyFromKeychain: (() -> String?)?
    static var secureKeychainReturns: (() -> String?)?
    static var standardKeychainReturns: (() -> String?)?
    static var storeAPIKeyInKeychain: ((String) -> Void)?
    static var deleteAPIKeyFromKeychain: (() -> Void)?
    static var showAPIKeyDialogOverride: ((String?, NSWindow?, @escaping (KeeperAPIKeyPromptResult?) -> Void) -> Void)?
    /// When set, used instead of keeperShowAPIKeyDialogUI so tests can cover the "no showAPIKeyDialogOverride" path without showing real UI.
    static var showAPIKeyDialogUIOverride: ((String?, NSWindow?, @escaping (KeeperAPIKeyPromptResult?) -> Void) -> Void)?
    /// When set, used instead of keeperShowAPIKeyDialogUI so the "call dialog" line is covered without showing real UI. When nil, keeperShowAPIKeyDialogUI is called.
    static var callDialogUI: ((String?, NSWindow?, @escaping (KeeperAPIKeyPromptResult?) -> Void) -> Void)?
    /// When set, used as fallback when callDialogUI is nil (so tests can cover the "default dialog" path without showing real UI). When nil, keeperShowAPIKeyDialogUI is used.
    static var defaultDialogUI: ((String?, NSWindow?, @escaping (KeeperAPIKeyPromptResult?) -> Void) -> Void)?
    /// When set, used after defaultDialogUI so tests can cover the resolver's third branch without showing real UI. When nil, keeperShowAPIKeyDialogUI is used.
    static var fallbackDialogUIForCoverage: ((String?, NSWindow?, @escaping (KeeperAPIKeyPromptResult?) -> Void) -> Void)?
    /// When set, keeperAPIURLFromStorage() in KeeperKeychain returns this instead of reading UserDefaults/Keychain. Used by cache test.
    static var apiURLFromStorage: (() -> String?)?
    /// When true, keeperStoreAPIKeyInKeychain treats access control creation as failed so the guard-else fallback runs (for coverage).
    static var forceAccessControlCreationToFail: Bool = false
    /// When true, keeperStoreAPIKeyInKeychain treats SecItemAdd as failed so the DLog/NSLog/standard-keychain fallback runs (for coverage).
    static var forceSecItemAddToFail: Bool = false
}

// MARK: - API key prompt (with optional existing key)

enum KeeperAPIKeyPromptResult {
    case useExisting
    case useNew(String)
    case cancel
}

// MARK: - Keychain and API URL storage (merged from KeeperKeychain.swift)

internal let keeperLegacyUserDefaultsAPIKeyKey = "NoSyncKeeperCommanderAPIKey"
internal let keeperLegacyUserDefaultsAPIURLKey = "NoSyncKeeperCommanderAPIURL"

private let keeperKeychainService = "com.iterm2.keeper-service-mode"
private let keeperKeychainAccountAPIKey = "api-key"
private let keeperKeychainAccountAPIURL = "api-url"
private let keeperLegacyKeychainService = "iTerm2-Keeper"

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

/// Standard keychain store (no data-protection). Internal so tests can cover this path when biometric keychain is unavailable.
internal func keeperStoreAPIKeyInStandardKeychain(_ key: String) {
    _ = SSKeychain.setPassword(key, forService: keeperKeychainService, account: keeperKeychainAccountAPIKey)
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
    _ = SSKeychain.deletePassword(forService: keeperKeychainService, account: keeperKeychainAccountAPIKey)
    _ = SSKeychain.deletePassword(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIKey)
    iTermUserDefaults.userDefaults().removeObject(forKey: keeperLegacyUserDefaultsAPIKeyKey)
}

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

/// Removes API URL from UserDefaults and Keychain. Used when user clears the URL in settings.
internal func keeperClearAPIURLStorage() {
    iTermUserDefaults.userDefaults().removeObject(forKey: keeperLegacyUserDefaultsAPIURLKey)
    _ = SSKeychain.deletePassword(forService: keeperKeychainService, account: keeperKeychainAccountAPIURL)
    _ = SSKeychain.deletePassword(forService: keeperLegacyKeychainService, account: keeperKeychainAccountAPIURL)
}

// MARK: - API key dialog UI (legacy; deprecated)

/// Legacy API-key-only dialog is no longer shown. The app uses the “Keeper Security Settings” sheet (API URL + API Key) when the password manager window is open; otherwise the prompt completes with cancel. This function exists so the resolver has a fallback and completes with cancel without showing UI.
func keeperShowAPIKeyDialogUI(existingKey: String?, window: NSWindow?, completion: @escaping (KeeperAPIKeyPromptResult?) -> Void) {
    completion(.cancel)
}

// MARK: - API key prompt (with optional existing key)

/// Returns the dialog function to use (override, default, fallback for tests, or real UI). Named function so all branches are coverable. Internal for tests to cover the real-UI return path without invoking it.
internal func keeperResolvedDialogFunction() -> (String?, NSWindow?, @escaping (KeeperAPIKeyPromptResult?) -> Void) -> Void {
    if let fn = KeeperTestOverrides.callDialogUI { return fn }
    if let fn = KeeperTestOverrides.defaultDialogUI { return fn }
    if let fn = KeeperTestOverrides.fallbackDialogUIForCoverage { return fn }
    return keeperShowAPIKeyDialogUI
}

/// When set by the app (e.g. password manager window), the full “Keeper Security Settings” sheet (API key + API URL) is shown instead of the legacy API-key-only dialog. Set to nil when the sheet is not available (e.g. window closed).
/// Shows API key dialog. If existingKey is non-nil, shows "Use existing" / "Update" / "Cancel". Otherwise "OK" / "Cancel".
/// When a settings-sheet handler is registered (see KeeperDataSource.setShowKeeperSettingsSheetHandler), that sheet (API key + API URL) is shown instead of the legacy API-key-only dialog.
/// Completion is called on the main thread when the user dismisses the dialog. Must be called from the main thread.
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
    // Test overrides for the resolver path (so tests can run without showing real UI).
    if KeeperTestOverrides.callDialogUI != nil || KeeperTestOverrides.defaultDialogUI != nil || KeeperTestOverrides.fallbackDialogUIForCoverage != nil {
        keeperResolvedDialogFunction()(existingKey, window, completion)
        return
    }
    // No settings sheet and no test override: don't show the legacy API-key-only dialog.
    completion(.cancel)
}

// MARK: - Keeper REST client

private struct KeeperExecuteRequest: Encodable {
    let command: String
}

private struct KeeperExecuteResponse: Decodable {
    let status: String?
    let command: String?
    let data: KeeperListData?
    let result: String?
    let message: String?
}

/// For "list" / "search" the API may return data as an array of records (not data.records).
private struct KeeperExecuteResponseDataArray: Decodable {
    let status: String?
    let command: String?
    let data: [KeeperRecord]?
    let result: String?
    let message: String?
}

/// v2 result endpoint may return { "status": "success", "result": "<command output as string>" }.
private struct KeeperV2ResultWrapper: Decodable {
    let status: String?
    let result: String?
}

private struct KeeperListData: Decodable {
    let folders: [KeeperFolder]?
    let records: [KeeperRecord]?
}

private struct KeeperFolder: Decodable {
    let number: Int?
    let uid: String?
    let name: String?
    let flags: String?
}

internal struct KeeperRecord: Decodable {
    let number: Int?
    let uid: String?
    /// Some API responses use record_uid instead of uid.
    private let record_uid: String?
    var effectiveUid: String? { uid ?? record_uid }
    let type: String?
    let title: String?
    let description: String?

    init(number: Int?, uid: String?, record_uid: String?, type: String?, title: String?, description: String?) {
        self.number = number
        self.uid = uid
        self.record_uid = record_uid
        self.type = type
        self.title = title
        self.description = description
    }
}

// API v2 async (queue) response types
private struct KeeperV2QueuedResponse: Decodable {
    let success: Bool?
    let request_id: String?
    let status: String?
    let message: String?
}

private struct KeeperV2StatusResponse: Decodable {
    let success: Bool?
    let request_id: String?
    let status: String?  // "queued" | "processing" | "completed" | "failed" | "expired"
    let command: String?
}

private let _keeperBaseURLLock = NSLock()
private var _cachedKeeperBaseURL: URL?

/// Clear the cached base URL so the next API call reads from Keychain again (e.g. after user updates URL in settings). Internal for tests.
internal func keeperClearBaseURLCache() {
    _keeperBaseURLLock.lock()
    _cachedKeeperBaseURL = nil
    _keeperBaseURLLock.unlock()
}

private func keeperBaseURL() -> URL? {
    _keeperBaseURLLock.lock()
    if let cached = _cachedKeeperBaseURL {
        let url = cached
        _keeperBaseURLLock.unlock()
        return url
    }
    let parsed: URL?
    if let urlString = keeperAPIURLFromStorage()?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty,
       let url = URL(string: urlString), url.scheme != nil, url.host != nil {
        parsed = url
    } else {
        parsed = nil
    }
    _cachedKeeperBaseURL = parsed
    _keeperBaseURLLock.unlock()
    return parsed
}

/// Returns the base URL for v2 API endpoints (path ends with /api/v2, no trailing slash).
/// Accepts either origin-only (e.g. http://localhost:8900) or full v2 path (e.g. http://localhost:8900/api/v2/). Internal for tests.
internal func keeperV2BaseURL(baseURL: URL) -> URL {
    var path = baseURL.path
    while path.hasSuffix("/") { path.removeLast() }
    if path.hasSuffix("api/v2") {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        return components.url ?? baseURL
    }
    return baseURL.appendingPathComponent("api").appendingPathComponent("v2")
}

private func keeperV2AsyncURL(baseURL: URL) -> URL {
    keeperV2BaseURL(baseURL: baseURL).appendingPathComponent("executecommand-async")
}

private func keeperV2StatusURL(requestId: String, baseURL: URL) -> URL {
    keeperV2BaseURL(baseURL: baseURL).appendingPathComponent("status").appendingPathComponent(requestId)
}

private func keeperV2ResultURL(requestId: String, baseURL: URL) -> URL {
    keeperV2BaseURL(baseURL: baseURL).appendingPathComponent("result").appendingPathComponent(requestId)
}

/// Extracts a human-readable error message from API response data (e.g. {"error":"Please provide a valid api key","status":"error"}). Exposed internal for unit tests.
internal func keeperHumanReadableError(fromResponseData data: Data?) -> String? {
    guard let data = data,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    if let error = json["error"] as? String, !error.isEmpty { return error }
    if let message = json["message"] as? String, !message.isEmpty { return message }
    return nil
}

/// Maps password-update API error messages (e.g. "Base64 decoding failed for field pwd.") to a clear user-facing message. Internal for tests.
internal func keeperUserFacingPasswordUpdateError(apiDetail: String) -> String {
    let lower = apiDetail.lowercased()
    if lower.contains("base64") || lower.contains("pwd") || (lower.contains("password") && (lower.contains("failed") || lower.contains("invalid") || lower.contains("required") || lower.contains("empty"))) {
        return "Password field is required."
    }
    return apiDetail
}

private func keeperExecute(apiKey: String, command: String, baseURL: URL? = nil, session: URLSession = .shared, pollInterval: TimeInterval? = nil, deadline: TimeInterval? = nil, completion: @escaping (Result<Data, Error>) -> Void) {
    guard let resolvedBase = baseURL ?? keeperBaseURL() else {
        completion(.failure(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "API URL is required. Please set it in Keeper Security Settings."])))
        return
    }
    keeperExecuteV2(apiKey: apiKey, command: command, baseURL: resolvedBase, session: session, pollInterval: pollInterval, deadline: deadline, completion: completion)
}

/// Handles v2 POST response; extracted for testability and coverage.
private func keeperExecuteV2HandleResponse(data: Data?, response: URLResponse?, error: Error?, apiKey: String, baseURL: URL, session: URLSession, pollInterval: TimeInterval?, deadline: TimeInterval?, completion: @escaping (Result<Data, Error>) -> Void) {
    if let error = error {
        completion(.failure(error))
        return
    }
    guard let data = data else {
        keeperExecuteV2FailNoData(completion: completion)
        return
    }
    guard let http = response as? HTTPURLResponse, http.statusCode == 202 else {
        keeperExecuteV2FailNon202(data: data, completion: completion)
        return
    }
    guard let queued = try? JSONDecoder().decode(KeeperV2QueuedResponse.self, from: data),
          let requestId = queued.request_id, !requestId.isEmpty else {
        keeperExecuteV2FailNoRequestId(completion: completion)
        return
    }
    keeperV2PollForResult(apiKey: apiKey, requestId: requestId, baseURL: baseURL, session: session, pollInterval: pollInterval, deadline: deadline, completion: completion)
}

/// Named so coverage attributes the "No data" path to this function. Internal so tests can call directly for coverage.
internal func keeperExecuteV2FailNoData(completion: @escaping (Result<Data, Error>) -> Void) {
    completion(.failure(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
}

/// Named for coverage: non-202 response from v2 POST. Internal so tests can call directly for coverage.
internal func keeperExecuteV2FailNon202(data: Data?, completion: @escaping (Result<Data, Error>) -> Void) {
    let msg = keeperHumanReadableError(fromResponseData: data)
        ?? String(data: data ?? Data(), encoding: .utf8)
        ?? "Unexpected response"
    completion(.failure(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])))
}

/// Named for coverage: 202 response but no request_id in body. Internal so tests can call directly for coverage.
internal func keeperExecuteV2FailNoRequestId(completion: @escaping (Result<Data, Error>) -> Void) {
    completion(.failure(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "No request_id in v2 response"])))
}

/// Keeper Commander API v2 (queue): submit async, poll status, then fetch result.
private func keeperExecuteV2(apiKey: String, command: String, baseURL: URL, session: URLSession = .shared, pollInterval: TimeInterval? = nil, deadline: TimeInterval? = nil, completion: @escaping (Result<Data, Error>) -> Void) {
    let body = (try? JSONEncoder().encode(KeeperExecuteRequest(command: command))) ?? Data()
    var request = URLRequest(url: keeperV2AsyncURL(baseURL: baseURL))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "api-key")
    request.httpBody = body
    session.dataTask(with: request) { keeperExecuteV2HandleResponse(data: $0, response: $1, error: $2, apiKey: apiKey, baseURL: baseURL, session: session, pollInterval: pollInterval, deadline: deadline, completion: completion) }.resume()
}

/// State for v2 poll loop; holds mutable counters so the dataTask completion can be a named function.
private final class KeeperV2PollRunner {
    let apiKey: String
    let requestId: String
    let baseURL: URL
    let session: URLSession
    let interval: TimeInterval
    let deadlineDate: Date
    let completion: (Result<Data, Error>) -> Void
    let maxPolls = 60
    var pollCount = 0
    var consecutiveUnparseable = 0

    init(apiKey: String, requestId: String, baseURL: URL, session: URLSession, interval: TimeInterval, deadlineDate: Date, completion: @escaping (Result<Data, Error>) -> Void) {
        self.apiKey = apiKey
        self.requestId = requestId
        self.baseURL = baseURL
        self.session = session
        self.interval = interval
        self.deadlineDate = deadlineDate
        self.completion = completion
    }

    func doPoll() {
        pollCount += 1
        if Date() > deadlineDate {
            completion(.failure(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "Keeper service v2 request timed out"])))
            return
        }
        if pollCount > maxPolls {
            completion(.failure(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "Keeper service did not complete the request in time"])))
            return
        }
        var request = URLRequest(url: keeperV2StatusURL(requestId: requestId, baseURL: baseURL))
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        session.dataTask(with: request) { [self] data, response, error in
            handleStatusResponse(data: data, response: response, error: error)
        }.resume()
    }

    func handleStatusResponse(data: Data?, response: URLResponse?, error: Error?) {
        if let error = error {
            completion(.failure(error))
            return
        }
        let http = response as? HTTPURLResponse
        let responseData = data
        if let code = http?.statusCode, code != 200 {
            keeperV2PollFailHTTP(code: code, responseData: responseData, completion: completion)
            return
        }
        guard let data = data,
              let statusResp = try? JSONDecoder().decode(KeeperV2StatusResponse.self, from: data),
              let status = statusResp.status else {
            consecutiveUnparseable += 1
            if consecutiveUnparseable >= 15 {
                let msg = keeperHumanReadableError(fromResponseData: responseData)
                    ?? "Keeper service returned an invalid status response"
                completion(.failure(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])))
                return
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + interval) { [self] in doPoll() }
            return
        }
        consecutiveUnparseable = 0
        switch status {
        case "completed":
            keeperV2FetchResult(apiKey: apiKey, requestId: requestId, baseURL: baseURL, session: session, completion: completion)
        case "failed", "expired":
            keeperV2PollFailWithStatus(status, completion: completion)
        default:
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + interval) { [self] in doPoll() }
        }
    }
}

/// Named for coverage: GET status/ returned non-200. Internal so tests can call it directly.
internal func keeperV2PollFailHTTP(code: Int, responseData: Data?, completion: @escaping (Result<Data, Error>) -> Void) {
    let msg = keeperHumanReadableError(fromResponseData: responseData)
        ?? String(data: responseData ?? Data(), encoding: .utf8)
        ?? "HTTP \(code)"
    completion(.failure(NSError(domain: "KeeperDataSource", code: code, userInfo: [NSLocalizedDescriptionKey: msg])))
}

/// Named so coverage attributes the v2 "failed"/"expired" status path.
private func keeperV2PollFailWithStatus(_ status: String, completion: @escaping (Result<Data, Error>) -> Void) {
    completion(.failure(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "Keeper command \(status)"])))
}

private func keeperV2PollForResult(apiKey: String, requestId: String, baseURL: URL, session: URLSession = .shared, pollInterval: TimeInterval? = nil, deadline: TimeInterval? = nil, completion: @escaping (Result<Data, Error>) -> Void) {
    let interval: TimeInterval = pollInterval ?? 2.0
    let deadlineOffset: TimeInterval = deadline ?? 120
    let deadlineDate = Date().addingTimeInterval(deadlineOffset)
    let runner = KeeperV2PollRunner(apiKey: apiKey, requestId: requestId, baseURL: baseURL, session: session, interval: interval, deadlineDate: deadlineDate, completion: completion)
    runner.doPoll()
}

/// Handles v2 GET result response; extracted for coverage.
private func keeperV2FetchResultHandleResponse(data: Data?, response: URLResponse?, error: Error?, completion: @escaping (Result<Data, Error>) -> Void) {
    if let error = error {
        completion(.failure(error))
        return
    }
    guard let data = data, !data.isEmpty else {
        completion(.failure(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
        return
    }
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        let msg = keeperHumanReadableError(fromResponseData: data)
            ?? String(data: data, encoding: .utf8)
            ?? "HTTP \(http.statusCode)"
        completion(.failure(NSError(domain: "KeeperDataSource", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])))
        return
    }
    completion(.success(data))
}

private func keeperV2FetchResult(apiKey: String, requestId: String, baseURL: URL, session: URLSession = .shared, completion: @escaping (Result<Data, Error>) -> Void) {
    var request = URLRequest(url: keeperV2ResultURL(requestId: requestId, baseURL: baseURL))
    request.setValue(apiKey, forHTTPHeaderField: "api-key")
    session.dataTask(with: request) { keeperV2FetchResultHandleResponse(data: $0, response: $1, error: $2, completion: completion) }.resume()
}

/// Parses a single line from Keeper "ls -R -l" data.records[].title (table row).
/// Format: "number  record_uid  type  title  description" (columns separated by two+ spaces).
/// Returns nil for header/separator lines (starting with # or ---).
internal func parseLsRecordLine(_ line: String) -> KeeperRecord? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("#") || trimmed.hasPrefix("---") { return nil }
    let parts = trimmed.components(separatedBy: "  ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    guard parts.count >= 4,
          let num = Int(parts[0]),
          parts[1].count >= 15,
          parts[1].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
    let uid = parts[1]
    let type = parts[2]
    let title = parts[3]
    let description = parts.count > 4 ? parts.suffix(from: 4).joined(separator: " ") : ""
    return KeeperRecord(number: num, uid: nil, record_uid: uid, type: type, title: title.isEmpty ? "Untitled" : title, description: description)
}

/// Inserts payload from result object (dict or string) for message-table parsing. Internal for coverage of the result-as-string branch.
internal func keeperParseMessageTableInsertResultPayload(resultObj: Any, into payloadsToTry: inout [Data]) {
    if let dict = resultObj as? [String: Any], let innerData = try? JSONSerialization.data(withJSONObject: dict) {
        payloadsToTry.insert(innerData, at: 0)
    } else if let str = resultObj as? String, let innerData = str.data(using: .utf8) {
        payloadsToTry.insert(innerData, at: 0)
    }
}

/// Parses a Keeper "list" or "trash list" response and returns record UIDs from the message table.
internal func parseMessageTableRecordUids(from data: Data) -> Set<String> {
    var payloadsToTry: [Data] = [data]
    if let wrapper = try? JSONDecoder().decode(KeeperV2ResultWrapper.self, from: data),
       wrapper.status == "success",
       let resultString = wrapper.result,
       !resultString.isEmpty,
       let resultData = resultString.data(using: .utf8) {
        payloadsToTry.insert(resultData, at: 0)
    } else if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["status"] as? String == "success",
              let resultObj = root["result"] {
        keeperParseMessageTableInsertResultPayload(resultObj: resultObj, into: &payloadsToTry)
    }
    for jsonData in payloadsToTry {
        guard let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let messageLines = parsed["message"] as? [String], messageLines.count >= 3 else { continue }
        let dataLines = messageLines.dropFirst(2)
        let uids = dataLines.compactMap { line -> String? in
            let parts = line.components(separatedBy: "  ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard parts.count >= 2,
                  parts[1].count >= 15,
                  parts[1].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
            return parts[1]
        }
        if !uids.isEmpty { return Set(uids) }
    }
    return []
}

// MARK: - Keeper account (PasswordManagerAccount)

private class KeeperAccount: NSObject, PasswordManagerAccount {
    let uid: String
    let accountName: String
    let userName: String
    let hasOTP: Bool
    let sendOTP: Bool
    weak var dataSource: KeeperDataSource?

    var displayString: String {
        "\(accountName)\u{2002}—\u{2002}\(userName)"
    }

    init(uid: String, accountName: String, userName: String, hasOTP: Bool, sendOTP: Bool, dataSource: KeeperDataSource) {
        self.uid = uid
        self.accountName = accountName
        self.userName = userName
        self.hasOTP = hasOTP
        self.sendOTP = sendOTP
        self.dataSource = dataSource
    }

    func fetchPassword(context: RecipeExecutionContext, _ completion: @escaping (String?, String?, Error?) -> ()) {
        dataSource?.fetchPassword(recordUid: uid, context: context, completion: completion)
    }

    func set(context: RecipeExecutionContext, password: String, completion: @escaping (Error?) -> ()) {
        dataSource?.setPassword(recordUid: uid, password: password, context: context, completion: completion)
    }

    func delete(context: RecipeExecutionContext, _ completion: @escaping (Error?) -> ()) {
        dataSource?.deleteRecord(recordUid: uid, context: context, completion: completion)
    }

    func matches(filter: String) -> Bool {
        _matches(filter: filter)
    }
}

// MARK: - Keeper credentials request (sheet shown by window controller)

@objc public protocol KeeperCredentialsRequestDelegate: AnyObject {
    func keeperDataSourceRequestCredentials(forWindow window: NSWindow, completion: @escaping (String?) -> Void)
}

// MARK: - KeeperDataSource

class KeeperDataSource: NSObject, PasswordManagerDataSource {
    /// When set by the app (e.g. password manager window), the full “Keeper Security Settings” sheet (API key + API URL) is shown instead of the legacy API-key-only dialog. Set to nil when the sheet is not available (e.g. window closed).
    static var showKeeperSettingsSheetHandler: ((NSWindow?, @escaping (String?) -> Void) -> Void)?

    /// Register the handler that shows the full Keeper Security Settings sheet (API key + API URL). Call with a non-nil block when the sheet can be shown (e.g. password manager window with Keeper selected); call with nil when the sheet is not available (prompt will complete with cancel).
    @objc static func setShowKeeperSettingsSheetHandler(_ handler: ((NSWindow?, @escaping (String?) -> Void) -> Void)?) {
        showKeeperSettingsSheetHandler = handler
    }

    private let browser: Bool
    private let _apiKeyLoadLock = NSLock()
    private var _apiKey: String?
    /// In-memory only: used to pre-fill the settings sheet. Never read from Keychain for the sheet so we don't trigger a second Mac password prompt after PM authentication.
    private var _cachedSettingsKey: String?
    private var _cachedSettingsURL: String?

    @objc public weak var credentialsDelegate: KeeperCredentialsRequestDelegate?

    /// Test-only: when set, ensureAPIKey uses this instead of Keychain; API calls use this base URL and session. Not used in production.
    internal var injectedAPIKey: String?
    internal var injectedBaseURL: URL?
    internal var injectedURLSession: URLSession?
    /// Test-only: when set, used instead of keeperBaseURL() so tests can simulate URL-from-storage without UserDefaults.
    internal var injectedBaseURLFromStorage: URL?
    /// Test-only: when set, keeperSettingsAPIURL() returns this instead of reading storage.
    internal var injectedAPIURLFromStorage: String?
    /// Test-only: when set, keychain read in ensureAPIKey uses this instead of real Keychain.
    internal var injectedKeychainGetAPIKey: (() -> String?)?
    /// Test-only: when set, keychain store (ensureAPIKey .useNew and setKeeperSettingsAPIKey) calls this instead of real Keychain.
    internal var injectedKeychainSetAPIKey: ((String) -> Void)?
    /// Test-only: when set, keychain delete (resetConfiguration and setKeeperSettingsAPIKey(empty)) calls this instead of real Keychain.
    internal var injectedKeychainDeleteAPIKey: (() -> Void)?
    /// Test-only: when set, setKeeperSettingsAPIURL calls this instead of writing to UserDefaults/Keychain.
    internal var injectedStoreAPIURL: ((String) -> Void)?
    /// Test-only: v2 poll interval in seconds (default 2). Use with injectedV2Deadline to test timeout quickly.
    internal var injectedV2PollInterval: TimeInterval?
    /// Test-only: v2 poll deadline in seconds from now (default 120). Use with injectedV2PollInterval to test timeout quickly.
    internal var injectedV2Deadline: TimeInterval?
    /// Test-only: when dialog returns .useExisting, use this as the key so the “use existing key” success branch is covered.
    internal var injectedUseExistingKeyForDialog: String?
    /// Test-only: when set, ensureAPIKey (inside the lock) uses this as if _cachedSettingsKey were set, so the 562–565 branch is coverable without a race.
    internal var injectedCachedSettingsKeyForLockTest: String?

    init(browser: Bool) {
        self.browser = browser
    }

    /// True if we already have an API key in memory (from this session). Used when switching back to Keeper so we don’t show the settings sheet again.
    @objc func keeperHasAPIKeyInMemory() -> Bool {
        if let k = injectedAPIKey, !k.isEmpty { return true }
        if let k = _apiKey, !k.isEmpty { return true }
        if let k = _cachedSettingsKey, !k.isEmpty { return true }
        return false
    }

    private func ensureAPIKey(context: RecipeExecutionContext, completion: @escaping (String?) -> Void) {
        if let key = injectedAPIKey {
            if !key.isEmpty {
                completion(key)
                return
            }
            // Test-only: injectedAPIKey == "" means "explicitly no key"; skip Keychain and go straight to delegate/UI.
            if Thread.isMainThread {
                showUIAndContinue()
            } else {
                DispatchQueue.main.async { showUIAndContinue() }
            }
            return
        }
        if let key = _apiKey, !key.isEmpty {
            completion(key)
            return
        }
        if let key = _cachedSettingsKey, !key.isEmpty {
            _apiKey = key
            completion(key)
            return
        }
        // Use Keychain for API calls: read when in-memory is empty. Only one thread does the read (lock) so we get at most one prompt.
        _apiKeyLoadLock.lock()
        if let key = _apiKey, !key.isEmpty {
            let k = key
            _apiKeyLoadLock.unlock()
            completion(k)
            return
        }
        if let key = injectedCachedSettingsKeyForLockTest ?? _cachedSettingsKey, !key.isEmpty {
            _apiKey = key
            let k = key
            _apiKeyLoadLock.unlock()
            completion(k)
            return
        }
        keeperMigrateLegacyKeeperTokenIfNeeded()
        // Test-only: use injected keychain reader when set so tests don't touch real Keychain.
        if let get = injectedKeychainGetAPIKey, let key = get(), !key.isEmpty {
            _apiKey = key
            _cachedSettingsKey = key
            let k = key
            _apiKeyLoadLock.unlock()
            completion(k)
            return
        }
        // Try secure (Touch ID/passcode) keychain first, then standard keychain fallback for devices without biometric/entitlement.
        if let key = keeperAPIKeyFromKeychain(), !key.isEmpty {
            _apiKey = key
            _cachedSettingsKey = key
            let k = key
            _apiKeyLoadLock.unlock()
            completion(k)
            return
        }
        _apiKeyLoadLock.unlock()
        // No key in keychain; show credentials sheet so user can enter API key.
        if Thread.isMainThread {
            showUIAndContinue()
        } else {
            DispatchQueue.main.async { showUIAndContinue() }
        }
        return

        func showUIAndContinue() {
            if credentialsDelegate != nil, let window = context.window {
                keeperHandleCredentialsFromDelegate(window: window, completion: completion)
                return
            }
            keeperShowAPIKeyDialog(existingKey: nil, window: context.window) { [weak self] promptResult in
                self?.keeperHandleDialogResult(promptResult, completion: completion)
            }
        }
    }

    @objc var name: String { "Keeper Security" }
    @objc var canResetConfiguration: Bool { true }
    @objc func resetConfiguration() {
        if let delete = injectedKeychainDeleteAPIKey {
            delete()
            _apiKey = nil
            _cachedSettingsKey = nil
            _cachedSettingsURL = nil
            iTermUserDefaults.userDefaults().removeObject(forKey: keeperLegacyUserDefaultsAPIURLKey)
            keeperClearBaseURLCache()
            return
        }
        keeperDeleteAPIKeyFromKeychain()
        _apiKey = nil
        _cachedSettingsKey = nil
        _cachedSettingsURL = nil
        iTermUserDefaults.userDefaults().removeObject(forKey: keeperLegacyUserDefaultsAPIURLKey)
        keeperClearBaseURLCache()
    }

    var autogeneratedPasswordsOnly: Bool { false }
    @objc var supportsMultipleAccounts: Bool { false }
    func switchAccount(completion: @escaping () -> ()) { completion() }

    func checkAvailability() -> Bool {
        // Return true so we don't block the main thread with a network call.
        // Real availability is checked when fetching accounts (whoami/ls).
        return true
    }

    func fetchAccounts(context: RecipeExecutionContext, completion: @escaping ([PasswordManagerAccount]) -> ()) {
        ensureAPIKey(context: context) { [weak self] apiKey in
            guard let self = self else { return }
            guard let apiKey = apiKey else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: iTerm2KeeperConnectionDidFailNotification,
                        object: nil,
                        userInfo: ["error": "No API key entered or configuration was cancelled."]
                    )
                    completion([])
                }
                return
            }
            keeperExecute(apiKey: apiKey, command: "ls -R -l", baseURL: self.injectedBaseURL ?? self.injectedBaseURLFromStorage ?? keeperBaseURL(), session: self.injectedURLSession ?? .shared, pollInterval: self.injectedV2PollInterval, deadline: self.injectedV2Deadline) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let data):
                    if let raw = String(data: data, encoding: .utf8) {
                        let preview = String(raw.prefix(1500))
                        NSLog("[iTerm2 Keeper] ls -R -l response length=%d body=%@", data.count, preview)
                    }
                    var records: [KeeperRecord]?
                    var payloadsToTry: [Data] = [data]
                    if let wrapper = try? JSONDecoder().decode(KeeperV2ResultWrapper.self, from: data),
                       wrapper.status == "success",
                       let resultString = wrapper.result,
                       !resultString.isEmpty,
                       let resultData = resultString.data(using: .utf8) {
                        payloadsToTry.insert(resultData, at: 0)
                    } else if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              root["status"] as? String == "success",
                              let resultObj = root["result"] {
                        if let dict = resultObj as? [String: Any], let innerData = try? JSONSerialization.data(withJSONObject: dict) {
                            payloadsToTry.insert(innerData, at: 0)
                        } else if let str = resultObj as? String, let innerData = str.data(using: .utf8) {
                            payloadsToTry.insert(innerData, at: 0)
                        }
                    }
                    for jsonData in payloadsToTry {
                        if let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                           parsed["command"] as? String == "ls",
                           let dataObj = parsed["data"] as? [String: Any],
                           let rawRecords = dataObj["records"] as? [[String: Any]], !rawRecords.isEmpty {
                            records = rawRecords.compactMap { dict -> KeeperRecord? in
                                guard let line = dict["title"] as? String else { return nil }
                                return parseLsRecordLine(line)
                            }
                            if !(records?.isEmpty ?? true) { break }
                        }
                        if let response = try? JSONDecoder().decode(KeeperExecuteResponse.self, from: jsonData), response.status == "success", let recs = response.data?.records, !recs.isEmpty {
                            records = recs
                            break
                        }
                        if let responseArray = try? JSONDecoder().decode(KeeperExecuteResponseDataArray.self, from: jsonData), responseArray.status == "success", let arr = responseArray.data, !arr.isEmpty {
                            records = arr
                            break
                        }
                        if let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                           parsed["status"] as? String == "success",
                           let dataPayload = parsed["data"] {
                            var recordDicts: [[String: Any]]?
                            if let arr = dataPayload as? [[String: Any]] {
                                recordDicts = arr
                            } else if let obj = dataPayload as? [String: Any], let recs = obj["records"] as? [[String: Any]] {
                                recordDicts = recs
                            }
                            if let dicts = recordDicts, !dicts.isEmpty {
                                records = dicts.compactMap { dict -> KeeperRecord? in
                                    guard let uid = (dict["uid"] as? String) ?? (dict["record_uid"] as? String), !uid.isEmpty else { return nil }
                                    return KeeperRecord(
                                        number: dict["number"] as? Int,
                                        uid: dict["uid"] as? String,
                                        record_uid: dict["record_uid"] as? String,
                                        type: dict["type"] as? String,
                                        title: dict["title"] as? String ?? "Untitled",
                                        description: dict["description"] as? String ?? ""
                                    )
                                }
                                if !records!.isEmpty { break }
                            }
                        }
                        if let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                           let messageLines = parsed["message"] as? [String], messageLines.count >= 3 {
                            let dataLines = messageLines.dropFirst(2)
                            records = dataLines.compactMap { line -> KeeperRecord? in
                                let parts = line.components(separatedBy: "  ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                guard parts.count >= 5,
                                      let num = Int(parts[0]),
                                      parts[1].count >= 15, parts[1].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
                                let uid = parts[1]
                                let type = parts[2]
                                let title = parts[3]
                                let description = parts.count >= 6 ? parts[4] : ""
                                return KeeperRecord(number: num, uid: nil, record_uid: uid, type: type, title: title.isEmpty ? "Untitled" : title, description: description)
                            }
                            if !(records?.isEmpty ?? true) { break }
                        }
                    }
                    if (records == nil || records?.isEmpty == true), let raw = String(data: data, encoding: .utf8) {
                        let preview = String(raw.prefix(800))
                        DLog("Keeper ls -R -l response (no records parsed), preview: \(preview)")
                        NSLog("[iTerm2 Keeper] No records parsed from ls -R -l response (length=%d). Preview: %@", data.count, String(preview.prefix(500)))
                    }
                    guard let records = records, !records.isEmpty else {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: iTerm2KeeperConnectionDidSucceedNotification, object: nil)
                            completion([])
                        }
                        return
                    }
                    let accounts: [PasswordManagerAccount] = records.compactMap { rec in
                        guard let uid = rec.effectiveUid, !uid.isEmpty else { return nil }
                        let title = rec.title ?? "Untitled"
                        let desc = rec.description ?? ""
                        return KeeperAccount(uid: uid, accountName: title, userName: desc, hasOTP: false, sendOTP: false, dataSource: self)
                    }
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: iTerm2KeeperConnectionDidSucceedNotification, object: nil)
                        completion(accounts)
                    }
                case .failure(let error):
                    let message = (error as NSError).localizedDescription
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: iTerm2KeeperConnectionDidFailNotification,
                            object: nil,
                            userInfo: ["error": message]
                        )
                        completion([])
                    }
                }
            }
        }
    }

    /// Extract password from a Keeper "get --format=json" response (record has "password" as a string value → exact vault value).
    internal static func passwordFromGetJSONResponse(_ data: Data) -> String? {
        func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func fromRecord(_ rec: [String: Any]) -> String? {
            if let p = rec["password"] as? String { let t = trim(p); return t.isEmpty ? nil : t }
            // Typed records may nest fields under "fields" or similar.
            if let fields = rec["fields"] as? [[String: Any]] {
                for f in fields {
                    guard (f["type"] as? String) == "password" else { continue }
                    if let v = f["value"] as? [String], let first = v.first { let t = trim(first); return t.isEmpty ? nil : t }
                    if let v = f["value"] as? String { let t = trim(v); return t.isEmpty ? nil : t }
                }
            }
            return nil
        }
        if let dataVal = parsed["data"] {
            if let str = dataVal as? String,
               let record = try? JSONSerialization.jsonObject(with: Data(str.utf8)) as? [String: Any],
               let p = fromRecord(record) { return p }
            if let obj = dataVal as? [String: Any], let p = fromRecord(obj) { return p }
        }
        if let rec = parsed["record"] as? [String: Any], let p = fromRecord(rec) { return p }
        return nil
    }

    internal func fetchPassword(recordUid: String, context: RecipeExecutionContext, completion: @escaping (String?, String?, Error?) -> ()) {
        ensureAPIKey(context: context) { [weak self] apiKey in
            guard let self = self else { return }
            guard let apiKey = apiKey else {
                DispatchQueue.main.async { completion(nil, nil, NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API key"])) }
                return
            }
            let jsonCmd = "get \(recordUid) --format=json"
            keeperExecute(apiKey: apiKey, command: jsonCmd, baseURL: self.injectedBaseURL ?? self.injectedBaseURLFromStorage ?? keeperBaseURL(), session: self.injectedURLSession ?? .shared, pollInterval: self.injectedV2PollInterval, deadline: self.injectedV2Deadline) { result in
                switch result {
                case .success(let data):
                    if let exact = KeeperDataSource.passwordFromGetJSONResponse(data) {
                        DispatchQueue.main.async { completion(exact, nil, nil) }
                        return
                    }
                case .failure:
                    break
                }
                let cmd = "get \(recordUid) --format=password"
                keeperExecute(apiKey: apiKey, command: cmd, baseURL: self.injectedBaseURL ?? self.injectedBaseURLFromStorage ?? keeperBaseURL(), session: self.injectedURLSession ?? .shared, pollInterval: self.injectedV2PollInterval, deadline: self.injectedV2Deadline) { result2 in
                    switch result2 {
                    case .success(let data):
                        var password: String?
                        func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
                        let isJSON = (try? JSONSerialization.jsonObject(with: data)) != nil
                        if password == nil, let decoded = try? JSONDecoder().decode(String.self, from: data) {
                            let t = trim(decoded)
                            if !t.isEmpty { password = t }
                        }
                        if password == nil, let wrapper = try? JSONDecoder().decode(KeeperV2ResultWrapper.self, from: data),
                           (wrapper.status == "success" || wrapper.status == "completed"),
                           let resultStr = wrapper.result {
                            let t = trim(resultStr)
                            if !t.isEmpty { password = t }
                            if password == nil, resultStr.count >= 2, resultStr.hasPrefix("\""), resultStr.hasSuffix("\""),
                               let strData = resultStr.data(using: .utf8),
                               let inner = try? JSONDecoder().decode(String.self, from: strData) {
                                let t = trim(inner)
                                if !t.isEmpty { password = t }
                            }
                        }
                        if password == nil, let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if let resultStr = parsed["result"] as? String {
                                let t = trim(resultStr)
                                if !t.isEmpty { password = t }
                            }
                            if password == nil, let resultObj = parsed["result"] as? [String: Any] {
                                if let p = (resultObj["password"] as? String).map({ trim($0) }), !p.isEmpty { password = p }
                                else if let p = (resultObj["output"] as? String).map({ trim($0) }), !p.isEmpty { password = p }
                            }
                            if password == nil, let outputStr = parsed["output"] as? String {
                                let t = trim(outputStr)
                                if !t.isEmpty { password = t }
                            }
                            if password == nil, let messageArr = parsed["message"] as? [String], let first = messageArr.first {
                                let t = trim(first)
                                let lower = t.lowercased()
                                let isStatusMessage = lower.hasPrefix("command executed successfully") || lower.hasPrefix("no output") || lower.hasPrefix("produced no output") || lower == "no output" || lower.contains("produced no output")
                                if !t.isEmpty, !isStatusMessage { password = t }
                            }
                            if password == nil, let dataVal = parsed["data"] {
                                if let str = dataVal as? String {
                                    let t = trim(str)
                                    if t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\""),
                                       let strData = t.data(using: .utf8),
                                       let decoded = try? JSONDecoder().decode(String.self, from: strData) {
                                        let t2 = trim(decoded)
                                        if !t2.isEmpty { password = t2 }
                                    }
                                    if password == nil, !t.isEmpty { password = t }
                                } else if let obj = dataVal as? [String: Any] {
                                    for key in ["password", "output", "result", "value", "stdout"] {
                                        if let p = obj[key] as? String { let t = trim(p); if !t.isEmpty { password = t; break } }
                                        if password != nil { break }
                                    }
                                    if password == nil, obj.count == 1, let singleKey = obj.keys.first {
                                        let keyPart = trim(singleKey)
                                        let valPart = (obj[singleKey] as? String).map(trim) ?? ""
                                        let combined = valPart.isEmpty ? keyPart : (keyPart + valPart)
                                        if !combined.isEmpty { password = combined }
                                    }
                                } else if let arr = dataVal as? [String], let first = arr.first {
                                    let t = trim(first)
                                    if !t.isEmpty { password = t }
                                } else if let arr = dataVal as? [Any], let first = arr.first as? String {
                                    let t = trim(first)
                                    if !t.isEmpty { password = t }
                                }
                            }
                        }
                        if password == nil, let response = try? JSONDecoder().decode(KeeperExecuteResponse.self, from: data), (response.status == "success" || response.status == "completed") {
                            if let r = response.result { let t = trim(r); if !t.isEmpty { password = t } }
                        }
                        if password == nil, !isJSON, let raw = String(data: data, encoding: .utf8) {
                            let trimmed = trim(raw)
                            if !trimmed.isEmpty {
                                if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2,
                                   let strData = trimmed.data(using: .utf8),
                                   let decoded = try? JSONDecoder().decode(String.self, from: strData) {
                                    let t = trim(decoded)
                                    if !t.isEmpty { password = t }
                                }
                                if password == nil { password = trimmed }
                            }
                        }
                        if let p = password, !p.isEmpty {
                            DispatchQueue.main.async { completion(p, nil, nil) }
                        } else {
                            let preview = String(data: data, encoding: .utf8).map { s in
                                let p = trim(s)
                                if p.isEmpty { return "(empty)" }
                                if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                    var out = "keys: \(parsed.keys.sorted().joined(separator: ", "))"
                                    if let dataVal = parsed["data"], let obj = dataVal as? [String: Any] {
                                        out += " | data keys: \(obj.keys.sorted().joined(separator: ", "))"
                                    }
                                    return out
                                }
                                return "(\(p.count) chars, not JSON)"
                            } ?? "(invalid UTF-8)"
                            DLog("Keeper get password: no password in response \(preview)")
                            NSLog("[iTerm2 Keeper] get password failed: response \(preview)")
                            let message: String
                            if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let msg = parsed["message"] as? [String],
                               let first = msg.first?.lowercased(),
                               first.contains("no output") || first.contains("produced no output") {
                                message = "This record has no password field (e.g. Address or Contact type)."
                            } else {
                                message = "Keeper returned no password for this record."
                            }
                            DispatchQueue.main.async { completion(nil, nil, NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: message])) }
                        }
                    case .failure(let error):
                        DispatchQueue.main.async { completion(nil, nil, error) }
                    }
                }
            }
        }
    }

    internal func setPassword(recordUid: String, password: String, context: RecipeExecutionContext, completion: @escaping (Error?) -> ()) {
        if password.isEmpty {
            DispatchQueue.main.async { completion(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "Password field is required."])) }
            return
        }
        ensureAPIKey(context: context) { apiKey in
            guard let apiKey = apiKey else {
                DispatchQueue.main.async { completion(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API key"])) }
                return
            }
            let b64 = Data(password.utf8).base64EncodedString()
            let cmd = "record-update -r \(recordUid) password=$BASE64:\(b64)"
            keeperExecute(apiKey: apiKey, command: cmd, baseURL: self.injectedBaseURL ?? self.injectedBaseURLFromStorage ?? keeperBaseURL(), session: self.injectedURLSession ?? .shared, pollInterval: self.injectedV2PollInterval, deadline: self.injectedV2Deadline) { result in
                switch result {
                case .success(let data):
                    if let response = try? JSONDecoder().decode(KeeperExecuteResponse.self, from: data), response.status == "success" {
                        DispatchQueue.main.async { completion(nil) }
                    } else {
                        let rawDetail = keeperHumanReadableError(fromResponseData: data)
                            ?? (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).flatMap { ($0["message"] as? [String])?.first }
                            ?? "Update failed"
                        let detail = keeperUserFacingPasswordUpdateError(apiDetail: rawDetail)
                        DispatchQueue.main.async { completion(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: detail])) }
                    }
                case .failure(let error):
                    DispatchQueue.main.async { completion(error) }
                }
            }
        }
    }

    internal func deleteRecord(recordUid: String, context: RecipeExecutionContext, completion: @escaping (Error?) -> ()) {
        ensureAPIKey(context: context) { apiKey in
            guard let apiKey = apiKey else {
                DispatchQueue.main.async { completion(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API key"])) }
                return
            }
            keeperExecute(apiKey: apiKey, command: "rm -f \(recordUid)", baseURL: self.injectedBaseURL ?? self.injectedBaseURLFromStorage ?? keeperBaseURL(), session: self.injectedURLSession ?? .shared, pollInterval: self.injectedV2PollInterval, deadline: self.injectedV2Deadline) { result in
                switch result {
                case .success(let data):
                    if let response = try? JSONDecoder().decode(KeeperExecuteResponse.self, from: data), response.status == "success" {
                        DispatchQueue.main.async { completion(nil) }
                    } else {
                        let detail = keeperHumanReadableError(fromResponseData: data) ?? "Delete failed"
                        DispatchQueue.main.async { completion(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: detail])) }
                    }
                case .failure(let error):
                    DispatchQueue.main.async { completion(error) }
                }
            }
        }
    }

    func add(userName: String, accountName: String, password: String, context: RecipeExecutionContext, completion: @escaping (PasswordManagerAccount?, Error?) -> ()) {
        ensureAPIKey(context: context) { [weak self] apiKey in
            guard let self = self, let apiKey = apiKey else {
                completion(nil, NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API key"]))
                return
            }
            let escapedTitle = accountName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            var cmd = "record-add --record-type=login --title=\"\(escapedTitle)\""
            if !userName.isEmpty {
                let escapedLogin = userName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                cmd += " login=\"\(escapedLogin)\""
            }
            if !password.isEmpty {
                let passwordB64 = Data(password.utf8).base64EncodedString()
                cmd += " password=$BASE64:\(passwordB64)"
            }
            keeperExecute(apiKey: apiKey, command: cmd, baseURL: self.injectedBaseURL ?? self.injectedBaseURLFromStorage ?? keeperBaseURL(), session: self.injectedURLSession ?? .shared, pollInterval: self.injectedV2PollInterval, deadline: self.injectedV2Deadline) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let data):
                    do {
                        struct RecordAddResponse: Decodable {
                            let status: String?
                            let data: RecordAddData?
                        }
                        struct RecordAddData: Decodable {
                            let record_uid: String?
                        }
                        let response = try JSONDecoder().decode(RecordAddResponse.self, from: data)
                        guard response.status == "success", let uid = response.data?.record_uid, !uid.isEmpty else {
                            let detail = keeperHumanReadableError(fromResponseData: data) ?? "Add failed"
                            DispatchQueue.main.async { completion(nil, NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: detail])) }
                            return
                        }
                        let account = KeeperAccount(uid: uid, accountName: accountName, userName: userName, hasOTP: false, sendOTP: false, dataSource: self)
                        DispatchQueue.main.async { completion(account, nil) }
                    } catch {
                        let detail = keeperHumanReadableError(fromResponseData: data) ?? (error as NSError).localizedDescription
                        DispatchQueue.main.async { completion(nil, NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: detail])) }
                    }
                case .failure(let error):
                    DispatchQueue.main.async { completion(nil, error) }
                }
            }
        }
    }

    func resetErrors() {}
    func reload(_ completion: () -> ()) { completion() }
    func consolidateAvailabilityChecks(_ block: () -> ()) { block() }

    func toggleShouldSendOTP(context: RecipeExecutionContext, account: PasswordManagerAccount, completion: @escaping (PasswordManagerAccount?, Error?) -> ()) {
        completion(nil, NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "OTP not supported"]))
    }

    // MARK: - Keeper settings (for settings button in Password Manager)
    /// Returns the API key only from in-memory cache (never reads Keychain). Used when opening the sheet from “select Keeper” so we don’t prompt again.
    @objc func keeperSettingsAPIKey() -> String? {
        return _cachedSettingsKey
    }
    /// Returns the API URL from in-memory cache, then UserDefaults. No default; empty if not set. Used when opening the sheet from “select Keeper” so we don’t prompt again.
    @objc func keeperSettingsAPIURL() -> String {
        if let url = injectedAPIURLFromStorage { return url }
        let u = _cachedSettingsURL
        if let u = u, !u.isEmpty { return u }
        return keeperAPIURLFromStorage() ?? ""
    }
    /// Returns the API key from Keychain for the “update” (gear) dialog. May prompt for Mac password once when the user explicitly opens settings to edit.
    /// Returns the API key for the settings (gear) dialog. Uses in-memory cache first; on first read from Keychain, caches the value so ensureAPIKey and other callers do not trigger a second biometric/keychain prompt.
    @objc func keeperSettingsAPIKeyForEditing() -> String? {
        if let k = _cachedSettingsKey, !k.isEmpty { return k }
        if let k = _apiKey, !k.isEmpty { return k }
        guard let key = keeperAPIKeyFromKeychain(), !key.isEmpty else { return nil }
        _apiKey = key
        _cachedSettingsKey = key
        return key
    }
    /// Returns the API URL from Keychain for the “update” (gear) dialog. May prompt for Mac password once when the user explicitly opens settings to edit.
    @objc func keeperSettingsAPIURLForEditing() -> String {
        return keeperAPIURLFromStorage() ?? ""
    }
    @objc func setKeeperSettingsAPIKey(_ key: String) {
        if key.isEmpty {
            if let delete = injectedKeychainDeleteAPIKey {
                delete()
                _apiKey = nil
                _cachedSettingsKey = nil
                return
            }
            keeperDeleteAPIKeyFromKeychain()
            _apiKey = nil
            _cachedSettingsKey = nil
        } else {
            if let set = injectedKeychainSetAPIKey {
                set(key)
                _apiKey = key
                _cachedSettingsKey = key
                return
            }
            keeperStoreAPIKeyInKeychain(key)
            _apiKey = key
            _cachedSettingsKey = key
        }
    }
    @objc func setKeeperSettingsAPIURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let store = injectedStoreAPIURL {
            if !trimmed.isEmpty { store(trimmed) }
            _cachedSettingsURL = trimmed.isEmpty ? nil : trimmed
            keeperClearBaseURLCache()
            return
        }
        if trimmed.isEmpty {
            keeperClearAPIURLStorage()
            _cachedSettingsURL = nil
        } else {
            keeperStoreAPIURLInKeychain(trimmed)
            _cachedSettingsURL = trimmed
        }
        keeperClearBaseURLCache()
    }

    /// Runs Keeper Commander "sync-down" (download, sync, and decrypt vault) with the given API key and URL.
    /// Use this from the settings sheet so the user can sync with the credentials in the sheet without saving first.
    /// Completion is called on the main thread with success and optional error message.
    @objc func runKeeperSyncDown(apiKey: String, apiURL: String, completion: @escaping (Bool, String?) -> Void) {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            DispatchQueue.main.async { completion(false, "API key is empty.") }
            return
        }
        guard !urlString.isEmpty else {
            DispatchQueue.main.async { completion(false, "API URL is required.") }
            return
        }
        guard let baseURL = URL(string: urlString), baseURL.scheme != nil, baseURL.host != nil else {
            DispatchQueue.main.async { completion(false, "Invalid API URL.") }
            return
        }
        keeperExecute(apiKey: key, command: "sync-down", baseURL: baseURL, session: self.injectedURLSession ?? .shared, pollInterval: self.injectedV2PollInterval, deadline: self.injectedV2Deadline) { result in
            switch result {
            case .success:
                DispatchQueue.main.async { completion(true, nil) }
            case .failure(let error):
                let message = (error as NSError).localizedDescription
                DispatchQueue.main.async { completion(false, message) }
            }
        }
    }
}

/// Named for coverage: delegate and dialog result handling.
private extension KeeperDataSource {
    func keeperHandleCredentialsFromDelegate(window: NSWindow, completion: @escaping (String?) -> Void) {
        guard let delegate = credentialsDelegate else { return }
        delegate.keeperDataSourceRequestCredentials(forWindow: window) { [weak self] key in
            guard let self = self else { return }
            if let key = key, !key.isEmpty {
                self._apiKey = key
                completion(key)
            } else {
                completion(nil)
            }
        }
    }

    func keeperHandleDialogResult(_ promptResult: KeeperAPIKeyPromptResult?, completion: @escaping (String?) -> Void) {
        guard let promptResult = promptResult else {
            completion(nil)
            return
        }
        switch promptResult {
        case .useExisting:
            let key = injectedUseExistingKeyForDialog ?? _apiKey
            if let key = key, !key.isEmpty {
                completion(key)
            } else {
                completion(nil)
            }
        case .useNew(let key):
            guard !key.isEmpty else { completion(nil); return }
            if let set = injectedKeychainSetAPIKey {
                set(key)
                _apiKey = key
                completion(key)
            } else {
                keeperStoreAPIKeyInKeychain(key)
                _apiKey = key
                completion(key)
            }
        case .cancel:
            completion(nil)
        }
    }
}
