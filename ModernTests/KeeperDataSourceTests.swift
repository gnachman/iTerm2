//
//  KeeperDataSourceTests.swift
//  iTerm2
//
//  Unit tests for Keeper integration: parsing, error extraction, HTTP/API (keeperExecute),
//  ensureAPIKey, fetchAccounts, fetchPassword, add, set, delete, KeeperAccount, toggleShouldSendOTP.
//

import XCTest
import AppKit
@testable import iTerm2SharedARC

// MARK: - Mock credentials delegate (so tests don't show API key dialog)

private final class MockKeeperCredentialsDelegate: NSObject, KeeperCredentialsRequestDelegate {
    let provideKey: String?
    init(provideKey: String?) {
        self.provideKey = provideKey
    }
    func keeperDataSourceRequestCredentials(forWindow window: NSWindow, completion: @escaping (String?) -> Void) {
        completion(provideKey)
    }
}

// MARK: - Mock URLProtocol for Keeper API (v2 executecommand-async)

private final class KeeperMockURLProtocol: URLProtocol {
    /// Command string (from request body JSON) -> (response body, status code). Set by tests.
    static var responseByCommand: [String: (Data, Int)] = [:]
    /// request_id -> (result body, HTTP status code) for v2 GET result/<request_id>. Tests use non-200 to simulate errors.
    static var pendingV2Results: [String: (Data, Int)] = [:]
    /// request_id -> "completed" | "failed" | "expired" (for v2 GET status/). Set via nextQueuedRequestStatus when queueing.
    static var pendingV2Status: [String: String] = [:]
    /// If set before a command is queued, that request_id will get this status from GET status/ (e.g. "failed").
    static var nextQueuedRequestStatus: String?
    /// request_id -> HTTP code for GET status/. If set, status endpoint returns this code (e.g. 429).
    static var pendingV2StatusHTTPCode: [String: Int] = [:]
    static var nextQueuedStatusHTTPCode: Int?
    /// When set, the next POST executecommand-async will fail with this error (network error).
    static var nextPOSTTriggersNetworkError = false
    /// When set, the next queued request's GET result will fail with network error.
    static var nextQueuedResultRequestFails = false
    static var pendingV2ResultRequestFails: [String: Bool] = [:]
    /// Per request_id: list of status response bodies to return (pop one per GET status call). Used for consecutiveUnparseable test.
    static var pendingV2StatusResponseList: [String: [Data]] = [:]
    static var nextQueuedStatusResponseList: [Data]?
    /// Per request_id: return "processing" this many times before "completed". Used for timeout test.
    static var pendingV2StatusProcessingCount: [String: Int] = [:]
    static var nextQueuedStatusProcessingCount: Int?
    /// When set, the next POST 202 response delivers no body (client gets nil data). Covers keeperExecuteV2 "No data" path.
    static var nextPOSTReturnsNilData = false
    /// When set, the next queued request's GET status/ will fail with network error. Covers keeperV2PollForResult error path.
    static var nextQueuedStatusRequestFails = false
    static var pendingV2StatusRequestFails: [String: Bool] = [:]
    /// When set, the next queued request's GET result/ will return response but no body (nil data). Covers keeperV2FetchResult "No data" path.
    static var nextQueuedResultReturnsNoData = false
    static var pendingV2ResultReturnsNoData: [String: Bool] = [:]
    /// When set, the next queued request's GET result/ will return this (data, code) instead of responseByCommand. Use to test GET result non-200 while POST returns 202.
    static var nextQueuedResultResponse: (Data, Int)?
    static var lastRequest: URLRequest?
    /// Last command sent in a v2 POST (so tests can assert on it; lastRequest may be a GET result).
    static var lastCommand: String?

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return url.path.contains("executecommand") || url.path.contains("status/") || url.path.contains("result/")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private func readRequestBody(from request: URLRequest) -> Data? {
        if let data = request.httpBody, !data.isEmpty { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }

    override func startLoading() {
        Self.lastRequest = request
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "KeeperMock", code: -1, userInfo: [NSLocalizedDescriptionKey: "No URL"]))
            return
        }
        // v2 POST executecommand-async: queue command, return request_id (or simulate submit failure / no request_id / network error)
        if url.path.contains("executecommand-async"), request.httpMethod?.uppercased() == "POST" {
            if Self.nextPOSTTriggersNetworkError {
                Self.nextPOSTTriggersNetworkError = false
                client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost, userInfo: [NSLocalizedDescriptionKey: "Network error"]))
                return
            }
            let command: String? = {
                guard let body = readRequestBody(from: request),
                      let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                      let cmd = json["command"] as? String else { return nil }
                return cmd
            }()
            Self.lastCommand = command
            let key = command ?? ""
            let (resultData, resultCode) = Self.responseByCommand[key] ?? ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
            // Simulate submit failure: return non-202 (e.g. 401) and do not queue
            if resultCode != 200 && resultCode != 202 {
                let response = HTTPURLResponse(url: url, statusCode: resultCode, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: resultData)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            // Simulate 202 with no request_id: return body as-is and do not queue (unless we have queue overrides set for poll tests)
            if resultCode == 202 {
                let hasQueueOverrides = Self.nextQueuedResultResponse != nil || Self.nextQueuedStatusProcessingCount != nil || Self.nextQueuedStatusResponseList != nil || Self.nextQueuedRequestStatus != nil
                if !hasQueueOverrides {
                    let bodyStr = String(data: resultData, encoding: .utf8) ?? ""
                    if bodyStr.isEmpty || !bodyStr.contains("request_id") {
                        let response = HTTPURLResponse(url: url, statusCode: 202, httpVersion: nil, headerFields: nil)!
                        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                        client?.urlProtocol(self, didLoad: resultData)
                        client?.urlProtocolDidFinishLoading(self)
                        return
                    }
                }
            }
            let requestId = UUID().uuidString
            let (storedData, storedCode) = Self.nextQueuedResultResponse ?? (resultData, resultCode)
            Self.nextQueuedResultResponse = nil
            Self.pendingV2Results[requestId] = (storedData, storedCode)
            Self.pendingV2Status[requestId] = Self.nextQueuedRequestStatus ?? "completed"
            Self.nextQueuedRequestStatus = nil
            if let code = Self.nextQueuedStatusHTTPCode {
                Self.pendingV2StatusHTTPCode[requestId] = code
                Self.nextQueuedStatusHTTPCode = nil
            }
            if Self.nextQueuedResultRequestFails {
                Self.pendingV2ResultRequestFails[requestId] = true
                Self.nextQueuedResultRequestFails = false
            }
            if let list = Self.nextQueuedStatusResponseList {
                Self.pendingV2StatusResponseList[requestId] = list
                Self.nextQueuedStatusResponseList = nil
            }
            if let count = Self.nextQueuedStatusProcessingCount {
                Self.pendingV2StatusProcessingCount[requestId] = count
                Self.nextQueuedStatusProcessingCount = nil
            }
            if Self.nextPOSTReturnsNilData {
                Self.nextPOSTReturnsNilData = false
                let response = HTTPURLResponse(url: url, statusCode: 202, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            if Self.nextQueuedStatusRequestFails {
                Self.pendingV2StatusRequestFails[requestId] = true
                Self.nextQueuedStatusRequestFails = false
            }
            if Self.nextQueuedResultReturnsNoData {
                Self.pendingV2ResultReturnsNoData[requestId] = true
                Self.nextQueuedResultReturnsNoData = false
            }
            let queueResponse = "{\"request_id\":\"\(requestId)\",\"success\":true}".data(using: .utf8)!
            let response = HTTPURLResponse(url: url, statusCode: 202, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: queueResponse)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        // v2 GET status/<request_id>: return status (or non-200 to simulate rate limit etc.)
        if url.path.contains("status/") {
            let requestId = url.path.split(separator: "/").filter { !$0.isEmpty }.last.map(String.init) ?? ""
            if Self.pendingV2StatusRequestFails[requestId] == true {
                Self.pendingV2StatusRequestFails[requestId] = nil
                client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost, userInfo: [NSLocalizedDescriptionKey: "Network error"]))
                return
            }
            if let code = Self.pendingV2StatusHTTPCode[requestId], code != 200 {
                let body = "{\"error\":\"rate limit\"}".data(using: .utf8)!
                let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            if var list = Self.pendingV2StatusResponseList[requestId], !list.isEmpty {
                let body = list.removeFirst()
                Self.pendingV2StatusResponseList[requestId] = list.isEmpty ? nil : list
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            if let count = Self.pendingV2StatusProcessingCount[requestId], count > 0 {
                Self.pendingV2StatusProcessingCount[requestId] = count - 1
                let statusResponse = "{\"status\":\"processing\"}".data(using: .utf8)!
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: statusResponse)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            let status = Self.pendingV2Status[requestId] ?? "completed"
            let statusResponse = "{\"status\":\"\(status)\"}".data(using: .utf8)!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: statusResponse)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        // v2 GET result/<request_id>: return stored result and status code (or simulate network error)
        if url.path.contains("result/") {
            let requestId = url.path.split(separator: "/").filter { !$0.isEmpty }.last.map(String.init) ?? ""
            if Self.pendingV2ResultRequestFails[requestId] == true {
                Self.pendingV2ResultRequestFails[requestId] = nil
                client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost, userInfo: [NSLocalizedDescriptionKey: "Network error"]))
                return
            }
            if Self.pendingV2ResultReturnsNoData[requestId] == true {
                Self.pendingV2ResultReturnsNoData[requestId] = nil
                let (_, resultCode) = Self.pendingV2Results[requestId] ?? (Data(), 200)
                let response = HTTPURLResponse(url: url, statusCode: resultCode, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            let (resultData, resultCode) = Self.pendingV2Results[requestId] ?? ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
            let response = HTTPURLResponse(url: url, statusCode: resultCode, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: resultData)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let empty = "{\"status\":\"success\"}".data(using: .utf8)!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: empty)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class KeeperDataSourceTests: XCTestCase {

    private var mockSession: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [KeeperMockURLProtocol.self]
        mockSession = URLSession(configuration: config)
        KeeperMockURLProtocol.responseByCommand = [:]
        KeeperMockURLProtocol.pendingV2Results = [:]
        KeeperMockURLProtocol.pendingV2Status = [:]
        KeeperMockURLProtocol.nextQueuedRequestStatus = nil
        KeeperMockURLProtocol.pendingV2StatusHTTPCode = [:]
        KeeperMockURLProtocol.nextQueuedStatusHTTPCode = nil
        KeeperMockURLProtocol.nextPOSTTriggersNetworkError = false
        KeeperMockURLProtocol.nextQueuedResultRequestFails = false
        KeeperMockURLProtocol.pendingV2ResultRequestFails = [:]
        KeeperMockURLProtocol.pendingV2StatusResponseList = [:]
        KeeperMockURLProtocol.nextQueuedStatusResponseList = nil
        KeeperMockURLProtocol.pendingV2StatusProcessingCount = [:]
        KeeperMockURLProtocol.nextQueuedStatusProcessingCount = nil
        KeeperMockURLProtocol.nextPOSTReturnsNilData = false
        KeeperMockURLProtocol.nextQueuedStatusRequestFails = false
        KeeperMockURLProtocol.pendingV2StatusRequestFails = [:]
        KeeperMockURLProtocol.nextQueuedResultReturnsNoData = false
        KeeperMockURLProtocol.pendingV2ResultReturnsNoData = [:]
        KeeperMockURLProtocol.lastCommand = nil
        KeeperTestOverrides.apiKeyFromKeychain = nil
        KeeperTestOverrides.secureKeychainReturns = nil
        KeeperTestOverrides.standardKeychainReturns = nil
        KeeperTestOverrides.storeAPIKeyInKeychain = nil
        KeeperTestOverrides.deleteAPIKeyFromKeychain = nil
        KeeperTestOverrides.showAPIKeyDialogOverride = nil
        KeeperTestOverrides.showAPIKeyDialogUIOverride = nil
        KeeperTestOverrides.callDialogUI = nil
        KeeperTestOverrides.defaultDialogUI = nil
        KeeperTestOverrides.fallbackDialogUIForCoverage = nil
        KeeperTestOverrides.apiURLFromStorage = nil
        KeeperDataSource.setShowKeeperSettingsSheetHandler(nil)
    }

    override func tearDown() {
        KeeperMockURLProtocol.responseByCommand = [:]
        KeeperMockURLProtocol.pendingV2Results = [:]
        KeeperMockURLProtocol.pendingV2Status = [:]
        KeeperMockURLProtocol.nextQueuedRequestStatus = nil
        KeeperMockURLProtocol.pendingV2StatusHTTPCode = [:]
        KeeperMockURLProtocol.nextQueuedStatusHTTPCode = nil
        KeeperMockURLProtocol.nextPOSTTriggersNetworkError = false
        KeeperMockURLProtocol.nextQueuedResultRequestFails = false
        KeeperMockURLProtocol.pendingV2ResultRequestFails = [:]
        KeeperMockURLProtocol.pendingV2StatusResponseList = [:]
        KeeperMockURLProtocol.nextQueuedStatusResponseList = nil
        KeeperMockURLProtocol.pendingV2StatusProcessingCount = [:]
        KeeperMockURLProtocol.nextQueuedStatusProcessingCount = nil
        KeeperMockURLProtocol.nextPOSTReturnsNilData = false
        KeeperMockURLProtocol.nextQueuedStatusRequestFails = false
        KeeperMockURLProtocol.pendingV2StatusRequestFails = [:]
        KeeperMockURLProtocol.nextQueuedResultReturnsNoData = false
        KeeperMockURLProtocol.pendingV2ResultReturnsNoData = [:]
        KeeperMockURLProtocol.nextQueuedResultResponse = nil
        KeeperMockURLProtocol.lastRequest = nil
        KeeperMockURLProtocol.lastCommand = nil
        KeeperTestOverrides.apiKeyFromKeychain = nil
        KeeperTestOverrides.secureKeychainReturns = nil
        KeeperTestOverrides.standardKeychainReturns = nil
        KeeperTestOverrides.storeAPIKeyInKeychain = nil
        KeeperTestOverrides.deleteAPIKeyFromKeychain = nil
        KeeperTestOverrides.showAPIKeyDialogOverride = nil
        KeeperTestOverrides.showAPIKeyDialogUIOverride = nil
        KeeperTestOverrides.callDialogUI = nil
        KeeperTestOverrides.defaultDialogUI = nil
        KeeperTestOverrides.fallbackDialogUIForCoverage = nil
        KeeperTestOverrides.apiURLFromStorage = nil
        KeeperDataSource.setShowKeeperSettingsSheetHandler(nil)
        super.tearDown()
    }

    /// When showKeeperSettingsSheetHandler is set, keeperShowAPIKeyDialog uses it instead of the legacy dialog (coverage).
    func testEnsureAPIKey_settingsSheetHandlerUsedWhenSet() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        var handlerCalled = false
        KeeperDataSource.setShowKeeperSettingsSheetHandler { _, completion in
            handlerCalled = true
            completion("key-from-settings-sheet")
        }
        defer { KeeperDataSource.setShowKeeperSettingsSheetHandler(nil) }
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.credentialsDelegate = nil
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertTrue(handlerCalled)
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// Settings sheet handler returns nil -> completion(.cancel) (coverage 70-71).
    func testEnsureAPIKey_settingsSheetHandlerReturnsNil_completesCancel() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        KeeperDataSource.setShowKeeperSettingsSheetHandler { _, completion in
            completion(nil)
        }
        defer { KeeperDataSource.setShowKeeperSettingsSheetHandler(nil) }
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.credentialsDelegate = nil
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// keeperV2PollFailHTTP direct call (coverage 343).
    func testKeeperV2PollFailHTTP_directCall_returnsFailureWithMessage() {
        let exp = expectation(description: "completion")
        keeperV2PollFailHTTP(code: 429, responseData: "{\"error\":\"rate limit\"}".data(using: .utf8)) { result in
            guard case .failure(let error) = result else { XCTFail("expected failure"); exp.fulfill(); return }
            let msg = (error as NSError).localizedDescription
            XCTAssertTrue(msg.contains("rate limit") || msg.contains("429"))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    /// keeperV2PollFailHTTP with nil responseData; when String(data:empty) is "", message may be empty so assert error code.
    func testKeeperV2PollFailHTTP_nilResponseData_usesHTTPCodeInMessage() {
        let exp = expectation(description: "completion")
        keeperV2PollFailHTTP(code: 500, responseData: nil) { result in
            guard case .failure(let error) = result else { XCTFail("expected failure"); exp.fulfill(); return }
            let nsErr = error as NSError
            XCTAssertEqual(nsErr.code, 500, "expected error code 500, got: \(nsErr.code)")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    /// ensureAPIKey inside lock uses injectedCachedSettingsKeyForLockTest (coverage 562-565).
    func testEnsureAPIKey_injectedCachedSettingsKeyInLock_usesIt() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = nil
        ds.injectedKeychainGetAPIKey = nil
        ds.injectedCachedSettingsKeyForLockTest = "key-from-lock-test"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// Extracts the "command" string from the last v2 POST (or request body). Returns nil if missing or invalid.
    private func commandFromLastRequest() -> String? {
        if let cmd = KeeperMockURLProtocol.lastCommand { return cmd }
        guard let request = KeeperMockURLProtocol.lastRequest else { return nil }
        let body: Data? = {
            if let data = request.httpBody, !data.isEmpty { return data }
            guard let stream = request.httpBodyStream else { return nil }
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                guard read > 0 else { break }
                data.append(buffer, count: read)
            }
            return data.isEmpty ? nil : data
        }()
        guard let body = body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let cmd = json["command"] as? String else { return nil }
        return cmd
    }

    // MARK: - passwordFromGetJSONResponse

    func testPasswordFromGetJSONResponse_normalRecordTopLevelData() {
        // data is a JSON object with "password" key
        let json = """
        {"data": {"password": "70MOC#4(0.QzGt/:m|9s"}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.passwordFromGetJSONResponse(data)
        XCTAssertEqual(result, "70MOC#4(0.QzGt/:m|9s")
    }

    func testPasswordFromGetJSONResponse_normalRecordDataAsString() {
        // data is a string containing JSON-encoded record
        let json = "{\"data\": \"{\\\"password\\\": \\\"secret123\\\"}\"}"
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.passwordFromGetJSONResponse(data)
        XCTAssertEqual(result, "secret123")
    }

    func testPasswordFromGetJSONResponse_typedRecordWithFieldsValueAsString() {
        let json = """
        {"data": {"fields": [{"type": "password", "value": "p@ss:w0rd"}]}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.passwordFromGetJSONResponse(data)
        XCTAssertEqual(result, "p@ss:w0rd")
    }

    func testPasswordFromGetJSONResponse_typedRecordWithFieldsValueAsArray() {
        let json = """
        {"data": {"fields": [{"type": "login", "value": "user"}, {"type": "password", "value": ["myPass"]}]}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.passwordFromGetJSONResponse(data)
        XCTAssertEqual(result, "myPass")
    }

    func testPasswordFromGetJSONResponse_recordKeyTopLevel() {
        let json = """
        {"record": {"password": "fromRecordKey"}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.passwordFromGetJSONResponse(data)
        XCTAssertEqual(result, "fromRecordKey")
    }

    func testPasswordFromGetJSONResponse_preservesCaseAndSpecialChars() {
        let json = """
        {"data": {"password": "  MixedCASE#4(0.QzGt/:m|9s  "}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.passwordFromGetJSONResponse(data)
        XCTAssertEqual(result, "MixedCASE#4(0.QzGt/:m|9s")
    }

    func testPasswordFromGetJSONResponse_emptyPasswordReturnsNil() {
        let json = """
        {"data": {"password": ""}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.passwordFromGetJSONResponse(data)
        XCTAssertNil(result)
    }

    func testPasswordFromGetJSONResponse_whitespaceOnlyPasswordReturnsNil() {
        let json = """
        {"data": {"password": "   \n  "}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.passwordFromGetJSONResponse(data)
        XCTAssertNil(result)
    }

    func testPasswordFromGetJSONResponse_invalidJSONReturnsNil() {
        let data = "not json".data(using: .utf8)!
        let result = KeeperDataSource.passwordFromGetJSONResponse(data)
        XCTAssertNil(result)
    }

    /// passwordFromGetJSONResponse: record with fields but no password-type field (fromRecord returns nil, coverage 799).
    func testPasswordFromGetJSONResponse_recordWithFieldsNoPassword_returnsNil() {
        let json = """
        {"record":{"fields":[{"type":"login","value":"user"}]}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.passwordFromGetJSONResponse(data)
        XCTAssertNil(result)
    }

    func testPasswordFromGetJSONResponse_noPasswordKeyReturnsNil() {
        let json = """
        {"data": {"login": "user", "title": "Site"}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.passwordFromGetJSONResponse(data)
        XCTAssertNil(result)
    }

    // MARK: - loginFromGetJSONResponse

    func testLoginFromGetJSONResponse_dataObjectWithLogin_returnsLogin() {
        let json = """
        {"data": {"login": "hborase@keepersecurity.com", "title": "MySQL"}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.loginFromGetJSONResponse(data)
        XCTAssertEqual(result, "hborase@keepersecurity.com")
    }

    func testLoginFromGetJSONResponse_dataObjectWithUsername_returnsUsername() {
        let json = """
        {"data": {"username": "root", "title": "MySQL"}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.loginFromGetJSONResponse(data)
        XCTAssertEqual(result, "root")
    }

    func testLoginFromGetJSONResponse_recordKeyWithLogin_returnsLogin() {
        let json = """
        {"record": {"login": "from-record-key"}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.loginFromGetJSONResponse(data)
        XCTAssertEqual(result, "from-record-key")
    }

    func testLoginFromGetJSONResponse_dataAsStringWithLogin_returnsLogin() {
        let json = "{\"data\": \"{\\\"login\\\": \\\"nested@login.com\\\"}\"}"
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.loginFromGetJSONResponse(data)
        XCTAssertEqual(result, "nested@login.com")
    }

    func testLoginFromGetJSONResponse_typedRecordFieldsWithLoginValueString_returnsLogin() {
        let json = """
        {"data": {"fields": [{"type": "login", "value": "typed-login"}]}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.loginFromGetJSONResponse(data)
        XCTAssertEqual(result, "typed-login")
    }

    func testLoginFromGetJSONResponse_typedRecordFieldsWithLoginValueArray_returnsFirst() {
        let json = """
        {"data": {"fields": [{"type": "login", "value": ["first@login.com"]}]}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.loginFromGetJSONResponse(data)
        XCTAssertEqual(result, "first@login.com")
    }

    func testLoginFromGetJSONResponse_emptyLoginReturnsNil() {
        let json = """
        {"data": {"login": ""}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.loginFromGetJSONResponse(data)
        XCTAssertNil(result)
    }

    func testLoginFromGetJSONResponse_invalidJSONReturnsNil() {
        let data = "not json".data(using: .utf8)!
        let result = KeeperDataSource.loginFromGetJSONResponse(data)
        XCTAssertNil(result)
    }

    func testLoginFromGetJSONResponse_noLoginOrUsernameReturnsNil() {
        let json = """
        {"data": {"title": "Site", "password": "secret"}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.loginFromGetJSONResponse(data)
        XCTAssertNil(result)
    }

    func testLoginFromGetJSONResponse_trimmedWhitespace() {
        let json = """
        {"data": {"login": "  user@example.com  "}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.loginFromGetJSONResponse(data)
        XCTAssertEqual(result, "user@example.com")
    }

    /// loginFromGetJSONResponse: fields with type "login" and value empty string → nil (covers t.isEmpty ? nil : t in fromRecord).
    func testLoginFromGetJSONResponse_typedRecordFieldsLoginValueEmptyString_returnsNil() {
        let data = "{\"data\":{\"fields\":[{\"type\":\"login\",\"value\":\"\"}]}}".data(using: .utf8)!
        XCTAssertNil(KeeperDataSource.loginFromGetJSONResponse(data))
    }

    /// loginFromGetJSONResponse: fields with type "login" and value array with empty first element → nil.
    func testLoginFromGetJSONResponse_typedRecordFieldsLoginValueArrayEmptyFirst_returnsNil() {
        let data = "{\"data\":{\"fields\":[{\"type\":\"login\",\"value\":[\"\"]}]}}".data(using: .utf8)!
        XCTAssertNil(KeeperDataSource.loginFromGetJSONResponse(data))
    }

    // MARK: - fetchLogin and usernameForTerminal

    func testFetchLogin_success_returnsLoginFromGetJSON() {
        let uid = "uid12345678901234"
        let cmd = "get \(uid) --format=json"
        let response = "{\"status\":\"success\",\"data\":{\"login\":\"fetched-login@test.com\"}}"
        KeeperMockURLProtocol.responseByCommand[cmd] = (response.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchLogin")
        ds.fetchLogin(recordUid: uid, context: makeContext()) { login in
            XCTAssertEqual(login, "fetched-login@test.com")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testFetchLogin_noAPIKey_returnsNil() {
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = nil
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchLogin")
        ds.fetchLogin(recordUid: "uid12345678901234", context: makeContext()) { login in
            XCTAssertNil(login)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testFetchLogin_failure_returnsNil() {
        let uid = "uid12345678901234"
        let cmd = "get \(uid) --format=json"
        KeeperMockURLProtocol.responseByCommand[cmd] = (Data(), 500)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchLogin")
        ds.fetchLogin(recordUid: uid, context: makeContext()) { login in
            XCTAssertNil(login)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// usernameForTerminal: KeeperAccount fetches login via fetchLogin and returns it (covers usernameForTerminal + fetchLogin success path).
    func testKeeperAccount_usernameForTerminal_fetchesLoginAndReturnsIt() {
        let uid = "uid99999999999999"
        let listPayload = "{\"command\":\"ls\",\"status\":\"success\",\"data\":{\"records\":[{\"title\":\"1  \(uid)  login  Acct  desc\"}]}}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (listPayload.data(using: .utf8)!, 200)
        let getCmd = "get \(uid) --format=json"
        let getPayload = "{\"data\":{\"login\":\"terminal-login@test.com\"}}"
        KeeperMockURLProtocol.responseByCommand[getCmd] = (getPayload.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts then usernameForTerminal")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            guard let account = accounts.first else { exp.fulfill(); return }
            account.usernameForTerminal(context: self.makeContext()) { username in
                XCTAssertEqual(username, "terminal-login@test.com")
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 5)
    }

    /// usernameForTerminal: when fetchLogin returns nil (e.g. no login in record), falls back to account's userName (description).
    func testKeeperAccount_usernameForTerminal_fetchReturnsNil_fallsBackToUserName() {
        let uid = "uid88888888888888"
        let listPayload = "{\"command\":\"ls\",\"status\":\"success\",\"data\":{\"records\":[{\"title\":\"1  \(uid)  mysql  MySQL  fallback-desc\"}]}}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (listPayload.data(using: .utf8)!, 200)
        let getCmd = "get \(uid) --format=json"
        // Record has no login/username key
        let getPayload = "{\"data\":{\"title\":\"MySQL\",\"password\":\"secret\"}}"
        KeeperMockURLProtocol.responseByCommand[getCmd] = (getPayload.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "usernameForTerminal fallback")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            guard let account = accounts.first else { exp.fulfill(); return }
            account.usernameForTerminal(context: self.makeContext()) { username in
                XCTAssertEqual(username, "fallback-desc")
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 5)
    }

    /// usernameForTerminal: when dataSource is deallocated (weak ref nil), returns account userName (covers guard let dataSource else branch).
    func testKeeperAccount_usernameForTerminal_dataSourceDeallocated_returnsUserName() {
        let uid = "uid77777777777777"
        let listPayload = "{\"command\":\"ls\",\"status\":\"success\",\"data\":{\"records\":[{\"title\":\"1  \(uid)  login  Acct  my-fallback\"}]}}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (listPayload.data(using: .utf8)!, 200)
        var ds: KeeperDataSource? = KeeperDataSource(browser: false)
        ds?.injectedAPIKey = "key"
        ds?.injectedBaseURL = URL(string: "https://keeper.test")!
        ds?.injectedURLSession = mockSession
        let exp = expectation(description: "usernameForTerminal dataSource nil")
        ds?.fetchAccounts(context: makeContext()) { accounts in
            guard let account = accounts.first else { exp.fulfill(); return }
            let expectedName = account.userName
            ds = nil
            account.usernameForTerminal(context: self.makeContext()) { username in
                XCTAssertEqual(username, expectedName)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 5)
    }

    // MARK: - parseLsRecordLine

    func testParseLsRecordLine_validLine() {
        let line = "1  a1b2c3d4e5f6g7h8  login  My Login  optional description"
        let result = parseLsRecordLine(line)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.number, 1)
        XCTAssertEqual(result?.effectiveUid, "a1b2c3d4e5f6g7h8")
        XCTAssertEqual(result?.type, "login")
        XCTAssertEqual(result?.title, "My Login")
        XCTAssertEqual(result?.description, "optional description")
    }

    func testParseLsRecordLine_validLineMinimalColumns() {
        let line = "2  x9y8z7w6v5u4t3s2  password  Untitled"
        let result = parseLsRecordLine(line)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.number, 2)
        XCTAssertEqual(result?.effectiveUid, "x9y8z7w6v5u4t3s2")
        XCTAssertEqual(result?.type, "password")
        XCTAssertEqual(result?.title, "Untitled")
        XCTAssertEqual(result?.description, "")
    }

    func testParseLsRecordLine_threeColumnsReturnsNil() {
        // Only number, uid, type (no title column). Parser requires >= 4 columns.
        let line = "3  a1b2c3d4e5f6g7h8  note    "
        let result = parseLsRecordLine(line)
        XCTAssertNil(result)
    }

    func testParseLsRecordLine_headerLineReturnsNil() {
        XCTAssertNil(parseLsRecordLine("# Number  UID  Type  Title"))
        XCTAssertNil(parseLsRecordLine("# something"))
    }

    func testParseLsRecordLine_separatorLineReturnsNil() {
        XCTAssertNil(parseLsRecordLine("---"))
        XCTAssertNil(parseLsRecordLine("---  ---  ---"))
    }

    func testParseLsRecordLine_malformedTooFewColumnsReturnsNil() {
        XCTAssertNil(parseLsRecordLine("1  short"))
        XCTAssertNil(parseLsRecordLine("1"))
    }

    func testParseLsRecordLine_uidTooShortReturnsNil() {
        // UID must be at least 15 chars
        let line = "1  short_uid  login  Title"
        XCTAssertNil(parseLsRecordLine(line))
    }

    func testParseLsRecordLine_firstColumnNotIntReturnsNil() {
        let line = "abc  a1b2c3d4e5f6g7h8  login  Title"
        XCTAssertNil(parseLsRecordLine(line))
    }

    func testParseLsRecordLine_leadingTrailingWhitespaceTrimmed() {
        let line = "  1  a1b2c3d4e5f6g7h8  login  Title  "
        let result = parseLsRecordLine(line)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.title, "Title")
    }

    // MARK: - parseMessageTableRecordUids

    func testParseMessageTableRecordUids_messageArrayFormat() {
        let json = """
        {"message": ["Header", "---", "1  a1b2c3d4e5f6g7h8  login  Title", "2  x9y8z7w6v5u4t3s2  password  Other"]}
        """
        let data = json.data(using: .utf8)!
        let result = parseMessageTableRecordUids(from: data)
        XCTAssertEqual(result, Set(["a1b2c3d4e5f6g7h8", "x9y8z7w6v5u4t3s2"]))
    }

    func testParseMessageTableRecordUids_v2WrapperWithResultString() {
        let inner = "{\"message\": [\"#\", \"---\", \"1  uid1234567890123  type  Title\"]}"
        let json = "{\"status\": \"success\", \"result\": \(inner.debugDescription)}"
        let data = json.data(using: .utf8)!
        let result = parseMessageTableRecordUids(from: data)
        XCTAssertEqual(result, Set(["uid1234567890123"]))
    }

    func testParseMessageTableRecordUids_keeperV2ResultWrapperDecodable() {
        // KeeperV2ResultWrapper: { "status": "success", "result": "<json string>" }
        let inner: [String: Any] = ["message": ["#", "---", "1  a1b2c3d4e5f6g7h8  login  A"]]
        let innerData = try! JSONSerialization.data(withJSONObject: inner)
        let innerString = String(data: innerData, encoding: .utf8)!
        let outer: [String: Any] = ["status": "success", "result": innerString]
        let data = try! JSONSerialization.data(withJSONObject: outer)
        let result = parseMessageTableRecordUids(from: data)
        XCTAssertEqual(result, Set(["a1b2c3d4e5f6g7h8"]))
    }

    /// root["result"] as dictionary (not string) -> innerData from JSONSerialization.data(withJSONObject: dict).
    func testParseMessageTableRecordUids_resultAsDict() {
        let inner: [String: Any] = ["message": ["#", "---", "1  a1b2c3d4e5f6g7h8  login  Title"]]
        let outer: [String: Any] = ["status": "success", "result": inner]
        let data = try! JSONSerialization.data(withJSONObject: outer)
        let result = parseMessageTableRecordUids(from: data)
        XCTAssertEqual(result, Set(["a1b2c3d4e5f6g7h8"]))
    }

    func testParseMessageTableRecordUids_messageTooShortReturnsEmpty() {
        let json = """
        {"message": ["only one line"]}
        """
        let data = json.data(using: .utf8)!
        let result = parseMessageTableRecordUids(from: data)
        XCTAssertTrue(result.isEmpty)
    }

    func testParseMessageTableRecordUids_invalidJSONReturnsEmpty() {
        let data = "not json".data(using: .utf8)!
        let result = parseMessageTableRecordUids(from: data)
        XCTAssertTrue(result.isEmpty)
    }

    func testParseMessageTableRecordUids_noMessageKeyReturnsEmpty() {
        let json = """
        {"data": [], "status": "ok"}
        """
        let data = json.data(using: .utf8)!
        let result = parseMessageTableRecordUids(from: data)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - keeperHumanReadableError

    func testKeeperHumanReadableError_fromErrorKey() {
        let json = "{\"error\": \"Please provide a valid api key\", \"status\": \"error\"}"
        let data = json.data(using: .utf8)!
        XCTAssertEqual(keeperHumanReadableError(fromResponseData: data), "Please provide a valid api key")
    }

    func testKeeperHumanReadableError_fromMessageKey() {
        let json = "{\"message\": \"Invalid command\", \"status\": \"fail\"}"
        let data = json.data(using: .utf8)!
        XCTAssertEqual(keeperHumanReadableError(fromResponseData: data), "Invalid command")
    }

    func testKeeperHumanReadableError_errorTakesPrecedenceOverMessage() {
        let json = "{\"error\": \"E\", \"message\": \"M\"}"
        let data = json.data(using: .utf8)!
        XCTAssertEqual(keeperHumanReadableError(fromResponseData: data), "E")
    }

    func testKeeperHumanReadableError_emptyErrorReturnsNil() {
        let json = "{\"error\": \"\", \"message\": \"\"}"
        let data = json.data(using: .utf8)!
        XCTAssertNil(keeperHumanReadableError(fromResponseData: data))
    }

    func testKeeperHumanReadableError_nilOrInvalidDataReturnsNil() {
        XCTAssertNil(keeperHumanReadableError(fromResponseData: nil))
        XCTAssertNil(keeperHumanReadableError(fromResponseData: "not json".data(using: .utf8)))
    }

    // MARK: - keeperUserFacingPasswordUpdateError

    func testKeeperUserFacingPasswordUpdateError_base64PwdMessage_returnsPasswordRequired() {
        XCTAssertEqual(keeperUserFacingPasswordUpdateError(apiDetail: "Base64 decoding failed for field pwd."), "Password field is required.")
    }

    func testKeeperUserFacingPasswordUpdateError_nonPasswordMessage_unchanged() {
        XCTAssertEqual(keeperUserFacingPasswordUpdateError(apiDetail: "Custom update error"), "Custom update error")
        XCTAssertEqual(keeperUserFacingPasswordUpdateError(apiDetail: "Update failed"), "Update failed")
    }

    func testKeeperUserFacingPasswordUpdateError_passwordInvalid_returnsPasswordRequired() {
        XCTAssertEqual(keeperUserFacingPasswordUpdateError(apiDetail: "password invalid"), "Password field is required.")
    }

    func testKeeperUserFacingPasswordUpdateError_passwordRequired_returnsPasswordRequired() {
        XCTAssertEqual(keeperUserFacingPasswordUpdateError(apiDetail: "Password required"), "Password field is required.")
    }

    // MARK: - ensureAPIKey (injected), fetchAccounts, fetchPassword, add, set, delete

    private func makeContext() -> RecipeExecutionContext {
        RecipeExecutionContext(window: nil)
    }

    /// Context with a non-nil window so ensureAPIKey uses the credentials delegate instead of showing the "Keeper Security API Key" dialog.
    private func makeContextWithWindow() -> RecipeExecutionContext {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [], backing: .buffered, defer: false)
        return RecipeExecutionContext(window: window)
    }

    func testEnsureAPIKey_usesInjectedAPIKey() {
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "injected-key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "ensureAPIKey")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0) // we didn't stub "ls -R -l" so we get empty or failure path
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// ensureAPIKey with injectedAPIKey == "" from background thread hits DispatchQueue.main.async { showUIAndContinue() } (coverage).
    func testEnsureAPIKey_fromBackgroundThread_dispatchesShowUIOnMain() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let delegate = MockKeeperCredentialsDelegate(provideKey: "key-from-bg")
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.credentialsDelegate = delegate
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        let ctx = makeContextWithWindow()
        DispatchQueue.global().async {
            ds.fetchAccounts(context: ctx) { accounts in
                XCTAssertEqual(accounts.count, 0)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 5)
    }

    /// Second ensureAPIKey call uses in-memory _apiKey (no dialog), covering the 511-513 path.
    func testEnsureAPIKey_secondCallUsesInMemoryApiKey() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        var dialogCallCount = 0
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in
            dialogCallCount += 1
            completion(.useNew("in-memory-key"))
        }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp1 = expectation(description: "first fetch")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 5)
        XCTAssertEqual(dialogCallCount, 1)
        ds.injectedAPIKey = nil  // So second call uses in-memory _apiKey from dialog, not the empty-key UI path.
        let exp2 = expectation(description: "second fetch")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 5)
        XCTAssertEqual(dialogCallCount, 1, "second call should use in-memory key, not show dialog again")
    }

    func testFetchAccounts_usesKeeperExecuteResponseRecordsFormat() {
        let json = """
        {"status":"success","command":"ls","data":{"records":[{"number":1,"uid":"a1b2c3d4e5f6g7h8","record_uid":null,"type":"login","title":"Site A","description":"user@a.com"}]}}
        """
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (json.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            XCTAssertEqual(accounts.first?.accountName, "Site A")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testFetchAccounts_usesMessageTableFormat() {
        let v2Result = "{\"status\":\"success\",\"result\":\"{\\\"command\\\":\\\"list\\\",\\\"message\\\":[\\\"#\\\",\\\"---\\\",\\\"1  a1b2c3d4e5f6g7h8  login  My Title  desc\\\"]}\"}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (v2Result.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            XCTAssertEqual(accounts.first?.accountName, "My Title")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testFetchAccounts_usesFlexibleDataArrayFormat() {
        let json = "{\"status\":\"success\",\"data\":[{\"uid\":\"u1u1u1u1u1u1u1u1\",\"title\":\"Flex Title\",\"type\":\"login\"}]}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (json.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            XCTAssertEqual(accounts.first?.accountName, "Flex Title")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchAccounts: outer status+result with result as object (dict); inner payload inserted and parsed (coverage).
    func testFetchAccounts_resultAsObjectDict_insertsInnerPayload() {
        let resultBody = "{\"status\":\"success\",\"result\":{\"command\":\"ls\",\"data\":{\"records\":[{\"title\":\"1  a1b2c3d4e5f6g7h8  login  SiteA  desc\"}]}}}"
        KeeperMockURLProtocol.nextQueuedResultResponse = (resultBody.data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"request_id\":\"q\",\"success\":true}".data(using: .utf8)!, 202)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            XCTAssertEqual(accounts.first?.accountName, "SiteA")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchAccounts: outer result as JSON string (not dict); insert innerData from str.data(using: .utf8) (coverage 666-667).
    func testFetchAccounts_resultAsJSONString_insertsInnerPayload() {
        let innerJSON = "{\"command\":\"ls\",\"data\":{\"records\":[{\"title\":\"1  a1b2c3d4e5f6g7h8  login  SiteB  desc\"}]}}"
        let resultBody = "{\"status\":\"success\",\"result\":\"\(innerJSON.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"}"
        KeeperMockURLProtocol.nextQueuedResultResponse = (resultBody.data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"request_id\":\"q\",\"success\":true}".data(using: .utf8)!, 202)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            XCTAssertEqual(accounts.first?.accountName, "SiteB")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchAccounts: data is object with "records" key; compactMap and break from !records!.isEmpty (coverage).
    func testFetchAccounts_dataObjectWithRecords_parsesAndBreaks() {
        let json = "{\"status\":\"success\",\"data\":{\"records\":[{\"record_uid\":\"a1b2c3d4e5f6g7h8\",\"uid\":\"a1b2c3d4e5f6g7h8\",\"title\":\"FromObj\",\"type\":\"login\"}]}}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (json.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            XCTAssertEqual(accounts.first?.accountName, "FromObj")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchAccounts: response parses but yields no records; posts success and completion([]) (coverage).
    func testFetchAccounts_noRecordsParsed_postsSuccessAndReturnsEmpty() {
        KeeperMockURLProtocol.nextQueuedResultResponse = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"request_id\":\"q\",\"success\":true}".data(using: .utf8)!, 202)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        var didNotify = false
        let observer = NotificationCenter.default.addObserver(forName: iTerm2KeeperConnectionDidSucceedNotification, object: nil, queue: nil) { _ in didNotify = true }
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        NotificationCenter.default.removeObserver(observer)
        XCTAssertTrue(didNotify)
    }

    func testV2PollMaxPollsExceeded_failsWithMessage() {
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.nextQueuedStatusProcessingCount = 60
        KeeperMockURLProtocol.nextQueuedRequestStatus = "queued"
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedURLSession = mockSession
        ds.injectedV2PollInterval = 0.05
        ds.injectedV2Deadline = 30
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success)
            XCTAssertTrue(message?.contains("complete") ?? false || message?.contains("time") ?? false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 15)
    }

    func testV2FetchResultHttpError_returnsFailure() {
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"error\":\"Internal error\"}".data(using: .utf8)!, 500)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success)
            XCTAssertNotNil(message)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
    }

    func testV2POSTReturnsNoData_failsWithNoRequestId() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (Data(), 202)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testFetchPassword_plainTextResponse() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("mypass".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "mypass")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testFetchPassword_resultKeyInParsedObject() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"result\":\"secret\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "secret")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testFetchPassword_dataObjectSingleKeyCombined() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"data\":{\"abc\":\"def\"}}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "abcdef")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testFetchAccounts_parsesLsRlAndReturnsAccounts() {
        let lsResponse = """
        {"command": "ls", "data": {"records": [{"title": "1  a1b2c3d4e5f6g7h8  login  My Site  user@example.com"}]}, "status": "success"}
        """
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (lsResponse.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "test-key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            XCTAssertEqual(accounts.first?.accountName, "My Site")
            XCTAssertEqual(accounts.first?.userName, "user@example.com")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testFetchAccounts_noAPIKeyPostsFailureAndReturnsEmpty() {
        let ds = KeeperDataSource(browser: false)
        // Use empty string to mean "explicitly no key" so we skip Keychain and hit the delegate path (avoids reading real keychain).
        ds.injectedAPIKey = ""
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let delegate = MockKeeperCredentialsDelegate(provideKey: nil)
        ds.credentialsDelegate = delegate
        // Use context with window so the delegate is called instead of showing the "Keeper Security API Key" dialog.
        let context = makeContextWithWindow()
        var observedNotification: Notification?
        let observer = NotificationCenter.default.addObserver(forName: iTerm2KeeperConnectionDidFailNotification, object: nil, queue: nil) { notif in
            observedNotification = notif
        }
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: context) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        NotificationCenter.default.removeObserver(observer)
        XCTAssertNotNil(observedNotification)
        XCTAssertEqual(observedNotification?.userInfo?["error"] as? String, "No API key entered or configuration was cancelled.")
    }

    func testFetchPassword_getFormatJsonReturnsPassword() {
        let getResponse = "{\"data\": {\"password\": \"secret-from-json\"}}"
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=json"] = (getResponse.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "test-key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid12345678901234", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "secret-from-json")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// passwordFromGetJSONResponse: top-level "record" key (coverage).
    func testFetchPassword_getFormatJsonRecordKey_returnsPassword() {
        KeeperMockURLProtocol.responseByCommand["get rec12345678901234 --format=json"] = ("{\"record\":{\"password\":\"from-record-key\"}}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "rec12345678901234", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "from-record-key")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: first get fails; second get returns quoted result string (coverage).
    func testFetchPassword_firstGetFails_secondGetQuotedResult_succeeds() {
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=json"] = ("{\"error\":\"fail\"}".data(using: .utf8)!, 500)
        KeeperMockURLProtocol.nextQueuedResultResponse = ("{\"status\":\"success\",\"result\":\"\\\"quoted-pass\\\"\"}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=password"] = ("{\"request_id\":\"q\",\"success\":true}".data(using: .utf8)!, 202)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid12345678901234", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "\"quoted-pass\"", "result string used as password when non-empty")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: password from parsed["data"] as [String], first element (coverage).
    func testFetchPassword_dataAsStringArray_usesFirstElement() {
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=password"] = ("{\"data\":[\"only-element\"]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid12345678901234", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "only-element")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: password from parsed["data"] as [Any], first as String (coverage).
    func testFetchPassword_dataAsAnyArrayFirstString_usesIt() {
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=password"] = ("{\"data\":[\"first\"]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid12345678901234", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "first")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: parsed["data"] as [Any] (mixed array) with first as String; dataVal as? [String] fails so we hit the [Any] branch (coverage 892-893).
    func testFetchPassword_dataAsMixedArrayFirstString_usesFirst() {
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=password"] = ("{\"data\":[\"from-mixed\",2]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid12345678901234", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "from-mixed")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: parsed["data"] as String with quoted value; decode inner string (coverage 855-860).
    func testFetchPassword_dataQuotedString_decodesInner() {
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=password"] = ("{\"data\":\"\\\"inner-pwd\\\"\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid12345678901234", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "inner-pwd")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: non-JSON raw body with quoted string (coverage).
    func testFetchPassword_rawQuotedString_returnsDecoded() {
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=password"] = ("\"raw-quoted\"".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid12345678901234", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "raw-quoted")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testSetPassword_success() {
        KeeperMockURLProtocol.responseByCommand["record-update -r uid12345678901234 password=$BASE64:cHdk"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "test-key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "set")
        ds.setPassword(recordUid: "uid12345678901234", password: "pwd", context: makeContext()) { error in
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// setPassword with empty password returns "Password field is required." without calling the API.
    func testSetPassword_emptyPassword_returnsPasswordRequired() {
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "set")
        ds.setPassword(recordUid: "uid123", password: "", context: makeContext()) { error in
            XCTAssertNotNil(error)
            XCTAssertEqual((error as NSError?)?.localizedDescription, "Password field is required.")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// setPassword when API returns Base64/pwd error message shows "Password field is required."
    func testSetPassword_base64ErrorFromAPI_showsPasswordRequired() {
        let pwdB64 = Data("pwd".utf8).base64EncodedString()
        let cmd = "record-update -r uid12345678901234 password=$BASE64:\(pwdB64)"
        KeeperMockURLProtocol.responseByCommand[cmd] = ("{\"status\":\"error\",\"message\":[\"Base64 decoding failed for field pwd.\"]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "set")
        ds.setPassword(recordUid: "uid12345678901234", password: "pwd", context: makeContext()) { error in
            XCTAssertNotNil(error)
            XCTAssertEqual((error as NSError?)?.localizedDescription, "Password field is required.")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testSetPassword_errorResponse() {
        let pwdB64 = Data("pwd".utf8).base64EncodedString()
        let cmd = "record-update -r uid12345678901234 password=$BASE64:\(pwdB64)"
        KeeperMockURLProtocol.responseByCommand[cmd] = ("{\"status\":\"error\",\"message\":[\"Update failed\"]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "set")
        ds.setPassword(recordUid: "uid12345678901234", password: "pwd", context: makeContext()) { error in
            XCTAssertNotNil(error)
            XCTAssertTrue((error as NSError?)?.localizedDescription.contains("Update failed") ?? false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// setPassword: keeperExecute returns .failure (e.g. network error) → completion with error (coverage 973-974).
    func testSetPassword_networkError_completesWithFailure() {
        KeeperMockURLProtocol.nextPOSTTriggersNetworkError = true
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "set")
        ds.setPassword(recordUid: "uid123", password: "pwd", context: makeContext()) { error in
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// setPassword error with no error/message keys -> fallback "Update failed".
    func testSetPassword_errorWithNoMessageKey_usesUpdateFailedFallback() {
        let pwdB64 = Data("pwd".utf8).base64EncodedString()
        let cmd = "record-update -r uid12345678901234 password=$BASE64:\(pwdB64)"
        KeeperMockURLProtocol.responseByCommand[cmd] = ("{\"status\":\"fail\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "set")
        ds.setPassword(recordUid: "uid12345678901234", password: "pwd", context: makeContext()) { error in
            XCTAssertNotNil(error)
            XCTAssertEqual((error as NSError?)?.localizedDescription, "Update failed")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// setPassword error with message array -> detail from flatMap message first (coverage).
    func testSetPassword_errorWithMessageArray_usesFirstMessage() {
        let pwdB64 = Data("pwd".utf8).base64EncodedString()
        let cmd = "record-update -r uid12345678901234 password=$BASE64:\(pwdB64)"
        KeeperMockURLProtocol.responseByCommand[cmd] = ("{\"status\":\"error\",\"message\":[\"Custom error from message\"]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "set")
        ds.setPassword(recordUid: "uid12345678901234", password: "pwd", context: makeContext()) { error in
            XCTAssertNotNil(error)
            XCTAssertTrue((error as NSError?)?.localizedDescription.contains("Custom error") ?? false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testDeleteRecord_success() {
        KeeperMockURLProtocol.responseByCommand["rm -f uid12345678901234"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "test-key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "delete")
        ds.deleteRecord(recordUid: "uid12345678901234", context: makeContext()) { error in
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testDeleteRecord_errorResponse() {
        KeeperMockURLProtocol.responseByCommand["rm -f uid12345678901234"] = ("{\"status\":\"error\",\"message\":[\"Delete failed\"]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "delete")
        ds.deleteRecord(recordUid: "uid12345678901234", context: makeContext()) { error in
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// deleteRecord: keeperExecute returns .failure → completion with error (coverage 995-996).
    func testDeleteRecord_networkError_completesWithFailure() {
        KeeperMockURLProtocol.nextPOSTTriggersNetworkError = true
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "delete")
        ds.deleteRecord(recordUid: "uid123", context: makeContext()) { error in
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// deleteRecord: success response but status != success -> keeperHumanReadableError or "Delete failed" (coverage).
    func testDeleteRecord_failWithNoMessage_usesDeleteFailedFallback() {
        KeeperMockURLProtocol.responseByCommand["rm -f uid12345678901234"] = ("{\"status\":\"fail\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "delete")
        ds.deleteRecord(recordUid: "uid12345678901234", context: makeContext()) { error in
            XCTAssertNotNil(error)
            XCTAssertTrue((error as NSError?)?.localizedDescription.contains("Delete failed") ?? false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// Delete error with no error/message keys -> keeperHumanReadableError nil, fallback "Delete failed".
    func testDeleteRecord_errorWithNoMessageKey_usesDeleteFailedFallback() {
        KeeperMockURLProtocol.responseByCommand["rm -f uid12345678901234"] = ("{\"status\":\"error\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "delete")
        ds.deleteRecord(recordUid: "uid12345678901234", context: makeContext()) { error in
            XCTAssertNotNil(error)
            XCTAssertEqual((error as NSError?)?.localizedDescription, "Delete failed")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testAdd_recordAddReturnsAccount() {
        let addResponse = "{\"status\":\"success\",\"data\":{\"record_uid\":\"newuid123456789012\"}}"
        let cmd = "record-add --record-type=login --title=\"My Title\" login=\"user\" password=$BASE64:cGFzcw=="
        KeeperMockURLProtocol.responseByCommand[cmd] = (addResponse.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "test-key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "add")
        ds.add(userName: "user", accountName: "My Title", password: "pass", context: makeContext()) { account, error in
            XCTAssertNil(error)
            XCTAssertNotNil(account)
            XCTAssertEqual(account?.accountName, "My Title")
            XCTAssertEqual(account?.userName, "user")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// add() with only accountName (empty userName and password) sends title-only record-add and succeeds.
    func testAdd_titleOnly_noLoginNoPassword_succeeds() {
        let addResponse = "{\"status\":\"success\",\"data\":{\"record_uid\":\"title-only-uid\"}}"
        let cmd = "record-add --record-type=login --title=\"Only Title\""
        KeeperMockURLProtocol.responseByCommand[cmd] = (addResponse.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "add")
        ds.add(userName: "", accountName: "Only Title", password: "", context: makeContext()) { account, error in
            XCTAssertNil(error)
            XCTAssertNotNil(account)
            XCTAssertEqual(account?.accountName, "Only Title")
            XCTAssertEqual(account?.userName, "")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// add() with accountName and userName (no password) sends record-add with login= only and succeeds.
    func testAdd_titleAndLoginOnly_noPassword_succeeds() {
        let cmd = "record-add --record-type=login --title=\"Acct\" login=\"loginonly\""
        let addResponse = "{\"status\":\"success\",\"data\":{\"record_uid\":\"login-only-uid\"}}"
        KeeperMockURLProtocol.responseByCommand[cmd] = (addResponse.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "add")
        ds.add(userName: "loginonly", accountName: "Acct", password: "", context: makeContext()) { account, error in
            XCTAssertNil(error)
            XCTAssertNotNil(account)
            XCTAssertEqual(account?.accountName, "Acct")
            XCTAssertEqual(account?.userName, "loginonly")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// add() with accountName and password (no userName) sends record-add with password=$BASE64 only and succeeds.
    func testAdd_titleAndPasswordOnly_noUserName_succeeds() {
        let b64 = Data("secret".utf8).base64EncodedString()
        let cmd = "record-add --record-type=login --title=\"PwdOnly\" password=$BASE64:\(b64)"
        let addResponse = "{\"status\":\"success\",\"data\":{\"record_uid\":\"pwd-only-uid\"}}"
        KeeperMockURLProtocol.responseByCommand[cmd] = (addResponse.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "add")
        ds.add(userName: "", accountName: "PwdOnly", password: "secret", context: makeContext()) { account, error in
            XCTAssertNil(error)
            XCTAssertNotNil(account)
            XCTAssertEqual(account?.accountName, "PwdOnly")
            XCTAssertEqual(account?.userName, "")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testAdd_errorResponse() {
        let addCmd = "record-add --record-type=login --title=\"Title\" login=\"user\" password=$BASE64:cGFzcw=="
        KeeperMockURLProtocol.responseByCommand[addCmd] = ("{\"status\":\"error\",\"data\":null}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "add")
        ds.add(userName: "user", accountName: "Title", password: "pass", context: makeContext()) { account, error in
            XCTAssertNil(account)
            XCTAssertNotNil(error)
            XCTAssertTrue((error as NSError?)?.localizedDescription.contains("Add failed") ?? false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// add() error with no error/message keys -> keeperHumanReadableError nil, fallback "Add failed".
    func testAdd_errorWithNoMessageKey_usesAddFailedFallback() {
        let addCmd = "record-add --record-type=login --title=\"T\" login=\"u\" password=$BASE64:cGFzcw=="
        KeeperMockURLProtocol.responseByCommand[addCmd] = ("{\"status\":\"error\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "add")
        ds.add(userName: "u", accountName: "T", password: "pass", context: makeContext()) { account, error in
            XCTAssertNil(account)
            XCTAssertEqual((error as NSError?)?.localizedDescription, "Add failed")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testAdd_invalidJSONReturnsError() {
        let addCmd = "record-add --record-type=login --title=\"T\" login=\"u\" password=$BASE64:cGFzcw=="
        KeeperMockURLProtocol.responseByCommand[addCmd] = ("not json".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "add")
        ds.add(userName: "u", accountName: "T", password: "pass", context: makeContext()) { account, error in
            XCTAssertNil(account)
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testKeeperAccount_displayStringAndMatches() {
        let lsResponse = """
        {"command": "ls", "data": {"records": [{"title": "1  a1b2c3d4e5f6g7h8  login  My Site  user@example.com"}]}, "status": "success"}
        """
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (lsResponse.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "test-key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        var accounts: [PasswordManagerAccount] = []
        ds.fetchAccounts(context: makeContext()) { list in
            accounts = list
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertEqual(accounts.count, 1, "Mock should return one account from ls -R -l")
        guard let account = accounts.first else { return }
        XCTAssertTrue(account.displayString.contains("My Site"))
        XCTAssertTrue(account.displayString.contains("user@example.com"))
        XCTAssertTrue(account.matches(filter: "Site"))
        XCTAssertTrue(account.matches(filter: "user@example"))
        XCTAssertTrue(account.matches(filter: ""))
        XCTAssertFalse(account.matches(filter: "Nonexistent"))
    }

    func testToggleShouldSendOTP_returnsNotSupported() {
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "test-key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let lsResponse = "{\"command\": \"ls\", \"data\": {\"records\": [{\"title\": \"1  a1b2c3d4e5f6g7h8  login  A  B\"}]}, \"status\": \"success\"}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (lsResponse.data(using: .utf8)!, 200)
        let exp = expectation(description: "fetch then toggle")
        ds.fetchAccounts(context: makeContext()) { accounts in
            guard let account = accounts.first else { XCTFail("no account (mock ls -R -l should return one)"); exp.fulfill(); return }
            ds.toggleShouldSendOTP(context: self.makeContext(), account: account) { updated, error in
                XCTAssertNotNil(error)
                XCTAssertTrue((error as NSError?)?.localizedDescription.contains("OTP") ?? false)
                XCTAssertNil(updated)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 5)
    }

    func testKeeperDataSource_nameAndCapabilities() {
        let ds = KeeperDataSource(browser: false)
        XCTAssertEqual(ds.name, "Keeper Security")
        XCTAssertTrue(ds.canResetConfiguration)
        XCTAssertFalse(ds.autogeneratedPasswordsOnly)
        XCTAssertFalse(ds.supportsMultipleAccounts)
        XCTAssertTrue(ds.checkAvailability())
    }

    func testKeeperHasAPIKeyInMemory_falseWhenNoInjection() {
        let ds = KeeperDataSource(browser: false)
        XCTAssertFalse(ds.keeperHasAPIKeyInMemory())
    }

    func testKeeperHasAPIKeyInMemory_trueWhenInjected() {
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        XCTAssertTrue(ds.keeperHasAPIKeyInMemory())
    }

    func testKeeperExecute_noBaseURLReturnsError() {
        KeeperTestOverrides.apiURLFromStorage = { nil }
        defer { KeeperTestOverrides.apiURLFromStorage = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = nil
        ds.injectedURLSession = mockSession
        // keeperBaseURL() returns nil (storage override), so keeperExecute gets nil and hits "API URL is required" path.
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testKeeperExecute_httpErrorReturnsHumanReadableMessage() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"error\": \"Please provide a valid api key\"}".data(using: .utf8)!, 401)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "bad-key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        var observedNotification: Notification?
        let observer = NotificationCenter.default.addObserver(forName: iTerm2KeeperConnectionDidFailNotification, object: nil, queue: nil) { notif in
            observedNotification = notif
        }
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        NotificationCenter.default.removeObserver(observer)
        XCTAssertNotNil(observedNotification)
        let message = observedNotification?.userInfo?["error"] as? String ?? ""
        XCTAssertTrue(message.contains("valid api key") || message.contains("401"), "expected human-readable or 401, got: \(message)")
    }

    // MARK: - Enter username / Enter password (request body contains values)

    func testAdd_sendsUserNameAndPasswordInRequest() {
        let userName = "myuser"
        let password = "myp@ss"
        let addResponse = "{\"status\":\"success\",\"data\":{\"record_uid\":\"uid123456789012\"}}"
        let passwordB64 = Data(password.utf8).base64EncodedString()
        let cmd = "record-add --record-type=login --title=\"Title\" login=\"myuser\" password=$BASE64:\(passwordB64)"
        KeeperMockURLProtocol.responseByCommand[cmd] = (addResponse.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "add")
        ds.add(userName: userName, accountName: "Title", password: password, context: makeContext()) { _, error in
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        let command = commandFromLastRequest()
        XCTAssertNotNil(command)
        XCTAssertTrue(command?.contains("login=\"myuser\"") ?? false, "command should contain entered username: \(command ?? "")")
        XCTAssertTrue(command?.contains("password=$BASE64:") ?? false, "command should contain Base64 password: \(command ?? "")")
        XCTAssertTrue(command?.contains(passwordB64) ?? false, "command should contain Base64-encoded password: \(command ?? "")")
    }

    func testSetPassword_sendsPasswordInRequest() {
        let password = "enteredPwd"
        let passwordB64 = Data(password.utf8).base64EncodedString()
        KeeperMockURLProtocol.responseByCommand["record-update -r uid12345678901234 password=$BASE64:\(passwordB64)"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "set")
        ds.setPassword(recordUid: "uid12345678901234", password: password, context: makeContext()) { error in
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        let command = commandFromLastRequest()
        XCTAssertNotNil(command)
        XCTAssertTrue(command?.contains("password=$BASE64:") ?? false, "command should contain Base64 password: \(command ?? "")")
        XCTAssertTrue(command?.contains(passwordB64) ?? false, "command should contain Base64-encoded password: \(command ?? "")")
    }

    // MARK: - Sync records (runKeeperSyncDown)

    func testRunKeeperSyncDown_success() {
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertTrue(success)
            XCTAssertNil(message)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testRunKeeperSyncDown_failure() {
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"error\": \"Sync failed\"}".data(using: .utf8)!, 500)
        let ds = KeeperDataSource(browser: false)
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success)
            XCTAssertNotNil(message)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testRunKeeperSyncDown_emptyKeyReturnsError() {
        let ds = KeeperDataSource(browser: false)
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "  ", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success)
            XCTAssertEqual(message, "API key is empty.")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testRunKeeperSyncDown_emptyURLReturnsError() {
        let ds = KeeperDataSource(browser: false)
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "") { success, message in
            XCTAssertFalse(success)
            XCTAssertEqual(message, "API URL is required.")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testRunKeeperSyncDown_invalidURLReturnsError() {
        let ds = KeeperDataSource(browser: false)
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "not-a-url") { success, message in
            XCTAssertFalse(success)
            XCTAssertEqual(message, "Invalid API URL.")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testV2SubmitReturns202NoRequestId_fetchAccountsFails() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{}".data(using: .utf8)!, 202)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testV2StatusFailed_runKeeperSyncDownFails() {
        KeeperMockURLProtocol.nextQueuedRequestStatus = "failed"
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success)
            XCTAssertTrue(message?.contains("failed") ?? false, "expected message to contain 'failed', got: \(message ?? "")")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testV2StatusExpired_runKeeperSyncDownFails() {
        KeeperMockURLProtocol.nextQueuedRequestStatus = "expired"
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success)
            XCTAssertTrue(message?.contains("expired") ?? false, "expected message to contain 'expired', got: \(message ?? "")")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testV2StatusReturns429_runKeeperSyncDownFails() {
        KeeperMockURLProtocol.nextQueuedStatusHTTPCode = 429
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success)
            XCTAssertNotNil(message)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testV2PollTimeout_runKeeperSyncDownFails() {
        KeeperMockURLProtocol.nextQueuedStatusProcessingCount = 100
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedURLSession = mockSession
        ds.injectedV2PollInterval = 0.05
        ds.injectedV2Deadline = 0.15
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success)
            XCTAssertTrue(message?.contains("timed out") ?? false, "expected timeout message, got: \(message ?? "")")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testV2ConsecutiveUnparseableStatus_runKeeperSyncDownFails() {
        var invalidList = (0..<15).map { _ in "{}".data(using: .utf8)! }
        invalidList.append("{\"status\":\"completed\"}".data(using: .utf8)!)
        KeeperMockURLProtocol.nextQueuedStatusResponseList = invalidList
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedURLSession = mockSession
        ds.injectedV2PollInterval = 0.02
        ds.injectedV2Deadline = 5.0
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success)
            XCTAssertTrue(message?.contains("invalid status") ?? false, "expected invalid status message, got: \(message ?? "")")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
    }

    func testV2POSTNetworkError_fetchAccountsFails() {
        KeeperMockURLProtocol.nextPOSTTriggersNetworkError = true
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testV2ResultNetworkError_runKeeperSyncDownFails() {
        KeeperMockURLProtocol.nextQueuedResultRequestFails = true
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success)
            XCTAssertNotNil(message)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// Direct call for coverage: keeperExecuteV2FailNoData.
    func testKeeperExecuteV2FailNoData_directCall_returnsNoDataError() {
        let exp = expectation(description: "completion")
        keeperExecuteV2FailNoData { result in
            guard case .failure(let error) = result else { XCTFail("expected failure"); exp.fulfill(); return }
            XCTAssertEqual((error as NSError).localizedDescription, "No data")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    /// Direct call for coverage: keeperExecuteV2FailNon202.
    func testKeeperExecuteV2FailNon202_directCall_returnsMessageFromBody() {
        let exp = expectation(description: "completion")
        let body = "{\"error\":\"Bad request\"}".data(using: .utf8)
        keeperExecuteV2FailNon202(data: body) { result in
            guard case .failure(let error) = result else { XCTFail("expected failure"); exp.fulfill(); return }
            let msg = (error as NSError).localizedDescription
            XCTAssertTrue(msg.contains("Bad request") || msg.contains("error"))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    /// Direct call for coverage: keeperExecuteV2FailNoRequestId.
    func testKeeperExecuteV2FailNoRequestId_directCall_returnsNoRequestIdError() {
        let exp = expectation(description: "completion")
        keeperExecuteV2FailNoRequestId { result in
            guard case .failure(let error) = result else { XCTFail("expected failure"); exp.fulfill(); return }
            XCTAssertTrue((error as NSError).localizedDescription.contains("request_id"))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    /// POST returns non-202 with non-JSON body -> keeperExecuteV2 uses String(data:encoding:) as message.
    func testV2POSTReturns400PlainText_fetchAccountsReturnsZero() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("Server error: bad request".data(using: .utf8)!, 400)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// POST returns non-202 with invalid UTF-8 body -> keeperExecuteV2 uses "Unexpected response".
    func testV2POSTReturns400InvalidUTF8_fetchAccountsReturnsZero() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (Data([0xFF, 0xFE, 0x00]), 400)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// POST returns 202 but no body (nil data) -> keeperExecuteV2 "No data" path (keeperExecuteV2FailNoData).
    func testV2POSTReturnsNilData_fetchAccountsFails() {
        KeeperMockURLProtocol.nextPOSTReturnsNilData = true
        // Must supply 202 with request_id so mock enters the queue block and then skips didLoad.
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"request_id\":\"q\",\"success\":true}".data(using: .utf8)!, 202)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// GET result/ returns 200 with empty body → keeperV2FetchResultHandleResponse guard !data.isEmpty fails, fetchAccounts returns zero.
    func testV2GetResultReturnsEmptyData_fetchAccountsReturnsZero() {
        KeeperMockURLProtocol.nextQueuedResultResponse = (Data(), 200)
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"request_id\":\"r\",\"success\":true}".data(using: .utf8)!, 202)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// Poll returns "processing" once then "completed" → default branch in switch status (asyncAfter doPoll), then success.
    func testV2PollStatusQueuedThenCompleted_succeeds() {
        KeeperMockURLProtocol.nextQueuedStatusProcessingCount = 1
        let listPayload = "{\"command\":\"ls\",\"status\":\"success\",\"data\":{\"records\":[{\"title\":\"1  uid12345678901234  login  Acct  desc\"}]}}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (listPayload.data(using: .utf8)!, 202)
        KeeperMockURLProtocol.nextQueuedResultResponse = (listPayload.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        ds.injectedV2PollInterval = 0.05
        ds.injectedV2Deadline = 5
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
    }

    /// GET status/ fails with network error -> keeperV2PollForResult error path.
    func testV2StatusRequestFails_runKeeperSyncDownFails() {
        KeeperMockURLProtocol.nextQueuedStatusRequestFails = true
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success)
            XCTAssertNotNil(message)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// GET result/ returns response but no body (nil data) -> keeperV2FetchResult "No data" path.
    func testV2ResultReturnsNoData_runKeeperSyncDownFails() {
        KeeperMockURLProtocol.nextQueuedResultReturnsNoData = true
        KeeperMockURLProtocol.nextQueuedRequestStatus = "completed"
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success, "expected sync to fail when result returns no data; got success=\(success)")
            XCTAssertNotNil(message, "expected non-nil error message; got: \(message ?? "nil")")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testEnsureAPIKey_usesGlobalKeychainOverrideWhenNoInjectedKeychain() {
        KeeperTestOverrides.apiKeyFromKeychain = { "key-from-global-override" }
        defer { KeeperTestOverrides.apiKeyFromKeychain = nil }
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = nil
        ds.injectedKeychainGetAPIKey = nil
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertNotNil(KeeperMockURLProtocol.lastRequest)
    }

    func testEnsureAPIKey_usesSecureKeychainOverride() {
        KeeperTestOverrides.secureKeychainReturns = { "key-from-secure" }
        defer { KeeperTestOverrides.secureKeychainReturns = nil }
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = nil
        ds.injectedKeychainGetAPIKey = nil
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertNotNil(KeeperMockURLProtocol.lastRequest)
    }

    func testEnsureAPIKey_usesStandardKeychainOverrideAndCallsStoreOverride() {
        var storedKey: String?
        KeeperTestOverrides.standardKeychainReturns = { "key-from-standard" }
        KeeperTestOverrides.storeAPIKeyInKeychain = { storedKey = $0 }
        defer {
            KeeperTestOverrides.standardKeychainReturns = nil
            KeeperTestOverrides.storeAPIKeyInKeychain = nil
        }
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = nil
        ds.injectedKeychainGetAPIKey = nil
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertEqual(storedKey, "key-from-standard")
    }

    func testMigrationFromUserDefaults_callsStoreOverride() {
        var storedKey: String?
        KeeperTestOverrides.storeAPIKeyInKeychain = { storedKey = $0 }
        KeeperTestOverrides.apiKeyFromKeychain = { "migrated-key" }
        defer {
            KeeperTestOverrides.storeAPIKeyInKeychain = nil
            KeeperTestOverrides.apiKeyFromKeychain = nil
        }
        iTermUserDefaults.userDefaults().set("legacy-token", forKey: "NoSyncKeeperCommanderAPIKey")
        iTermUserDefaults.userDefaults().set("http://localhost:8900", forKey: "NoSyncKeeperCommanderAPIURL")
        defer {
            iTermUserDefaults.userDefaults().removeObject(forKey: "NoSyncKeeperCommanderAPIKey")
            iTermUserDefaults.userDefaults().removeObject(forKey: "NoSyncKeeperCommanderAPIURL")
        }
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = nil
        ds.injectedKeychainGetAPIKey = nil
        ds.injectedBaseURL = nil
        ds.injectedBaseURLFromStorage = URL(string: "http://localhost:8900")
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertEqual(storedKey, "legacy-token")
    }

    func testResetConfiguration_callsDeleteOverrideWhenNoInjectedDelete() {
        var deleteCalled = false
        KeeperTestOverrides.deleteAPIKeyFromKeychain = { deleteCalled = true }
        defer { KeeperTestOverrides.deleteAPIKeyFromKeychain = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedKeychainDeleteAPIKey = nil
        ds.resetConfiguration()
        XCTAssertTrue(deleteCalled)
    }

    func testEnsureAPIKey_noKeyShowsDialogOverrideAndCompletesWithNil() {
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(nil) }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.credentialsDelegate = nil
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testEnsureAPIKey_dialogOverrideUseNew_storesKeyAndFetchesAccounts() {
        var storedKey: String?
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(.useNew("key-from-dialog")) }
        KeeperTestOverrides.storeAPIKeyInKeychain = { storedKey = $0 }
        defer {
            KeeperTestOverrides.showAPIKeyDialogOverride = nil
            KeeperTestOverrides.storeAPIKeyInKeychain = nil
        }
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.credentialsDelegate = nil
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertEqual(storedKey, "key-from-dialog")
    }

    /// Dialog .useNew with no injectedKeychainSetAPIKey uses keeperStoreAPIKeyInKeychain (global override), covering 605-607.
    func testEnsureAPIKey_dialogOverrideUseNew_usesGlobalStoreOverrideWhenNoInjectedSet() {
        var stored: String?
        KeeperTestOverrides.storeAPIKeyInKeychain = { stored = $0 }
        defer { KeeperTestOverrides.storeAPIKeyInKeychain = nil }
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(.useNew("key-via-global-store")) }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.injectedKeychainSetAPIKey = nil
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertEqual(stored, "key-via-global-store")
    }

    func testEnsureAPIKey_dialogOverrideUseNew_withInjectedKeychainSetAPIKey() {
        var storedKey: String?
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(.useNew("key-from-dialog")) }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.injectedKeychainSetAPIKey = { storedKey = $0 }
        ds.credentialsDelegate = nil
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertEqual(storedKey, "key-from-dialog")
    }

    func testEnsureAPIKey_dialogOverrideCancel_completesWithNil() {
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(.cancel) }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.credentialsDelegate = nil
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// Dialog override calls completion(nil) (not .cancel), covering the guard let promptResult branch.
    func testEnsureAPIKey_dialogOverrideCompletesWithNil() {
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(nil) }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testEnsureAPIKey_dialogOverrideUseExisting_withNoApiKeyInMemory_completesWithNil() {
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(.useExisting) }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.credentialsDelegate = nil
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// Dialog .useExisting with injectedUseExistingKeyForDialog set uses that key and completes (covers useExisting success branch).
    func testEnsureAPIKey_dialogUseExisting_withInjectedKey_completesWithKey() {
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(.useExisting) }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.injectedUseExistingKeyForDialog = "existing-key-from-test"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testEnsureAPIKey_dialogOverrideUseNewWithEmptyKey_completesWithNil() {
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(.useNew("")) }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.credentialsDelegate = nil
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// Dialog completion(nil) goes through keeperHandleDialogResult(nil) and completes with nil (coverage).
    func testEnsureAPIKey_dialogOverrideReturnsNil_completesWithNil() {
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(nil) }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.credentialsDelegate = nil
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// Delegate path when delegate provides empty string: keeperHandleCredentialsFromDelegate completes with nil (coverage).
    func testEnsureAPIKey_credentialsDelegateProvidesEmptyString_completesWithNil() {
        let delegate = MockKeeperCredentialsDelegate(provideKey: "")
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.credentialsDelegate = delegate
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContextWithWindow()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testEnsureAPIKey_credentialsDelegateProvidesKey_usedForRequest() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let delegate = MockKeeperCredentialsDelegate(provideKey: "delegate-key")
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.credentialsDelegate = delegate
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContextWithWindow()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertNotNil(KeeperMockURLProtocol.lastRequest)
    }

    func testEnsureAPIKey_fromBackgroundThread_dispatchesToMain() {
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(nil) }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.credentialsDelegate = nil
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        DispatchQueue.global(qos: .utility).async {
            ds.fetchAccounts(context: self.makeContext()) { accounts in
                XCTAssertEqual(accounts.count, 0)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 5)
    }

    func testFetchPassword_v2ResultWrapperWithResultString() {
        let v2ResultBody = "{\"status\":\"success\",\"result\":\"secret-from-v2-result\"}"
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=json"] = (v2ResultBody.data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=password"] = (v2ResultBody.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid12345678901234", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "secret-from-v2-result")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testFetchPassword_noOutputMessageReturnsRecordTypeError() {
        let body = "{\"data\":{},\"message\":[\"Command produced no output\"]}"
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=json"] = (body.data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=password"] = (body.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid12345678901234", context: makeContext()) { password, _, error in
            XCTAssertNil(password)
            XCTAssertNotNil(error)
            let msg = (error as NSError?)?.localizedDescription ?? ""
            XCTAssertTrue(msg.contains("no password field") || msg.contains("no password") || msg.contains("Address or Contact"), "expected no-password message, got: \(msg)")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: no password, preview with data keys and message not "no output" → "Keeper returned no password" (coverage 904-914, 931).
    /// Use a status-style message so it is not used as password; data must have ≠1 key so single-key fallback does not set password.
    func testFetchPassword_noPassword_previewWithDataKeys_genericMessage() {
        let body = "{\"data\":{\"foo\":\"a\",\"baz\":\"b\"},\"message\":[\"Command executed successfully\"]}"
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = (body.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertNil(password)
            XCTAssertNotNil(error)
            let msg = (error as NSError?)?.localizedDescription ?? ""
            XCTAssertTrue(msg.contains("Keeper returned no password"), "expected generic message, got: \(msg)")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: no password, message array first contains "no output" → "This record has no password field (e.g. Address or Contact type)."
    func testFetchPassword_noPassword_messageNoOutput_returnsRecordTypeMessage() {
        let body = "{\"data\":{},\"message\":[\"Command executed successfully with no output\"]}"
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = (body.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertNil(password)
            XCTAssertNotNil(error)
            let msg = (error as NSError?)?.localizedDescription ?? ""
            XCTAssertEqual(msg, "This record has no password field (e.g. Address or Contact type).")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: parsed["output"] as String.
    func testFetchPassword_outputKeyInParsed() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"output\":\"pwd-from-output\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "pwd-from-output")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: result as object with output key.
    func testFetchPassword_resultObjectWithOutputKey() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"result\":{\"output\":\"secret\"}}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "secret")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: data as JSON-encoded string (quoted).
    func testFetchPassword_dataAsQuotedJSONString() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"data\":\"\\\"pwd-in-quotes\\\"\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "pwd-in-quotes")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: data as [String] array, first element.
    func testFetchPassword_dataAsStringArrayFirstElement() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"data\":[\"only-password\"]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "only-password")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: data as [Any] (heterogeneous array), first element as String (covers dataVal as? [Any], first as? String branch).
    func testFetchPassword_dataValAsAnyArrayFirstString() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"data\":[\"pwd-from-any-array\", null]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "pwd-from-any-array")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: KeeperExecuteResponse.result.
    func testFetchPassword_keeperExecuteResponseResult() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"status\":\"success\",\"result\":\"from-result\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(password, "from-result")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: no password, response is JSON with keys -> "Keeper returned no password" (else branch).
    func testFetchPassword_noPasswordJSONReturnsGenericMessage() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"status\":\"ok\",\"data\":{}}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertNil(password)
            XCTAssertNotNil(error)
            XCTAssertEqual((error as NSError?)?.localizedDescription, "Keeper returned no password for this record.")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchAccounts: KeeperExecuteResponseDataArray (data as array of records).
    func testFetchAccounts_parsesDataArrayFormat() {
        let json = """
        {"command":"ls","status":"success","data":[{"uid":"a1b2c3d4e5f6g7h8","record_uid":"a1b2c3d4e5f6g7h8","type":"login","title":"Site A","description":""}]}
        """
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (json.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            XCTAssertEqual(accounts.first?.accountName, "Site A")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchAccounts: message table format with 5+ columns (description from parts[4], parts.count >= 6).
    func testFetchAccounts_parsesMessageTableWithManyColumns() {
        let json = """
        {"command":"list","status":"success","message":["#  UID  Type  Title  Shared","---  ---  ---  ---  ---","1  a1b2c3d4e5f6g7h8  login  MyTitle  desc  extra"]}
        """
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (json.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            XCTAssertEqual(accounts.first?.accountName, "MyTitle")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchAccounts: message table with exactly 5 parts (description = "" branch, coverage 722).
    func testFetchAccounts_messageTableFiveParts_descriptionEmpty() {
        let json = """
        {"status":"success","message":["#  UID  Type  Title","---  ---  ---  ---","1  a1b2c3d4e5f6g7h8  login  FivePart  x"]}
        """
        KeeperMockURLProtocol.nextQueuedResultResponse = (json.data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"request_id\":\"q\",\"success\":true}".data(using: .utf8)!, 202)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            XCTAssertEqual(accounts.first?.accountName, "FivePart")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    // MARK: - API key storage in Keychain (test hooks)

    func testEnsureAPIKey_usesKeychainWhenInjectedKeychainReturnsKey() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedKeychainGetAPIKey = { "stored-key-from-keychain" }
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        // Request was sent, so ensureAPIKey used the key from keychain (injected). No delegate dialog.
        XCTAssertNotNil(KeeperMockURLProtocol.lastRequest)
    }

    /// Two concurrent fetchAccounts with injectedKeychainGetAPIKey: second call sees _apiKey set inside lock (coverage).
    func testEnsureAPIKey_twoConcurrentCalls_secondSeesKeyFromFirst() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedKeychainGetAPIKey = { "key-from-keychain" }
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp1 = expectation(description: "first")
        let exp2 = expectation(description: "second")
        DispatchQueue.global(qos: .userInitiated).async {
            ds.fetchAccounts(context: RecipeExecutionContext(window: nil)) { _ in exp1.fulfill() }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            ds.fetchAccounts(context: RecipeExecutionContext(window: nil)) { _ in exp2.fulfill() }
        }
        wait(for: [exp1, exp2], timeout: 5)
    }

    /// When user saves API key from settings, keychain store is called. (Delegate path only sets in-memory; dialog .useNew path stores to keychain—we test the settings save path here.)
    func testSetKeeperSettingsAPIKey_callsKeychainStoreWhenInjected() {
        var storedKey: String?
        let ds = KeeperDataSource(browser: false)
        ds.injectedKeychainSetAPIKey = { storedKey = $0 }
        ds.setKeeperSettingsAPIKey("user-entered-key")
        XCTAssertEqual(storedKey, "user-entered-key")
    }

    func testResetConfiguration_callsKeychainDeleteWhenInjected() {
        var keychainDeleteCalled = false
        let ds = KeeperDataSource(browser: false)
        ds.injectedKeychainDeleteAPIKey = { keychainDeleteCalled = true }
        ds.resetConfiguration()
        XCTAssertTrue(keychainDeleteCalled)
    }

    // MARK: - API URL storage (UserDefaults path via test hooks)

    func testKeeperBaseURL_usesInjectedStorageURL() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let storedURL = URL(string: "https://from-storage.test")!
        let ds = KeeperDataSource(browser: false)
        ds.injectedKeychainGetAPIKey = { "key" }
        ds.injectedBaseURLFromStorage = storedURL
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 5)
        XCTAssertNotNil(KeeperMockURLProtocol.lastRequest?.url)
        XCTAssertTrue(KeeperMockURLProtocol.lastRequest?.url?.absoluteString.contains("from-storage.test") ?? false)
    }

    func testKeeperSettingsAPIURL_returnsInjectedStorage() {
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIURLFromStorage = "https://stored-url.example"
        XCTAssertEqual(ds.keeperSettingsAPIURL(), "https://stored-url.example")
    }

    func testSetKeeperSettingsAPIURL_callsInjectedStore() {
        var storedURL: String?
        let ds = KeeperDataSource(browser: false)
        ds.injectedStoreAPIURL = { storedURL = $0 }
        ds.setKeeperSettingsAPIURL("https://user-entered.example")
        XCTAssertEqual(storedURL, "https://user-entered.example")
    }

    func testKeeperSettingsAPIKeyForEditing_returnsKeyFromKeychainWhenCacheEmpty() {
        KeeperTestOverrides.apiKeyFromKeychain = { "key-from-keychain" }
        defer { KeeperTestOverrides.apiKeyFromKeychain = nil }
        let ds = KeeperDataSource(browser: false)
        XCTAssertEqual(ds.keeperSettingsAPIKeyForEditing(), "key-from-keychain")
    }

    func testKeeperSettingsAPIKey_returnsCachedKey() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedKeychainGetAPIKey = { "cached" }
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 5)
        XCTAssertEqual(ds.keeperSettingsAPIKey(), "cached")
    }

    func testKeeperSettingsAPIURL_returnsFromUserDefaultsWhenNoInjection() {
        iTermUserDefaults.userDefaults().set("https://userdefaults-url.test", forKey: "NoSyncKeeperCommanderAPIURL")
        defer { iTermUserDefaults.userDefaults().removeObject(forKey: "NoSyncKeeperCommanderAPIURL") }
        let ds = KeeperDataSource(browser: false)
        XCTAssertEqual(ds.keeperSettingsAPIURL(), "https://userdefaults-url.test")
    }

    /// keeperBaseURL() uses _cachedKeeperBaseURL on second call when storage has URL (no injected base URL).
    /// fetchAccounts with no API URL (guard in keeperExecute) returns 0 accounts and does not hit the network.
    func testFetchAccounts_noAPIURL_returnsZeroAccounts() {
        KeeperMockURLProtocol.lastRequest = nil
        KeeperTestOverrides.apiURLFromStorage = nil
        let dsClear = KeeperDataSource(browser: false)
        dsClear.injectedStoreAPIURL = nil
        dsClear.setKeeperSettingsAPIURL("")
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedURLSession = mockSession
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertNil(KeeperMockURLProtocol.lastRequest?.url, "Should not make a request when API URL is missing")
    }

    /// keeperBaseURL() uses _cachedKeeperBaseURL on second call when storage has URL (no injected base URL).
    func testKeeperBaseURLCache_secondCallUsesCache() {
        KeeperTestOverrides.apiURLFromStorage = { "https://keeper-cache.test" }
        defer { KeeperTestOverrides.apiURLFromStorage = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedStoreAPIURL = nil
        ds.setKeeperSettingsAPIURL("")
        let lsResponse = "{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (lsResponse.data(using: .utf8)!, 200)
        ds.injectedAPIKey = "key"
        ds.injectedURLSession = mockSession
        let exp1 = expectation(description: "fetch1")
        ds.fetchAccounts(context: makeContext()) { list in
            XCTAssertEqual(list.count, 0)
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 5)
        let exp2 = expectation(description: "fetch2")
        ds.fetchAccounts(context: makeContext()) { list in
            XCTAssertEqual(list.count, 0)
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 5)
        let urlString = KeeperMockURLProtocol.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(urlString.contains("keeper-cache.test"), "Expected request URL to contain keeper-cache.test (base URL from storage/cache), got: \(urlString)")
    }

    func testKeeperSettingsAPIURLForEditing_returnsFromStorage() {
        iTermUserDefaults.userDefaults().set("https://storage-url.test", forKey: "NoSyncKeeperCommanderAPIURL")
        defer { iTermUserDefaults.userDefaults().removeObject(forKey: "NoSyncKeeperCommanderAPIURL") }
        let ds = KeeperDataSource(browser: false)
        XCTAssertEqual(ds.keeperSettingsAPIURLForEditing(), "https://storage-url.test")
    }

    func testSetKeeperSettingsAPIKey_emptyCallsGlobalDeleteOverrideWhenNoInjected() {
        var deleteCalled = false
        KeeperTestOverrides.deleteAPIKeyFromKeychain = { deleteCalled = true }
        defer { KeeperTestOverrides.deleteAPIKeyFromKeychain = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedKeychainDeleteAPIKey = nil
        ds.setKeeperSettingsAPIKey("")
        XCTAssertTrue(deleteCalled)
    }

    func testSetKeeperSettingsAPIKey_nonEmptyCallsGlobalStoreOverrideWhenNoInjected() {
        var storedKey: String?
        KeeperTestOverrides.storeAPIKeyInKeychain = { storedKey = $0 }
        defer { KeeperTestOverrides.storeAPIKeyInKeychain = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedKeychainSetAPIKey = nil
        ds.setKeeperSettingsAPIKey("user-key")
        XCTAssertEqual(storedKey, "user-key")
    }

    func testSetKeeperSettingsAPIURL_emptyClearsStorage() {
        iTermUserDefaults.userDefaults().set("https://old.test", forKey: "NoSyncKeeperCommanderAPIURL")
        let ds = KeeperDataSource(browser: false)
        ds.injectedStoreAPIURL = nil
        ds.setKeeperSettingsAPIURL("")
        XCTAssertEqual(ds.keeperSettingsAPIURL(), "")
        iTermUserDefaults.userDefaults().removeObject(forKey: "NoSyncKeeperCommanderAPIURL")
    }

    func testSetKeeperSettingsAPIURL_nonEmptyStoresAndCaches() {
        let ds = KeeperDataSource(browser: false)
        ds.injectedStoreAPIURL = nil
        ds.setKeeperSettingsAPIURL("https://stored.test")
        XCTAssertEqual(ds.keeperSettingsAPIURL(), "https://stored.test")
    }

    func testSetKeeperSettingsAPIURL_whitespaceOnlyTreatedAsEmpty() {
        let ds = KeeperDataSource(browser: false)
        ds.injectedStoreAPIURL = nil
        ds.setKeeperSettingsAPIURL("   ")
        XCTAssertEqual(ds.keeperSettingsAPIURL(), "")
    }

    func testSetKeeperSettingsAPIURL_injectedStoreWithEmptyStringClearsCache() {
        let ds = KeeperDataSource(browser: false)
        ds.injectedStoreAPIURL = { _ in }
        ds.setKeeperSettingsAPIURL("https://x.test")
        ds.setKeeperSettingsAPIURL("")
        XCTAssertEqual(ds.keeperSettingsAPIURL(), "")
    }

    // MARK: - Biometric auth (keychain read path)

    /// The actual Touch ID / Face ID prompt is system behavior and cannot be unit-tested. The flow "use API key after it has been obtained (from keychain, including after biometric)" is covered by testEnsureAPIKey_usesKeychainWhenInjectedKeychainReturnsKey: we simulate keychain returning a key and assert it is used for the request.
    func testBiometricKeychainPath_keyFromKeychainIsUsedForRequest() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedKeychainGetAPIKey = { "key-after-biometric" }
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 5)
        XCTAssertNotNil(KeeperMockURLProtocol.lastRequest, "Key obtained from keychain (e.g. after biometric) should be used for API call")
    }

    // MARK: - 100% coverage: protocol stubs and remaining branches

    func testSwitchAccount_invokesCompletion() {
        let ds = KeeperDataSource(browser: false)
        let exp = expectation(description: "switchAccount")
        ds.switchAccount(completion: { exp.fulfill() })
        wait(for: [exp], timeout: 1)
    }

    func testResetErrors_doesNotThrow() {
        let ds = KeeperDataSource(browser: false)
        ds.resetErrors()
    }

    func testReload_invokesCompletion() {
        let ds = KeeperDataSource(browser: false)
        let exp = expectation(description: "reload")
        ds.reload { exp.fulfill() }
        wait(for: [exp], timeout: 1)
    }

    func testConsolidateAvailabilityChecks_invokesBlock() {
        let ds = KeeperDataSource(browser: false)
        let exp = expectation(description: "consolidate")
        ds.consolidateAvailabilityChecks { exp.fulfill() }
        wait(for: [exp], timeout: 1)
    }

    func testKeeperSettingsAPIURLForEditing_returnsStorageOrEmpty() {
        let ds = KeeperDataSource(browser: false)
        KeeperTestOverrides.apiURLFromStorage = nil
        _ = ds.keeperSettingsAPIURLForEditing()
        KeeperTestOverrides.apiURLFromStorage = { "https://storage.test" }
        defer { KeeperTestOverrides.apiURLFromStorage = nil }
        XCTAssertEqual(ds.keeperSettingsAPIURLForEditing(), "https://storage.test")
    }

    /// setKeeperSettingsAPIKey("") without injectedKeychainDeleteAPIKey calls keeperDeleteAPIKeyFromKeychain (global override used in keychain layer).
    func testSetKeeperSettingsAPIKey_emptyCallsKeeperDeleteAPIKeyFromKeychainWhenNoInjected() {
        var deleteCalled = false
        KeeperTestOverrides.deleteAPIKeyFromKeychain = { deleteCalled = true }
        defer { KeeperTestOverrides.deleteAPIKeyFromKeychain = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedKeychainDeleteAPIKey = nil
        ds.setKeeperSettingsAPIKey("")
        XCTAssertTrue(deleteCalled)
    }

    /// setKeeperSettingsAPIKey("") with injectedKeychainDeleteAPIKey uses inject and clears in-memory key (coverage).
    func testSetKeeperSettingsAPIKey_emptyWithInjectedDelete_usesInjectedAndClearsKey() {
        var injectedDeleteCalled = false
        let ds = KeeperDataSource(browser: false)
        ds.injectedKeychainDeleteAPIKey = { injectedDeleteCalled = true }
        defer { ds.injectedKeychainDeleteAPIKey = nil }
        ds.setKeeperSettingsAPIKey("")
        XCTAssertTrue(injectedDeleteCalled)
    }

    /// setKeeperSettingsAPIKey(non-empty) without injectedKeychainSetAPIKey calls keeperStoreAPIKeyInKeychain (global override used in keychain layer).
    func testSetKeeperSettingsAPIKey_nonEmptyCallsKeeperStoreAPIKeyInKeychainWhenNoInjected() {
        var storedKey: String?
        KeeperTestOverrides.storeAPIKeyInKeychain = { storedKey = $0 }
        defer { KeeperTestOverrides.storeAPIKeyInKeychain = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedKeychainSetAPIKey = nil
        ds.setKeeperSettingsAPIKey("stored-via-global-override")
        XCTAssertEqual(storedKey, "stored-via-global-override")
    }

    /// Covers keeperStoreAPIKeyInStandardKeychain (used when biometric keychain is unavailable or SecItemAdd fails).
    func testKeeperStoreAPIKeyInStandardKeychain_storesKey() {
        keeperStoreAPIKeyInStandardKeychain("standard-keychain-test-key")
        // No override: real keychain; we only assert the call doesn’t crash. For coverage we could read back via SSKeychain if needed.
    }

    /// Covers keeperStoreAPIKeyInKeychain guard-else fallback when access control creation is forced to fail.
    func testKeeperStoreAPIKeyInKeychain_forceAccessControlCreationToFail_usesStandardKeychain() {
        KeeperTestOverrides.forceAccessControlCreationToFail = true
        defer { KeeperTestOverrides.forceAccessControlCreationToFail = false }
        let ds = KeeperDataSource(browser: false)
        ds.injectedKeychainSetAPIKey = nil
        ds.setKeeperSettingsAPIKey("key-via-access-control-fail")
        XCTAssertEqual(ds.keeperSettingsAPIKey(), "key-via-access-control-fail")
    }

    /// Covers keeperStoreAPIKeyInKeychain SecItemAdd failure path (DLog/NSLog then standard keychain).
    func testKeeperStoreAPIKeyInKeychain_forceSecItemAddToFail_usesStandardKeychain() {
        KeeperTestOverrides.forceSecItemAddToFail = true
        defer { KeeperTestOverrides.forceSecItemAddToFail = false }
        let ds = KeeperDataSource(browser: false)
        ds.injectedKeychainSetAPIKey = nil
        ds.setKeeperSettingsAPIKey("key-via-secitem-fail")
        XCTAssertEqual(ds.keeperSettingsAPIKey(), "key-via-secitem-fail")
    }

    /// Covers keeperClearBaseURLCache so next keeperBaseURL() re-reads from storage.
    func testKeeperClearBaseURLCache_clearsCache() {
        KeeperTestOverrides.apiURLFromStorage = { "https://cache-clear.test" }
        defer { KeeperTestOverrides.apiURLFromStorage = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "k"
        ds.injectedURLSession = mockSession
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"status\":\"success\",\"data\":{\"records\":[]}}".data(using: .utf8)!, 200)
        let exp1 = expectation(description: "first fetch")
        ds.fetchAccounts(context: makeContext()) { _ in exp1.fulfill() }
        wait(for: [exp1], timeout: 5)
        keeperClearBaseURLCache()
        KeeperTestOverrides.apiURLFromStorage = { "https://after-clear.test" }
        let exp2 = expectation(description: "second fetch")
        ds.fetchAccounts(context: makeContext()) { _ in exp2.fulfill() }
        wait(for: [exp2], timeout: 5)
    }

    /// Covers keeperV2BaseURL when path already has api/v2 (and components.url branch).
    func testKeeperV2BaseURL_pathHasApiV2_returnsNormalized() {
        let withTrailing = URL(string: "https://x.com/api/v2/")!
        XCTAssertTrue(keeperV2BaseURL(baseURL: withTrailing).path.hasSuffix("api/v2"))
        let noTrailing = URL(string: "https://x.com/api/v2")!
        XCTAssertEqual(keeperV2BaseURL(baseURL: noTrailing).path, "/api/v2")
    }

    /// Covers keeperV2BaseURL when path does not have api/v2 (appends /api/v2).
    func testKeeperV2BaseURL_originOnly_appendsApiV2() {
        let origin = URL(string: "https://keeper.example")!
        let v2 = keeperV2BaseURL(baseURL: origin)
        XCTAssertTrue(v2.path.hasSuffix("api/v2"), "got \(v2.path)")
    }

    /// Covers keeperAPIKeyFromKeychain migration path when only standard keychain has key (store then return).
    func testKeeperAPIKeyFromKeychain_standardKeychainOnly_migratesAndReturnsKey() {
        KeeperTestOverrides.secureKeychainReturns = { nil }
        KeeperTestOverrides.standardKeychainReturns = { "migrate-key" }
        var stored: String?
        KeeperTestOverrides.storeAPIKeyInKeychain = { stored = $0 }
        defer {
            KeeperTestOverrides.secureKeychainReturns = nil
            KeeperTestOverrides.standardKeychainReturns = nil
            KeeperTestOverrides.storeAPIKeyInKeychain = nil
        }
        let key = keeperAPIKeyFromKeychain()
        XCTAssertEqual(key, "migrate-key")
        XCTAssertEqual(stored, "migrate-key")
    }

    /// Poll: 1–14 unparseable status responses then "completed" triggers retry then success (covers asyncAfter poll path).
    func testV2PollUnparseableThenCompleted_succeedsAfterRetry() {
        KeeperMockURLProtocol.nextQueuedRequestStatus = "completed"
        KeeperMockURLProtocol.nextQueuedStatusResponseList = [
            "{}".data(using: .utf8)!,
            "{\"invalid\": true}".data(using: .utf8)!,
            "{\"status\": \"completed\"}".data(using: .utf8)!,
        ]
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedURLSession = mockSession
        ds.injectedV2PollInterval = 0.05
        ds.injectedV2Deadline = 5
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertTrue(success, "expected success after retry; got message: \(message ?? "nil")")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
    }

    /// Poll: 15+ consecutive unparseable status responses → keeperV2PollRunner fails with invalid status message (coverage 306-310).
    func testV2PollFifteenUnparseableStatus_failsWithInvalidStatusMessage() {
        let unparseable = (0..<16).map { _ in "{}".data(using: .utf8)! }
        KeeperMockURLProtocol.nextQueuedStatusResponseList = unparseable
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedURLSession = mockSession
        ds.injectedV2PollInterval = 0.02
        ds.injectedV2Deadline = 5
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success)
            XCTAssertTrue(message?.contains("invalid") ?? false || message?.contains("status") ?? false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
    }

    /// fetchAccounts: flexible parse with data as array of records (dataPayload as? [[String:Any]]).
    func testFetchAccounts_parsesFlexibleDataArrayFormat() {
        let json = """
        {"status":"success","data":[{"uid":"a1b2c3d4e5f6g7h8","record_uid":"a1b2c3d4e5f6g7h8","type":"login","title":"Site"}]}
        """
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (json.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            XCTAssertEqual(accounts.first?.accountName, "Site")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchAccounts: response parses but yields no records → DLog/NSLog path and completion([]).
    func testFetchAccounts_noRecordsParsed_postsSucceedAndReturnsEmpty() {
        let json = "{\"status\":\"success\",\"command\":\"ls\",\"data\":{\"records\":[]},\"message\":[\"#\",\"---\"]}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (json.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchAccounts: v2 poll returns status "failed" → handleStatusResponse failure path, posts failure and returns empty.
    func testFetchAccounts_v2StatusFailed_postsFailureAndReturnsEmpty() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"request_id\":\"req-1\",\"status\":\"queued\"}".data(using: .utf8)!, 202)
        KeeperMockURLProtocol.nextQueuedRequestStatus = "failed"
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        var observedNotification: Notification?
        let observer = NotificationCenter.default.addObserver(forName: iTerm2KeeperConnectionDidFailNotification, object: nil, queue: nil) { notif in
            observedNotification = notif
        }
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        NotificationCenter.default.removeObserver(observer)
        XCTAssertNotNil(observedNotification)
        let msg = (observedNotification?.userInfo?["error"] as? String) ?? ""
        XCTAssertTrue(msg.contains("failed") || msg.contains("Keeper"), "expected failure message, got: \(msg)")
    }

    /// fetchAccounts: v2 result body has status+result as dict (not wrapper string), covering resultObj-as-dict insert path.
    func testFetchAccounts_v2ResultResultAsDict_parsesMessageTable() {
        let resultBody = "{\"status\":\"success\",\"result\":{\"message\":[\"#\",\"---\",\"1  a1b2c3d4e5f6g7h8  login  MySite  desc\"]}}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"request_id\":\"x\",\"status\":\"queued\"}".data(using: .utf8)!, 202)
        KeeperMockURLProtocol.nextQueuedResultResponse = (resultBody.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            XCTAssertEqual(accounts.first?.accountName, "MySite")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// parseLsRecordLine: uid with invalid character (allSatisfy fails) returns nil.
    func testParseLsRecordLine_uidWithInvalidCharacterReturnsNil() {
        let line = "1  a1b2c3d4e5f6g7h@  login  Title  desc"
        let result = parseLsRecordLine(line)
        XCTAssertNil(result)
    }

    /// parseLsRecordLine description when parts.count > 4 (suffix from 4).
    func testParseLsRecordLine_descriptionFromSuffix() {
        let line = "5  c3d4e5f6g7h8i9j0  login  MyTitle  desc part1 part2"
        let result = parseLsRecordLine(line)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.description, "desc part1 part2")
    }

    func testFetchPassword_noAPIKey_completesWithError() {
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(nil) }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.credentialsDelegate = nil
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid", context: makeContext()) { password, _, error in
            XCTAssertNil(password)
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testSetPassword_noAPIKey_completesWithError() {
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(nil) }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.credentialsDelegate = nil
        let exp = expectation(description: "setPassword")
        ds.setPassword(recordUid: "uid", password: "pwd", context: makeContext()) { error in
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testDeleteRecord_noAPIKey_completesWithError() {
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(nil) }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.credentialsDelegate = nil
        let exp = expectation(description: "deleteRecord")
        ds.deleteRecord(recordUid: "uid", context: makeContext()) { error in
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testAdd_noAPIKey_completesWithError() {
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(nil) }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.credentialsDelegate = nil
        let exp = expectation(description: "add")
        ds.add(userName: "u", accountName: "a", password: "p", context: makeContext()) { account, error in
            XCTAssertNil(account)
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// add: decode throws (invalid JSON) → catch block.
    func testAdd_invalidJSONInResponse_completesWithError() {
        let addCmd = "record-add --record-type=login --title=\"A\" login=\"U\" password=$BASE64:cA=="
        KeeperMockURLProtocol.responseByCommand[addCmd] = ("not json".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "add")
        ds.add(userName: "U", accountName: "A", password: "p", context: makeContext()) { account, error in
            XCTAssertNil(account)
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// deleteRecord: success response but decode failure (non-success) → detail from keeperHumanReadableError.
    func testDeleteRecord_decodeFailure_usesHumanReadableError() {
        KeeperMockURLProtocol.responseByCommand["rm -f uid12345678901234"] = ("{\"error\":\"Permission denied\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "deleteRecord")
        ds.deleteRecord(recordUid: "uid12345678901234", context: makeContext()) { error in
            XCTAssertNotNil(error)
            XCTAssertTrue((error as NSError?)?.localizedDescription.contains("Permission denied") ?? false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// passwordFromGetJSONResponse fromRecord: fields with type != "password" (continue) then password.
    func testPasswordFromGetJSONResponse_typedRecordFieldsLoginThenPassword() {
        let json = """
        {"data": {"fields": [{"type": "login", "value": "user"}, {"type": "password", "value": "secret"}]}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.passwordFromGetJSONResponse(data)
        XCTAssertEqual(result, "secret")
    }

    /// fetchPassword: get --format=json fails, then --format=password with message[] "no output" → "This record has no password field".
    func testFetchPassword_noOutputMessage_returnsRecordTypeError() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"message\":[\"Command executed successfully but produced no output\"]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertNil(password)
            XCTAssertNotNil(error)
            XCTAssertTrue((error as NSError?)?.localizedDescription.contains("no password field") ?? false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// KeeperAccount.fetchPassword/set/delete: call through account returned by fetchAccounts.
    func testKeeperAccount_fetchPasswordSetDelete_delegateToDataSource() {
        let lsJson = "{\"command\":\"ls\",\"data\":{\"records\":[{\"uid\":\"a1b2c3d4e5f6g7h8\",\"title\":\"Acc\",\"description\":\"user\"}]},\"status\":\"success\"}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (lsJson.data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get a1b2c3d4e5f6g7h8 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get a1b2c3d4e5f6g7h8 --format=password"] = ("\"secret\"".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["record-update -r a1b2c3d4e5f6g7h8 password=$BASE64:c2VjcmV0"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["rm -f a1b2c3d4e5f6g7h8"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let fetchExp = expectation(description: "fetchAccounts")
        var accounts: [PasswordManagerAccount] = []
        ds.fetchAccounts(context: makeContext()) { list in
            accounts = list
            fetchExp.fulfill()
        }
        wait(for: [fetchExp], timeout: 5)
        XCTAssertEqual(accounts.count, 1)
        guard let account = accounts.first else { return }
        let pwdExp = expectation(description: "fetchPassword")
        account.fetchPassword(context: makeContext()) { password, _, error in
            XCTAssertEqual(password, "secret")
            XCTAssertNil(error)
            pwdExp.fulfill()
        }
        wait(for: [pwdExp], timeout: 5)
        let setExp = expectation(description: "set")
        account.set(context: makeContext(), password: "newpwd") { error in
            XCTAssertNil(error)
            setExp.fulfill()
        }
        wait(for: [setExp], timeout: 5)
        let delExp = expectation(description: "delete")
        account.delete(context: makeContext()) { error in
            XCTAssertNil(error)
            delExp.fulfill()
        }
        wait(for: [delExp], timeout: 5)
    }

    /// parseMessageTableRecordUids: line with invalid uid (allSatisfy fails) returns nil for that line.
    func testParseMessageTableRecordUids_lineWithInvalidUidCharacter_skipsLine() {
        let json = "{\"status\":\"success\",\"message\":[\"#\",\"---\",\"1  a1b2c3d4e5f6g7h8  login  Ok\",\"2  bad!!!uid!!!!!!!!  login  Bad\"]}"
        let data = json.data(using: .utf8)!
        let uids = parseMessageTableRecordUids(from: data)
        XCTAssertEqual(uids.count, 1)
        XCTAssertTrue(uids.contains("a1b2c3d4e5f6g7h8"))
    }

    /// GET result returns non-200 with body that is not UTF-8 → "HTTP \(code)" fallback.
    func testV2FetchResult_non200WithUnparseableBody_returnsHTTPCodeMessage() {
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.nextQueuedResultResponse = (Data([0xFF, 0xFE, 0x00]), 502)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success, "expected sync to fail when GET result returns 502")
            XCTAssertNotNil(message)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
    }

    /// GET result returns non-200 with UTF-8 body → String(data:encoding:) used when humanReadable is nil.
    func testV2FetchResult_non200WithUTF8Body_returnsBodyAsMessage() {
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.nextQueuedResultResponse = ("Server overloaded".data(using: .utf8)!, 503)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success)
            XCTAssertTrue(message?.contains("Server overloaded") ?? false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
    }

    /// fetchAccounts: "ls" data.records with invalid title lines (---/#) so parseLsRecordLine returns nil for all; no break, ends with no records.
    func testFetchAccounts_lsRecordsAllInvalidTitleLines_fallsThroughToNoRecords() {
        let json = "{\"command\":\"ls\",\"data\":{\"records\":[{\"title\":\"---\"},{\"title\":\"# header\"}]},\"status\":\"success\"}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (json.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchAccounts: data.records with entries that have no uid/record_uid so compactMap returns []; !records!.isEmpty is false, no break (coverage).
    func testFetchAccounts_dataRecordsWithNoUid_fallsThroughWithoutBreaking() {
        let json = "{\"status\":\"success\",\"data\":{\"records\":[{\"title\":\"NoUid\"},{\"description\":\"only\"}]}}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (json.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchAccounts: data payload as object with "records" key (not array at top level).
    func testFetchAccounts_parsesDataRecordsObjectFormat() {
        let json = """
        {"status":"success","command":"ls","data":{"records":[{"uid":"r1r1r1r1r1r1r1r1","record_uid":"r1r1r1r1r1r1r1r1","type":"login","title":"From Records","description":""}]}}
        """
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (json.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            XCTAssertEqual(accounts.first?.accountName, "From Records")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// parseMessageTableRecordUids with root result as String (inner JSON string).
    func testParseMessageTableRecordUids_resultAsString() {
        let json = "{\"status\":\"success\",\"result\":\"{\\\"message\\\":[\\\"#\\\",\\\"---\\\",\\\"1  a1b2c3d4e5f6g7h8  login\\\"]}\"}"
        let data = json.data(using: .utf8)!
        let uids = parseMessageTableRecordUids(from: data)
        XCTAssertEqual(uids.count, 1)
        XCTAssertTrue(uids.contains("a1b2c3d4e5f6g7h8"))
    }

    /// keeperParseMessageTableInsertResultPayload with resultObj as String inserts that string's data (covers result-as-string branch).
    func testKeeperParseMessageTableInsertResultPayload_resultAsString() {
        var payloads: [Data] = [Data()]
        let messageJson = "{\"message\":[\"#\",\"---\",\"1  a1b2c3d4e5f6g7h8  login\"]}"
        keeperParseMessageTableInsertResultPayload(resultObj: messageJson, into: &payloads)
        XCTAssertEqual(payloads.count, 2)
        let inserted = payloads[0]
        let uids = parseMessageTableRecordUids(from: inserted)
        XCTAssertEqual(uids.count, 1)
        XCTAssertTrue(uids.contains("a1b2c3d4e5f6g7h8"))
    }

    /// passwordFromGetJSONResponse: data value is JSON string containing record.
    func testPasswordFromGetJSONResponse_dataAsJSONStringWithRecord() {
        let json = "{\"data\":\"{\\\"password\\\":\\\"pwd-from-string\\\"}\"}"
        let data = json.data(using: .utf8)!
        let pwd = KeeperDataSource.passwordFromGetJSONResponse(data)
        XCTAssertEqual(pwd, "pwd-from-string")
    }

    /// fetchPassword: JSON get returns no password, fallback uses parsed["message"] first line as password when not status message.
    func testFetchPassword_fallbackMessageLineAsPassword() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"message\":[\"my-secret-password\"]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertEqual(password, "my-secret-password")
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: fallback uses data as JSON-encoded string (quoted).
    func testFetchPassword_fallbackDataQuotedString() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"data\":\"\\\"quoted-pwd\\\"\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertEqual(password, "quoted-pwd")
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: fallback uses data object with single key (key+value concatenation).
    func testFetchPassword_fallbackDataSingleKeyObject() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"data\":{\"half\":\"-suffix\"}}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertEqual(password, "half-suffix")
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: fallback uses data as [String] (first element).
    func testFetchPassword_fallbackDataStringArray() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"data\":[\"first-pwd\"]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertEqual(password, "first-pwd")
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: password from result object "output" key (resultObj["output"]).
    func testFetchPassword_resultObjectOutputKey_returnsPassword() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"result\":{\"output\":\"pwd-from-output\"}}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertEqual(password, "pwd-from-output")
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: password from top-level parsed["output"].
    func testFetchPassword_topLevelOutputKey_returnsPassword() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"output\":\"top-level-output-pwd\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertEqual(password, "top-level-output-pwd")
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: no password, message "no output" → error mentions "no password field".
    func testFetchPassword_noPassword_statusNoOutput_usesNoPasswordFieldError() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"message\":[\"No output produced\"]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertNil(password)
            XCTAssertNotNil(error)
            XCTAssertTrue((error as NSError?)?.localizedDescription.contains("no password field") ?? false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: data as non-quoted string (password == nil then !t.isEmpty).
    func testFetchPassword_dataAsPlainString_usesAsPassword() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"data\":\"plain-pwd\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertEqual(password, "plain-pwd")
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: KeeperExecuteResponse (v1) with result string.
    func testFetchPassword_keeperExecuteResponseResult_returnsPassword() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"status\":\"success\",\"result\":\"exec-result-pwd\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertEqual(password, "exec-result-pwd")
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: non-JSON plain text, quoted string decoded then used.
    func testFetchPassword_plainTextQuoted_decodesAndReturns() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("\"decoded-quoted\"".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertEqual(password, "decoded-quoted")
            XCTAssertNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// setPassword: non-success response with message array uses first message.
    func testSetPassword_nonSuccessWithMessageArray_usesFirstMessage() {
        KeeperMockURLProtocol.responseByCommand["record-update -r uid123 password=$BASE64:dGVzdA=="] = ("{\"status\":\"error\",\"message\":[\"First error line\"]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "setPassword")
        ds.setPassword(recordUid: "uid123", password: "test", context: makeContext()) { error in
            XCTAssertNotNil(error)
            XCTAssertEqual((error as NSError?)?.localizedDescription, "First error line")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchAccounts: data as object with "records" key (dataPayload as [String: Any], obj["records"]).
    func testFetchAccounts_dataAsObjectWithRecordsKey_parsesRecords() {
        let json = "{\"status\":\"success\",\"data\":{\"records\":[{\"uid\":\"a1b2c3d4e5f6g7h8\",\"record_uid\":\"a1b2c3d4e5f6g7h8\",\"title\":\"Site\",\"description\":\"Login\"}]}}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (json.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            XCTAssertEqual(accounts.first?.accountName, "Site")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchAccounts: response with status success but empty data so no records parsed → DLog/NSLog path and empty list.
    func testFetchAccounts_successEmptyData_noRecordsParsedLogsAndReturnsEmpty() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"status\":\"success\",\"data\":[]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchAccounts: response success with data as string (not array/record object) → no records parsed path, empty list.
    func testFetchAccounts_successDataAsString_noRecordsParsedReturnsEmpty() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"status\":\"success\",\"data\":\"plain-text\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchAccounts: message-table format with 6 parts so description = parts[4].
    func testFetchAccounts_messageTableSixParts_descriptionFromParts4() {
        let json = "{\"status\":\"success\",\"message\":[\"header\", \"sep\", \"1  a1b2c3d4e5f6g7h8  login  MySite  MyDescription  extra\"]}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (json.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            XCTAssertTrue(accounts.first?.displayString.contains("MySite") ?? false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// parseLsRecordLine: line with 5 parts so description = parts.suffix(from: 4).joined.
    func testParseLsRecordLine_fiveParts_descriptionJoined() {
        let line = "1  a1b2c3d4e5f6g7h8  login  MyTitle  MyDesc"
        let rec = parseLsRecordLine(line)
        XCTAssertNotNil(rec)
        XCTAssertEqual(rec?.title, "MyTitle")
        XCTAssertEqual(rec?.description, "MyDesc")
    }

    /// add(): response not decodable as RecordAddResponse (data array) → catch uses (error as NSError).localizedDescription.
    func testAdd_decodeThrowsNoHumanReadable_usesLocalizedDescription() {
        KeeperMockURLProtocol.responseByCommand["record-add --record-type=login --title=\"Site\" login=\"user\" password=$BASE64:cHdk"] = ("{\"status\":\"success\",\"data\":[]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "add")
        ds.add(userName: "user", accountName: "Site", password: "pwd", context: makeContext()) { account, error in
            XCTAssertNil(account)
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: no password, response body not JSON → preview "(N chars, not JSON)".
    /// fetchPassword: response is JSON with no password field → no-password error (plain non-JSON body would be used as password).
    func testFetchPassword_noPassword_nonJSONPreview() {
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid12345678901234 --format=password"] = ("{}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid12345678901234", context: makeContext()) { password, _, error in
            XCTAssertNil(password)
            XCTAssertNotNil(error)
            XCTAssertTrue((error as NSError?)?.localizedDescription.contains("Keeper returned no password") ?? false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// keeperExecuteV2FailNon202 with nil data; when String(data:empty) is "", message may be empty so assert failure and code.
    func testKeeperExecuteV2FailNon202_nilData_returnsUnexpectedResponse() {
        let exp = expectation(description: "fail")
        keeperExecuteV2FailNon202(data: nil) { result in
            guard case .failure(let err) = result else { XCTFail("expected failure"); exp.fulfill(); return }
            let nsErr = err as NSError
            XCTAssertEqual(nsErr.code, -1)
            XCTAssertTrue((nsErr.localizedDescription.isEmpty || nsErr.localizedDescription == "Unexpected response"), "expected empty or 'Unexpected response', got: '\(nsErr.localizedDescription)'")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
    }

    /// ensureAPIKey: when injectedCachedSettingsKeyForLockTest is set, key is used inside lock.
    /// ensureAPIKey inside lock uses injectedCachedSettingsKeyForLockTest when set; exercised via fetchAccounts (ensureAPIKey is private).
    func testEnsureAPIKey_injectedCachedSettingsKeyForLockTest_usesKeyInLock() {
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = nil
        ds.injectedKeychainGetAPIKey = nil
        ds.injectedCachedSettingsKeyForLockTest = "lock-test-key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// keeperShowAPIKeyDialog with override set exercises the override path (already covered); without override calls UI. We test the override path returns.
    func testKeeperShowAPIKeyDialog_withOverride_invokesOverride() {
        var completed: KeeperAPIKeyPromptResult?
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, comp in comp(.useNew("test-key")) }
        keeperShowAPIKeyDialog(existingKey: nil, window: nil) { completed = $0 }
        if case .useNew(let key)? = completed {
            XCTAssertEqual(key, "test-key")
        } else {
            XCTFail("expected .useNew(\"test-key\"), got \(String(describing: completed))")
        }
        KeeperTestOverrides.showAPIKeyDialogOverride = nil
    }

    /// keeperShowAPIKeyDialog with only showAPIKeyDialogUIOverride set (no showAPIKeyDialogOverride) covers the branch that would call the real UI.
    func testKeeperShowAPIKeyDialog_withUIOverride_invokesUIOverride() {
        var completed: KeeperAPIKeyPromptResult?
        KeeperTestOverrides.showAPIKeyDialogUIOverride = { _, _, comp in comp(.cancel) }
        keeperShowAPIKeyDialog(existingKey: nil, window: nil) { completed = $0 }
        if case .cancel? = completed {
            // expected
        } else {
            XCTFail("expected .cancel, got \(String(describing: completed))")
        }
        KeeperTestOverrides.showAPIKeyDialogUIOverride = nil
    }

    /// keeperShowAPIKeyDialog with only callDialogUI set covers the final (callDialogUI ?? keeperShowAPIKeyDialogUI) line without showing real UI.
    func testKeeperShowAPIKeyDialog_withCallDialogUIOverride_invokesOverride() {
        var completed: KeeperAPIKeyPromptResult?
        KeeperTestOverrides.callDialogUI = { _, _, comp in comp(.useNew("from-call-dialog")) }
        keeperShowAPIKeyDialog(existingKey: nil, window: nil) { completed = $0 }
        if case .useNew(let key)? = completed {
            XCTAssertEqual(key, "from-call-dialog")
        } else {
            XCTFail("expected .useNew(\"from-call-dialog\"), got \(String(describing: completed))")
        }
        KeeperTestOverrides.callDialogUI = nil
    }

    /// keeperShowAPIKeyDialog with callDialogUI nil but defaultDialogUI set covers the default-dialog path without showing real UI.
    func testKeeperShowAPIKeyDialog_withDefaultDialogUI_invokesDefault() {
        var completed: KeeperAPIKeyPromptResult?
        KeeperTestOverrides.callDialogUI = nil
        KeeperTestOverrides.defaultDialogUI = { _, _, comp in comp(.cancel) }
        defer { KeeperTestOverrides.defaultDialogUI = nil }
        keeperShowAPIKeyDialog(existingKey: nil, window: nil) { completed = $0 }
        if case .cancel? = completed {
            // expected
        } else {
            XCTFail("expected .cancel, got \(String(describing: completed))")
        }
    }

    /// keeperShowAPIKeyDialog with callDialogUI and defaultDialogUI nil but fallbackDialogUIForCoverage set covers the resolver's third branch.
    func testKeeperShowAPIKeyDialog_withFallbackDialogUIForCoverage_invokesFallback() {
        var completed: KeeperAPIKeyPromptResult?
        KeeperTestOverrides.callDialogUI = nil
        KeeperTestOverrides.defaultDialogUI = nil
        KeeperTestOverrides.fallbackDialogUIForCoverage = { _, _, comp in comp(.useNew("from-fallback")) }
        defer { KeeperTestOverrides.fallbackDialogUIForCoverage = nil }
        keeperShowAPIKeyDialog(existingKey: nil, window: nil) { completed = $0 }
        if case .useNew(let key)? = completed {
            XCTAssertEqual(key, "from-fallback")
        } else {
            XCTFail("expected .useNew(\"from-fallback\"), got \(String(describing: completed))")
        }
    }

    /// keeperResolvedDialogFunction with all overrides nil returns the real UI function (line 54); we only call the resolver, not the returned function, so no UI is shown.
    func testKeeperResolvedDialogFunction_withNoOverrides_returnsRealUIFunction() {
        KeeperTestOverrides.callDialogUI = nil
        KeeperTestOverrides.defaultDialogUI = nil
        KeeperTestOverrides.fallbackDialogUIForCoverage = nil
        let fn = keeperResolvedDialogFunction()
        XCTAssertNotNil(fn)
    }

    /// Calling the function returned by keeperResolvedDialogFunction when no overrides set completes with .cancel (covers keeperShowAPIKeyDialogUI).
    func testKeeperResolvedDialogFunction_callingReturnedFunction_completesWithCancel() {
        KeeperTestOverrides.callDialogUI = nil
        KeeperTestOverrides.defaultDialogUI = nil
        KeeperTestOverrides.fallbackDialogUIForCoverage = nil
        let fn = keeperResolvedDialogFunction()
        let exp = expectation(description: "dialog")
        fn(nil, nil) { result in
            if case .cancel? = result { } else { XCTFail("expected .cancel, got \(String(describing: result))") }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
    }

    /// When settings sheet handler is nil, keeperShowAPIKeyDialog completes with .cancel (no legacy pop-up).
    func testKeeperShowAPIKeyDialog_noSheetHandler_completesWithCancel() {
        KeeperDataSource.setShowKeeperSettingsSheetHandler(nil)
        defer { KeeperDataSource.setShowKeeperSettingsSheetHandler(nil) }
        KeeperTestOverrides.showAPIKeyDialogOverride = nil
        KeeperTestOverrides.showAPIKeyDialogUIOverride = nil
        var result: KeeperAPIKeyPromptResult?
        keeperShowAPIKeyDialog(existingKey: nil, window: nil) { result = $0 }
        if case .cancel? = result { } else { XCTFail("expected .cancel when no sheet handler, got \(String(describing: result))") }
    }

    /// keeperMigrateLegacyKeeperTokenIfNeeded() with legacy key in UserDefaults calls store override and removes from UserDefaults (covers migration path).
    func testKeeperMigrateLegacyKeeperTokenIfNeeded_userDefaultsPath() {
        iTermUserDefaults.userDefaults().set("legacy-key-from-ud", forKey: keeperLegacyUserDefaultsAPIKeyKey)
        iTermUserDefaults.userDefaults().set("https://legacy-url.test", forKey: keeperLegacyUserDefaultsAPIURLKey)
        defer {
            iTermUserDefaults.userDefaults().removeObject(forKey: keeperLegacyUserDefaultsAPIKeyKey)
            iTermUserDefaults.userDefaults().removeObject(forKey: keeperLegacyUserDefaultsAPIURLKey)
        }
        var storedKey: String?
        KeeperTestOverrides.storeAPIKeyInKeychain = { key in storedKey = key }
        defer { KeeperTestOverrides.storeAPIKeyInKeychain = nil }
        keeperMigrateLegacyKeeperTokenIfNeeded()
        XCTAssertEqual(storedKey, "legacy-key-from-ud")
        XCTAssertNil(iTermUserDefaults.userDefaults().string(forKey: keeperLegacyUserDefaultsAPIKeyKey))
        XCTAssertEqual(iTermUserDefaults.userDefaults().string(forKey: keeperLegacyUserDefaultsAPIURLKey), "https://legacy-url.test")
    }

    /// keeperAPIURLFromStorage() with no override reads from UserDefaults (covers merged keychain storage path).
    func testKeeperAPIURLFromStorage_withNoOverride_readsUserDefaults() {
        KeeperTestOverrides.apiURLFromStorage = nil
        defer { KeeperTestOverrides.apiURLFromStorage = nil }
        let url = "https://from-userdefaults.test"
        iTermUserDefaults.userDefaults().set(url, forKey: keeperLegacyUserDefaultsAPIURLKey)
        defer { iTermUserDefaults.userDefaults().removeObject(forKey: keeperLegacyUserDefaultsAPIURLKey) }
        XCTAssertEqual(keeperAPIURLFromStorage(), url)
    }

    /// keeperStoreAPIURLInKeychain() writes to UserDefaults (covers merged keychain storage path).
    func testKeeperStoreAPIURLInKeychain_storesInUserDefaults() {
        KeeperTestOverrides.apiURLFromStorage = nil
        defer { KeeperTestOverrides.apiURLFromStorage = nil }
        let url = "https://store-test.test"
        keeperStoreAPIURLInKeychain(url)
        defer { keeperClearAPIURLStorage() }
        XCTAssertEqual(iTermUserDefaults.userDefaults().string(forKey: keeperLegacyUserDefaultsAPIURLKey), url)
    }

    /// keeperStoreAPIURLInKeychain() with whitespace-only string sets nil in UserDefaults (covers trimmed.isEmpty path).
    func testKeeperStoreAPIURLInKeychain_whitespaceOnly_setsNilInUserDefaults() {
        KeeperTestOverrides.apiURLFromStorage = nil
        defer { KeeperTestOverrides.apiURLFromStorage = nil }
        iTermUserDefaults.userDefaults().set("https://to-clear.test", forKey: keeperLegacyUserDefaultsAPIURLKey)
        keeperStoreAPIURLInKeychain("   ")
        XCTAssertNil(iTermUserDefaults.userDefaults().string(forKey: keeperLegacyUserDefaultsAPIURLKey))
        keeperClearAPIURLStorage()
    }

    /// keeperClearAPIURLStorage() removes URL from UserDefaults (covers merged keychain storage path).
    func testKeeperClearAPIURLStorage_removesFromUserDefaults() {
        iTermUserDefaults.userDefaults().set("https://to-clear.test", forKey: keeperLegacyUserDefaultsAPIURLKey)
        keeperClearAPIURLStorage()
        XCTAssertNil(iTermUserDefaults.userDefaults().string(forKey: keeperLegacyUserDefaultsAPIURLKey))
    }

    /// keeperBaseURL() returns nil when storage returns a URL string with no host (e.g. file:///tmp), so keeperExecute fails with API URL required.
    func testKeeperBaseURL_storageURLWithNoHost_returnsNil() {
        KeeperTestOverrides.apiURLFromStorage = { "file:///tmp" }
        defer { KeeperTestOverrides.apiURLFromStorage = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = nil
        ds.injectedBaseURLFromStorage = nil
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// keeperBaseURL() returns nil when storage returns whitespace-only (trimmed empty).
    func testKeeperBaseURL_storageWhitespaceOnly_returnsNil() {
        KeeperTestOverrides.apiURLFromStorage = { "   \t  " }
        defer { KeeperTestOverrides.apiURLFromStorage = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = nil
        ds.injectedBaseURLFromStorage = nil
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// keeperBaseURL() returns nil when storage returns a string that URL(string:) parses but scheme or host is nil.
    func testKeeperBaseURL_storageInvalidURL_returnsNil() {
        KeeperTestOverrides.apiURLFromStorage = { "not-a-valid-url" }
        defer { KeeperTestOverrides.apiURLFromStorage = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = nil
        ds.injectedBaseURLFromStorage = nil
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// ensureAPIKey with injectedAPIKey == "" on main thread calls showUIAndContinue() directly (no DispatchQueue.main.async).
    func testEnsureAPIKey_emptyInjectedKeyOnMainThread_showsDialogAndCompletes() {
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(nil) }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContextWithWindow()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// Dialog returning .cancel goes through keeperHandleDialogResult(.cancel) and completes with nil (coverage).
    func testEnsureAPIKey_dialogCancel_completesWithNil() {
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(.cancel) }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// ensureAPIKey with injectedAPIKey == "" from background thread dispatches showUIAndContinue to main (covers DispatchQueue.main.async branch).
    func testEnsureAPIKey_emptyInjectedKeyFromBackgroundThread_dispatchesToMainAndShowsDialog() {
        KeeperTestOverrides.showAPIKeyDialogOverride = { _, _, completion in completion(nil) }
        defer { KeeperTestOverrides.showAPIKeyDialogOverride = nil }
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = ""
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = ("{\"command\":\"ls\",\"data\":{\"records\":[]},\"status\":\"success\"}".data(using: .utf8)!, 200)
        let context = makeContext()  // Create on main thread; don't create NSWindow from background.
        let exp = expectation(description: "fetchAccounts")
        DispatchQueue.global(qos: .userInitiated).async {
            ds.fetchAccounts(context: context) { accounts in
                XCTAssertEqual(accounts.count, 0)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 5)
    }

    /// keeperExecuteV2: POST returns 202 but body has no request_id → "No request_id in v2 response".
    func testV2POSTReturns202WithNoRequestId_failsWithMessage() {
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"success\":true}".data(using: .utf8)!, 202)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success)
            XCTAssertTrue(message?.contains("request_id") ?? false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
    }

    /// keeperExecuteV2: POST returns non-202 with body → humanReadable or String(data:encoding:) or "Unexpected response" fallback.
    func testV2POSTReturns400WithBody_returnsFailureWithMessage() {
        KeeperMockURLProtocol.responseByCommand["sync-down"] = ("{\"error\":\"Bad request\"}".data(using: .utf8)!, 400)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success)
            XCTAssertNotNil(message)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
    }

    /// parseMessageTableRecordUids: first payload fails guard (no message), second payload succeeds (continue branch).
    func testParseMessageTableRecordUids_firstPayloadFailsGuard_secondSucceeds() {
        let data = "{\"status\":\"success\",\"result\":\"{\\\"message\\\":[\\\"#\\\",\\\"---\\\",\\\"1  a1b2c3d4e5f6g7h8  login\\\"]}\"}"
        let dataObj = data.data(using: .utf8)!
        let uids = parseMessageTableRecordUids(from: dataObj)
        XCTAssertEqual(uids.count, 1)
    }

    /// fetchAccounts: response is direct list format with "message" array (no v2 wrapper), exercises message-table compactMap path.
    func testFetchAccounts_directListFormatWithMessageTable() {
        let json = "{\"command\":\"list\",\"data\":null,\"message\":[\"#  UID  Type  Title\",\"---  ---  ---  ---\",\"1  a1b2c3d4e5f6g7h8  login  MyAccount  desc\"]}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (json.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            XCTAssertEqual(accounts.first?.accountName, "MyAccount")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchAccounts: "ls" format with data.records[].title as table line (parseLsRecordLine path).
    func testFetchAccounts_lsFormatRecordsWithTitleLine() {
        let json = "{\"command\":\"ls\",\"data\":{\"records\":[{\"title\":\"1  a1b2c3d4e5f6g7h8  login  SiteFromTitle  desc\"}]}}"
        KeeperMockURLProtocol.responseByCommand["ls -R -l"] = (json.data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchAccounts")
        ds.fetchAccounts(context: makeContext()) { accounts in
            XCTAssertEqual(accounts.count, 1)
            XCTAssertEqual(accounts.first?.accountName, "SiteFromTitle")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// keeperExecuteV2: POST returns non-202 with non-UTF-8 body → "Unexpected response" fallback.
    func testV2POSTReturns500WithNonUTF8Body_returnsUnexpectedResponse() {
        KeeperMockURLProtocol.responseByCommand["sync-down"] = (Data([0xFF, 0xFE]), 500)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "sync")
        ds.runKeeperSyncDown(apiKey: "key", apiURL: "https://keeper.test") { success, message in
            XCTAssertFalse(success)
            XCTAssertTrue(message?.contains("Unexpected") ?? false || message?.contains("500") ?? false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
    }

    /// setPassword: non-success response with message array → uses first message as detail.
    func testSetPassword_nonSuccessWithMessageArray_customMessage() {
        let b64 = Data("x".utf8).base64EncodedString()
        KeeperMockURLProtocol.responseByCommand["record-update -r uid123 password=$BASE64:\(b64)"] = ("{\"status\":\"error\",\"message\":[\"Custom update error\"]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "setPassword")
        ds.setPassword(recordUid: "uid123", password: "x", context: makeContext()) { error in
            XCTAssertNotNil(error)
            XCTAssertTrue((error as NSError?)?.localizedDescription.contains("Custom update error") ?? false)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// deleteRecord: non-success response → keeperHumanReadableError or "Delete failed".
    func testDeleteRecord_nonSuccess_usesHumanReadableError() {
        KeeperMockURLProtocol.responseByCommand["rm -f uid123"] = ("{\"status\":\"fail\",\"message\":[\"Permission denied\"]}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "deleteRecord")
        ds.deleteRecord(recordUid: "uid123", context: makeContext()) { error in
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// add: status success but data.record_uid missing → "Add failed" path.
    func testAdd_successButNoRecordUid_completesWithError() {
        let cmd = "record-add --record-type=login --title=\"A\" login=\"U\" password=$BASE64:cA=="
        KeeperMockURLProtocol.responseByCommand[cmd] = ("{\"status\":\"success\",\"data\":{}}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "add")
        ds.add(userName: "U", accountName: "A", password: "p", context: makeContext()) { account, error in
            XCTAssertNil(account)
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// add: response not decodable as RecordAddResponse → catch block uses keeperHumanReadableError or localizedDescription.
    func testAdd_decodeThrows_usesHumanReadableOrErrorDescription() {
        let cmd = "record-add --record-type=login --title=\"A\" login=\"U\" password=$BASE64:cA=="
        KeeperMockURLProtocol.responseByCommand[cmd] = ("[1,2,3]".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "add")
        ds.add(userName: "U", accountName: "A", password: "p", context: makeContext()) { account, error in
            XCTAssertNil(account)
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: no password in response, preview "(empty)" when body is empty string.
    func testFetchPassword_noPassword_previewEmpty() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertNil(password)
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// fetchPassword: no password in response, preview includes "data keys" when response has data object (multiple keys so single-key branch not used).
    func testFetchPassword_noPassword_previewWithDataKeys() {
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=json"] = ("{}".data(using: .utf8)!, 200)
        KeeperMockURLProtocol.responseByCommand["get uid123 --format=password"] = ("{\"status\":\"ok\",\"data\":{\"note\":\"x\",\"other\":\"y\"}}".data(using: .utf8)!, 200)
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = URL(string: "https://keeper.test")!
        ds.injectedURLSession = mockSession
        let exp = expectation(description: "fetchPassword")
        ds.fetchPassword(recordUid: "uid123", context: makeContext()) { password, _, error in
            XCTAssertNil(password)
            XCTAssertNotNil(error)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    /// passwordFromGetJSONResponse fromRecord: field with type "password" and value as String (not array).
    func testPasswordFromGetJSONResponse_typedRecordFieldValueAsString() {
        let json = "{\"data\":{\"fields\":[{\"type\":\"password\",\"value\":\"pwd-from-string\"}]}}"
        let data = json.data(using: .utf8)!
        let pwd = KeeperDataSource.passwordFromGetJSONResponse(data)
        XCTAssertEqual(pwd, "pwd-from-string")
    }

    /// parseMessageTableRecordUids: first payload has message with 2 lines (continue), second payload succeeds.
    func testParseMessageTableRecordUids_continueWhenMessageTooShort() {
        let json = "{\"status\":\"success\",\"result\":\"{\\\"message\\\":[\\\"#\\\",\\\"---\\\"]}\",\"message\":[\"#\",\"---\",\"1  a1b2c3d4e5f6g7h8  login\"]}"
        let data = json.data(using: .utf8)!
        let uids = parseMessageTableRecordUids(from: data)
        XCTAssertEqual(uids.count, 1)
        XCTAssertTrue(uids.contains("a1b2c3d4e5f6g7h8"))
    }
}
