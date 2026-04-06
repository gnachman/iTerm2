// Keeper Commander Service Mode HTTP client (v2 queue API). Sole copy of Commander networking for iTerm2 Keeper integration.
// Sync API: each CLI invocation runs one subcommand and blocks until completion.

import Foundation
import PasswordManagerProtocol

// MARK: - Request/response types (mirror iTerm2 Keeper integration)

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

private struct KeeperExecuteResponseDataArray: Decodable {
    let status: String?
    let command: String?
    let data: [KeeperRecord]?
    let result: String?
    let message: String?
}

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

/// Commander `ls -l` often appends connection info after `login @ …`: `https://…`, or database-style
/// `host:port` / IPv4. iTerm2 sends `userName` to the terminal as-is, so we keep only the login segment.
private func loginFromKeeperListDisplayDescription(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let range = trimmed.range(of: " @ ", options: .literal) else {
        return trimmed
    }
    let head = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    let tail = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    if tail.isEmpty { return trimmed }
    if keeperListDescriptionSuffixIsConnectionInfo(tail) {
        return head.isEmpty ? trimmed : head
    }
    return trimmed
}

/// True when the part after ` @ ` looks like a URL or server address (not part of the login).
private func keeperListDescriptionSuffixIsConnectionInfo(_ tail: String) -> Bool {
    let t = tail.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return false }
    let lower = t.lowercased()
    if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return true }
    // IPv4 or IPv4:port (e.g. 127.0.0.1:3366)
    if t.range(of: #"^(?:\d{1,3}\.){3}\d{1,3}(:\d+)?$"#, options: .regularExpression) != nil {
        return true
    }
    // hostname:port (e.g. db.example.com:3306)
    if t.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9.-]*:\d{1,5}$"#, options: .regularExpression) != nil {
        return true
    }
    return false
}

struct KeeperRecord: Decodable {
    let number: Int?
    let uid: String?
    private let record_uid: String?
    var effectiveUid: String? { uid ?? record_uid }
    let type: String?
    let title: String?
    let description: String?
    /// Present in some Commander JSON list payloads; avoids N+1 `get` calls (which trigger HTTP 429 rate limits).
    let login: String?
    let username: String?

    init(number: Int?, uid: String?, record_uid: String?, type: String?, title: String?, description: String?, login: String? = nil, username: String? = nil) {
        self.number = number
        self.uid = uid
        self.record_uid = record_uid
        self.type = type
        self.title = title
        self.description = description
        self.login = login
        self.username = username
    }

    /// Best-effort login/username for the password manager list without extra API round-trips.
    var listUserName: String {
        if let l = login?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty { return l }
        if let u = username?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty { return u }
        let d = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if d.isEmpty { return "" }
        return loginFromKeeperListDisplayDescription(d)
    }
}

private struct KeeperV2QueuedResponse: Decodable {
    let request_id: String?
    let status: String?
}

private struct KeeperV2StatusResponse: Decodable {
    let status: String?
}

enum KeeperClientError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let s): return s
        }
    }
}

final class KeeperCommanderClient {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    static func v2BaseURL(from base: URL) -> URL {
        var path = base.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("api/v2") {
            var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            c.path = path
            return c.url ?? base
        }
        return base.appendingPathComponent("api").appendingPathComponent("v2")
    }

    private func asyncURL() -> URL {
        Self.v2BaseURL(from: baseURL).appendingPathComponent("executecommand-async")
    }

    private func statusURL(requestId: String) -> URL {
        Self.v2BaseURL(from: baseURL).appendingPathComponent("status").appendingPathComponent(requestId)
    }

    private func resultURL(requestId: String) -> URL {
        Self.v2BaseURL(from: baseURL).appendingPathComponent("result").appendingPathComponent(requestId)
    }

    func executeCommand(apiKey: String, command: String) throws -> Data {
        let body = try JSONEncoder().encode(KeeperExecuteRequest(command: command))
        var request = URLRequest(url: asyncURL())
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.httpBody = body
        let (data, response, err) = session.synchronousData(for: request)
        if let err = err { throw err }
        guard let data = data else { throw KeeperClientError.message("No data") }
        guard let http = response as? HTTPURLResponse, http.statusCode == 202 else {
            throw KeeperClientError.message(keeperHumanReadableError(fromResponseData: data) ?? String(data: data, encoding: .utf8) ?? "Unexpected response")
        }
        let queued = try JSONDecoder().decode(KeeperV2QueuedResponse.self, from: data)
        guard let requestId = queued.request_id, !requestId.isEmpty else {
            throw KeeperClientError.message("No request_id in v2 response")
        }
        return try pollForResult(apiKey: apiKey, requestId: requestId)
    }

    private func pollForResult(apiKey: String, requestId: String) throws -> Data {
        let interval: TimeInterval = 2
        let deadline = Date().addingTimeInterval(120)
        var pollCount = 0
        var consecutiveUnparseable = 0
        while true {
            pollCount += 1
            if Date() > deadline { throw KeeperClientError.message("Keeper service v2 request timed out") }
            if pollCount > 60 { throw KeeperClientError.message("Keeper service did not complete the request in time") }
            var sreq = URLRequest(url: statusURL(requestId: requestId))
            sreq.setValue(apiKey, forHTTPHeaderField: "api-key")
            let (sdata, sresp, serr) = session.synchronousData(for: sreq)
            if let serr = serr { throw serr }
            let scode = (sresp as? HTTPURLResponse)?.statusCode ?? 0
            if scode != 200 {
                throw KeeperClientError.message(keeperHumanReadableError(fromResponseData: sdata) ?? "HTTP \(scode)")
            }
            guard let sdata = sdata,
                  let statusResp = try? JSONDecoder().decode(KeeperV2StatusResponse.self, from: sdata),
                  let status = statusResp.status else {
                consecutiveUnparseable += 1
                if consecutiveUnparseable >= 15 {
                    throw KeeperClientError.message(keeperHumanReadableError(fromResponseData: sdata) ?? "Invalid status response")
                }
                Thread.sleep(forTimeInterval: interval)
                continue
            }
            consecutiveUnparseable = 0
            switch status {
            case "completed":
                var rreq = URLRequest(url: resultURL(requestId: requestId))
                rreq.setValue(apiKey, forHTTPHeaderField: "api-key")
                let (rdata, rresp, rerr) = session.synchronousData(for: rreq)
                if let rerr = rerr { throw rerr }
                guard let rdata = rdata, !rdata.isEmpty else { throw KeeperClientError.message("No data") }
                if let http = rresp as? HTTPURLResponse, http.statusCode != 200 {
                    throw KeeperClientError.message(keeperHumanReadableError(fromResponseData: rdata) ?? "HTTP \(http.statusCode)")
                }
                return rdata
            case "failed", "expired":
                throw KeeperClientError.message("Keeper command \(status)")
            default:
                Thread.sleep(forTimeInterval: interval)
            }
        }
    }
}

// MARK: - URLSession sync helper

private extension URLSession {
    func synchronousData(for request: URLRequest) -> (Data?, URLResponse?, Error?) {
        let sem = DispatchSemaphore(value: 0)
        var out: (Data?, URLResponse?, Error?) = (nil, nil, nil)
        dataTask(with: request) { d, r, e in
            out = (d, r, e)
            sem.signal()
        }.resume()
        sem.wait()
        return out
    }
}

// MARK: - Parsing / list / password

func parseLsRecordLine(_ line: String) -> KeeperRecord? {
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

func passwordFromGetJSONResponse(_ data: Data) -> String? {
    func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    func fromRecord(_ rec: [String: Any]) -> String? {
        if let p = rec["password"] as? String { let t = trim(p); return t.isEmpty ? nil : t }
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

func loginFromGetJSONResponse(_ data: Data) -> String? {
    func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    func fromRecord(_ rec: [String: Any]) -> String? {
        if let login = rec["login"] as? String { let t = trim(login); return t.isEmpty ? nil : t }
        if let login = rec["username"] as? String { let t = trim(login); return t.isEmpty ? nil : t }
        if let fields = rec["fields"] as? [[String: Any]] {
            for f in fields {
                guard (f["type"] as? String) == "login" else { continue }
                if let v = f["value"] as? [String], let first = v.first { let t = trim(first); return t.isEmpty ? nil : t }
                if let v = f["value"] as? String { let t = trim(v); return t.isEmpty ? nil : t }
            }
        }
        return nil
    }
    if let dataVal = parsed["data"] {
        if let str = dataVal as? String,
           let record = try? JSONSerialization.jsonObject(with: Data(str.utf8)) as? [String: Any],
           let login = fromRecord(record) { return login }
        if let obj = dataVal as? [String: Any], let login = fromRecord(obj) { return login }
    }
    if let rec = parsed["record"] as? [String: Any], let login = fromRecord(rec) { return login }
    return nil
}

func decodeToken(_ token: String?) -> String? {
    guard let token = token, !token.isEmpty else { return nil }
    guard let data = Data(base64Encoded: token) else { return nil }
    return String(data: data, encoding: .utf8)
}

func extractServiceURL(from header: PasswordManagerProtocol.RequestHeader) throws -> URL {
    let candidates = [
        header.settings?["serviceURL"],
        header.settings?["apiURL"],
        header.pathToDatabase,
    ]
    guard let raw = candidates
        .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
        .first(where: { !$0.isEmpty }) else {
        throw KeeperClientError.message("Commander API URL is required in request header (pathToDatabase).")
    }
    guard let url = URL(string: raw), url.scheme != nil, url.host != nil else {
        throw KeeperClientError.message("Invalid Commander API URL.")
    }
    return url
}

private let keeperRecordUIDRegex = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{15,}$")

private func validatedRecordUID(_ recordUid: String) throws -> String {
    let uid = recordUid.trimmingCharacters(in: .whitespacesAndNewlines)
    let range = NSRange(location: 0, length: uid.utf16.count)
    let match = keeperRecordUIDRegex.firstMatch(in: uid, options: [], range: range)
    guard !uid.isEmpty, match != nil else {
        throw KeeperClientError.message("Invalid record identifier.")
    }
    return uid
}

func listAccountsRecords(apiKey: String, client: KeeperCommanderClient) throws -> [PasswordManagerProtocol.Account] {
    let data = try client.executeCommand(apiKey: apiKey, command: "ls -R -l")
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
    }
    guard let recs = records, !recs.isEmpty else { return [] }
    // Do not call `get` per record here: each record would add several HTTP calls and Commander
    // Service Mode often returns HTTP 429 (Too Many Requests). Usernames come from `ls` output
    // (description column and optional login/username fields in JSON).
    return recs.compactMap { rec -> PasswordManagerProtocol.Account? in
        guard let uid = rec.effectiveUid, !uid.isEmpty else { return nil }
        let title = rec.title ?? "Untitled"
        return PasswordManagerProtocol.Account(
            identifier: PasswordManagerProtocol.AccountIdentifier(accountID: uid),
            userName: rec.listUserName,
            accountName: title,
            hasOTP: false)
    }
}

func getPassword(apiKey: String, recordUid: String, client: KeeperCommanderClient) throws -> PasswordManagerProtocol.Password {
    let uid = try validatedRecordUID(recordUid)
    let jsonData = try client.executeCommand(apiKey: apiKey, command: "get \(uid) --format=json")
    if let exact = passwordFromGetJSONResponse(jsonData) {
        return PasswordManagerProtocol.Password(password: exact, otp: nil)
    }
    let data = try client.executeCommand(apiKey: apiKey, command: "get \(uid) --format=password")
    guard let pwd = extractPasswordFromRawGet(data: data) else {
        throw KeeperClientError.message("Keeper returned no password for this record.")
    }
    return PasswordManagerProtocol.Password(password: pwd, otp: nil)
}

func getLogin(apiKey: String, recordUid: String, client: KeeperCommanderClient) throws -> String {
    let uid = try validatedRecordUID(recordUid)
    let jsonData = try client.executeCommand(apiKey: apiKey, command: "get \(uid) --format=json")
    if let login = loginFromGetJSONResponse(jsonData) {
        return login
    }
    throw KeeperClientError.message("Keeper returned no login for this record.")
}

private func extractPasswordFromRawGet(data: Data) -> String? {
    func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    if let decoded = try? JSONDecoder().decode(String.self, from: data) {
        let t = trim(decoded)
        if !t.isEmpty { return t }
    }
    if let wrapper = try? JSONDecoder().decode(KeeperV2ResultWrapper.self, from: data),
       (wrapper.status == "success" || wrapper.status == "completed"),
       let resultStr = wrapper.result {
        let t = trim(resultStr)
        if !t.isEmpty { return t }
    }
    if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if let resultStr = parsed["result"] as? String {
            let t = trim(resultStr)
            if !t.isEmpty { return t }
        }
        if let msg = parsed["message"] as? [String], let first = msg.first {
            let t = trim(first)
            let lower = t.lowercased()
            let skip = lower.hasPrefix("command executed successfully") || lower.contains("no output")
            if !t.isEmpty, !skip { return t }
        }
    }
    if let raw = String(data: data, encoding: .utf8) {
        let t = trim(raw)
        if !t.isEmpty { return t }
    }
    return nil
}

func setPassword(apiKey: String, recordUid: String, newPassword: String?, client: KeeperCommanderClient) throws {
    guard let newPassword = newPassword, !newPassword.isEmpty else {
        throw KeeperClientError.message("Password field is required.")
    }
    let uid = try validatedRecordUID(recordUid)
    let b64 = Data(newPassword.utf8).base64EncodedString()
    let cmd = "record-update -r \(uid) password=$BASE64:\(b64)"
    let data = try client.executeCommand(apiKey: apiKey, command: cmd)
    if let response = try? JSONDecoder().decode(KeeperExecuteResponse.self, from: data), response.status == "success" {
        return
    }
    let raw = keeperHumanReadableError(fromResponseData: data) ?? "Update failed"
    throw KeeperClientError.message(keeperUserFacingPasswordUpdateError(apiDetail: raw))
}

/// Escape `accountName` / `userName` for `record-add ... --title="..." login="..."`.
///
/// Commander receives the command as a string and may evaluate it in a shell-like way. Values are
/// wrapped in double quotes; inside those quotes, POSIX-ish shells still treat `\`, `"`, `` ` ``,
/// and `$` specially (command substitution / expansion). We also normalize line breaks and escape
/// `!` for bash `histexpand` edge cases.
private func escapeForKeeperDoubleQuotedCommandField(_ s: String) -> String {
    s
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "$", with: "\\$")
        .replacingOccurrences(of: "`", with: "\\`")
        .replacingOccurrences(of: "!", with: "\\!")
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
}

func deleteRecord(apiKey: String, recordUid: String, client: KeeperCommanderClient) throws {
    let uid = try validatedRecordUID(recordUid)
    let data = try client.executeCommand(apiKey: apiKey, command: "rm -f \(uid)")
    if let response = try? JSONDecoder().decode(KeeperExecuteResponse.self, from: data), response.status == "success" {
        return
    }
    throw KeeperClientError.message("Delete failed")
}

func addRecord(apiKey: String, userName: String, accountName: String, password: String?, client: KeeperCommanderClient) throws -> String {
    let escapedTitle = escapeForKeeperDoubleQuotedCommandField(accountName)
    var cmd = "record-add --record-type=login --title=\"\(escapedTitle)\""
    if !userName.isEmpty {
        let escapedLogin = escapeForKeeperDoubleQuotedCommandField(userName)
        cmd += " login=\"\(escapedLogin)\""
    }
    if let password = password, !password.isEmpty {
        let passwordB64 = Data(password.utf8).base64EncodedString()
        cmd += " password=$BASE64:\(passwordB64)"
    }
    let data = try client.executeCommand(apiKey: apiKey, command: cmd)
    struct RecordAddResponse: Decodable {
        let status: String?
        let data: RecordAddData?
    }
    struct RecordAddData: Decodable {
        let record_uid: String?
    }
    let response = try JSONDecoder().decode(RecordAddResponse.self, from: data)
    guard response.status == "success", let uid = response.data?.record_uid, !uid.isEmpty else {
        throw KeeperClientError.message("Add failed")
    }
    return uid
}
