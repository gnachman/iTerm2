//
//  KeeperDataSource.swift
//  iTerm2SharedARC
//
//  Keeper Security integration via Keeper Commander service mode.
//  Communicates with local Keeper Commander service (e.g. service-create -p 8900 -f json -aip 127.0.0.1).
//

import Foundation
import AppKit

private let keeperKeychainService = "iTerm2-Keeper"
private let keeperKeychainAccountAPIKey = "api-key"
private let keeperKeychainAccountAPIURL = "api-url"
/// Default Keeper Commander service URL when none is stored.
private let keeperDefaultAPIURL = "http://127.0.0.1:8900"

/// Posted when Keeper connection fails (e.g. no API key, service unreachable). userInfo[@"error"] = error message (String).
public let iTerm2KeeperConnectionDidFailNotification = Notification.Name("iTerm2KeeperConnectionDidFail")
/// Posted when Keeper fetch succeeds after a connection attempt.
public let iTerm2KeeperConnectionDidSucceedNotification = Notification.Name("iTerm2KeeperConnectionDidSucceed")

// MARK: - API Key storage (macOS Keychain)

private func keeperAPIKeyFromKeychain() -> String? {
    try? SSKeychain.password(forService: keeperKeychainService, account: keeperKeychainAccountAPIKey)
}

private func keeperStoreAPIKeyInKeychain(_ key: String) {
    _ = try? SSKeychain.setPassword(key, forService: keeperKeychainService, account: keeperKeychainAccountAPIKey)
}

private func keeperDeleteAPIKeyFromKeychain() {
    try? SSKeychain.deletePassword(forService: keeperKeychainService, account: keeperKeychainAccountAPIKey)
}

// MARK: - API URL storage (macOS Keychain)

private func keeperAPIURLFromKeychain() -> String? {
    try? SSKeychain.password(forService: keeperKeychainService, account: keeperKeychainAccountAPIURL)
}

private func keeperStoreAPIURLInKeychain(_ url: String) {
    _ = try? SSKeychain.setPassword(url, forService: keeperKeychainService, account: keeperKeychainAccountAPIURL)
}

// MARK: - API key prompt (with optional existing key)

enum KeeperAPIKeyPromptResult {
    case useExisting
    case useNew(String)
    case cancel
}

/// Shows API key dialog. If existingKey is non-nil, shows "Use existing" / "Update" / "Cancel". Otherwise "OK" / "Cancel".
/// Completion is called on the main thread when the user dismisses the dialog. Must be called from the main thread.
func keeperShowAPIKeyDialog(existingKey: String?, window: NSWindow?, completion: @escaping (KeeperAPIKeyPromptResult?) -> Void) {
    dispatchPrecondition(condition: .onQueue(.main))
    let alert = NSAlert()
    alert.messageText = "Keeper Security API Key"
    if let existing = existingKey, !existing.isEmpty {
        alert.informativeText = "An API key is already stored. To update it, enter a new key below and choose Update. To continue with the stored key, choose Use Existing."
        alert.addButton(withTitle: "Use Existing")
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")
    } else {
        alert.informativeText = "Enter your Keeper Commander API key. The key is stored in macOS Keychain. If you have stored a key before, enter or paste it again to use or update it."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
    }
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
    field.placeholderString = (existingKey?.isEmpty ?? true) ? "Enter Keeper Commander service API key" : "API Key"
    field.stringValue = existingKey ?? ""
    alert.accessoryView = field
    let sheetWindow = window ?? NSApp.keyWindow ?? NSApp.mainWindow
    if let window = sheetWindow, window.isVisible {
        alert.beginSheetModal(for: window) { response in
            let result: KeeperAPIKeyPromptResult?
            if response == .alertFirstButtonReturn {
                if existingKey != nil, !(existingKey?.isEmpty ?? true) {
                    result = .useExisting
                } else {
                    result = .useNew(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } else if response == .alertSecondButtonReturn, existingKey != nil, !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result = .useNew(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                result = .cancel
            }
            completion(result)
        }
    } else {
        let response = alert.runModal()
        let result: KeeperAPIKeyPromptResult?
        if response == .alertFirstButtonReturn {
            if existingKey != nil, !(existingKey?.isEmpty ?? true) {
                result = .useExisting
            } else {
                result = .useNew(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } else if response == .alertSecondButtonReturn, existingKey != nil, !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result = .useNew(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            result = .cancel
        }
        completion(result)
    }
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

private struct KeeperRecord: Decodable {
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

/// Clear the cached base URL so the next API call reads from Keychain again (e.g. after user updates URL in settings).
private func keeperClearBaseURLCache() {
    _keeperBaseURLLock.lock()
    _cachedKeeperBaseURL = nil
    _keeperBaseURLLock.unlock()
}

private func keeperBaseURL() -> URL {
    _keeperBaseURLLock.lock()
    if let cached = _cachedKeeperBaseURL {
        let url = cached
        _keeperBaseURLLock.unlock()
        return url
    }
    let urlString = keeperAPIURLFromKeychain() ?? keeperDefaultAPIURL
    let parsed: URL
    if let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil, url.host != nil {
        parsed = url
    } else {
        parsed = URL(string: keeperDefaultAPIURL)!
    }
    _cachedKeeperBaseURL = parsed
    _keeperBaseURLLock.unlock()
    return parsed
}

private func keeperV1ExecuteCommandURL(baseURL: URL? = nil) -> URL {
    (baseURL ?? keeperBaseURL()).appendingPathComponent("api/v1/executecommand")
}

private func keeperV2AsyncURL(baseURL: URL? = nil) -> URL {
    (baseURL ?? keeperBaseURL()).appendingPathComponent("api/v2/executecommand-async")
}

private func keeperV2StatusURL(requestId: String, baseURL: URL? = nil) -> URL {
    (baseURL ?? keeperBaseURL()).appendingPathComponent("api/v2/status/\(requestId)")
}

private func keeperV2ResultURL(requestId: String, baseURL: URL? = nil) -> URL {
    (baseURL ?? keeperBaseURL()).appendingPathComponent("api/v2/result/\(requestId)")
}

/// Extracts a human-readable error message from API response data (e.g. {"error":"Please provide a valid api key","status":"error"}).
private func keeperHumanReadableError(fromResponseData data: Data?) -> String? {
    guard let data = data,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    if let error = json["error"] as? String, !error.isEmpty { return error }
    if let message = json["message"] as? String, !message.isEmpty { return message }
    return nil
}

private func keeperExecute(apiKey: String, command: String, baseURL: URL? = nil, completion: @escaping (Result<Data, Error>) -> Void) {
    let body = (try? JSONEncoder().encode(KeeperExecuteRequest(command: command))) ?? Data()
    // Try API v1 (sync) first; if 404, use API v2 (queue) async.
    let v1Completion: (Result<Data, Error>) -> Void = { result in
        switch result {
        case .success(let data):
            completion(.success(data))
        case .failure(let err):
            let nsErr = err as NSError
            if nsErr.domain == "KeeperDataSource", nsErr.code == 404 {
                keeperExecuteV2(apiKey: apiKey, command: command, baseURL: baseURL, completion: completion)
            } else {
                completion(.failure(err))
            }
        }
    }

    var request = URLRequest(url: keeperV1ExecuteCommandURL(baseURL: baseURL))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "api-key")
    request.httpBody = body
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            v1Completion(.failure(error))
            return
        }
        guard let data = data else {
            v1Completion(.failure(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
            return
        }
        let http = response as? HTTPURLResponse
        if http?.statusCode == 404 {
            keeperExecuteV2(apiKey: apiKey, command: command, baseURL: baseURL, completion: completion)
            return
        }
        if http?.statusCode != 200 {
            let msg = keeperHumanReadableError(fromResponseData: data)
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(http?.statusCode ?? -1)"
            v1Completion(.failure(NSError(domain: "KeeperDataSource", code: http?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: msg])))
            return
        }
        v1Completion(.success(data))
    }.resume()
}

/// Keeper Commander API v2 (queue): submit async, poll status, then fetch result.
private func keeperExecuteV2(apiKey: String, command: String, baseURL: URL? = nil, completion: @escaping (Result<Data, Error>) -> Void) {
    let body = (try? JSONEncoder().encode(KeeperExecuteRequest(command: command))) ?? Data()
    var request = URLRequest(url: keeperV2AsyncURL(baseURL: baseURL))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "api-key")
    request.httpBody = body
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            completion(.failure(error))
            return
        }
        guard let data = data else {
            completion(.failure(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
            return
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 202 else {
            let msg = keeperHumanReadableError(fromResponseData: data)
                ?? String(data: data, encoding: .utf8)
                ?? "Unexpected response"
            completion(.failure(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])))
            return
        }
        guard let queued = try? JSONDecoder().decode(KeeperV2QueuedResponse.self, from: data),
              let requestId = queued.request_id, !requestId.isEmpty else {
            completion(.failure(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "No request_id in v2 response"])))
            return
        }
        keeperV2PollForResult(apiKey: apiKey, requestId: requestId, baseURL: baseURL, completion: completion)
    }.resume()
}

private func keeperV2PollForResult(apiKey: String, requestId: String, baseURL: URL? = nil, completion: @escaping (Result<Data, Error>) -> Void) {
    // Poll at most once per 2 seconds to stay under service rate limit (60 status requests per minute).
    let pollInterval: TimeInterval = 2.0
    let deadline = Date().addingTimeInterval(120)
    let maxPolls = 60  // 120s at 2s interval
    var pollCount = 0
    var consecutiveUnparseable = 0
    func poll() {
        pollCount += 1
        if Date() > deadline {
            completion(.failure(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "Keeper service v2 request timed out"])))
            return
        }
        if pollCount > maxPolls {
            completion(.failure(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "Keeper service did not complete the request in time"])))
            return
        }
        var request = URLRequest(url: keeperV2StatusURL(requestId: requestId, baseURL: baseURL))
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            let http = response as? HTTPURLResponse
            let responseData = data
            // If status endpoint returned an HTTP error (e.g. 429 rate limit), surface that message immediately.
            if let code = http?.statusCode, code != 200 {
                let msg = keeperHumanReadableError(fromResponseData: responseData)
                    ?? String(data: responseData ?? Data(), encoding: .utf8)
                    ?? "HTTP \(code)"
                completion(.failure(NSError(domain: "KeeperDataSource", code: code, userInfo: [NSLocalizedDescriptionKey: msg])))
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
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + pollInterval) { poll() }
                return
            }
            consecutiveUnparseable = 0
            switch status {
            case "completed":
                keeperV2FetchResult(apiKey: apiKey, requestId: requestId, baseURL: baseURL, completion: completion)
            case "failed", "expired":
                completion(.failure(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "Keeper command \(status)"])))
            default:
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + pollInterval) { poll() }
            }
        }.resume()
    }
    poll()
}

private func keeperV2FetchResult(apiKey: String, requestId: String, baseURL: URL? = nil, completion: @escaping (Result<Data, Error>) -> Void) {
    var request = URLRequest(url: keeperV2ResultURL(requestId: requestId, baseURL: baseURL))
    request.setValue(apiKey, forHTTPHeaderField: "api-key")
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            completion(.failure(error))
            return
        }
        guard let data = data else {
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
    }.resume()
}

/// Parses a Keeper "list" or "trash list" response and returns record UIDs from the message table.
private func parseMessageTableRecordUids(from data: Data) -> Set<String> {
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
    private let browser: Bool
    private let _apiKeyLoadLock = NSLock()
    private var _apiKey: String?
    /// In-memory only: used to pre-fill the settings sheet. Never read from Keychain for the sheet so we don't trigger a second Mac password prompt after PM authentication.
    private var _cachedSettingsKey: String?
    private var _cachedSettingsURL: String?

    @objc public weak var credentialsDelegate: KeeperCredentialsRequestDelegate?

    init(browser: Bool) {
        self.browser = browser
    }

    /// True if we already have an API key in memory (from this session). Used when switching back to Keeper so we don’t show the settings sheet again.
    @objc func keeperHasAPIKeyInMemory() -> Bool {
        if let k = _apiKey, !k.isEmpty { return true }
        if let k = _cachedSettingsKey, !k.isEmpty { return true }
        return false
    }

    private func ensureAPIKey(context: RecipeExecutionContext, completion: @escaping (String?) -> Void) {
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
        if let key = _cachedSettingsKey, !key.isEmpty {
            _apiKey = key
            let k = key
            _apiKeyLoadLock.unlock()
            completion(k)
            return
        }
        if let key = keeperAPIKeyFromKeychain(), !key.isEmpty {
            _apiKey = key
            _cachedSettingsKey = key
            let k = key
            _apiKeyLoadLock.unlock()
            completion(k)
            return
        }
        _apiKeyLoadLock.unlock()
        // No key in Keychain; show the settings sheet.
        func showUIAndContinue() {
            if let delegate = credentialsDelegate, let window = context.window {
                delegate.keeperDataSourceRequestCredentials(forWindow: window) { [weak self] key in
                    guard let self = self else { return }
                    if let key = key, !key.isEmpty {
                        self._apiKey = key
                        completion(key)
                    } else {
                        completion(nil)
                    }
                }
                return
            }
            keeperShowAPIKeyDialog(existingKey: nil, window: context.window) { promptResult in
                guard let promptResult = promptResult else {
                    completion(nil)
                    return
                }
                switch promptResult {
                case .useExisting:
                    if let key = self._apiKey, !key.isEmpty {
                        completion(key)
                    } else {
                        completion(nil)
                    }
                case .useNew(let key):
                    guard !key.isEmpty else { completion(nil); return }
                    keeperStoreAPIKeyInKeychain(key)
                    self._apiKey = key
                    completion(key)
                case .cancel:
                    completion(nil)
                }
            }
        }
        if Thread.isMainThread {
            showUIAndContinue()
        } else {
            DispatchQueue.main.async { showUIAndContinue() }
        }
    }

    @objc var name: String { "Keeper Security" }
    @objc var canResetConfiguration: Bool { true }
    @objc func resetConfiguration() {
        keeperDeleteAPIKeyFromKeychain()
        _apiKey = nil
        _cachedSettingsKey = nil
        _cachedSettingsURL = nil
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
                }
                completion([])
                return
            }
            keeperExecute(apiKey: apiKey, command: "list") { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let data):
                // Log raw response for debugging (visible in Xcode console and Console.app when filtering iTerm2).
                if let raw = String(data: data, encoding: .utf8) {
                    let preview = String(raw.prefix(1500))
                    NSLog("[iTerm2 Keeper] list response length=%d body=%@", data.count, preview)
                }
                do {
                    // v2 result endpoint returns { "status": "success", "result": "<command output as string>" }.
                    // With -f json, the command output is JSON; try parsing the inner string first.
                    // Some implementations may return "result" as a nested object.
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
                        if let response = try? JSONDecoder().decode(KeeperExecuteResponse.self, from: jsonData), response.status == "success", let recs = response.data?.records, !recs.isEmpty {
                            records = recs
                            break
                        }
                        if let responseArray = try? JSONDecoder().decode(KeeperExecuteResponseDataArray.self, from: jsonData), responseArray.status == "success", let arr = responseArray.data, !arr.isEmpty {
                            records = arr
                            break
                        }
                        // Flexible parse: accept any JSON with "data" (array or object with "records") and "status":"success".
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
                        // List command returns {"command":"list","data":null,"message":["#  Record uid  ...","---  ...","1  uid  type  title  description  True",...]}.
                        if let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                           let messageLines = parsed["message"] as? [String], messageLines.count >= 3 {
                            let dataLines = messageLines.dropFirst(2) // skip header and "---" separator
                            records = dataLines.compactMap { line -> KeeperRecord? in
                                let parts = line.components(separatedBy: "  ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                // Require at least 5 columns: number, uid, type, title, shared (description may be missing)
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
                        DLog("Keeper list response (no records parsed), preview: \(preview)")
                        NSLog("[iTerm2 Keeper] No records parsed from response (length=%d). Preview: %@", data.count, String(preview.prefix(500)))
                    }
                    guard let records = records, !records.isEmpty else {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: iTerm2KeeperConnectionDidSucceedNotification, object: nil)
                            completion([])
                        }
                        return
                    }
                    // Exclude records that are in trash (deleted).
                    keeperExecute(apiKey: apiKey, command: "trash list") { trashResult in
                        let trashUids: Set<String>
                        if case .success(let trashData) = trashResult {
                            trashUids = parseMessageTableRecordUids(from: trashData)
                        } else {
                            trashUids = []
                        }
                        let filtered = records.filter { rec in
                            guard let uid = rec.effectiveUid else { return true }
                            return !trashUids.contains(uid)
                        }
                        let accounts: [PasswordManagerAccount] = filtered.compactMap { rec in
                            guard let uid = rec.effectiveUid, !uid.isEmpty else { return nil }
                            let title = rec.title ?? "Untitled"
                            let desc = rec.description ?? ""
                            return KeeperAccount(uid: uid, accountName: title, userName: desc, hasOTP: false, sendOTP: false, dataSource: self)
                        }
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: iTerm2KeeperConnectionDidSucceedNotification, object: nil)
                            completion(accounts)
                        }
                    }
                } catch {
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

    fileprivate func fetchPassword(recordUid: String, context: RecipeExecutionContext, completion: @escaping (String?, String?, Error?) -> ()) {
        ensureAPIKey(context: context) { [weak self] apiKey in
            guard let apiKey = apiKey else {
                DispatchQueue.main.async { completion(nil, nil, NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API key"])) }
                return
            }
            let cmd = "get \(recordUid) --format=password"
            keeperExecute(apiKey: apiKey, command: cmd) { result in
            switch result {
            case .success(let data):
                var password: String?
                func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
                let isJSON = (try? JSONSerialization.jsonObject(with: data)) != nil
                // v2 result wrapper: { "status": "success"|"completed", "result": "<password>" }
                if let wrapper = try? JSONDecoder().decode(KeeperV2ResultWrapper.self, from: data),
                   (wrapper.status == "success" || wrapper.status == "completed"),
                   let resultStr = wrapper.result {
                    let t = trim(resultStr)
                    if !t.isEmpty { password = t }
                }
                // Direct or inner response: result, message[], or data (string or object with password key)
                if password == nil, let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let resultStr = parsed["result"] as? String {
                        let t = trim(resultStr)
                        if !t.isEmpty { password = t }
                    }
                    if password == nil, let resultObj = parsed["result"] as? [String: Any] {
                        if let p = (resultObj["password"] as? String).map({ trim($0) }), !p.isEmpty { password = p }
                        else if let p = (resultObj["output"] as? String).map({ trim($0) }), !p.isEmpty { password = p }
                    }
                    if password == nil, let messageArr = parsed["message"] as? [String], let first = messageArr.first {
                        let t = trim(first)
                        // Do not use status messages as password (e.g. "Command executed successfully but produced no output")
                        let ignoredPrefixes = ["command executed successfully", "no output", "produced no output"]
                        let isStatusMessage = ignoredPrefixes.contains { t.lowercased().contains($0) }
                        if !t.isEmpty, !isStatusMessage { password = t }
                    }
                    if password == nil, let dataVal = parsed["data"] {
                        if let str = dataVal as? String {
                            let t = trim(str)
                            if !t.isEmpty { password = t }
                        } else if let obj = dataVal as? [String: Any], let p = obj["password"] as? String {
                            let t = trim(p)
                            if !t.isEmpty { password = t }
                        }
                    }
                }
                if password == nil, let response = try? JSONDecoder().decode(KeeperExecuteResponse.self, from: data), (response.status == "success" || response.status == "completed") {
                    if let r = response.result { let t = trim(r); if !t.isEmpty { password = t } }
                }
                // Plain text body only when response is NOT JSON (e.g. raw stdout from get --format=password).
                // Never use the full JSON response body as the password.
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
                            return "keys: \(parsed.keys.sorted().joined(separator: ", "))"
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

    fileprivate func setPassword(recordUid: String, password: String, context: RecipeExecutionContext, completion: @escaping (Error?) -> ()) {
        ensureAPIKey(context: context) { apiKey in
            guard let apiKey = apiKey else {
                DispatchQueue.main.async { completion(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API key"])) }
                return
            }
            let escaped = password.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let cmd = "record-update -r \(recordUid) password=\"\(escaped)\""
            keeperExecute(apiKey: apiKey, command: cmd) { result in
                switch result {
                case .success(let data):
                    if let response = try? JSONDecoder().decode(KeeperExecuteResponse.self, from: data), response.status == "success" {
                        DispatchQueue.main.async { completion(nil) }
                    } else {
                        let detail = keeperHumanReadableError(fromResponseData: data)
                            ?? (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).flatMap { ($0["message"] as? [String])?.first }
                            ?? "Update failed"
                        DispatchQueue.main.async { completion(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: detail])) }
                    }
                case .failure(let error):
                    DispatchQueue.main.async { completion(error) }
                }
            }
        }
    }

    fileprivate func deleteRecord(recordUid: String, context: RecipeExecutionContext, completion: @escaping (Error?) -> ()) {
        ensureAPIKey(context: context) { apiKey in
            guard let apiKey = apiKey else {
                DispatchQueue.main.async { completion(NSError(domain: "KeeperDataSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API key"])) }
                return
            }
            keeperExecute(apiKey: apiKey, command: "rm -f \(recordUid)") { result in
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
            let escapedLogin = userName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escapedPassword = password.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let cmd = "record-add --record-type=login --title=\"\(escapedTitle)\" login=\"\(escapedLogin)\" password=\"\(escapedPassword)\""
            keeperExecute(apiKey: apiKey, command: cmd) { [weak self] result in
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
    /// Returns the API URL from in-memory cache or the default. Used when opening the sheet from “select Keeper” so we don’t prompt again.
    @objc func keeperSettingsAPIURL() -> String {
        let u = _cachedSettingsURL
        return (u != nil && !u!.isEmpty) ? u! : keeperDefaultAPIURL
    }
    /// Returns the API key from Keychain for the “update” (gear) dialog. May prompt for Mac password once when the user explicitly opens settings to edit.
    @objc func keeperSettingsAPIKeyForEditing() -> String? {
        return keeperAPIKeyFromKeychain()
    }
    /// Returns the API URL from Keychain for the “update” (gear) dialog. May prompt for Mac password once when the user explicitly opens settings to edit.
    @objc func keeperSettingsAPIURLForEditing() -> String {
        return keeperAPIURLFromKeychain() ?? keeperDefaultAPIURL
    }
    @objc func setKeeperSettingsAPIKey(_ key: String) {
        if key.isEmpty {
            keeperDeleteAPIKeyFromKeychain()
            _apiKey = nil
            _cachedSettingsKey = nil
        } else {
            keeperStoreAPIKeyInKeychain(key)
            _apiKey = key
            _cachedSettingsKey = key
        }
    }
    @objc func setKeeperSettingsAPIURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? SSKeychain.deletePassword(forService: keeperKeychainService, account: keeperKeychainAccountAPIURL)
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
        let baseURL: URL
        if let parsed = URL(string: urlString), parsed.scheme != nil, parsed.host != nil {
            baseURL = parsed
        } else {
            baseURL = URL(string: keeperDefaultAPIURL)!
        }
        keeperExecute(apiKey: key, command: "sync-down", baseURL: baseURL) { result in
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
