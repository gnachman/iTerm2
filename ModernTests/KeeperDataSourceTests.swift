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
    /// request_id -> result body (for v2 GET result/<request_id>).
    static var pendingV2Results: [String: Data] = [:]
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
        // v2 POST executecommand-async: queue command, return request_id
        if url.path.contains("executecommand-async"), request.httpMethod?.uppercased() == "POST" {
            let command: String? = {
                guard let body = readRequestBody(from: request),
                      let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                      let cmd = json["command"] as? String else { return nil }
                return cmd
            }()
            Self.lastCommand = command
            let key = command ?? ""
            let (resultData, _) = Self.responseByCommand[key] ?? ("{\"status\":\"success\"}".data(using: .utf8)!, 200)
            let requestId = UUID().uuidString
            Self.pendingV2Results[requestId] = resultData
            let queueResponse = "{\"request_id\":\"\(requestId)\",\"success\":true}".data(using: .utf8)!
            let response = HTTPURLResponse(url: url, statusCode: 202, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: queueResponse)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        // v2 GET status/<request_id>: return completed so client fetches result
        if url.path.contains("status/") {
            let requestId = String(url.path.split(separator: "/").last ?? "")
            let statusResponse = "{\"status\":\"completed\"}".data(using: .utf8)!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: statusResponse)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        // v2 GET result/<request_id>: return stored result for that command
        if url.path.contains("result/") {
            let requestId = String(url.path.split(separator: "/").last ?? "")
            let resultData = Self.pendingV2Results[requestId] ?? "{\"status\":\"success\"}".data(using: .utf8)!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
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
        KeeperMockURLProtocol.lastCommand = nil
    }

    override func tearDown() {
        KeeperMockURLProtocol.responseByCommand = [:]
        KeeperMockURLProtocol.pendingV2Results = [:]
        KeeperMockURLProtocol.lastRequest = nil
        KeeperMockURLProtocol.lastCommand = nil
        super.tearDown()
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

    func testPasswordFromGetJSONResponse_noPasswordKeyReturnsNil() {
        let json = """
        {"data": {"login": "user", "title": "Site"}}
        """
        let data = json.data(using: .utf8)!
        let result = KeeperDataSource.passwordFromGetJSONResponse(data)
        XCTAssertNil(result)
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
        let ds = KeeperDataSource(browser: false)
        ds.injectedAPIKey = "key"
        ds.injectedBaseURL = nil
        ds.injectedURLSession = mockSession
        // Without setting injectedBaseURL, keeperBaseURL() is used (from storage). We don't set storage, so it's nil.
        // So fetchAccounts will call keeperExecute with baseURL nil and no cached URL -> error.
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
}
