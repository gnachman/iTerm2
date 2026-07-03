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

/// Strip URL/host suffix after `login @ …` from Commander list descriptions.
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

private func keeperListDescriptionSuffixIsConnectionInfo(_ tail: String) -> Bool {
    let t = tail.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return false }
    let lower = t.lowercased()
    if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return true }
    if t.range(of: #"^(?:\d{1,3}\.){3}\d{1,3}(:\d+)?$"#, options: .regularExpression) != nil {
        return true
    }
    if t.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9.-]*:\d{1,5}$"#, options: .regularExpression) != nil {
        return true
    }
    return false
}

struct KeeperRecord: Decodable {
    let number: Int?
    let uid: String?
    private let record_uid: String?
    let type: String?
    let title: String?
    let description: String?
    let name: String?
    let details: String?
    let source: String?
    let login: String?
    let username: String?
    let record_category: String?

    private let upperUID: String?
    private let upperTitle: String?
    private let upperType: String?
    private let itemType: String?

    enum CodingKeys: String, CodingKey {
        case number, uid, record_uid, type, title, description
        case name, details, source, login, username, record_category
        case upperUID = "UID"
        case upperTitle = "Title"
        case upperType = "Type"
        case itemType = "Item Type"
    }

    init(number: Int? = nil, uid: String? = nil, record_uid: String? = nil,
         type: String? = nil, title: String? = nil, description: String? = nil,
         name: String? = nil, details: String? = nil, source: String? = nil,
         login: String? = nil, username: String? = nil,
         record_category: String? = nil,
         upperUID: String? = nil, upperTitle: String? = nil,
         upperType: String? = nil, itemType: String? = nil) {
        self.number = number
        self.uid = uid
        self.record_uid = record_uid
        self.type = type
        self.title = title
        self.description = description
        self.name = name
        self.details = details
        self.source = source
        self.login = login
        self.username = username
        self.record_category = record_category
        self.upperUID = upperUID
        self.upperTitle = upperTitle
        self.upperType = upperType
        self.itemType = itemType
    }

    func withRecordCategory(_ category: String) -> KeeperRecord {
        KeeperRecord(number: number, uid: uid, record_uid: record_uid,
                     type: type, title: title, description: description,
                     name: name, details: details, source: source,
                     login: login, username: username, record_category: category,
                     upperUID: upperUID, upperTitle: upperTitle,
                     upperType: upperType, itemType: itemType)
    }

    var effectiveUid: String? { uid ?? record_uid ?? upperUID }
    var effectiveType: String? { type ?? upperType }

    var isFolder: Bool {
        if let t = effectiveType?.lowercased(), t == "folder" { return true }
        if let it = itemType?.lowercased(), it == "folder" { return true }
        return false
    }

    var displayTitle: String {
        for candidate in [title, upperTitle, name] {
            if let t = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        }
        return "Untitled"
    }

    var detailsDescription: String? {
        guard let d = details else { return nil }
        guard let range = d.range(of: "Description:", options: .literal) else { return nil }
        let raw = d[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || raw.caseInsensitiveCompare("None") == .orderedSame { return nil }
        return raw
    }

    var listUserName: String {
        if let l = login?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty { return l }
        if let u = username?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty { return u }
        for candidate in [description, detailsDescription] {
            let d = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if d.isEmpty { continue }
            return loginFromKeeperListDisplayDescription(d)
        }
        return ""
    }

    var sourceLabel: String? {
        if let cat = record_category?.trimmingCharacters(in: .whitespacesAndNewlines), !cat.isEmpty {
            switch cat.lowercased() {
            case "classic", "legacy": return "Classic"
            case "nested",
                 "nested share folder",
                 "nested share subfolder",
                 "nested share subfolders": return "Nested"
            default: return cat
            }
        }
        guard let raw = source?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "legacy": return "Classic"
        case "nested",
             "nested share folder",
             "nested share subfolder",
             "nested share subfolders": return "Nested"
        default: return raw
        }
    }

    var displayTitleWithSource: String {
        guard let label = sourceLabel else { return displayTitle }
        return "\(displayTitle) (\(label))"
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
    static let longRequestTimeout: TimeInterval = 300
    static let validationRequestTimeout: TimeInterval = 20
    static let statusPollTimeout: TimeInterval = 30

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

    func executeCommand(apiKey: String,
                        command: String,
                        timeout: TimeInterval = longRequestTimeout) throws -> Data {
        let body = try JSONEncoder().encode(KeeperExecuteRequest(command: command))
        var request = URLRequest(url: asyncURL())
        request.timeoutInterval = timeout
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.httpBody = body
        let (data, response, err) = session.synchronousData(for: request)
        if let err = err {
            throw KeeperClientError.message(keeperConnectivityErrorMessage(urlError: err) ?? err.localizedDescription)
        }
        guard let data = data else { throw KeeperClientError.message("No data") }
        guard let http = response as? HTTPURLResponse, http.statusCode == 202 else {
            let code = (response as? HTTPURLResponse)?.statusCode
            throw KeeperClientError.message(keeperConnectivityErrorMessage(statusCode: code, data: data))
        }
        let queued = try JSONDecoder().decode(KeeperV2QueuedResponse.self, from: data)
        guard let requestId = queued.request_id, !requestId.isEmpty else {
            throw KeeperClientError.message("No request_id in v2 response")
        }
        return try pollForResult(apiKey: apiKey, requestId: requestId, totalTimeout: timeout)
    }

    private func pollForResult(apiKey: String,
                               requestId: String,
                               totalTimeout: TimeInterval) throws -> Data {
        let interval: TimeInterval = 2
        let deadline = Date().addingTimeInterval(totalTimeout)
        let maxPolls = Int(totalTimeout / interval) + 30
        var pollCount = 0
        var consecutiveUnparseable = 0
        while true {
            pollCount += 1
            if Date() > deadline { throw KeeperClientError.message("Keeper service v2 request timed out") }
            if pollCount > maxPolls { throw KeeperClientError.message("Keeper service did not complete the request in time") }
            var sreq = URLRequest(url: statusURL(requestId: requestId))
            sreq.timeoutInterval = Self.statusPollTimeout
            sreq.setValue(apiKey, forHTTPHeaderField: "api-key")
            let (sdata, sresp, serr) = session.synchronousData(for: sreq)
            if let serr = serr {
                throw KeeperClientError.message(keeperConnectivityErrorMessage(urlError: serr) ?? serr.localizedDescription)
            }
            let scode = (sresp as? HTTPURLResponse)?.statusCode ?? 0
            if scode != 200 {
                throw KeeperClientError.message(keeperConnectivityErrorMessage(statusCode: scode, data: sdata))
            }
            guard let sdata = sdata,
                  let statusResp = try? JSONDecoder().decode(KeeperV2StatusResponse.self, from: sdata),
                  let status = statusResp.status else {
                consecutiveUnparseable += 1
                if consecutiveUnparseable >= 15 {
                    throw KeeperClientError.message(keeperConnectivityErrorMessage(statusCode: scode, data: sdata))
                }
                Thread.sleep(forTimeInterval: interval)
                continue
            }
            consecutiveUnparseable = 0
            switch status {
            case "completed":
                var rreq = URLRequest(url: resultURL(requestId: requestId))
                rreq.timeoutInterval = totalTimeout
                rreq.setValue(apiKey, forHTTPHeaderField: "api-key")
                let (rdata, rresp, rerr) = session.synchronousData(for: rreq)
                if let rerr = rerr {
                    throw KeeperClientError.message(keeperConnectivityErrorMessage(urlError: rerr) ?? rerr.localizedDescription)
                }
                guard let rdata = rdata, !rdata.isEmpty else { throw KeeperClientError.message("No data") }
                if let http = rresp as? HTTPURLResponse, http.statusCode != 200 {
                    throw KeeperClientError.message(keeperConnectivityErrorMessage(statusCode: http.statusCode, data: rdata))
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

private let keeperEmbeddedRecordUIDRegex = try! NSRegularExpression(pattern: "[A-Za-z0-9_-]{15,}")

private func extractRecordUID(from text: String) throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let uid = try? validatedRecordUID(trimmed) {
        return uid
    }
    let fullRange = NSRange(trimmed.startIndex..., in: trimmed)
    for match in keeperEmbeddedRecordUIDRegex.matches(in: trimmed, range: fullRange) {
        guard let range = Range(match.range, in: trimmed) else { continue }
        if let uid = try? validatedRecordUID(String(trimmed[range])) {
            return uid
        }
    }
    throw KeeperClientError.message("Invalid record identifier.")
}

private enum KeeperMutationStrategy {
    case stopAfterFirstFailure
    case tryAllPreservingFirstError
}

private struct KeeperMutationAttempt {
    let label: String
    let run: () throws -> Data
}

private func runKeeperMutationAttempts(logPrefix: String,
                                       uid: String,
                                       attempts: [KeeperMutationAttempt],
                                       strategy: KeeperMutationStrategy,
                                       formatFailure: (Data) -> String) throws {
    func attempt(_ step: KeeperMutationAttempt) throws -> (success: Bool, raw: Data) {
        KeeperAdapterLog.write("\(logPrefix): trying verb=\(step.label) uid=\(uid)")
        let data: Data
        do {
            data = try step.run()
        } catch {
            KeeperAdapterLog.write("\(logPrefix): \(step.label) executeCommand threw: \(error.localizedDescription)")
            throw error
        }
        KeeperAdapterLog.write("\(logPrefix): \(step.label) raw response (\(data.count) bytes): \(String(data: data, encoding: .utf8) ?? "<binary>")")
        let success = (try? JSONDecoder().decode(KeeperExecuteResponse.self, from: data))?.status == "success"
        return (success, data)
    }

    var firstFailureResponse: Data?
    var networkError: Error?
    for step in attempts {
        do {
            let result = try attempt(step)
            if result.success {
                KeeperAdapterLog.write("\(logPrefix): success uid=\(uid) via \(step.label)")
                return
            }
            if firstFailureResponse == nil {
                firstFailureResponse = result.raw
            }
            if strategy == .stopAfterFirstFailure {
                break
            }
        } catch {
            networkError = error
            break
        }
    }

    if let response = firstFailureResponse {
        let raw = formatFailure(response)
        KeeperAdapterLog.write("\(logPrefix): FAILED uid=\(uid): \(raw)")
        throw KeeperClientError.message(raw)
    }
    if let error = networkError {
        throw error
    }
    throw KeeperClientError.message(formatFailure(Data()))
}

enum KeeperRecordSource: String {
    case classic
    case nested

    var idPrefix: String { rawValue }

    static func fromLabel(_ label: String?) -> KeeperRecordSource? {
        switch label?.lowercased() {
        case "classic": return .classic
        case "nested":  return .nested
        default:        return nil
        }
    }
}

struct ParsedAccountIdentifier {
    let source: KeeperRecordSource?
    let uid: String
}

// accountID is `classic:<uid>` or `nested:<uid>` so per-record routing survives the host protocol.
func parseAccountIdentifier(_ raw: String) -> ParsedAccountIdentifier {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if let colon = trimmed.firstIndex(of: ":") {
        let prefix = String(trimmed[..<colon])
        let rest = String(trimmed[trimmed.index(after: colon)...])
        if let source = KeeperRecordSource(rawValue: prefix.lowercased()), !rest.isEmpty {
            return ParsedAccountIdentifier(source: source, uid: rest)
        }
    }
    return ParsedAccountIdentifier(source: nil, uid: trimmed)
}

func prefixedAccountID(uid: String, source: KeeperRecordSource?) -> String {
    guard let source = source else { return uid }
    return "\(source.idPrefix):\(uid)"
}

private func parseListingPayload(_ data: Data) -> [KeeperRecord] {
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
            let recs = rawRecords.compactMap { dict -> KeeperRecord? in
                guard let line = dict["title"] as? String else { return nil }
                return parseLsRecordLine(line)
            }
            if !recs.isEmpty { return recs }
        }
        if let response = try? JSONDecoder().decode(KeeperExecuteResponse.self, from: jsonData),
           response.status == "success", let recs = response.data?.records, !recs.isEmpty {
            return recs
        }
        if let responseArray = try? JSONDecoder().decode(KeeperExecuteResponseDataArray.self, from: jsonData),
           responseArray.status == "success", let arr = responseArray.data, !arr.isEmpty {
            return arr
        }
    }
    return []
}

private func taggedAsNested(_ records: [KeeperRecord]) -> [KeeperRecord] {
    return records.map { rec in
        if let cat = rec.record_category?.trimmingCharacters(in: .whitespacesAndNewlines), !cat.isEmpty {
            return rec
        }
        if let s = rec.source?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return rec
        }
        return rec.withRecordCategory("Nested")
    }
}

func validateApiKey(apiKey: String, client: KeeperCommanderClient) throws {
    _ = try client.executeCommand(apiKey: apiKey,
                                  command: "list --format=json",
                                  timeout: KeeperCommanderClient.validationRequestTimeout)
}

func listAccountsRecords(apiKey: String,
                         client: KeeperCommanderClient,
                         syncFirst: Bool = false) throws -> [PasswordManagerProtocol.Account] {
    KeeperAdapterLog.write("listAccountsRecords: begin syncFirst=\(syncFirst)")
    if syncFirst {
        _ = try? client.executeCommand(apiKey: apiKey, command: "sync-down")
        KeeperAdapterLog.write("listAccountsRecords: sync-down completed")
    }

    let listData = try client.executeCommand(apiKey: apiKey, command: "list --format=json")
    let listRecords = parseListingPayload(listData)
    KeeperAdapterLog.write("listAccountsRecords: list returned \(listRecords.count) records")

    var nsfRecords: [KeeperRecord] = []
    if let nsfData = try? client.executeCommand(apiKey: apiKey, command: "nsf-list --records --format=json") {
        nsfRecords = taggedAsNested(parseListingPayload(nsfData))
        KeeperAdapterLog.write("listAccountsRecords: nsf-list returned \(nsfRecords.count) records")
    } else {
        KeeperAdapterLog.write("listAccountsRecords: nsf-list call failed (continuing with `list` results only)")
    }

    var byUid: [String: KeeperRecord] = [:]
    var order: [String] = []
    for rec in listRecords {
        guard let uid = rec.effectiveUid, !uid.isEmpty else { continue }
        if byUid[uid] == nil { order.append(uid) }
        byUid[uid] = rec
    }
    for rec in nsfRecords {
        guard let uid = rec.effectiveUid, !uid.isEmpty else { continue }
        if byUid[uid] == nil {
            order.append(uid)
        }
        byUid[uid] = rec
    }
    let merged = order.compactMap { byUid[$0] }
    KeeperAdapterLog.write("listAccountsRecords: merged total=\(merged.count) unique UIDs (list=\(listRecords.count), nsf=\(nsfRecords.count))")

    return merged.compactMap { rec -> PasswordManagerProtocol.Account? in
        if rec.isFolder { return nil }
        guard let uid = rec.effectiveUid, !uid.isEmpty else { return nil }
        let source = KeeperRecordSource.fromLabel(rec.sourceLabel)
        return PasswordManagerProtocol.Account(
            identifier: PasswordManagerProtocol.AccountIdentifier(accountID: prefixedAccountID(uid: uid, source: source)),
            userName: rec.listUserName,
            accountName: rec.displayTitleWithSource,
            hasOTP: false)
    }
}

func getPassword(apiKey: String, recordUid: String, client: KeeperCommanderClient) throws -> PasswordManagerProtocol.Password {
    let uid = try validatedRecordUID(parseAccountIdentifier(recordUid).uid)
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
    let uid = try validatedRecordUID(parseAccountIdentifier(recordUid).uid)
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

private func passwordCommandFragment(password: String) -> String {
    let b64 = Data(password.utf8).base64EncodedString()
    return "password=$BASE64:\(b64)"
}

private func redactedPasswordFragment(password: String) -> String {
    let b64Length = Data(password.utf8).base64EncodedString().count
    return "password=$BASE64:<\(b64Length) chars>"
}

func setPassword(apiKey: String, recordUid: String, newPassword: String?, client: KeeperCommanderClient) throws {
    guard let newPassword = newPassword, !newPassword.isEmpty else {
        throw KeeperClientError.message("Password field is required.")
    }
    let parsed = parseAccountIdentifier(recordUid)
    let uid = try validatedRecordUID(parsed.uid)

    func makeAttempt(verb: String) -> KeeperMutationAttempt {
        KeeperMutationAttempt(label: verb) {
            let cmd = "\(verb) --force -r \(uid) \(passwordCommandFragment(password: newPassword))"
            KeeperAdapterLog.write("setPassword: issuing verb=\(verb) uid=\(uid) \(redactedPasswordFragment(password: newPassword))")
            return try client.executeCommand(apiKey: apiKey, command: cmd)
        }
    }

    let attempts: [KeeperMutationAttempt]
    let strategy: KeeperMutationStrategy
    switch parsed.source {
    case .classic:
        attempts = [makeAttempt(verb: "record-update")]
        strategy = .stopAfterFirstFailure
    case .nested:
        attempts = [makeAttempt(verb: "nsf-record-update")]
        strategy = .stopAfterFirstFailure
    case .none:
        attempts = [makeAttempt(verb: "record-update"), makeAttempt(verb: "nsf-record-update")]
        strategy = .tryAllPreservingFirstError
    }

    try runKeeperMutationAttempts(
        logPrefix: "setPassword",
        uid: uid,
        attempts: attempts,
        strategy: strategy,
        formatFailure: { keeperUserFacingPasswordUpdateError(apiDetail: keeperHumanReadableError(fromResponseData: $0) ?? "Update failed") })
}

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
    let parsed = parseAccountIdentifier(recordUid)
    let uid = try validatedRecordUID(parsed.uid)

    func makeAttempt(cmd: String, label: String) -> KeeperMutationAttempt {
        KeeperMutationAttempt(label: label) {
            try client.executeCommand(apiKey: apiKey, command: cmd)
        }
    }

    let attempts: [KeeperMutationAttempt]
    let strategy: KeeperMutationStrategy
    switch parsed.source {
    case .classic:
        attempts = [makeAttempt(cmd: "rm -f \(uid)", label: "rm")]
        strategy = .stopAfterFirstFailure
    case .nested:
        attempts = [makeAttempt(cmd: "nsf-rm \(uid) -f", label: "nsf-rm")]
        strategy = .stopAfterFirstFailure
    case .none:
        attempts = [
            makeAttempt(cmd: "rm -f \(uid)", label: "rm"),
            makeAttempt(cmd: "nsf-rm \(uid) -f", label: "nsf-rm"),
        ]
        strategy = .tryAllPreservingFirstError
    }

    try runKeeperMutationAttempts(
        logPrefix: "deleteRecord",
        uid: uid,
        attempts: attempts,
        strategy: strategy,
        formatFailure: { keeperHumanReadableError(fromResponseData: $0) ?? "Delete failed" })
}

func addRecord(apiKey: String,
               userName: String,
               accountName: String,
               password: String?,
               useClassicPermission: Bool,
               client: KeeperCommanderClient) throws -> String {
    let escapedTitle = escapeForKeeperDoubleQuotedCommandField(accountName)
    let verb = useClassicPermission ? "record-add" : "nsf-record-add"
    var cmd = "\(verb) --force --record-type=login --title=\"\(escapedTitle)\""
    if !userName.isEmpty {
        let escapedLogin = escapeForKeeperDoubleQuotedCommandField(userName)
        cmd += " login=\"\(escapedLogin)\""
    }
    if let password = password, !password.isEmpty {
        cmd += " " + passwordCommandFragment(password: password)
    }
    let loggableCmd: String = {
        guard let password = password, !password.isEmpty else { return cmd }
        return cmd.replacingOccurrences(of: passwordCommandFragment(password: password),
                                        with: redactedPasswordFragment(password: password))
    }()
    KeeperAdapterLog.write("addRecord: verb=\(verb) issuing command=\(loggableCmd)")
    let data: Data
    do {
        data = try client.executeCommand(apiKey: apiKey, command: cmd)
    } catch {
        KeeperAdapterLog.write("addRecord: \(verb) executeCommand threw: \(error.localizedDescription)")
        throw error
    }
    KeeperAdapterLog.write("addRecord: \(verb) raw response (\(data.count) bytes): \(String(data: data, encoding: .utf8) ?? "<binary>")")
    struct RecordAddResponse: Decodable {
        let status: String?
        let data: RecordAddData?
        let message: String?
    }
    struct RecordAddData: Decodable {
        let record_uid: String?
        let uid: String?
        var effectiveUid: String? { record_uid ?? uid }
    }
    let response = try JSONDecoder().decode(RecordAddResponse.self, from: data)
    guard response.status == "success" else {
        KeeperAdapterLog.write("addRecord: \(verb) failed; raw=\(String(data: data, encoding: .utf8) ?? "<binary>")")
        throw KeeperClientError.message("Add failed")
    }
    let uid: String
    if let fromData = response.data?.effectiveUid?.trimmingCharacters(in: .whitespacesAndNewlines),
       !fromData.isEmpty {
        uid = try validatedRecordUID(fromData)
    } else if let message = response.message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty,
              let extracted = try? extractRecordUID(from: message) {
        uid = extracted
    } else {
        KeeperAdapterLog.write("addRecord: \(verb) returned without a valid record_uid; raw=\(String(data: data, encoding: .utf8) ?? "<binary>")")
        throw KeeperClientError.message("Add failed")
    }
    KeeperAdapterLog.write("addRecord: \(verb) returned uid=\(uid)")
    let source: KeeperRecordSource = useClassicPermission ? .classic : .nested
    return prefixedAccountID(uid: uid, source: source)
}
