//
//  AICassette.swift
//  iTerm2 AI live harness
//
//  Record/playback for the live AI harness. The live tests hit real
//  vendor APIs and cost real money. The assumption this layer rests on:
//  a vendor returns the same answer for the same input, so we only need
//  to spend money when our request would differ from one we have already
//  recorded.
//
//  A cassette is keyed by a canonicalized form of the outgoing WebRequest
//  with the per-run noise stripped out: API keys (we know their values
//  from the config), UUIDs (multipart boundaries, locally minted ids),
//  and JSON key ordering. Two runs that build the same logical request
//  therefore hash to the same key and replay the same recorded response.
//
//  Modes (CASSETTE_MODE in the harness config, set by run_ai_live.sh):
//    off     no interception; pure live (default)
//    auto    replay on hit, go live and record on miss
//    replay  replay on hit, FAIL offline on miss (strict; for CI)
//    record  always go live and (over)write the cassette (refresh)
//
//  Cassettes are scrubbed of secret values and are safe to commit, which
//  is the whole point: once recorded, CI and local dev replay them for
//  free and only the live drift suite spends money.
//

import CryptoKit
import Foundation
@testable import iTerm2SharedARC

enum AICassetteMode: String {
    case off
    case auto
    case replay
    case record
}

/// Turns a WebRequest into a stable canonical string (and its SHA256 key)
/// by removing the parts that legitimately vary run to run.
struct AICassetteCanonicalizer {
    /// Known secret values (API keys), longest first so a key that is a
    /// prefix of another does not get partially replaced.
    let secrets: [String]

    init(secrets: [String]) {
        self.secrets = secrets
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
    }

    private static let uuidRegex = try! NSRegularExpression(
        pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")

    struct Canonical {
        let key: String
        let text: String
    }

    /// Replace every known secret value with a fixed placeholder. Applied
    /// to the request for keying and to recorded responses so nothing
    /// secret is ever written to a committed cassette.
    func redactSecrets(_ s: String) -> String {
        var out = s
        for secret in secrets {
            out = out.replacingOccurrences(of: secret, with: "<SECRET>")
        }
        return out
    }

    /// Build a replacer that maps each distinct UUID to a positional
    /// placeholder, numbered by first appearance across the supplied texts.
    /// Distinct numbering keeps two genuinely different UUIDs apart while
    /// collapsing each run's random ones (multipart boundary, minted ids)
    /// to a stable token. The same UUID appearing many times (the boundary
    /// is repeated throughout a multipart body) always maps to one token.
    private func uuidReplacer(scanning texts: [String]) -> (String) -> String {
        var map: [String: String] = [:]
        var next = 0
        for text in texts {
            let ns = text as NSString
            let matches = Self.uuidRegex.matches(
                in: text, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                let u = ns.substring(with: m.range)
                if map[u] == nil {
                    map[u] = "<UUID-\(next)>"
                    next += 1
                }
            }
        }
        // UUIDs are fixed-length and never overlap, so replacement order is
        // irrelevant.
        return { input in
            var out = input
            for (u, placeholder) in map {
                out = out.replacingOccurrences(of: u, with: placeholder)
            }
            return out
        }
    }

    func canonicalize(_ request: WebRequest) -> Canonical {
        let method = request.method.uppercased()

        // Scan url + header values + string body together so a UUID shared
        // between, say, the Content-Type boundary and the body gets the same
        // token everywhere.
        var scanTexts: [String] = [request.url]
        for (_, v) in request.headers { scanTexts.append(v) }
        if case .string(let s) = request.body { scanTexts.append(s) }
        let replaceUUIDs = uuidReplacer(scanning: scanTexts)

        // The multipart boundary is per-run noise wherever it appears (the
        // Content-Type header, the body part separators). It is usually a
        // UUID, which the UUID pass would catch, but don't rely on that:
        // pull the literal value out of the Content-Type and neutralize it
        // explicitly so a non-UUID boundary canonicalizes too.
        let contentType = request.headers
            .first { $0.key.lowercased() == "content-type" }?.value
        let boundary = Self.boundary(fromContentType: contentType)
        let redactBoundary: (String) -> String = { s in
            guard let boundary, !boundary.isEmpty else { return s }
            return s.replacingOccurrences(of: boundary, with: "<BOUNDARY>")
        }
        let redact: (String) -> String = { s in
            redactBoundary(replaceUUIDs(self.redactSecrets(s)))
        }

        let url = redact(Self.canonicalURL(request.url))
        let headerLines = request.headers
            .map { (k, v) in (k.lowercased(), redact(v)) }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0): \($0.1)" }
        let body = canonicalBody(request.body, contentType: contentType, redact: redact)

        var text = method + "\n" + url + "\n"
        text += headerLines.joined(separator: "\n")
        text += "\n\n" + body

        let digest = SHA256.hash(data: Data(text.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        return Canonical(key: key, text: text)
    }

    private func canonicalBody(_ body: WebRequest.Body,
                               contentType: String?,
                               redact: (String) -> String) -> String {
        switch body {
        case .string(let s):
            let canonical = Self.canonicalJSON(s) ?? s
            return redact(canonical)
        case .bytes(let bytes):
            // Multipart/binary upload. The only per-run variation is the
            // multipart boundary, which is echoed in the Content-Type
            // header (multipart/form-data; boundary=...). Replace its bytes
            // with a fixed token, then digest. The file payload is a
            // deterministic fixture, so the digest is stable across runs.
            var canonicalBytes = bytes
            if let boundary = Self.boundary(fromContentType: contentType) {
                canonicalBytes = Self.replace(in: bytes,
                                              occurrencesOf: Array(boundary.utf8),
                                              with: Array("BOUNDARY".utf8))
            }
            let digest = SHA256.hash(data: Data(canonicalBytes))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            return "bytes:sha256:\(hex):len=\(canonicalBytes.count)"
        }
    }

    /// Re-serialize a JSON string with sorted keys so Swift dictionary
    /// ordering (which is not stable) does not change the key. Returns nil
    /// when the string is not JSON (e.g. a multipart text body), in which
    /// case the caller keeps the original.
    static func canonicalJSON(_ s: String) -> String? {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(
                with: data, options: [.fragmentsAllowed]),
              let out = try? JSONSerialization.data(
                withJSONObject: obj, options: [.sortedKeys, .fragmentsAllowed]),
              let str = String(data: out, encoding: .utf8) else {
            return nil
        }
        return str
    }

    /// Sort query items so query ordering does not affect the key. The
    /// secret in Gemini's ?key= is redacted by the caller after this.
    static func canonicalURL(_ url: String) -> String {
        guard var comps = URLComponents(string: url) else { return url }
        if let items = comps.queryItems {
            comps.queryItems = items.sorted {
                ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "")
            }
        }
        return comps.string ?? url
    }

    static func boundary(fromContentType ct: String?) -> String? {
        guard let ct, let range = ct.range(of: "boundary=") else { return nil }
        var b = String(ct[range.upperBound...])
        if let semi = b.firstIndex(of: ";") {
            b = String(b[..<semi])
        }
        b = b.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return b.isEmpty ? nil : b
    }

    static func replace(in haystack: [UInt8],
                        occurrencesOf needle: [UInt8],
                        with replacement: [UInt8]) -> [UInt8] {
        guard !needle.isEmpty, haystack.count >= needle.count else { return haystack }
        var result: [UInt8] = []
        result.reserveCapacity(haystack.count)
        var i = 0
        while i < haystack.count {
            if i + needle.count <= haystack.count,
               Array(haystack[i..<i + needle.count]) == needle {
                result.append(contentsOf: replacement)
                i += needle.count
            } else {
                result.append(haystack[i])
                i += 1
            }
        }
        return result
    }
}

/// On-disk cassette. Stored pretty-printed with sorted keys so diffs are
/// readable. Secret values are already scrubbed before it is built.
struct AICassette: Codable {
    var key: String
    var canonicalRequest: String
    var streaming: Bool
    var streamChunks: [String]
    var response: WebResponse?
    var errorReason: String?
}

final class AICassetteStore {
    let directory: URL
    private let lock = NSLock()

    init(directory: URL) {
        self.directory = directory
    }

    private func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    func exists(key: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(forKey: key).path)
    }

    func load(key: String) -> AICassette? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL(forKey: key)) else { return nil }
        return try? JSONDecoder().decode(AICassette.self, from: data)
    }

    func save(_ cassette: AICassette) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(cassette)
            try data.write(to: fileURL(forKey: cassette.key), options: .atomic)
        } catch {
            print("[cassette] failed to save \(cassette.key): \(error)")
        }
    }
}

/// Owns the interceptor installed into iTermAIClient and the record path
/// the driver calls. Process-global; the harness runs with parallel
/// testing disabled, so a single shared instance is safe.
final class AICassetteSession {
    let mode: AICassetteMode
    let store: AICassetteStore
    let canon: AICassetteCanonicalizer

    init(mode: AICassetteMode, store: AICassetteStore, canon: AICassetteCanonicalizer) {
        self.mode = mode
        self.store = store
        self.canon = canon
    }

    func install() {
        iTermAIClient.requestInterceptor = { [weak self] request, streaming in
            self?.intercept(request, streaming: streaming) ?? nil
        }
        // Record on every completed live round-trip, independent of
        // AILiveDriver. This is what lets chat-queue tests (which never
        // install liveObserver) get recorded.
        iTermAIClient.responseRecorder = { [weak self] capture in
            self?.recordIfNeeded(capture: capture)
        }
    }

    func uninstall() {
        iTermAIClient.requestInterceptor = nil
        iTermAIClient.responseRecorder = nil
    }

    private func intercept(_ request: WebRequest,
                           streaming: Bool) -> iTermAIClient.ReplayDelivery? {
        let label = shortLabel(request, streaming: streaming)
        switch mode {
        case .off:
            return nil
        case .record:
            // record always goes live so it can refresh the cassette.
            print("[cassette] LIVE   (record) \(label)")
            return nil
        case .auto, .replay:
            let canonical = canon.canonicalize(request)
            let short = canonical.key.prefix(12)
            if let cassette = store.load(key: canonical.key) {
                print("[cassette] HIT    (\(mode.rawValue)) key=\(short) \(label)")
                return iTermAIClient.ReplayDelivery(
                    streamChunks: cassette.streamChunks,
                    response: cassette.response,
                    errorReason: cassette.errorReason)
            }
            if mode == .replay {
                // Strict: fail offline rather than silently spend money.
                print("[cassette] MISS   (replay, FAILING) key=\(canonical.key) \(label)")
                print(canonical.text)
                return iTermAIClient.ReplayDelivery(
                    streamChunks: [],
                    response: nil,
                    errorReason: "CASSETTE MISS in replay mode (no recording for key "
                        + "\(canonical.key)). Re-run with CASSETTE_MODE=auto or "
                        + "CASSETTE_MODE=record to capture it.")
            }
            // auto: let the live call proceed; consume() records it after.
            print("[cassette] MISS   (auto, going live) key=\(short) \(label)")
            return nil
        }
    }

    /// A compact, secret-scrubbed one-liner for the request, for logs.
    private func shortLabel(_ request: WebRequest, streaming: Bool) -> String {
        let suffix = streaming ? " [stream]" : ""
        return "\(request.method) \(canon.redactSecrets(request.url))\(suffix)"
    }

    func recordIfNeeded(capture: iTermAIClient.LiveCapture) {
        guard mode == .auto || mode == .record else { return }
        if isTransient(capture: capture) {
            print("[cassette] skip record: transient failure, not caching")
            return
        }
        let canonical = canon.canonicalize(capture.request)
        let short = canonical.key.prefix(12)
        // auto leaves an already-recorded response in place (this fires for
        // replayed hits too); record always overwrites.
        if mode == .auto, store.exists(key: canonical.key) { return }

        let response = capture.response.map {
            WebResponse(data: canon.redactSecrets($0.data),
                        error: $0.error.map(canon.redactSecrets))
        }
        let cassette = AICassette(
            key: canonical.key,
            canonicalRequest: canonical.text,
            streaming: capture.streaming,
            streamChunks: capture.streamChunks.map(canon.redactSecrets),
            response: response,
            errorReason: capture.error.map { canon.redactSecrets($0.reason) })
        store.save(cassette)
        let verb = mode == .record ? "REWRITE" : "RECORD "
        print("[cassette] \(verb)(\(mode.rawValue)) key=\(short) "
              + "(\(capture.streamChunks.count) chunks)")
    }

    /// Don't poison the cassette with capacity blips. Checks two channels:
    ///
    /// 1. The error channels (PluginError / WebResponse.error): HTTP/plugin
    ///    level failures. Broad markers here, including generic timeouts.
    ///
    /// 2. The CONTENT channel (stream chunks + response data): some vendors
    ///    deliver a capacity/quota error as the streamed body with HTTP 200
    ///    rather than as an error status. OpenAI streaming, for instance,
    ///    emits response.created and then an error event carrying
    ///    insufficient_quota; the plugin surfaces that as ordinary content,
    ///    so the error never reaches the error channels. If we don't catch
    ///    it here we cache the error as if it were a real answer, and replay
    ///    then serves that error forever. Only high-specificity vendor error
    ///    signatures are matched in the content channel so a legitimate
    ///    response that merely contains the word "timeout" still records.
    private func isTransient(capture: iTermAIClient.LiveCapture) -> Bool {
        let errorChannel = [capture.error?.reason, capture.response?.error]
            .compactMap { $0 }
            .joined(separator: " ")
        if !errorChannel.isEmpty {
            let lower = errorChannel.lowercased()
            if errorChannel.contains("status 429")
                || errorChannel.contains("status 500")
                || errorChannel.contains("status 502")
                || errorChannel.contains("status 503")
                || errorChannel.contains("status 504")
                || errorChannel.contains("RESOURCE_EXHAUSTED")
                || errorChannel.contains("UNAVAILABLE")
                || lower.contains("timed out")
                || lower.contains("timeout")
                // A request cancelled by a test timeout (slow reasoning
                // model) has no real response; never cache it.
                || lower.contains("cancelled") {
                return true
            }
        }

        let content = (capture.streamChunks + [capture.response?.data].compactMap { $0 })
            .joined(separator: " ")
        if content.isEmpty { return false }
        return content.contains("insufficient_quota")
            || content.contains("exceeded your current quota")
            || content.contains("RESOURCE_EXHAUSTED")
            || content.contains("rate_limit_exceeded")
            || content.contains("Rate limit reached")
    }

    // MARK: - Configuration

    /// Built once per process from the harness config file. Returns nil
    /// (no interception, pure live) unless CASSETTE_MODE names a real mode.
    static let shared: AICassetteSession? = fromConfig()

    private static func fromConfig() -> AICassetteSession? {
        func cfg(_ key: String) -> String? {
            let path = AILiveHarness.configFilePath()
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data)
                    as? [String: String] else {
                return nil
            }
            return json[key]
        }

        guard let raw = cfg("CASSETTE_MODE"),
              let mode = AICassetteMode(rawValue: raw),
              mode != .off else {
            return nil
        }

        let directory: URL
        if let d = cfg("CASSETTE_DIR"), !d.isEmpty {
            directory = URL(fileURLWithPath: d)
        } else if let root = cfg("PROJECT_ROOT"), !root.isEmpty {
            directory = URL(fileURLWithPath: root)
                .appendingPathComponent("ModernTests/Resources/AICassettes")
        } else {
            print("[cassette] no CASSETTE_DIR or PROJECT_ROOT; cassette disabled")
            return nil
        }

        let secrets = ["OPENAI_API_KEY", "ANTHROPIC_API_KEY",
                       "GEMINI_API_KEY", "DEEPSEEK_API_KEY"]
            .compactMap { cfg($0) }
            .filter { !$0.isEmpty }

        return AICassetteSession(
            mode: mode,
            store: AICassetteStore(directory: directory),
            canon: AICassetteCanonicalizer(secrets: secrets))
    }
}
