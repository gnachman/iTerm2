//
//  AIChatWireLogger.swift
//  iTerm2
//

import Foundation

// Disk logger for raw AI API traffic. When the
// `aiChatRawWireLogging` advanced setting is on, every WebRequest sent
// through iTermAIClient.request and every byte received back (full
// response body or per-chunk streamed data) is appended to a single
// per-app-launch log file under
// `~/Library/Application Support/iTerm2/AIChatWire/`.
//
// Purpose: reproduce vendor-side problems where the bug shows up after
// JSON parsing or after model output post-processing has masked the
// original bytes. The console-only `aiChatVerboseConsoleLogging` logs
// turn-shaped events, which is fine for tool-dispatch bugs but loses
// the wire format (request body assembly, streamed SSE fragments,
// vendor error envelopes). This logger sits below all that and records
// the bytes verbatim, preserving timing.
//
// SECURITY: the log captures the full prompt + response content; users
// opt in explicitly via the advanced setting. Credentials, however, are
// scrubbed on the write path: every header value except a short list of
// known-harmless ones (Content-Type, Accept, anthropic-version, ...) is
// reduced to a fingerprint, since user-configured custom headers can
// carry credentials under any name, and
// the request URL, string bodies, responses, and stream chunks are
// regex-scrubbed for key-shaped tokens (sk-* for OpenAI/Anthropic/
// DeepSeek, AIza* for Gemini, whose keys ride in the URL query) and
// for the value of a key-like URL query parameter (key=, api_key=, ...).
// Fingerprints keep enough of each key to
// tell WHICH key was used (wrong-vendor-key bugs stay debuggable)
// while making the log safe to attach to a bug report. Redacting only
// credentials preserves the logger's purpose of full-fidelity
// debugging of bytes-in / bytes-out; no vendor requires the key inside
// the body, so scrubbing cannot mask a payload bug.
//
// Threading: all file I/O happens on a single serial DispatchQueue so
// concurrent calls from the plugin's executionQueue (and main, for
// the response emit hop) don't interleave inside one record. The
// file handle is opened lazily on the first log call and is held open
// for the process lifetime.
@objc(iTermAIChatWireLogger)
final class AIChatWireLogger: NSObject {
    @objc static let instance = AIChatWireLogger()

    private let queue = DispatchQueue(label: "com.googlecode.iterm2.ai-wire-logger")
    private var fileHandle: FileHandle?
    private var logPath: String?
    private var openAttempted = false

    @objc static var isEnabled: Bool {
        return iTermAdvancedSettingsModel.aiChatRawWireLogging()
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Public API

    func logRequest(callID: UUID, request: WebRequest) {
        guard Self.isEnabled else { return }
        let stamp = Self.iso8601.string(from: Date())
        append(Self.requestRecord(callID: callID, stamp: stamp, request: request))
    }

    // The text logRequest writes for one request, credentials scrubbed.
    static func requestRecord(callID: UUID, stamp: String, request: WebRequest) -> String {
        let id = callID.uuidString
        var text = ""
        text += "=== call \(id) request \(stamp) ===\n"
        text += "\(request.method) \(AIChatWireLogSanitizer.scrubbingSecrets(request.url))\n"
        text += "Headers (\(request.headers.count)):\n"
        text += AIChatWireLogSanitizer.sanitizedHeadersDescription(request.headers)
        // The binary case is base64 (attachment bytes); a key inside it
        // is not recoverable by grep, and decoding megabytes to scan
        // them isn't worth it.
        switch request.body {
        case .string(let s):
            let bytes = s.utf8.count
            text += "Body (string, \(bytes) bytes):\n"
            let scrubbed = AIChatWireLogSanitizer.scrubbingSecrets(s)
            text += scrubbed
            if !scrubbed.hasSuffix("\n") { text += "\n" }
        case .bytes(let b):
            text += "Body (binary, \(b.count) bytes, base64):\n"
            text += Data(b).base64EncodedString()
            text += "\n"
        }
        text += "--- end request \(id) ---\n\n"
        return text
    }

    // Responses and stream chunks are scrubbed too, even though
    // credentials are client-sent: error envelopes (from the vendor or
    // from a proxy/relay in front of it) sometimes echo the request
    // URL, and on the Gemini path the key rides in the URL query.
    func logStreamChunk(callID: UUID, chunk: String) {
        guard Self.isEnabled else { return }
        let stamp = Self.iso8601.string(from: Date())
        let id = callID.uuidString
        var text = ""
        text += "=== call \(id) stream chunk \(stamp) (\(chunk.utf8.count) bytes) ===\n"
        let scrubbed = AIChatWireLogSanitizer.scrubbingSecrets(chunk)
        text += scrubbed
        if !scrubbed.hasSuffix("\n") { text += "\n" }
        text += "--- end chunk \(id) ---\n\n"
        append(text)
    }

    func logSuccess(callID: UUID, response: WebResponse, elapsed: TimeInterval) {
        guard Self.isEnabled else { return }
        let stamp = Self.iso8601.string(from: Date())
        let id = callID.uuidString
        let elapsedStr = String(format: "%.3f", elapsed)
        var text = ""
        text += "=== call \(id) response \(stamp) elapsed=\(elapsedStr)s ===\n"
        text += "Body (\(response.data.utf8.count) bytes):\n"
        let scrubbed = AIChatWireLogSanitizer.scrubbingSecrets(response.data)
        text += scrubbed
        if !scrubbed.hasSuffix("\n") { text += "\n" }
        if let err = response.error, !err.isEmpty {
            text += "Error (in-band): \(AIChatWireLogSanitizer.scrubbingSecrets(err))\n"
        }
        text += "--- end response \(id) ---\n\n"
        append(text)
    }

    func logFailure(callID: UUID, error: PluginError, elapsed: TimeInterval) {
        guard Self.isEnabled else { return }
        let stamp = Self.iso8601.string(from: Date())
        let id = callID.uuidString
        let elapsedStr = String(format: "%.3f", elapsed)
        var text = ""
        text += "=== call \(id) error \(stamp) elapsed=\(elapsedStr)s ===\n"
        text += error.reason
        text += "\n--- end error \(id) ---\n\n"
        append(text)
    }

    // MARK: - File

    private func append(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            guard let handle = self.handleOpeningIfNeeded() else { return }
            do {
                try handle.write(contentsOf: data)
            } catch {
                NSFuckingLog("AIChatWireLogger: write failed: \(error)")
            }
        }
    }

    // Lazily open the per-launch log file. Called only from `queue`.
    // Returns nil if open failed (we tried once and won't retry on
    // every call). Holds the handle for the process lifetime; the
    // logger has no close method because the app is the natural
    // lifetime boundary and macOS closes handles at exit.
    private func handleOpeningIfNeeded() -> FileHandle? {
        if let fileHandle { return fileHandle }
        if openAttempted { return nil }
        openAttempted = true
        guard let path = Self.makeLogPath() else {
            NSFuckingLog("AIChatWireLogger: could not resolve log directory")
            return nil
        }
        let fm = FileManager.default
        if !fm.createFile(atPath: path, contents: nil, attributes: nil) {
            NSFuckingLog("AIChatWireLogger: could not create \(path)")
            return nil
        }
        guard let handle = FileHandle(forWritingAtPath: path) else {
            NSFuckingLog("AIChatWireLogger: could not open \(path) for writing")
            return nil
        }
        fileHandle = handle
        logPath = path
        let header = "# iTerm2 AI chat wire log, started "
            + Self.iso8601.string(from: Date())
            + " pid \(ProcessInfo.processInfo.processIdentifier)\n\n"
        if let data = header.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
        NSFuckingLog("AIChatWireLogger: logging to \(path)")
        return handle
    }

    private static func makeLogPath() -> String? {
        guard let appSupport = FileManager.default.applicationSupportDirectory() else {
            return nil
        }
        let dir = (appSupport as NSString).appendingPathComponent("AIChatWire")
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: dir, isDirectory: &isDir) {
            do {
                try fm.createDirectory(atPath: dir,
                                       withIntermediateDirectories: true,
                                       attributes: nil)
            } catch {
                return nil
            }
        } else if !isDir.boolValue {
            return nil
        }
        // Filename-safe ISO 8601: no colons (illegal on some FS roundtrips
        // when copied to FAT/SMB) and second resolution is sufficient since
        // one process produces one file.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay,
                                   .withTime]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let pid = ProcessInfo.processInfo.processIdentifier
        let name = "aichat-wire-\(stamp)-pid\(pid).log"
        return (dir as NSString).appendingPathComponent(name)
    }
}

// Credential scrubbing for the wire log. Pure functions, kept separate
// from the logger's I/O so they're unit-testable.
//
// Two layers:
//  1. sanitizedHeaderValue: every header that isn't known to be
//     harmless is fingerprinted wholesale, no pattern needed. Users
//     can configure custom headers per model (Proxy-Authorization,
//     X-Auth-Token, anything), so any unknown header may carry a
//     credential. This is the layer that catches keys whose format
//     we don't know about.
//  2. scrubbingSecrets: key-shaped tokens and key-like URL query
//     parameter values are fingerprinted wherever they appear (URL
//     query for Gemini, bodies, error text that echoes a URL).
//
// The debug log (WebRequest.debugDescription, PluginClient) uses the
// same functions, so a debug log is as safe to attach as the wire log.
//
// A fingerprint keeps a short prefix and suffix, e.g.
// "sk-ant-a…BkXm [redacted 108 chars]", so the log still shows which
// key was used (a wrong-vendor-key 401 stays diagnosable) without
// disclosing it.
enum AIChatWireLogSanitizer {
    // Lowercased names of headers whose values are logged as-is
    // (pattern-scrubbed only). Every other header's value is treated
    // as a credential. Keep this list to headers that never carry
    // secrets.
    private static let harmlessHeaders: Set<String> = [
        "accept", "accept-encoding", "accept-language",
        "anthropic-beta", "anthropic-version", "cache-control",
        "connection", "content-length", "content-type", "openai-beta",
        "user-agent",
    ]

    // Lowercased names of headers whose value starts with an auth
    // scheme ("Bearer ", "Basic ") that is safe to keep visible.
    private static let schemeHeaders: Set<String> = [
        "authorization", "proxy-authorization",
    ]

    // Key-shaped tokens:
    //  - sk-… covers OpenAI (sk-, sk-proj-), Anthropic (sk-ant-) and
    //    DeepSeek (sk-<hex>) keys. 16 is well below any real key's
    //    length but above what appears in prose ("sk-learn" etc.).
    //  - AIza… is the fixed-format Google API key used by Gemini.
    // Both patterns require a non-token character (or start of text)
    // before the match: without that anchor, ordinary hyphenated
    // identifiers whose head ends in "sk" ("disk-configuration-
    // manager-2024", "task-management-migration") would match from
    // the embedded "sk-" and get mangled.
    private static let secretPatterns: [NSRegularExpression] = {
        let patterns = [
            // Value of a key-like URL query parameter. Listed first so
            // a Gemini key is fingerprinted as a whole here rather than
            // first by the AIza pattern and then again by this one.
            "(?<=[?&](?i:key|api_key|apikey|api-key|access_token|access-token|token|auth|secret|client_secret|password|sig|signature)=)[^&#\\s\"'}]+",
            "(?<![A-Za-z0-9_-])sk-[A-Za-z0-9_-]{16,}",
            "(?<![A-Za-z0-9_-])AIza[0-9A-Za-z_-]{35}",
        ]
        return patterns.map {
            try! NSRegularExpression(pattern: $0)
        }
    }()

    static func sanitizedHeaderValue(_ value: String, forHeader header: String) -> String {
        let lowercased = header.lowercased()
        if harmlessHeaders.contains(lowercased) {
            return scrubbingSecrets(value)
        }
        // Preserve an auth-scheme prefix ("Bearer ") so the scheme
        // stays visible; fingerprint the credential part. Only for
        // auth headers: in an arbitrary custom header the text before
        // the first space could be part of the secret.
        if schemeHeaders.contains(lowercased),
           let spaceIndex = value.firstIndex(of: " "),
           value.distance(from: value.startIndex, to: spaceIndex) <= 16 {
            let scheme = value[..<spaceIndex]
            let credential = String(value[value.index(after: spaceIndex)...])
            return "\(scheme) \(fingerprint(credential))"
        }
        return fingerprint(value)
    }

    // One "Name: value" line per header, each terminated by a newline,
    // in stable (sorted) order so diffs across calls read cleanly.
    static func sanitizedHeadersDescription(_ headers: [String: String]) -> String {
        var text = ""
        for key in headers.keys.sorted() {
            let value = headers[key] ?? ""
            text += "\(key): \(sanitizedHeaderValue(value, forHeader: key))\n"
        }
        return text
    }

    static func scrubbingSecrets(_ text: String) -> String {
        var result = text
        for regex in secretPatterns {
            // Replace back to front so earlier ranges stay valid.
            let matches = regex.matches(in: result,
                                        range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                result.replaceSubrange(range, with: fingerprint(String(result[range])))
            }
        }
        return result
    }

    static func fingerprint(_ secret: String) -> String {
        // Show the 12-char prefix+suffix fingerprint only when it is a
        // modest fraction of the secret. Every real vendor key is 35+
        // chars, but the credential-header path also fingerprints keys
        // of unknown format, where e.g. a 16-char key would have 12 of
        // its 16 chars disclosed. Below the threshold, redact whole.
        guard secret.count >= 32 else {
            return "[redacted \(secret.count) chars]"
        }
        let prefix = secret.prefix(8)
        let suffix = secret.suffix(4)
        return "\(prefix)\u{2026}\(suffix) [redacted \(secret.count) chars]"
    }
}
