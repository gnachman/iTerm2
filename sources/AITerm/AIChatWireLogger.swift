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
// SECURITY: the log captures Authorization / X-Api-Key headers and
// the full prompt + response content. The advanced setting's
// description spells this out; users opt in explicitly. Keep logs out
// of bug reports unless you've scrubbed them. No redaction on the
// write path because the whole point of this logger is full-fidelity
// debugging of bytes-in / bytes-out.
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
        let id = callID.uuidString
        var text = ""
        text += "=== call \(id) request \(stamp) ===\n"
        text += "\(request.method) \(request.url)\n"
        text += "Headers (\(request.headers.count)):\n"
        // Stable order so diffs across calls read cleanly.
        for key in request.headers.keys.sorted() {
            let value = request.headers[key] ?? ""
            text += "\(key): \(value)\n"
        }
        switch request.body {
        case .string(let s):
            let bytes = s.utf8.count
            text += "Body (string, \(bytes) bytes):\n"
            text += s
            if !s.hasSuffix("\n") { text += "\n" }
        case .bytes(let b):
            text += "Body (binary, \(b.count) bytes, base64):\n"
            text += Data(b).base64EncodedString()
            text += "\n"
        }
        text += "--- end request \(id) ---\n\n"
        append(text)
    }

    func logStreamChunk(callID: UUID, chunk: String) {
        guard Self.isEnabled else { return }
        let stamp = Self.iso8601.string(from: Date())
        let id = callID.uuidString
        var text = ""
        text += "=== call \(id) stream chunk \(stamp) (\(chunk.utf8.count) bytes) ===\n"
        text += chunk
        if !chunk.hasSuffix("\n") { text += "\n" }
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
        text += response.data
        if !response.data.hasSuffix("\n") { text += "\n" }
        if let err = response.error, !err.isEmpty {
            text += "Error (in-band): \(err)\n"
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
